param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9242 })
$udir = "$env:TEMP\opencode\cdp-pattern-profile"
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
    cards: [ { id: "c1", deckId: "d1", question: "cat", answer: "кот", status: "new" } ],
    selectedDeckId: "d1",
    tab: "menu",
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
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const palettes = ["ember", "sea", "moss", "berry", "violet", "gold", "crimson", "teal", "slate", "indigo"];
  try {

  await sleep(700);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));

  const baseFont = getComputedStyle($(".menu-cover .subject")).fontFamily;
  const fonts = new Set();
  const studies = new Set();
  const dots = new Set();
  const modes = new Set();
  for (const p of palettes) {
    $('.theme-dot[data-palette="' + p + '"]').click();
    await sleep(650);
    fonts.add(getComputedStyle($(".menu-cover .subject")).fontFamily);
    studies.add(getComputedStyle($("#menu-study-btn")).backgroundImage);
    const active = $(".theme-dot.is-active");
    dots.add(getComputedStyle(active).backgroundImage);
    modes.add(getComputedStyle($("#menu-mode-switch .btn.is-active")).backgroundImage);
    check("pal-" + p, document.documentElement.dataset.palette === p, document.documentElement.dataset.palette);
  }
  check("font-stable", fonts.size === 1 && fonts.has(baseFont), [...fonts].join(" | "));
  check("study-patterned", [...studies].every((s) => s !== "none"), [...studies].join(" | ").slice(0, 60));
  check("study-unique", studies.size === palettes.length, String(studies.size));
  check("dot-patterned", [...dots].every((s) => s !== "none"), [...dots].join(" | ").slice(0, 60));
  check("dot-unique", dots.size === palettes.length, String(dots.size));
  check("mode-patterned", [...modes].every((s) => s !== "none"), [...modes].join(" | ").slice(0, 60));
  check("mode-unique", modes.size === palettes.length, String(modes.size));

  $('[data-mode="dark"]').click();
  await sleep(650);
  check("dark-mode", document.documentElement.dataset.mode === "dark");
  check("dark-study", getComputedStyle($("#menu-study-btn")).backgroundImage !== "none");
  check("dark-dot", getComputedStyle($(".theme-dot.is-active")).backgroundImage !== "none");

  $("#menu-cards-btn").click();
  await sleep(400);
  const items = $$("#deck-pick-list .deck-pick-item");
  check("picker", items.length === 1, String(items.length));
    items[0].querySelector(".deck-pick-more").click();
  await sleep(400);
  const popBtn = $("#menu-pop-actions .btn-primary");
  check("popup-study-pattern", !!popBtn && getComputedStyle(popBtn).backgroundImage !== "none", popBtn ? getComputedStyle(popBtn).backgroundImage.slice(0, 60) : "no-btn");

  check("no-errors", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));

  } catch (e) {
    check("scenario-error", false, String(e));
  }
  return JSON.stringify(res);
})()
'@

  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3

  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenario; awaitPromise = $true; returnByValue = $true }
  if ($res.exceptionDetails) {
    Write-Output ("EXC: " + $res.exceptionDetails.exception.description)
  } else {
    Write-Output $res.result.value
  }
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}






















