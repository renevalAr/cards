param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9320 })
$udir = "C:\Users\Lenovo\AppData\Local\Temp\opencode\cdp-autotheme-profile"
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
  function Set-Scheme($ws, [string]$value) {
    Invoke-Cdp $ws "Emulation.setEmulatedMedia" @{ features = @(@{ name = "prefers-color-scheme"; value = $value }) } | Out-Null
  }
  $seed = @'
try {
  var d = new Date();
  var pad = function (n) { return String(n).padStart(2, "0"); };
  var today = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
  localStorage.setItem("flashcards-app-v1", JSON.stringify({
    decks: [{ id: "d1", name: "Основы" }],
    cards: [{ id: "c1", deckId: "d1", question: "в", answer: "о", status: "new" }],
    selectedDeckId: "d1",
    tab: "edit",
    today: { date: today, known: 0, unknown: 0 },
    history: {},
    sessions: []
  }));
  localStorage.setItem("flashcards-onboarded", "1");
  localStorage.setItem("flashcards-palette", "ember");
  localStorage.setItem("flashcards-mode", "auto");
} catch (e) {}
window.__errors = [];
window.addEventListener("error", function (e) { window.__errors.push((e.error && e.error.stack) || String(e.message)); });
'@
  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Set-Scheme $ws "dark"
  Invoke-Cdp $ws "Emulation.setDeviceMetricsOverride" @{ width = 1280; height = 800; deviceScaleFactor = 1; mobile = $false } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 1
  Start-Sleep -Milliseconds 500
  Set-Scheme $ws "dark"
  Start-Sleep -Seconds 2

  $scenarioA = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const root = document.documentElement;
  await sleep(700);
  check("boot-dark-auto", root.dataset.mode === "dark" && root.dataset.modePref === "auto", root.dataset.mode + "/" + root.dataset.modePref);
  check("switch3-settings", $$("#mode-switch .btn").map((b) => b.textContent).join("|") === "Светлая|Тёмная|Авто");
  check("switch3-menu", $$("#menu-mode-switch .btn").map((b) => b.textContent).join("|") === "Светлая|Тёмная|Авто");
  check("auto-active", $('#mode-switch [data-mode="auto"]').classList.contains("is-active") && $('#menu-mode-switch [data-mode="auto"]').classList.contains("is-active"));
  $("#menu-close").click(); await sleep(300);
  return JSON.stringify(res);
})()
'@
  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioA; awaitPromise = $true; returnByValue = $true }
  $results = @()
  $results += ($res.result.value | ConvertFrom-Json)

  Set-Scheme $ws "light"
  Start-Sleep -Milliseconds 500
  $scenarioB = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const root = document.documentElement;
  await sleep(150);
  check("sys-value-light", !window.matchMedia("(prefers-color-scheme: dark)").matches);
  applyAppearance({ mode: "auto" }, { clientX: window.innerWidth / 2, clientY: window.innerHeight / 2 });
  await sleep(600);
  check("follows-light", root.dataset.mode === "light" && root.dataset.modePref === "auto", root.dataset.mode);
  const bloom = $("#theme-bloom");
  check("bloom-coords", bloom.style.getPropertyValue("--bloom-x") !== "", bloom.style.cssText);
  check("stored-still-auto", localStorage.getItem("flashcards-mode") === "auto");
  return JSON.stringify(res);
})()
'@
  $r2 = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioB; awaitPromise = $true; returnByValue = $true }
  $results += ($r2.result.value | ConvertFrom-Json)

  $scenarioC = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const root = document.documentElement;
  $("#settings-btn").click(); await sleep(400);
  $('#mode-switch [data-mode="dark"]').click(); await sleep(600);
  check("manual-dark", root.dataset.modePref === "dark" && root.dataset.mode === "dark");
  check("manual-active-btn", $('#mode-switch [data-mode="dark"]').classList.contains("is-active"));
  return JSON.stringify(res);
})()
'@
  $r3 = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioC; awaitPromise = $true; returnByValue = $true }
  $results += ($r3.result.value | ConvertFrom-Json)

  Set-Scheme $ws "light"
  Start-Sleep -Milliseconds 400
  Set-Scheme $ws "dark"
  Start-Sleep -Milliseconds 400
  Set-Scheme $ws "light"
  Start-Sleep -Milliseconds 500
  $scenarioD = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const root = document.documentElement;
  await sleep(200);
  check("manual-holds", root.dataset.modePref === "dark" && root.dataset.mode === "dark");
  $('#mode-switch [data-mode="auto"]').click(); await sleep(600);
  check("auto-resumed-light", root.dataset.modePref === "auto" && root.dataset.mode === "light", root.dataset.mode);
  $("#settings-close").click(); await sleep(300);
  check("no-errors", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []).slice(0, 200));
  return JSON.stringify(res);
})()
'@
  $r4 = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioD; awaitPromise = $true; returnByValue = $true }
  $results += ($r4.result.value | ConvertFrom-Json)

  Set-Scheme $ws "dark"
  Invoke-Cdp $ws "Page.reload" @{ ignoreCache = $true } | Out-Null
  Start-Sleep -Seconds 3
  Start-Sleep -Milliseconds 600
  $scenarioE = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const root = document.documentElement;
  await sleep(300);
  check("persist-auto", localStorage.getItem("flashcards-mode") === "auto" && root.dataset.modePref === "auto");
  check("persist-follows-dark", root.dataset.mode === "dark", root.dataset.mode);
  return JSON.stringify(res);
})()
'@
  $r5 = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioE; awaitPromise = $true; returnByValue = $true }
  $results += ($r5.result.value | ConvertFrom-Json)

  $fails = @($results | Where-Object { -not $_.ok }).Count
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  Write-Output ("=== AUTOTHEME TOTAL: {0} checks / {1} fails ===" -f $results.Count, $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}























