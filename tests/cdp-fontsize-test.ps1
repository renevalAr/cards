param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9330 })
$udir = "$env:TEMP\opencode\cdp-fontsize-profile"
$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$url = "file:///" + ($rootDir -replace "\\","/") + "/index.html"
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
  $seedTemplate = @'
try {
  var d = new Date();
  var pad = function (n) { return String(n).padStart(2, "0"); };
  var today = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
  localStorage.setItem("flashcards-app-v1", JSON.stringify({
    decks: [{ id: "d1", name: "Основы" }],
    cards: [
      { id: "c1", deckId: "d1", question: "Вопрос для проверки размера", answer: "Ответ", status: "new" },
      { id: "c2", deckId: "d1", question: "в2", answer: "о2", status: "new" },
      { id: "c3", deckId: "d1", question: "в3", answer: "о3", status: "new" },
      { id: "c4", deckId: "d1", question: "в4", answer: "о4", status: "new" }
    ],
    selectedDeckId: "d1",
    tab: "edit",
    today: { date: today, known: 0, unknown: 0 },
    history: {},
    sessions: []
  }));
  localStorage.setItem("flashcards-onboarded", "1");
  localStorage.setItem("flashcards-palette", "ember");
  localStorage.setItem("flashcards-mode", "light");
  __FS__
} catch (e) {}
window.__errors = [];
window.addEventListener("error", function (e) { window.__errors.push((e.error && e.error.stack) || String(e.message)); });
'@
  $seed = $seedTemplate.Replace("__FS__", "")
  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Emulation.setDeviceMetricsOverride" @{ width = 1280; height = 800; deviceScaleFactor = 1; mobile = $false } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3

  $scenarioA = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const root = document.documentElement;
  const fsOf = (sel) => parseFloat(getComputedStyle($(sel)).fontSize);

  await sleep(700);
  $("#menu-close").click(); await sleep(300);

  check("default-m", root.dataset.fontsize === "m");
  $("#settings-btn").click(); await sleep(400);
  check("labels", $$("#fontsize-switch .btn").map((b) => b.textContent).join("|") === "S|M|L");
  check("m-active", $('#fontsize-switch [data-size="m"]').classList.contains("is-active"));
  const rowM = fsOf("#card-rows li");
  $("#settings-close").click(); await sleep(250);

  $("#tab-study").click(); await sleep(400);
  const faceM = fsOf(".face-text");

  $("#tab-edit").click(); await sleep(300);
  $("#settings-btn").click(); await sleep(350);
  $('#fontsize-switch [data-size="s"]').click(); await sleep(250);
  const rowS = fsOf("#card-rows li");
  check("row-scaled-down", Math.abs(rowS - rowM * 0.9) < 0.6, rowM + " -> " + rowS);
  $('#fontsize-switch [data-size="l"]').click(); await sleep(250);
  check("attr-l", root.dataset.fontsize === "l");
  check("stored-l", localStorage.getItem("flashcards-fontsize") === "l");
  check("l-active", $('#fontsize-switch [data-size="l"]').classList.contains("is-active"));
  const rowL = fsOf("#card-rows li");
  check("row-scaled-up", Math.abs(rowL - rowM * 1.1) < 0.6, rowM + " -> " + rowL);
  $("#settings-close").click(); await sleep(250);

  $("#tab-study").click(); await sleep(400);
  const faceL = fsOf(".face-text");
  check("face-scaled-up", Math.abs(faceL - faceM * 1.1) < 0.9, faceM + " -> " + faceL);

  check("no-errors-a", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []).slice(0, 200));
  return JSON.stringify(res);
})()
'@
  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioA; awaitPromise = $true; returnByValue = $true }
  $results = @()
  $results += ($res.result.value | ConvertFrom-Json)

  # Scenario B: reload with stored "l"
  Invoke-Cdp $ws "Page.reload" @{ ignoreCache = $true } | Out-Null
  Start-Sleep -Seconds 3
  $scenarioB = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const root = document.documentElement;
  await sleep(500);
  check("persist-l", root.dataset.fontsize === "l" && localStorage.getItem("flashcards-fontsize") === "l");
  check("no-errors-b", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []).slice(0, 200));
  return JSON.stringify(res);
})()
'@
  $r2 = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioB; awaitPromise = $true; returnByValue = $true }
  $results += ($r2.result.value | ConvertFrom-Json)

  # Scenario C: corrupted fontsize value -> falls back to m
  Invoke-Cdp $ws "Runtime.evaluate" @{ expression = "localStorage.setItem('flashcards-fontsize','huge'); 'ok'" } | Out-Null
  Invoke-Cdp $ws "Page.reload" @{ ignoreCache = $true } | Out-Null
  Start-Sleep -Seconds 3
  $scenarioC = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const root = document.documentElement;
  await sleep(500);
  check("bad-value-fallback-m", root.dataset.fontsize === "m", root.dataset.fontsize);
  return JSON.stringify(res);
})()
'@
  $r3 = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioC; awaitPromise = $true; returnByValue = $true }
  $results += ($r3.result.value | ConvertFrom-Json)

  $fails = @($results | Where-Object { -not $_.ok }).Count
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  Write-Output ("=== FONTSIZE TOTAL: {0} checks / {1} fails ===" -f $results.Count, $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}



















