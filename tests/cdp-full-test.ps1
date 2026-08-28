param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9228 })
$udir = "$env:TEMP\opencode\cdp-full-profile"
$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$base = "file:///" + ($rootDir -replace "\\","/") + "/frontend/frontend/index.html"

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
  var mode = new URLSearchParams(location.search).get("mode");
  if (mode === "corrupt") {
    localStorage.setItem("flashcards-app-v1", "null");
    localStorage.setItem("flashcards-onboarded", "1");
  } else {
    (function () {
      var d = new Date();
      var pad = function (n) { return String(n).padStart(2, "0"); };
      var today = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
      localStorage.setItem("flashcards-app-v1", JSON.stringify({
        decks: [
          { id: "d1", name: "Английский" },
          { id: "d2", name: "География" }
        ],
        cards: [
          { id: "c1", deckId: "d1", question: "cat", answer: "кот", status: "known" },
          { id: "c2", deckId: "d1", question: "dog", answer: "собака", status: "unknown" },
          { id: "c3", deckId: "d1", question: "bird", answer: "птица", status: "unknown" },
          { id: "c4", deckId: "d2", question: "столица", answer: "Москва", status: "known" }
        ],
        selectedDeckId: "d1",
        tab: "edit",
        today: { date: today, known: 0, unknown: 0 },
        history: {},
        sessions: []
      }));
    })();
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

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));

  // Tour auto-shown (not onboarded)
  check("tour-visible", !$("#tour-tip").hidden, "hidden=" + $("#tour-tip").hidden);
  const arrowLeft = getComputedStyle($("#tour-tip"), "::before").left;
  check("tour-arrow-px", typeof arrowLeft === "string" && arrowLeft.endsWith("px"), arrowLeft);
  check("tour-step1", $("#tour-text").textContent.includes("Счётчик"), $("#tour-text").textContent);

  // Stats backdrop must NOT inherit menu-backdrop class
  check("stats-no-menubackdrop", !$("#stats-backdrop").classList.contains("menu-backdrop"));

  // Finish tour
  $("#tour-next").click(); await sleep(80);
  $("#tour-next").click(); await sleep(80);
  $("#tour-next").click(); await sleep(80);
  $("#tour-next").click(); await sleep(150);
  check("tour-done", $("#tour-tip").hidden && localStorage.getItem("flashcards-onboarded") === "1");

  // Dark mode from menu
  $("#menu-mode-switch [data-mode=dark]").click(); await sleep(200);
  check("dark-mode", document.documentElement.dataset.mode === "dark", document.documentElement.dataset.mode);
  $("#menu-mode-switch [data-mode=light]").click(); await sleep(200);
  check("light-mode", document.documentElement.dataset.mode === "light");

  // Palette switch from menu
  $("#menu-theme-dots [data-palette=sea]").click(); await sleep(200);
  check("palette-sea", document.documentElement.dataset.palette === "sea", document.documentElement.dataset.palette);

  // menu-cover must stay compact (no scroll)
  const coverEl = $(".menu-cover");
  const cover = getComputedStyle(coverEl);
  check("cover-no-scroll", coverEl.scrollHeight <= window.innerHeight, "sh=" + coverEl.scrollHeight + " vh=" + window.innerHeight);
  check("cover-overflow", cover.overflowY === "visible" || cover.overflowY === "auto", cover.overflowY);

  // .modal unified radius
  check("modal-radius", getComputedStyle($("#modal-backdrop .modal")).borderRadius === "16px", getComputedStyle($("#modal-backdrop .modal")).borderRadius);

  // Deck picker via "Колоды"
  $("#menu-cards-btn").click(); await sleep(400);
  check("picker-open", $("#deck-pick-backdrop").classList.contains("is-open"));
  const pickItems = $$("#deck-pick-list .deck-pick-item");
  check("picker-items", pickItems.length === 2, String(pickItems.length));
  check("picker-title", $("#deck-pick-title").textContent === "Колоды", $("#deck-pick-title").textContent);

  // Open actions for first deck, then "Карточки"
    pickItems[0].querySelector(".deck-pick-more").click(); await sleep(400);
  check("pop-open", $("#menu-pop-backdrop").classList.contains("is-open"));
  check("pop-title", $("#menu-pop-title").textContent === "Английский", $("#menu-pop-title").textContent);
  const popButtons = $$("#menu-pop-actions button").map((b) => b.textContent);
  check("pop-buttons", JSON.stringify(popButtons).includes("Учить колоду") && JSON.stringify(popButtons).includes("Карточки") && JSON.stringify(popButtons).includes("Переименовать") && JSON.stringify(popButtons).includes("Удалить"), popButtons.join("|"));
  [...document.querySelectorAll("#menu-pop-actions button")].find(b=>b.textContent.includes("Карточки")).click(); await sleep(500); // "Карточки"
  check("workspace-edit", !$("#menu-backdrop").classList.contains("is-open") && !$("#workspace").classList.contains("hidden") && $("#panel-edit").classList.contains("hidden") === false);

  // deck-item no longer rotated
  const diTransform = getComputedStyle($(".deck-item")).transform;
  check("deckitem-no-rotate", !diTransform.toLowerCase().includes("rotate"), diTransform);

  // #stats header counter from ui.js (renderStats collision fix)
  const known = state.cards.filter((c) => c.deckId === "d1" && c.status === "known").length;
  const unknown = state.cards.filter((c) => c.deckId === "d1" && c.status === "unknown").length;
  check("header-stats", $("#stats").textContent === "Всего 3 · знаю " + known + " · не знаю " + unknown, $("#stats").textContent);

  // Start study from menu
  $("#menu-back-btn").click(); await sleep(400);
  check("menu-again", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-study-btn").click(); await sleep(600);
  check("study-on", !$("#menu-backdrop").classList.contains("is-open") && !$("#deck-pick-backdrop").classList.contains("is-open") && meta().includes("1 из 3"), meta());

  // 3D flip + preserve-3d on .flashcard
  check("flashcard-p3d", getComputedStyle($("#flashcard")).transformStyle === "preserve-3d", getComputedStyle($("#flashcard")).transformStyle);
  $("#flashcard").click(); await sleep(150);
  check("flipped", $("#flashcard").classList.contains("is-flipped"));
  check("pressed-unknown", $("#mark-unknown-btn").getAttribute("aria-pressed") === "true", $("#mark-unknown-btn").getAttribute("aria-pressed"));

  // Round: card1 known, card2 unknown, card3 known
  $("#mark-known-btn").click(); await sleep(550);
  check("advance2", meta().includes("2 из 3"), meta());
  const hKnown = state.cards.filter((c) => c.deckId === "d1" && c.status === "known").length;
  const hUnknown = state.cards.filter((c) => c.deckId === "d1" && c.status === "unknown").length;
  check("header-updated", $("#stats").textContent === "Всего 3 · знаю " + hKnown + " · не знаю " + hUnknown, $("#stats").textContent);

  $("#flashcard").click(); await sleep(150);
  $("#mark-unknown-btn").click(); await sleep(550);
  check("advance3", meta().includes("3 из 3"), meta());
  $("#flashcard").click(); await sleep(150);
  $("#mark-known-btn").click(); await sleep(550);
  check("summary-open", $("#summary-backdrop").classList.contains("is-open"));
  check("summary-line", $("#summary-line").textContent === "Всего 3 · знаю 2 · не знаю 1", $("#summary-line").textContent);
  check("repeat-unknown", $("#summary-repeat").textContent === "Повторить неизученное" && !$("#summary-repeat").hidden);

  // Repeat only unknown cards
  $("#summary-repeat").click(); await sleep(600);
  check("repeat-on", meta().includes("1 из 1"), meta());
  $("#flashcard").click(); await sleep(150);
  $("#mark-known-btn").click(); await sleep(550);
  check("summary2", $("#summary-backdrop").classList.contains("is-open"));
  check("summary-line2", $("#summary-line").textContent === "Всего 1 · знаю 1 · не знаю 0", $("#summary-line").textContent);
  check("repeat-all", $("#summary-repeat").textContent === "Пройти ещё раз", $("#summary-repeat").textContent);

  // Summary -> stats
  $("#summary-stats").click(); await sleep(500);
  check("stats-from-summary", $("#stats-backdrop").classList.contains("is-open") && !$("#summary-backdrop").classList.contains("is-open"));

  const todayN = state.today.known + state.today.unknown;
  let allK = 0, allU = 0;
  for (const dk of Object.keys(state.history)) for (const dt of Object.keys(state.history[dk])) { allK += state.history[dk][dt].known; allU += state.history[dk][dt].unknown; }
  check("stats-total", $("#stats-total").textContent === String(state.cards.length), $("#stats-total").textContent);
  check("stats-today", $("#stats-today").textContent === String(todayN), $("#stats-today").textContent + " vs " + todayN);
  check("stats-alltime", $("#stats-alltime").textContent === String(allK + allU), $("#stats-alltime").textContent + " vs " + (allK + allU));

  const sItems = $$("#stats-list .stats-item");
  check("stats-items", sItems.length === 2, String(sItems.length));
  check("stats-item1", sItems[0].textContent.includes("Английский") && sItems[0].textContent.includes("3 карт"), sItems[0].textContent);
  const days = sItems[0].querySelectorAll(".stats-days .stats-day");
  check("stats-days", days.length === 7, String(days.length));

  // Deck detail
  sItems[0].click(); await sleep(400);
  check("deck-detail", !$("#stats-main").classList.contains("hidden") === false && !$("#stats-deck").classList.contains("hidden"));
  check("detail-title", $("#stats-deck-title").textContent === "Английский", $("#stats-deck-title").textContent);
  const sessions = $$("#stats-sessions .session-item");
  check("sessions2", sessions.length === 2, String(sessions.length));
  check("session-newest", sessions[0].textContent.includes("знаю 1") && sessions[0].textContent.includes("не знаю 0"), sessions[0].textContent);

  $("#stats-back").click(); await sleep(300);
  check("stats-back-main", !$("#stats-main").classList.contains("hidden") && $("#stats-deck").classList.contains("hidden"));

  // Escape closes stats
  $("#stats-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("stats-esc", !$("#stats-backdrop").classList.contains("is-open"));

  // Rename flow via menu
  $("#menu-back-btn").click(); await sleep(400);
  $("#menu-cards-btn").click(); await sleep(400);
  $$("#deck-pick-list .deck-pick-item")[0].querySelector(".deck-pick-more").click(); await sleep(300);
  [...document.querySelectorAll("#menu-pop-actions button")].find(b=>b.textContent.includes("Переименовать")).click(); await sleep(300); // "Переименовать"
  check("rename-modal", $("#modal-backdrop").classList.contains("is-open"));
  $("#modal-input").value = "Испанский";
  $("#modal-ok").click(); await sleep(400);
  check("renamed", state.decks.find((d) => d.id === "d1").name === "Испанский", state.decks.find((d) => d.id === "d1").name);

  // Delete flow via menu
  $("#menu-back-btn").click(); await sleep(400);
  $("#menu-cards-btn").click(); await sleep(400);
  $$("#deck-pick-list .deck-pick-item")[0].querySelector(".deck-pick-more").click(); await sleep(300);
  [...document.querySelectorAll("#menu-pop-actions button")].find(b=>b.textContent.includes("Удалить")).click(); await sleep(300); // "Удалить"
  check("delete-modal", $("#modal-backdrop").classList.contains("is-open"));
  check("delete-confirm", $("#modal-ok").textContent === "Удалить", $("#modal-ok").textContent);
  $("#modal-ok").click(); await sleep(400);
  check("deleted", !state.decks.some((d) => d.id === "d1") && state.cards.filter((c) => c.deckId === "d1").length === 0, "decks=" + state.decks.length);

  // Create flow via menu
  $("#menu-back-btn").click(); await sleep(400);
  $("#menu-cards-btn").click(); await sleep(400);
  $("#deck-pick-new").click(); await sleep(300);
  check("create-modal", $("#modal-backdrop").classList.contains("is-open"));
  $("#modal-input").value = "Новая";
  $("#modal-ok").click(); await sleep(400);
  check("created", state.decks.some((d) => d.name === "Новая"), JSON.stringify(state.decks.map((d) => d.name)));

  // Stats from menu still works
  $("#menu-back-btn").click(); await sleep(400);
  $("#menu-stats-btn").click(); await sleep(500);
  check("stats-from-menu", $("#stats-backdrop").classList.contains("is-open"));
  check("stats-empty-hidden", $("#stats-empty").classList.contains("hidden"));
  $("#stats-close").click(); await sleep(400);
  check("stats-closed", !$("#stats-backdrop").classList.contains("is-open"));

  check("no-errors", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));

  return JSON.stringify(res);
})()
'@

  $scenarioB = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);

  await sleep(800);
  check("no-crash", typeof state === "object" && state !== null);
  check("today-fixed", state.today && typeof state.today.date === "string" && state.today.date.length === 10, state.today && state.today.date);
  check("decks-empty", state.decks.length === 0, String(state.decks.length));
  check("menu-open-b", $("#menu-backdrop").classList.contains("is-open"));
  check("empty-visible", !$("#empty-state").classList.contains("hidden"));

  // Create a deck from empty state to ensure app is fully usable
  $("#empty-new-deck-btn").click(); await sleep(300);
  check("create-modal-b", $("#modal-backdrop").classList.contains("is-open"));
  $("#modal-input").value = "С нуля";
  $("#modal-ok").click(); await sleep(400);
  check("deck-created-b", state.decks.length === 1 && state.decks[0].name === "С нуля", JSON.stringify(state.decks));

  check("no-errors-b", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));

  return JSON.stringify(res);
})()
'@

  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null

  Invoke-Cdp $ws "Page.navigate" @{ url = $base } | Out-Null
  Start-Sleep -Seconds 3
  $resA = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioA; awaitPromise = $true; returnByValue = $true }
  if ($resA.exceptionDetails) { Write-Output ("A EXC: " + $resA.exceptionDetails.exception.description) }

  Invoke-Cdp $ws "Page.navigate" @{ url = $base + "?mode=corrupt" } | Out-Null
  Start-Sleep -Seconds 3
  $resB = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioB; awaitPromise = $true; returnByValue = $true }

  Write-Output "=== SCENARIO A (clean flow) ==="
  $resultsA = $resA.result.value | ConvertFrom-Json
  $resultsA | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  Write-Output "=== SCENARIO B (corrupted storage) ==="
  $resultsB = $resB.result.value | ConvertFrom-Json
  $resultsB | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $fails = @($resultsA + $resultsB | Where-Object { -not $_.ok }).Count
  Write-Output ("=== TOTAL FAILS: {0} ===" -f $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}





















































