param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9239 })
$udir = "C:\Users\Lenovo\AppData\Local\Temp\opencode\cdp-extra-profile"
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
  if (sessionStorage.getItem("use-empty") === "1") {
    localStorage.removeItem("flashcards-app-v1");
  } else if (!localStorage.getItem("flashcards-app-v1")) {
    (function () {
      var d = new Date();
      var pad = function (n) { return String(n).padStart(2, "0"); };
      var today = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
      localStorage.setItem("flashcards-app-v1", JSON.stringify({
        decks: [{ id: "d1", name: "Основы" }],
        cards: [
          { id: "c1", deckId: "d1", question: "1+1", answer: "2", status: "new" },
          { id: "c2", deckId: "d1", question: "цвет неба", answer: "голубой", status: "new" }
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
  }
} catch (e) {}
window.__errors = [];
window.addEventListener("error", function (e) { window.__errors.push((e.error && e.error.stack) || String(e.message)); });
window.addEventListener("unhandledrejection", function (e) { window.__errors.push(String(e.reason)); });
'@
  $scenarioA = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const meta = () => $("#study-meta").textContent;
  const deckCards = () => state.cards.filter((c) => c.deckId === state.selectedDeckId);

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);

  // Keyboard tab switching
  document.querySelector(".tabs").dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true, cancelable: true }));
  await sleep(400);
  check("tab-kbd-right", $("#tab-study").classList.contains("is-active") && $("#tab-study").getAttribute("aria-selected") === "true" && !$("#panel-study").classList.contains("hidden"));
  document.querySelector(".tabs").dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true, cancelable: true }));
  await sleep(400);
  check("tab-kbd-left", $("#tab-edit").classList.contains("is-active") && $("#tab-edit").getAttribute("aria-selected") === "true" && !$("#panel-edit").classList.contains("hidden"));

  // Ctrl+Enter submits the card form
  $("#card-question").value = "столица Франции";
  $("#card-answer").value = "Париж";
  $("#card-form").dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", ctrlKey: true, bubbles: true, cancelable: true }));
  await sleep(400);
  check("ctrl-enter-add", deckCards().length === 3 && $("#card-question").value === "", String(deckCards().length));

  // Study + focus prev/next navigation
  $("#tab-study").click(); await sleep(400);
  check("study-3", meta().includes("1 из 3"), meta());
  $("#focus-btn").click(); await sleep(400);
  check("focus-open", $("#focus-backdrop").classList.contains("is-open"));
  $("#focus-next").click(); await sleep(500);
  check("focus-next-meta", $("#focus-meta").textContent.includes("2 из 3"), $("#focus-meta").textContent);
  $("#focus-prev").click(); await sleep(500);
  check("focus-prev-meta", $("#focus-meta").textContent.includes("1 из 3"), $("#focus-meta").textContent);
  $("#focus-exit").click(); await sleep(400);
  check("focus-closed", !$("#focus-backdrop").classList.contains("is-open"));

  // Complete round: mark known on all 3 (no flips)
  $("#mark-known-btn").click(); await sleep(500);
  check("k1", meta().includes("2 из 3"), meta());
  $("#mark-known-btn").click(); await sleep(500);
  check("k2", meta().includes("3 из 3"), meta());
  $("#mark-known-btn").click(); await sleep(500);
  check("summary", $("#summary-backdrop").classList.contains("is-open"));
  check("summary-line", $("#summary-line").textContent === "Всего 3 · знаю 3 · не знаю 0", $("#summary-line").textContent);
  check("today-k3", getTodayStats().known === 3, String(getTodayStats().known));
  $("#summary-menu").click(); await sleep(500);
  check("menu-open2", $("#menu-backdrop").classList.contains("is-open"));

  // Big study from menu -> direct workspace
  $("#menu-study-btn").click(); await sleep(600);
  check("big-study", !$("#menu-backdrop").classList.contains("is-open") && !$("#study-board").classList.contains("hidden") && meta().includes("1 из 3"), meta());
  $("#menu-back-btn").click(); await sleep(500);
  check("menu-open3", $("#menu-backdrop").classList.contains("is-open"));

  // To edit via popup -> bulk with Ctrl+Enter, then Escape closes
  $("#menu-cards-btn").click(); await sleep(400);
  $$("#deck-pick-list .deck-pick-item")[0].querySelector(".deck-pick-main").click(); await sleep(600);
  check("edit-via-popup", !$("#menu-backdrop").classList.contains("is-open") && !$("#panel-edit").classList.contains("hidden"));
  $("#bulk-btn").click(); await sleep(400);
  $("#bulk-input").value = "вода = water";
  $("#bulk-input").dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", ctrlKey: true, bubbles: true, cancelable: true }));
  await sleep(500);
  check("bulk-ctrl-enter", deckCards().length === 4 && $("#bulk-feedback").textContent.includes("Добавлено 1"), $("#bulk-feedback").textContent);
  $("#bulk-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("bulk-esc", !$("#bulk-backdrop").classList.contains("is-open"));

  // Settings: tab trap + Escape
  $("#settings-btn").click(); await sleep(400);
  $("#mode-switch [data-mode='light']").focus();
  $("#settings-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", shiftKey: true, bubbles: true, cancelable: true }));
  await sleep(200);
  check("tab-trap", document.activeElement.id === "settings-close", document.activeElement.id);
  $("#settings-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("settings-esc-ws", !$("#settings-backdrop").classList.contains("is-open"));

  // Rename via workspace header
  $("#rename-deck-btn").click(); await sleep(400);
  check("rename-modal", $("#modal-backdrop").classList.contains("is-open") && $("#modal-title").textContent === "Переименовать");
  check("rename-prefill", $("#modal-input").value === "Основы", $("#modal-input").value);
  $("#modal-input").value = "Основы 2";
  $("#modal-ok").click(); await sleep(400);
  check("renamed", state.decks[0].name === "Основы 2" && $("#deck-title").textContent === "Основы 2", $("#deck-title").textContent);

  // Delete via workspace header -> empty state
  $("#delete-deck-btn").click(); await sleep(400);
  check("del-deck-modal", $("#modal-backdrop").classList.contains("is-open") && $("#modal-title").textContent === "Удалить колоду?");
  $("#modal-ok").click(); await sleep(500);
  check("empty-state", state.decks.length === 0 && !$("#empty-state").classList.contains("hidden") && $("#workspace").classList.contains("hidden"));

  // Empty state "← Меню"
  $("#empty-menu-btn").click(); await sleep(500);
  check("empty-menu-btn", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);
  check("empty-again", !$("#empty-state").classList.contains("hidden"));

  // Empty state "Завести колоду"
  $("#empty-new-deck-btn").click(); await sleep(400);
  check("create-from-empty", $("#modal-backdrop").classList.contains("is-open") && $("#modal-title").textContent === "Новая колода");
  $("#modal-input").value = "Пустая";
  $("#modal-ok").click(); await sleep(500);
  check("deck-created", state.decks.length === 1 && state.decks[0].name === "Пустая" && $("#deck-title").textContent === "Пустая");

  check("no-errors-a", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));
  return JSON.stringify(res);
})()
'@
  $scenarioB = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);

  await sleep(1000);
  check("empty-menu-open", $("#menu-backdrop").classList.contains("is-open"));
  check("empty-storage", state.decks.length === 0 && state.cards.length === 0 && state.selectedDeckId === null);
  $("#menu-close").click(); await sleep(400);
  check("empty-visible-b", !$("#empty-state").classList.contains("hidden") && $("#workspace").classList.contains("hidden"));

  // Big study with zero decks -> opens create modal
  $("#empty-menu-btn").click(); await sleep(500);
  check("menu-reopen-b", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-study-btn").click(); await sleep(400);
  check("create-no-decks", $("#modal-backdrop").classList.contains("is-open") && $("#modal-title").textContent === "Новая колода", $("#modal-title").textContent);
  $("#modal-cancel").click(); await sleep(400);
  check("create-cancelled", !$("#modal-backdrop").classList.contains("is-open"));

  // Menu "Колоды" with zero decks -> create modal too
  $("#menu-cards-btn").click(); await sleep(400);
  check("cards-no-decks", $("#modal-backdrop").classList.contains("is-open"), $("#modal-title").textContent);
  $("#modal-input").value = "С нуля";
  $("#modal-ok").click(); await sleep(500);
  check("deck-from-menu", state.decks.length === 1 && state.decks[0].name === "С нуля" && !$("#workspace").classList.contains("hidden"));
  check("study-empty-panel", !$("#study-empty").classList.contains("hidden") && $("#study-board").classList.contains("hidden"));

  check("no-errors-b", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));
  return JSON.stringify(res);
})()
'@
  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3
  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioA; awaitPromise = $true; returnByValue = $true }
  Write-Output "=== SCENARIO A ==="
  $results = $res.result.value | ConvertFrom-Json
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $failsA = @($results | Where-Object { -not $_.ok }).Count

  Invoke-Cdp $ws "Runtime.evaluate" @{ expression = "sessionStorage.setItem('use-empty','1');" } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3
  $resB = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioB; awaitPromise = $true; returnByValue = $true }
  Write-Output "=== SCENARIO B (empty storage) ==="
  $resultsB = $resB.result.value | ConvertFrom-Json
  $resultsB | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $failsB = @($resultsB | Where-Object { -not $_.ok }).Count
  Write-Output ("=== EXTRA TOTAL: A {0} checks / {1} fails, B {2} checks / {3} fails ===" -f $results.Count, $failsA, $resultsB.Count, $failsB)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}
























