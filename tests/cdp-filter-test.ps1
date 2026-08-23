param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9240 })
$udir = "C:\Users\Lenovo\AppData\Local\Temp\opencode\cdp-filter-profile"
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
        decks: [{ id: "d1", name: "Основы" }],
        cards: [
          { id: "c1", deckId: "d1", question: "1+1", answer: "2", status: "new" },
          { id: "c2", deckId: "d1", question: "знаю?", answer: "да", status: "known" },
          { id: "c3", deckId: "d1", question: "забыл?", answer: "да", status: "unknown" },
          { id: "c4", deckId: "d1", question: "столица", answer: "Париж", status: "new" }
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
  const rows = () => $$("#card-rows li[data-card-id]");
  const badges = () => rows().map((li) => li.querySelector(".badge").textContent).join("|");
  const setFilter = async (value) => { $$("#card-filters .filter-btn").find((b) => b.dataset.filter === value).click(); await sleep(400); };
  const activeFilter = () => $("#card-filters .filter-btn.is-active").dataset.filter;

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);

  check("filters-visible", !$("#card-filters").classList.contains("hidden"));
  check("filters-btns", $$("#card-filters .filter-btn").map((b) => b.textContent).join("|") === "Все|Новые|Знаю|Не знаю", $$("#card-filters .filter-btn").map((b) => b.textContent).join("|"));
  check("all-active", activeFilter() === "all" && $$("#card-filters .filter-btn")[0].classList.contains("is-active"), activeFilter());
  check("rows-all", rows().length === 4, String(rows().length));

  await setFilter("known");
  check("known-filter", rows().length === 1 && activeFilter() === "known", rows().length + " / " + activeFilter());
  check("known-badge", badges() === "знаю", badges());

  await setFilter("unknown");
  check("unknown-filter", rows().length === 1 && badges() === "не знаю", rows().length + " / " + badges());

  await setFilter("new");
  check("new-filter", rows().length === 2 && activeFilter() === "new", rows().length + " / " + activeFilter());
  check("new-badges", badges() === "новая|новая", badges());

  // Delete the only known card while the "Знаю" filter is active -> filter empty message
  await setFilter("known");
  rows()[0].querySelector(".row-actions button:last-child").click(); await sleep(400);
  check("del-modal", $("#modal-backdrop").classList.contains("is-open") && $("#modal-title").textContent === "Удалить карточку?");
  $("#modal-ok").click(); await sleep(500);
  check("filter-empty", rows().length === 0 && activeFilter() === "known");
  check("filter-empty-msg", $("#card-rows .empty-row").textContent === "Нет карточек со статусом «знаю».", $("#card-rows .empty-row").textContent);

  await setFilter("all");
  check("all-back", rows().length === 3, String(rows().length));

  // Live update: flip c1 (new) in study while filter "Новые" is active -> row disappears
  await setFilter("new");
  check("new-before-flip", rows().length === 2, String(rows().length));
  $("#tab-study").click(); await sleep(500);
  const idx = state.studyOrder.indexOf("c1");
  state.studyIndex = idx;
  state.flipped = false;
  showStudyCard();
  $("#flashcard").click(); await sleep(500);
  check("flipped-c1", state.cards.find((c) => c.id === "c1").status === "unknown", state.cards.find((c) => c.id === "c1").status);
  $("#tab-edit").click(); await sleep(500);
  check("row-removed-live", rows().length === 1 && !rows().some((li) => li.dataset.cardId === "c1") && badges() === "новая", badges());

  // Filter bar hidden for an empty deck, then back
  $("#new-deck-btn").click(); await sleep(400);
  $("#modal-input").value = "Пустая";
  $("#modal-ok").click(); await sleep(500);
  check("empty-deck-selected", state.selectedDeckId === state.decks[1].id && state.decks[1].name === "Пустая");
  check("filters-hidden", $("#card-filters").classList.contains("hidden"));
  check("no-cards-msg", $("#card-rows .empty-row").textContent === "Карточек пока нет — заполни форму выше.", $("#card-rows .empty-row").textContent);
  $$("#deck-list .deck-item")[0].click(); await sleep(500);
  check("filters-back", !$("#card-filters").classList.contains("hidden") && activeFilter() === "new" && rows().length === 1, activeFilter() + " / " + rows().length);

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
  const rows = () => $$("#card-rows li[data-card-id]");
  const activeFilter = () => $("#card-filters .filter-btn.is-active").dataset.filter;

  await sleep(1000);
  check("menu-open-b", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);

  // Filter not persisted: resets to "all" after reload
  check("filter-reset", activeFilter() === "all", activeFilter());
  check("rows-after-reload", rows().length === 3, String(rows().length));

  // Unit checks for the filter helpers
  const units = [];
  units.push(state.cardFilter === "all");
  state.cardFilter = "new";
  units.push(cardMatchesFilter({ status: "new" }) === true && cardMatchesFilter({ status: "known" }) === false && cardMatchesFilter({ status: "unknown" }) === false);
  state.cardFilter = "known";
  units.push(cardMatchesFilter({ status: "known" }) === true && cardMatchesFilter({ status: "new" }) === false);
  state.cardFilter = "all";
  units.push(cardMatchesFilter({ status: "anything" }) === true);
  units.push(filterLabel("new") === "новая" && filterLabel("known") === "знаю" && filterLabel("unknown") === "не знаю");
  units.push($$("#card-filters .filter-btn").length === 4);
  state.cardFilter = "all";
  render();
  check("unit-helpers", units.every(Boolean), JSON.stringify(units));

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
  Write-Output "=== SCENARIO B (reload) ==="
  $resultsB = $resB.result.value | ConvertFrom-Json
  $resultsB | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $failsB = @($resultsB | Where-Object { -not $_.ok }).Count
  Write-Output ("=== FILTER TOTAL: A {0} checks / {1} fails, B {2} checks / {3} fails ===" -f $results.Count, $failsA, $resultsB.Count, $failsB)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}





















