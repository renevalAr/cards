param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9226 })
$udir = "C:\Users\Lenovo\AppData\Local\Temp\opencode\cdp-profile4"
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
    var y = new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1);
    var yesterday = y.getFullYear() + "-" + pad(y.getMonth() + 1) + "-" + pad(y.getDate());

    var history = {};
    history["d1"] = {};
    history["d1"][today] = { known: 1, unknown: 1 };
    history["d1"][yesterday] = { known: 1, unknown: 0 };
    history["d2"] = {};
    history["d2"][today] = { known: 1, unknown: 0 };

    localStorage.setItem("flashcards-app-v1", JSON.stringify({
      decks: [
        { id: "d1", name: "Английский" },
        { id: "d2", name: "География" }
      ],
      cards: [
        { id: "c1", deckId: "d1", question: "cat", answer: "кот", status: "known" },
        { id: "c2", deckId: "d1", question: "dog", answer: "собака", status: "unknown" },
        { id: "c3", deckId: "d2", question: "столица", answer: "Москва", status: "known" }
      ],
      selectedDeckId: "d1",
      tab: "edit",
      today: { date: today, known: 4, unknown: 1 },
      history: history,
      sessions: [
        { deckId: "d1", date: today, known: 2, unknown: 0 },
        { deckId: "d1", date: yesterday, known: 1, unknown: 1 },
        { deckId: "d2", date: today, known: 1, unknown: 0 }
      ]
    }));
  })();
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
  const meta = () => $("#study-meta").textContent;

  await sleep(700);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));

  $("#menu-stats-btn").click(); await sleep(500);
  check("stats-open", $("#stats-backdrop").classList.contains("is-open") && $("#menu-backdrop").classList.contains("is-open"));
  check("stats-total", $("#stats-total").textContent === "3", $("#stats-total").textContent);
  check("stats-today", $("#stats-today").textContent === "5", $("#stats-today").textContent);
  check("stats-alltime", $("#stats-alltime").textContent === "4", $("#stats-alltime").textContent);
  const items = $$("#stats-list .stats-item");
  check("stats-items", items.length === 2, String(items.length));
  check("item1", items[0].textContent.includes("Английский") && items[0].textContent.includes("2 карт"), items[0].textContent);
  check("item-bar", items[0].querySelector(".stats-bar i").style.width === "50%", items[0].querySelector(".stats-bar i").style.width);
  const days = items[0].querySelectorAll(".stats-days .stats-day");
  check("day-bars", days.length === 7, String(days.length));
  const heights = Array.from(days).map((d) => d.querySelector("i").style.height);
  check("day-activity", heights.some((h) => h !== "2px"), heights.join(","));
  check("empty-hidden", $("#stats-empty").classList.contains("hidden"));

  items[0].click(); await sleep(400);
  check("deck-detail", !$("#stats-main").classList.contains("hidden") === false && !$("#stats-deck").classList.contains("hidden"));
  check("detail-title", $("#stats-deck-title").textContent === "Английский", $("#stats-deck-title").textContent);
  const sessions = $$("#stats-sessions .session-item");
  check("sessions2", sessions.length === 2, String(sessions.length));
  const s0 = sessions[0].textContent;
  check("session-newest", s0.includes("знаю 2") && s0.includes("не знаю 0"), s0);

  $("#stats-back").click(); await sleep(300);
  check("back-main", !$("#stats-main").classList.contains("hidden") && $("#stats-deck").classList.contains("hidden"));

  $("#stats-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("stats-esc", !$("#stats-backdrop").classList.contains("is-open") && $("#menu-backdrop").classList.contains("is-open"));

  $("#menu-back-btn").click(); await sleep(500);
  check("menu-again", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-study-btn").click(); await sleep(600);
  check("study-on", !$("#menu-backdrop").classList.contains("is-open") && !$("#deck-pick-backdrop").classList.contains("is-open") && meta().includes("1 из 2"), meta());

  $("#mark-known-btn").click(); await sleep(450);
  $("#mark-known-btn").click(); await sleep(450);
  check("summary-open", $("#summary-backdrop").classList.contains("is-open"));
  $("#summary-stats").click(); await sleep(500);
  check("stats-from-summary", $("#stats-backdrop").classList.contains("is-open") && !$("#summary-backdrop").classList.contains("is-open"));

  var d = new Date();
  var pad = function (n) { return String(n).padStart(2, "0"); };
  var todayKey = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
  check("sessions-grew", state.sessions.filter(function (s) { return s.deckId === "d1"; }).length === 3, String(state.sessions.length));
  check("history-grew", state.history["d1"][todayKey].known === 3, JSON.stringify(state.history["d1"][todayKey]));

  $("#stats-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("stats-close2", !$("#stats-backdrop").classList.contains("is-open"));

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





















