param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9232 })
$udir = "$env:TEMP\opencode\cdp-library-profile"
$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$url = "file:///" + ($rootDir -replace "\\","/") + "/frontend/index.html"

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
  localStorage.removeItem("flashcards-app-v1");
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
  const coverFits = () => $(".menu-cover").scrollHeight <= window.innerHeight;

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));
  check("menu-fits", coverFits(), "sh=" + $(".menu-cover").scrollHeight + " vh=" + window.innerHeight);
  check("library-btn", !!$("#menu-library-btn") && $("#menu-library-btn").textContent === "Библиотека");

  // Open library
  $("#menu-library-btn").click(); await sleep(400);
  check("lib-open", $("#library-backdrop").classList.contains("is-open"));
  const items = $$("#library-list .library-item");
  check("lib-items", items.length === 3, String(items.length));
  check("lib-names", items[0].textContent.includes("Английский") && items[1].textContent.includes("Столицы") && items[2].textContent.includes("элементов"), items.map((i) => i.querySelector(".library-name").textContent).join("|"));
  check("lib-counts", items[0].textContent.includes("30 карточек") && items[1].textContent.includes("12 карточек") && items[2].textContent.includes("15 карточек"));
  check("lib-hint", $("#library-hint") === null || $("#library-hint").textContent.length > 0);
  check("lib-focus-modal", $("#library-backdrop").querySelector(".modal") === document.activeElement);

  // Escape closes library, menu stays
  $("#library-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("lib-esc", !$("#library-backdrop").classList.contains("is-open"));
  check("menu-still-open", $("#menu-backdrop").classList.contains("is-open"));

  // Add first demo deck
  $("#menu-library-btn").click(); await sleep(400);
  $$("#library-list .library-item")[0].querySelector("button").click(); await sleep(500);
  check("lib-closed", !$("#library-backdrop").classList.contains("is-open"));
  check("deck-added", state.decks.length === 1 && state.decks[0].name === "Английский · старт", JSON.stringify(state.decks.map((d) => d.name)));
  const d1 = state.decks[0];
  check("cards30", state.cards.filter((c) => c.deckId === d1.id).length === 30, String(state.cards.filter((c) => c.deckId === d1.id).length));
  check("all-new", state.cards.every((c) => c.deckId === d1.id && c.status === "new"));
  check("selected", state.selectedDeckId === d1.id && state.tab === "edit");
  check("workspace", !$("#workspace").classList.contains("hidden") && $("#deck-title").textContent === "Английский · старт", $("#deck-title").textContent);

  // Add second demo deck from menu
  $("#menu-back-btn").click(); await sleep(400);
  $("#menu-library-btn").click(); await sleep(400);
  $$("#library-list .library-item")[1].querySelector("button").click(); await sleep(500);
  check("decks2", state.decks.length === 2, String(state.decks.length));
  check("cards42", state.cards.length === 42, String(state.cards.length));

  // Back to menu: fits without scroll, library reachable
  $("#menu-back-btn").click(); await sleep(400);
  check("menu-fits2", coverFits(), "sh=" + $(".menu-cover").scrollHeight + " vh=" + window.innerHeight);
  $("#menu-library-btn").click(); await sleep(400);
  check("lib-reopen", $("#library-backdrop").classList.contains("is-open"));
  $("#library-cancel").click(); await sleep(400);
  check("lib-cancel", !$("#library-backdrop").classList.contains("is-open"));

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




















