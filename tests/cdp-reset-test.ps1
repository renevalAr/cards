param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9234 })
$udir = "$env:TEMP\opencode\cdp-reset-profile"
$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$url = "file:///" + ($rootDir -replace "\\","/") + "/index.html"

if (Test-Path $udir) { Remove-Item -Recurse -Force $udir }

$proc = Start-Process $chrome -ArgumentList @(
  "--headless=new",
  "--remote-debugging-port=$port",
  "--user-data-dir=$udir",
  
  "--disable-gpu",
  "--no-first-run",
  "about:blank"
) -PassThru -WindowStyle Hidden

$ws = $null
try {
  Start-Sleep -Seconds 2
  $list = Invoke-RestMethod "http://127.0.0.1:$port/json/list"
  $page = $list | Where-Object { $_.type -eq "page" } | Select-Object -First 1
  $wsUrl = $page.webSocketDebuggerUrl

  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ct = [System.Threading.CancellationToken]::None
  $ws.ConnectAsync([Uri]$wsUrl, $ct).GetAwaiter().GetResult() | Out-Null

  $script:id = 0

  function Send-Ws([System.Net.WebSockets.ClientWebSocket]$ws, [string]$json) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList (,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
  }

  function Receive-Ws([System.Net.WebSockets.ClientWebSocket]$ws) {
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

  function Invoke-Cdp([System.Net.WebSockets.ClientWebSocket]$ws, [string]$method, $params) {
    $script:id += 1
    $id = $script:id
    if ($null -eq $params) { $params = @{} }
    $payload = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 30
    Send-Ws $ws $payload
    while ($true) {
      $msg = Receive-Ws $ws
      $obj = $msg | ConvertFrom-Json
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
      decks: [
        { id: "d1", name: "Английский" },
        { id: "d2", name: "География" }
      ],
      cards: [
        { id: "c1", deckId: "d1", question: "cat", answer: "кот", status: "known" },
        { id: "c2", deckId: "d1", question: "dog", answer: "собака", status: "unknown" },
        { id: "c3", deckId: "d1", question: "bird", answer: "птица", status: "new" },
        { id: "c4", deckId: "d2", question: "столица", answer: "Москва", status: "known" }
      ],
      selectedDeckId: "d1",
      tab: "edit",
      today: { date: today, known: 2, unknown: 1 },
      history: { d1: {}, d2: {} },
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
  const d1 = () => state.cards.filter((c) => c.deckId === "d1");
  const d2 = () => state.cards.filter((c) => c.deckId === "d2");

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));

  // Open deck picker, then actions for first deck
  $("#menu-cards-btn").click(); await sleep(400);
  $$("#deck-pick-list .deck-pick-item")[0].querySelector(".deck-pick-more").click(); await sleep(400);
  const labels = $$("#menu-pop-actions button").map((b) => b.textContent);
  check("pop-has-reset", labels.includes("Начать заново"), labels.join("|"));
  check("pop-btns7", labels.length === 7, String(labels.length));

  // Click "Начать заново" (index 3)
  [...document.querySelectorAll("#menu-pop-actions button")].find(b=>b.textContent.includes("заново")).click(); await sleep(400);
  check("confirm-open", $("#modal-backdrop").classList.contains("is-open"));
  check("confirm-title", $("#modal-title").textContent === "Начать заново?", $("#modal-title").textContent);
  check("confirm-kicker", $("#modal-kicker").textContent === "прогресс", $("#modal-kicker").textContent);
  check("confirm-text", $("#modal-text").textContent.includes("сброшены"), $("#modal-text").textContent);
  check("confirm-btn", $("#modal-ok").textContent === "Сбросить", $("#modal-ok").textContent);
  check("confirm-no-input", $("#modal-field").classList.contains("hidden"));

  // Confirm reset
  $("#modal-ok").click(); await sleep(500);
  check("modal-closed", !$("#modal-backdrop").classList.contains("is-open"));
  check("all-new", d1().every((c) => c.status === "new"), JSON.stringify(d1().map((c) => c.status)));
  check("other-deck-intact", d2().every((c) => c.status === "known"));
  check("header-stats", $("#stats").textContent === "Всего 3 · знаю 0 · не знаю 0", $("#stats").textContent);
  const badges = $$("#card-rows .badge").map((b) => b.textContent);
  check("row-badges", badges.length === 3 && badges.every((b) => b === "новая"), badges.join("|"));

  // Cancel path: reset again, cancel, nothing changes
  $("#menu-back-btn").click(); await sleep(400);
  $("#menu-cards-btn").click(); await sleep(400);
  $$("#deck-pick-list .deck-pick-item")[0].querySelector(".deck-pick-more").click(); await sleep(400);
  [...document.querySelectorAll("#menu-pop-actions button")].find(b=>b.textContent.includes("заново")).click(); await sleep(400);
  check("confirm2", $("#modal-backdrop").classList.contains("is-open"));
  $("#modal-cancel").click(); await sleep(400);
  check("cancel-closed", !$("#modal-backdrop").classList.contains("is-open"));
  check("still-new", d1().every((c) => c.status === "new"), JSON.stringify(d1().map((c) => c.status)));

  check("no-errors", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));

  return JSON.stringify(res);
})()
'@

  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3

  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenario; awaitPromise = $true; returnByValue = $true }
  if ($res.exceptionDetails) { Write-Output ("R EXC: " + $res.exceptionDetails.exception.description) }
  $results = $res.result.value | ConvertFrom-Json
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $fails = @($results | Where-Object { -not $_.ok }).Count
  Write-Output ("=== TOTAL FAILS: {0} ===" -f $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}


























