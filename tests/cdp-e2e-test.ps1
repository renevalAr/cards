param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9238 })
$udir = "$env:TEMP\opencode\cdp-e2e-profile"
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
  if (!localStorage.getItem("flashcards-app-v1")) {
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
          { id: "c1", deckId: "d1", question: "cat", answer: "кот", status: "new" },
          { id: "c2", deckId: "d1", question: "dog", answer: "собака", status: "new" },
          { id: "c3", deckId: "d1", question: "bird", answer: "птица", status: "new" },
          { id: "c4", deckId: "d2", question: "столица России", answer: "Москва", status: "known" }
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
  const row = (i) => $$("#card-rows li")[i];

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);
  check("workspace-edit", !$("#workspace").classList.contains("hidden") && !$("#panel-edit").classList.contains("hidden") && $("#panel-study").classList.contains("hidden"));
  check("rows3", $$("#card-rows li").length === 3, String($$("#card-rows li").length));
  check("badges-new", $$("#card-rows .badge").every((b) => b.textContent === "новая"), $$("#card-rows .badge").map((b) => b.textContent).join("|"));
  check("header0", $("#stats").textContent === "Всего 3 · знаю 0 · не знаю 0", $("#stats").textContent);

  // Add a card via the form
  $("#card-question").value = "apple";
  $("#card-answer").value = "яблоко";
  $("#save-card-btn").click(); await sleep(400);
  check("rows4", $$("#card-rows li").length === 4 && deckCards().length === 4, String(deckCards().length));
  check("header4", $("#stats").textContent.includes("Всего 4"), $("#stats").textContent);
  check("new-added", deckCards().some((c) => c.question === "apple" && c.answer === "яблоко" && c.status === "new"));
  check("form-cleared", $("#card-question").value === "" && $("#card-answer").value === "" && $("#save-card-btn").textContent === "Добавить карточку");

  // Whitespace-only input must not add a card
  $("#card-question").value = "   ";
  $("#card-answer").value = "   ";
  $("#save-card-btn").click(); await sleep(300);
  check("rows-still4", deckCards().length === 4, String(deckCards().length));

  // Edit existing card
  row(0).querySelector(".row-actions button").click(); await sleep(300);
  check("edit-mode", $("#save-card-btn").textContent === "Сохранить" && !$("#cancel-edit-btn").classList.contains("hidden") && $("#card-question").value === "cat", $("#card-question").value);
  $("#card-question").value = "cat?";
  $("#save-card-btn").click(); await sleep(400);
  check("edit-saved", deckCards().find((c) => c.id === "c1").question === "cat?" && $$("#card-rows li").length === 4);
  check("row1-text", row(0).textContent.includes("cat?"), row(0).textContent);

  // Cancel edit
  row(0).querySelector(".row-actions button").click(); await sleep(300);
  $("#cancel-edit-btn").click(); await sleep(300);
  check("cancel-edit", $("#save-card-btn").textContent === "Добавить карточку" && $("#cancel-edit-btn").classList.contains("hidden") && $("#card-question").value === "");

  // Delete first card (c1) with confirm
  row(0).querySelectorAll(".row-actions button")[1].click(); await sleep(300);
  check("del-modal", $("#modal-backdrop").classList.contains("is-open") && $("#modal-title").textContent === "Удалить карточку?", $("#modal-title").textContent);
  $("#modal-ok").click(); await sleep(400);
  check("rows3-after-del", deckCards().length === 3 && !state.cards.some((c) => c.id === "c1"), String(deckCards().length));
  check("header3", $("#stats").textContent.includes("Всего 3"), $("#stats").textContent);

  // Tab switch to study
  $("#tab-study").click(); await sleep(400);
  check("tab-study-on", !$("#panel-study").classList.contains("hidden") && $("#panel-edit").classList.contains("hidden") && !$("#study-board").classList.contains("hidden"));
  check("meta1", meta().includes("1 из 3"), meta());

  // Keyboard navigation on document
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true, cancelable: true }));
  await sleep(300);
  check("kbd-right", meta().includes("2 из 3"), meta());
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true, cancelable: true }));
  await sleep(300);
  check("kbd-left", meta().includes("1 из 3"), meta());
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true, cancelable: true }));
  await sleep(300);
  check("kbd-wrap-prev", meta().includes("3 из 3"), meta());
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true, cancelable: true }));
  await sleep(300);
  check("kbd-wrap-next", meta().includes("1 из 3"), meta());

  // Buttons
  $("#next-card-btn").click(); await sleep(300);
  check("btn-next", meta().includes("2 из 3"), meta());
  $("#prev-card-btn").click(); await sleep(300);
  check("btn-prev", meta().includes("1 из 3"), meta());

  // Flip marks unknown exactly once
  $("#flashcard").click(); await sleep(300);
  check("flipped", $("#flashcard").classList.contains("is-flipped"));
  check("press-unknown", $("#mark-unknown-btn").getAttribute("aria-pressed") === "true");
  check("today-u1", getTodayStats().unknown === 1, String(getTodayStats().unknown));
  $("#flashcard").click(); await sleep(300);
  check("unflipped", !$("#flashcard").classList.contains("is-flipped"));
  check("today-u1-again", getTodayStats().unknown === 1, String(getTodayStats().unknown));

  // Mark known after flip -> advances; verdict known, daily event already spent at flip
  $("#mark-known-btn").click(); await sleep(500);
  check("meta2", meta().includes("2 из 3"), meta());
  check("today-k1", getTodayStats().known === 0, String(getTodayStats().known));
  check("press-reset", $("#mark-known-btn").getAttribute("aria-pressed") === "false" && $("#mark-unknown-btn").getAttribute("aria-pressed") === "false");

  // Unflipped unknown on card 2
  $("#mark-unknown-btn").click(); await sleep(500);
  check("meta3", meta().includes("3 из 3"), meta());
  check("today-u2", getTodayStats().unknown === 2, String(getTodayStats().unknown));

  // Complete round on card 3
  $("#mark-known-btn").click(); await sleep(500);
  check("summary-open", $("#summary-backdrop").classList.contains("is-open"));
  check("summary-line", $("#summary-line").textContent === "Всего 3 · знаю 2 · не знаю 1", $("#summary-line").textContent);
  check("repeat-unknown-txt", $("#summary-repeat").textContent === "Повторить неизученное", $("#summary-repeat").textContent);

  // Repeat unknown only (1 card)
  $("#summary-repeat").click(); await sleep(500);
  check("repeat-meta", meta().includes("1 из 1"), meta());
  $("#mark-known-btn").click(); await sleep(500);
  check("summary2", $("#summary-backdrop").classList.contains("is-open"));
  check("summary-line2", $("#summary-line").textContent === "Всего 1 · знаю 1 · не знаю 0", $("#summary-line").textContent);
  check("repeat-all-txt", $("#summary-repeat").textContent === "Пройти ещё раз", $("#summary-repeat").textContent);

  // To menu
  $("#summary-menu").click(); await sleep(500);
  check("to-menu", $("#menu-backdrop").classList.contains("is-open"));
  const today = $("#menu-today-stats").textContent;
  check("menu-today", today.includes("изучено 4") && today.includes("знаю 2") && today.includes("не знаю 2"), today);;

  // Settings over menu
  $("#menu-settings-btn").click(); await sleep(500);
  check("settings-over-menu", $("#settings-backdrop").classList.contains("is-open") && $("#menu-backdrop").classList.contains("is-open"));
  $("#settings-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  await sleep(400);
  check("settings-esc-menu", !$("#settings-backdrop").classList.contains("is-open") && $("#menu-backdrop").classList.contains("is-open"));

  // Create deck from picker
  $("#menu-cards-btn").click(); await sleep(400);
  check("picker-open", $("#deck-pick-backdrop").classList.contains("is-open"));
  check("picker-2", $$("#deck-pick-list .deck-pick-item").length === 2, String($$("#deck-pick-list .deck-pick-item").length));
  $("#deck-pick-new").click(); await sleep(300);
  check("create-modal", $("#modal-backdrop").classList.contains("is-open"));
  $("#modal-input").value = "Новая";
  $("#modal-ok").click(); await sleep(500);
  check("new-deck-created", state.decks.some((d) => d.name === "Новая") && $("#deck-title").textContent === "Новая", $("#deck-title").textContent);
  check("deck-list3", $$("#deck-list .deck-item").length === 3, String($$("#deck-list .deck-item").length));
  check("empty-study", !$("#study-empty").classList.contains("hidden"));

  // Switch deck via sidebar
  $$("#deck-list .deck-item").find((b) => b.textContent.includes("Английский")).click(); await sleep(500);
  check("switched", $("#deck-title").textContent === "Английский" && state.selectedDeckId === "d1");
  check("rows3-sidebar", $$("#card-rows li").length === 3, String($$("#card-rows li").length));

  // Settings from workspace: dark + sea palette + persistence
  $("#settings-btn").click(); await sleep(400);
  check("settings-ws", $("#settings-backdrop").classList.contains("is-open") && !$("#workspace").classList.contains("hidden"));
  $("#mode-switch [data-mode='dark']").click(); await sleep(500);
  check("dark-on", document.documentElement.dataset.mode === "dark");
  $("#theme-dots .theme-dot[data-palette='sea']").click(); await sleep(500);
  check("sea-on", document.documentElement.dataset.palette === "sea");
  check("persist-dark", localStorage.getItem("flashcards-mode") === "dark");
  check("persist-sea", localStorage.getItem("flashcards-palette") === "sea");
  $("#settings-close").click(); await sleep(400);
  check("settings-closed", !$("#settings-backdrop").classList.contains("is-open"));

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
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const meta = () => $("#study-meta").textContent;
  const d1Cards = () => state.cards.filter((c) => c.deckId === "d1");

  await sleep(1000);
  check("menu-open-b", $("#menu-backdrop").classList.contains("is-open"));
  check("persisted-decks", state.decks.length === 3 && state.decks.some((d) => d.name === "Новая"), String(state.decks.length));
  check("persisted-cards", d1Cards().length === 3, String(d1Cards().length));
  check("persisted-selected", state.selectedDeckId === "d1", String(state.selectedDeckId));
  check("persisted-mode", document.documentElement.dataset.mode === "dark", document.documentElement.dataset.mode);
  check("persisted-palette", document.documentElement.dataset.palette === "sea", document.documentElement.dataset.palette);
  check("persisted-today", state.today.known === 2 && state.today.unknown === 2, JSON.stringify(state.today));

  // Close menu -> workspace, bulk add
  $("#menu-close").click(); await sleep(400);
  check("ws-b", !$("#workspace").classList.contains("hidden") && $("#deck-title").textContent === "Английский");
  $("#bulk-btn").click(); await sleep(400);
  check("bulk-open-b", $("#bulk-backdrop").classList.contains("is-open"));
  $("#bulk-input").value = "pear = груша\n1 = one\nстол = table";
  $("#bulk-ok").click(); await sleep(500);
  check("bulk-added", d1Cards().length === 6 && $("#bulk-feedback").textContent.includes("Добавлено 3"), $("#bulk-feedback").textContent);
  $("#bulk-cancel").click(); await sleep(400);
  check("bulk-closed-b", !$("#bulk-backdrop").classList.contains("is-open"));

  // Reset progress via popup
  $("#menu-back-btn").click(); await sleep(400);
  $("#menu-cards-btn").click(); await sleep(400);
  $$("#deck-pick-list .deck-pick-item").find((b) => b.textContent.includes("Английский")).querySelector(".deck-pick-more").click(); await sleep(400);
  const popBtns = $$("#menu-pop-actions button").map((b) => b.textContent);
  check("pop-actions-b", popBtns.length === 7 && popBtns.some((t) => t.includes("Начать заново")), popBtns.join("|"));
  [...document.querySelectorAll("#menu-pop-actions button")].find(b=>b.textContent.includes("заново")).click(); await sleep(300);
  check("reset-modal", $("#modal-backdrop").classList.contains("is-open") && $("#modal-title").textContent === "Начать заново?", $("#modal-title").textContent);
  check("reset-btn", $("#modal-ok").textContent === "Сбросить", $("#modal-ok").textContent);
  $("#modal-ok").click(); await sleep(500);
  check("all-new-b", d1Cards().every((c) => c.status === "new"), d1Cards().map((c) => c.status).join("|"));
  check("today-reset-kept", state.today.known === 2 && state.today.unknown === 2);

  // Study via popup
  $("#menu-back-btn").click(); await sleep(400);
  $("#menu-cards-btn").click(); await sleep(400);
  $$("#deck-pick-list .deck-pick-item").find((b) => b.textContent.includes("Английский")).querySelector(".deck-pick-more").click(); await sleep(400);
  [...document.querySelectorAll("#menu-pop-actions button")].find(b=>b.textContent.includes("Учить колоду")).click(); await sleep(600);
  check("study-popup-b", !$("#menu-backdrop").classList.contains("is-open") && !$("#study-board").classList.contains("hidden") && meta().includes("1 из 6"), meta());

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

  Invoke-Cdp $ws "Page.reload" @{ ignoreCache = $true } | Out-Null
  Start-Sleep -Seconds 3
  $resB = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenarioB; awaitPromise = $true; returnByValue = $true }
  if ($resB.exceptionDetails) { Write-Output ("B EXC: " + $resB.exceptionDetails.exception.description) }
  Write-Output "=== SCENARIO B (reload) ==="
  $resultsB = $resB.result.value | ConvertFrom-Json
  $resultsB | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $failsB = @($resultsB | Where-Object { -not $_.ok }).Count
  Write-Output ("=== E2E TOTAL: A {0} checks / {1} fails, B {2} checks / {3} fails ===" -f $results.Count, $failsA, $resultsB.Count, $failsB)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}










































