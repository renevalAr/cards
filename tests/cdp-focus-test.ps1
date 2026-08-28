param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9230 })
$udir = "$env:TEMP\opencode\cdp-focus-profile"
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
      decks: [{ id: "d1", name: "Английский" }],
      cards: [
        { id: "c1", deckId: "d1", question: "cat", answer: "кот", status: "known" },
        { id: "c2", deckId: "d1", question: "dog", answer: "собака", status: "unknown" },
        { id: "c3", deckId: "d1", question: "bird", answer: "птица", status: "unknown" }
      ],
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
  const inFocus = () => $("#flashcard").parentElement && $("#flashcard").parentElement.id === "focus-wrap";
  const atHome = () => $("#flashcard").parentElement && $("#flashcard").parentElement.classList.contains("flashcard-wrap");

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));

  // Start study (single deck with cards -> direct)
  $("#menu-study-btn").click(); await sleep(600);
  check("study-on", $("#study-meta").textContent.includes("1 из 3"), $("#study-meta").textContent);

  // Enter focus mode
  $("#focus-btn").click(); await sleep(400);
  check("focus-open", $("#focus-backdrop").classList.contains("is-open"));
  check("card-in-focus", inFocus());
  check("focus-meta", $("#focus-meta").textContent.includes("1 из 3"), $("#focus-meta").textContent);
  check("focus-active", document.activeElement === $("#flashcard"));

  // Flip inside focus
  $("#flashcard").click(); await sleep(200);
  check("focus-flipped", $("#flashcard").classList.contains("is-flipped"));
  check("focus-unknown-pressed", $("#focus-unknown").getAttribute("aria-pressed") === "true", $("#focus-unknown").getAttribute("aria-pressed"));

  // Mark unknown (card1 stays unknown) -> advances to card 2, still in focus
  $("#focus-unknown").click(); await sleep(550);
  check("focus-advance", $("#focus-meta").textContent.includes("2 из 3"), $("#focus-meta").textContent);
  check("card-still-in-focus", inFocus());

  // Exit via Escape
  $("#focus-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("focus-esc", !$("#focus-backdrop").classList.contains("is-open"));
  check("card-home-esc", atHome());

  // Re-enter, exit via backdrop click
  $("#focus-btn").click(); await sleep(400);
  check("focus-reopen", $("#focus-backdrop").classList.contains("is-open") && inFocus());
  $("#focus-backdrop").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
  await sleep(400);
  check("focus-backdrop-click", !$("#focus-backdrop").classList.contains("is-open") && atHome());

  // Re-enter, complete the round from focus mode (card2 known, card3 known)
  $("#focus-btn").click(); await sleep(400);
  $("#focus-known").click(); await sleep(550); // card 2 -> 3
  check("focus-meta3", $("#focus-meta").textContent.includes("3 из 3"), $("#focus-meta").textContent);
  $("#focus-known").click(); await sleep(550); // card 3 -> complete
  check("summary-open", $("#summary-backdrop").classList.contains("is-open"));
  check("focus-stays-open", $("#focus-backdrop").classList.contains("is-open"));
  check("card-in-focus-summary", !atHome() && $("#focus-wrap").contains($("#flashcard")));
  check("summary-over-focus", $("#summary-backdrop").style.zIndex === "66", $("#summary-backdrop").style.zIndex);
  check("summary-line", $("#summary-line").textContent === "Всего 3 · знаю 2 · не знаю 1", $("#summary-line").textContent);

  // Back to menu (exits focus), restart, focus, exit via close button, panel meta intact
  $("#summary-menu").click(); await sleep(500);
  check("menu-again", $("#menu-backdrop").classList.contains("is-open") && atHome());
  $("#menu-study-btn").click(); await sleep(600);
  check("study-again", $("#study-meta").textContent.includes("1 из 3"), $("#study-meta").textContent);
  $("#focus-btn").click(); await sleep(400);
  $("#focus-exit").click(); await sleep(400);
  check("exit-btn", !$("#focus-backdrop").classList.contains("is-open") && atHome());
  check("panel-meta", $("#study-meta").textContent.includes("1 из 3"), $("#study-meta").textContent);

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




































