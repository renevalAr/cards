param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9225 })
$udir = "$env:TEMP\opencode\cdp-profile3"
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
  localStorage.setItem("flashcards-app-v1", JSON.stringify({
    decks: [ { id: "d1", name: "Английский" } ],
    cards: [
      { id: "c1", deckId: "d1", question: "cat", answer: "кот", status: "new" },
      { id: "c2", deckId: "d1", question: "dog", answer: "собака", status: "new" }
    ],
    selectedDeckId: "d1",
    tab: "edit",
    today: { date: "2026-08-20", known: 0, unknown: 0 }
  }));
  localStorage.setItem("flashcards-onboarded", "1");
  localStorage.setItem("flashcards-palette", "ember");
  localStorage.setItem("flashcards-mode", "light");
} catch (e) {}
window.__errors = [];
window.addEventListener("error", function (e) { window.__errors.push((e.error && e.error.stack) || String(e.message)); });
'@

  $scenario = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const meta = () => $("#study-meta").textContent;

  await sleep(700);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));

  $("#menu-study-btn").click(); await sleep(600);
  check("study-on", !$("#menu-backdrop").classList.contains("is-open") && !$("#study-board").classList.contains("hidden"));
  check("meta1", meta().includes("1 из 2"), meta());

  $("#mark-known-btn").click(); await sleep(500);
  check("meta2", meta().includes("2 из 2"), meta());
  $("#mark-known-btn").click(); await sleep(500);
  check("summary-open", $("#summary-backdrop").classList.contains("is-open"));
  const line = $("#summary-line").textContent;
  check("line-known", line.includes("Всего 2") && line.includes("знаю 2") && line.includes("не знаю 0"), line);
  check("fill100", $("#summary-fill").style.width === "100%", $("#summary-fill").style.width);
  check("repeat-all", $("#summary-repeat").textContent === "Пройти ещё раз", $("#summary-repeat").textContent);

  $("#summary-repeat").click(); await sleep(500);
  check("repeat-closed", !$("#summary-backdrop").classList.contains("is-open"));
  check("repeat-meta", meta().includes("1 из 2"), meta());

  $("#mark-unknown-btn").click(); await sleep(500);
  check("u2", meta().includes("2 из 2"), meta());
  $("#mark-unknown-btn").click(); await sleep(500);
  const line2 = $("#summary-line").textContent;
  check("line-unknown", line2.includes("знаю 0") && line2.includes("не знаю 2"), line2);
  check("fill0", $("#summary-fill").style.width === "0%", $("#summary-fill").style.width);
  check("repeat-unknown", $("#summary-repeat").textContent === "Повторить неизученное", $("#summary-repeat").textContent);

  $("#summary-repeat").click(); await sleep(500);
  check("repeat2-meta", meta().includes("1 из 2"), meta());
  $("#mark-known-btn").click(); await sleep(500);
  $("#mark-known-btn").click(); await sleep(500);
  const line3 = $("#summary-line").textContent;
  check("line3", line3.includes("знаю 2") && line3.includes("не знаю 0"), line3);

  $("#summary-menu").click(); await sleep(600);
  check("to-menu", $("#menu-backdrop").classList.contains("is-open") && !$("#summary-backdrop").classList.contains("is-open"));
  const today = $("#menu-today-stats").textContent;
  check("today6", today.includes("изучено 6"), today);

  $("#menu-study-btn").click(); await sleep(600);
  $("#flashcard").click(); await sleep(400);
  $("#next-card-btn").click(); await sleep(400);
  $("#flashcard").click(); await sleep(400);
  $("#next-card-btn").click(); await sleep(500);
  check("flip-summary", $("#summary-backdrop").classList.contains("is-open"));
  const line4 = $("#summary-line").textContent;
  check("flip-line", line4.includes("знаю 0") && line4.includes("не знаю 2"), line4);

  $("#summary-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(500);
  check("esc-to-menu", !$("#summary-backdrop").classList.contains("is-open") && $("#menu-backdrop").classList.contains("is-open"));

  check("no-errors", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));

  return JSON.stringify(res);
})()
'@

  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3

  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenario; awaitPromise = $true; returnByValue = $true }
  Write-Output $res.result.value
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}

























