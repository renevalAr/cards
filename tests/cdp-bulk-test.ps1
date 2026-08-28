param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9236 })
$udir = "$env:TEMP\opencode\cdp-bulk-profile"
$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$url = "file:///" + ($rootDir -replace "\\","/") + "/frontend/index.html"
if (Test-Path $udir) { Remove-Item -Recurse -Force $udir }
$proc = Start-Process $chrome -ArgumentList @("--headless=new","--remote-debugging-port=$port","--user-data-dir=$udir","--disable-gpu","--no-first-run","about:blank") -PassThru -WindowStyle Hidden
$ws = $null
try {
  Start-Sleep -Seconds 2
  $list = Invoke-RestMethod "http://127.0.0.1:$port/json/list"
  $page = $list | Where-Object { $_.type -eq "page" } | Select-Object -First 1
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
  $script:id = 0
  function Send-Ws($ws, [string]$json) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$bytes)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
  }
  function Receive-Ws($ws) {
    $buffer = New-Object byte[] 262144
    $ms = New-Object System.IO.MemoryStream
    while ($true) {
      $seg = New-Object System.ArraySegment[byte] -ArgumentList (,$buffer)
      $res = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
      $ms.Write($buffer, 0, $res.Count)
      if ($res.EndOfMessage) { break }
    }
    [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
  }
  function Invoke-Cdp($ws, [string]$method, $params) {
    $script:id += 1
    $id = $script:id
    if ($null -eq $params) { $params = @{} }
    Send-Ws $ws (@{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 30)
    while ($true) {
      $obj = Receive-Ws $ws | ConvertFrom-Json
      if ($obj.id -eq $id) {
        if ($obj.error) { throw "CDP error: $($obj.error.message)" }
        return $obj.result
      }
    }
  }
  $seed = @'
try {
  (function () {
    var d = new Date();
    var pad = function (n) { return String(n).padStart(2, "0"); };
    var today = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
    localStorage.setItem("flashcards-app-v1", JSON.stringify({
      decks: [{ id: "d1", name: "Английский" }],
      cards: [{ id: "c1", deckId: "d1", question: "hello", answer: "привет", status: "new" }],
      selectedDeckId: "d1",
      tab: "edit",
      today: { date: today, known: 0, unknown: 0 },
      history: {},
      sessions: []
    }));
  })();
  localStorage.setItem("flashcards-onboarded", "1");
  localStorage.setItem("flashcards-palette", "ember");
  localStorage.setItem("flashcards-mode", "light");
} catch (e) {}
window.__errors = [];
window.addEventListener("error", function (e) { window.__errors.push((e.error && e.error.stack) || String(e.message)); });
window.addEventListener("unhandledrejection", function (e) { window.__errors.push(String(e.reason)); });
'@
  $scenario = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const cards = () => state.cards.filter((c) => c.deckId === "d1");

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));

  $("#menu-cards-btn").click(); await sleep(400);
  $$("#deck-pick-list .deck-pick-item")[0].querySelector(".deck-pick-main").click(); await sleep(500);
  // "Карточки"
  check("workspace", !$("#workspace").classList.contains("hidden") && !$("#panel-edit").classList.contains("hidden"));

  $("#bulk-btn").click(); await sleep(400);
  check("bulk-open", $("#bulk-backdrop").classList.contains("is-open"));
  check("bulk-focus", document.activeElement === $("#bulk-input"));

  const bulkText = ["один = one", "два = two", "три = three", "четыре = four", "пять = five", "строка без разделителя пропущена", "шесть = six", "семь = seven", ""].join("\n");
  $("#bulk-input").value = bulkText;
  $("#bulk-ok").click(); await sleep(500);
  check("bulk-feedback", $("#bulk-feedback").textContent.includes("Добавлено 7") && $("#bulk-feedback").textContent.includes("пропущено 1"), $("#bulk-feedback").textContent);
  check("cards8", cards().length === 8, String(cards().length));
  check("textarea-cleared", $("#bulk-input").value === "");
  const qs = cards().map((c) => c.question);
  check("parsed", ["один", "два", "три", "четыре", "пять", "шесть", "семь"].every((q) => qs.includes(q)), qs.join("|"));
  check("no-garbage", !qs.some((q) => q.includes("без разделителя")), qs.join("|"));
  check("all-new", cards().every((c) => c.status === "new"));
  check("answers", cards().find((c) => c.question === "два").answer === "two");

  $("#bulk-input").value = "alpha = бета";
  $("#bulk-ok").click(); await sleep(400);
  check("batch2", cards().length === 9 && $("#bulk-feedback").textContent.includes("Добавлено 1"), $("#bulk-feedback").textContent);
  check("rows9", $$("#card-rows li").length === 9, String($$("#card-rows li").length));

  $("#bulk-cancel").click(); await sleep(400);
  check("bulk-closed", !$("#bulk-backdrop").classList.contains("is-open"));
  check("focus-back", document.activeElement === $("#bulk-btn"));

  $("#bulk-btn").click(); await sleep(400);
  $("#bulk-input").value = "   \n  ";
  $("#bulk-ok").click(); await sleep(200);
  check("empty-warn", $("#bulk-feedback").textContent.includes("ни одной пары"), $("#bulk-feedback").textContent);
  $("#bulk-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(300);
  check("bulk-esc", !$("#bulk-backdrop").classList.contains("is-open"));

  check("no-errors", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));
  return JSON.stringify(res);
})()
'@
  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3
  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenario; awaitPromise = $true; returnByValue = $true }
  $results = $res.result.value | ConvertFrom-Json
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $fails = @($results | Where-Object { -not $_.ok }).Count
  Write-Output ("=== TOTAL FAILS: {0} ===" -f $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}























