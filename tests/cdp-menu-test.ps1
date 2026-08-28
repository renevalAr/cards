param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9223 })
$udir = "$env:TEMP\opencode\cdp-profile"
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
  var __d = new Date();
  var __dk = __d.getFullYear() + "-" + String(__d.getMonth() + 1).padStart(2, "0") + "-" + String(__d.getDate()).padStart(2, "0");
  localStorage.setItem("flashcards-app-v1", JSON.stringify({
    decks: [
      { id: "d1", name: "Английский" },
      { id: "d2", name: "География" }
    ],
    cards: [
      { id: "c1", deckId: "d1", question: "cat", answer: "кот", status: "known" },
      { id: "c2", deckId: "d1", question: "dog", answer: "собака", status: "unknown" },
      { id: "c3", deckId: "d2", question: "столица России", answer: "Москва", status: "known" }
    ],
    selectedDeckId: "d1",
    tab: "menu",
    today: { date: __dk, known: 2, unknown: 1 }
  }));
  localStorage.removeItem("flashcards-onboarded");
  localStorage.setItem("flashcards-palette", "ember");
  localStorage.setItem("flashcards-mode", "light");
} catch (e) {}
window.__errors = [];
window.addEventListener("error", function (e) { window.__errors.push((e.error && e.error.stack) || (e.message + " @ " + (e.filename || "") + ":" + (e.lineno || ""))); });
'@

  $scenario = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => Array.from(document.querySelectorAll(s));

  await sleep(700);

  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));
  const cover = $(".menu-cover");
  check("cover-fits", cover.scrollHeight <= cover.clientHeight + 1, "sh=" + cover.scrollHeight + " ch=" + cover.clientHeight);
  const today = $("#menu-today-stats").textContent;
  check("today", today.includes("изучено 3") && today.includes("знаю 2"), today);
  const bg = getComputedStyle($("#menu-backdrop")).backgroundImage;
  check("pattern-bg", bg.includes("radial-gradient") && bg.includes("linear-gradient"), bg.slice(0, 90));
  check("tour-visible", $("#tour-tip").hidden === false);
  check("tour-text", $("#tour-text").textContent.length > 0);

  for (let i = 0; i < 4; i++) { $("#tour-next").click(); await sleep(80); }
  check("tour-done", $("#tour-tip").hidden === true);
  check("tour-flag", localStorage.getItem("flashcards-onboarded") === "1");

  $("#menu-cards-btn").click(); await sleep(500);
  check("picker-open", $("#deck-pick-backdrop").classList.contains("is-open"));
  check("picker-title", $("#deck-pick-title").textContent === "Колоды", $("#deck-pick-title").textContent);
  const items = $$("#deck-pick-list .deck-pick-item");
  check("picker-count", items.length === 2, String(items.length));
  check("picker-active", !!$("#deck-pick-list .deck-pick-item.is-active"));
  check("picker-c1", items[0].textContent.includes("Английский") && items[0].textContent.includes("2 карт"), items[0].textContent);
  check("picker-c2", items[1].textContent.includes("География") && items[1].textContent.includes("1 карт"), items[1].textContent);
  const bar = items[0].querySelector(".deck-pick-bar i");
  check("picker-bar", !!bar && bar.style.width === "50%", bar ? bar.style.width : "no bar");

  items[0].querySelector(".deck-pick-more").click(); await sleep(400);
  check("pop-open", $("#menu-pop-backdrop").classList.contains("is-open"));
  check("pop-title", $("#menu-pop-title").textContent === "Английский", $("#menu-pop-title").textContent);
  const popBtns = $$("#menu-pop-actions button");
  check("pop-btns", popBtns.length === 7 && popBtns[0].textContent.includes("Учить колоду") && popBtns[5].textContent.includes("Начать заново") && popBtns[6].textContent.includes("Удалить"), popBtns.map((b) => b.textContent).join("|"));;

  $("#menu-pop-cancel").click(); await sleep(400);
  check("pop-closed", !$("#menu-pop-backdrop").classList.contains("is-open"));

  $("#deck-pick-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("picker-esc", !$("#deck-pick-backdrop").classList.contains("is-open"));
  check("menu-still-open", $("#menu-backdrop").classList.contains("is-open"));

  $("#menu-study-btn").click(); await sleep(600);
  check("study-started", !$("#menu-backdrop").classList.contains("is-open") && !$("#study-board").classList.contains("hidden"));
  check("study-meta", $("#study-meta").textContent.includes("2"), $("#study-meta").textContent);

  $("#menu-back-btn").click(); await sleep(500);
  check("menu-reopen", $("#menu-backdrop").classList.contains("is-open"));

  const bgBefore = getComputedStyle($("#menu-backdrop")).backgroundImage;
  $('.theme-dot[data-palette="sea"]').click(); await sleep(800);
  const bgAfter = getComputedStyle($("#menu-backdrop")).backgroundImage;
  check("theme-switch", document.documentElement.dataset.palette === "sea" && bgAfter !== bgBefore, document.documentElement.dataset.palette);

  const cover2 = $(".menu-cover");
  check("cover-fits2", cover2.scrollHeight <= cover2.clientHeight + 1, "sh=" + cover2.scrollHeight + " ch=" + cover2.clientHeight);

  $("#menu-settings-btn").click(); await sleep(500);
  check("settings-over-menu", $("#settings-backdrop").classList.contains("is-open") && $("#menu-backdrop").classList.contains("is-open"));
  const szi = parseInt(getComputedStyle($("#settings-backdrop")).zIndex, 10);
  const mzi = parseInt(getComputedStyle($("#menu-backdrop")).zIndex, 10);
  check("settings-z-above", szi > mzi, szi + " vs " + mzi);
  $("#settings-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("settings-esc", !$("#settings-backdrop").classList.contains("is-open") && $("#menu-backdrop").classList.contains("is-open"));

  $("#menu-backdrop").click(); await sleep(400);
  check("menu-close", !$("#menu-backdrop").classList.contains("is-open"));

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
































