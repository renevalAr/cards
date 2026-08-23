param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9241 })
$udir = "C:\Users\Lenovo\AppData\Local\Temp\opencode\cdp-spacing-profile"
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
  $seed = @'
try {
  (function () {
    var d = new Date();
    var pad = function (n) { return String(n).padStart(2, "0"); };
    var day = function (offset) { var x = new Date(d.getFullYear(), d.getMonth(), d.getDate() - offset); return x.getFullYear() + "-" + pad(x.getMonth() + 1) + "-" + pad(x.getDate()); };
    localStorage.setItem("flashcards-app-v1", JSON.stringify({
      decks: [{ id: "d1", name: "Основы" }],
      cards: [{ id: "c1", deckId: "d1", question: "1+1", answer: "2", status: "new" }],
      selectedDeckId: "d1",
      tab: "edit",
      today: { date: day(0), known: 0, unknown: 0 },
      history: { d1: { [day(0)]: { known: 2, unknown: 0 }, [day(1)]: { known: 3, unknown: 0 } } },
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
  const gap = (a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().bottom;
  const round = (n) => Math.round(n * 10) / 10;

  await sleep(900);
  // Menu theme section spacing
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));
  const subject = $(".menu-theme .subject");
  const sw = $("#menu-mode-switch");
  const dots = $("#menu-theme-dots");
  const g1 = round(gap(subject, sw));
  const g2 = round(gap(sw, dots));
  check("menu-subject-switch", g1 >= 10, String(g1));
  check("menu-switch-dots", g2 >= 12, String(g2));

  // Streak visible (2 days) and has top margin
  const streak = $("#menu-streak");
  check("streak-shown", !streak.hidden, String(streak.hidden));
  check("streak-margin", getComputedStyle(streak).marginTop === "8px", getComputedStyle(streak).marginTop);
  check("streak-text", streak.textContent.includes("2 дня"), streak.textContent);
  const gStreak = round(gap($("#menu-today-stats"), streak));
  check("streak-gap", gStreak >= 8, String(gStreak));

  // Rename modal spacing
  $("#menu-close").click(); await sleep(400);
  $("#rename-deck-btn").click(); await sleep(400);
  check("rename-open", $("#modal-backdrop").classList.contains("is-open"));
  const gTxt = round(gap($("#modal-text"), $("#modal-field")));
  const gFld = round(gap($("#modal-input"), $("#modal-backdrop .form-actions")));
  const gTitle = round(gap($("#modal-kicker"), $("#modal-title")));
  check("rename-title-gap", gTitle >= 6, String(gTitle));
  check("rename-text-field", gTxt >= 14, String(gTxt));
  check("rename-field-btns", gFld >= 18, String(gFld));
  $("#modal-cancel").click(); await sleep(400);

  // Settings modal: label "Цвет" after mode switch
  $("#settings-btn").click(); await sleep(400);
  const labels = Array.from(document.querySelectorAll("#settings-backdrop .setting-label"));
  const colorLabel = labels[1];
  const gLabel = round(gap($("#settings-backdrop #mode-switch"), colorLabel));
  check("settings-label-gap", gLabel >= 16, String(gLabel));
  $("#settings-close").click(); await sleep(400);

  check("no-errors", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));
  return JSON.stringify(res);
})()
'@
  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3
  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenario; awaitPromise = $true; returnByValue = $true }
  Write-Output "=== SPACING ==="
  $results = $res.result.value | ConvertFrom-Json
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $fails = @($results | Where-Object { -not $_.ok }).Count
  Write-Output ("=== SPACING TOTAL: {0} checks / {1} fails ===" -f $results.Count, $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}























