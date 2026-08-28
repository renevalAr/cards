param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9260 })
$udir = "$env:TEMP\opencode\cdp-search-profile"
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
  var d = new Date();
  var pad = function (n) { return String(n).padStart(2, "0"); };
  var today = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
  localStorage.setItem("flashcards-app-v1", JSON.stringify({
    decks: [
      { id: "d1", name: "Основы" },
      { id: "d2", name: "География" }
    ],
    cards: [
      { id: "c1", deckId: "d1", question: "Собака", answer: "dog", status: "new" },
      { id: "c2", deckId: "d1", question: "Кот", answer: "кошка", status: "known" },
      { id: "c3", deckId: "d1", question: "Париж", answer: "столица Франции", status: "unknown" },
      { id: "c4", deckId: "d1", question: "котангенс", answer: "катет и гипотенуза", status: "new" }
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
  const inp = $("#card-search");
  const type = async (text) => { inp.value = text; inp.dispatchEvent(new Event("input", { bubbles: true })); await sleep(300); };
  const setFilter = async (value) => { $$("#card-filters .filter-btn").find((b) => b.dataset.filter === value).click(); await sleep(400); };

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);

  check("search-visible", !$("#card-search-row").classList.contains("hidden"));
  check("search-empty-start", inp.value === "" && !$("#card-search-clear").classList.contains("is-visible"));

  await type("кот");
  check("query-basic", rows().length === 2 && rows().some((li) => li.dataset.cardId === "c2") && rows().some((li) => li.dataset.cardId === "c4"), rows().map((li) => li.dataset.cardId).join(","));
  check("clear-btn-shown", $("#card-search-clear").classList.contains("is-visible"));

  const q2p = rows().find((li) => li.dataset.cardId === "c2").querySelector("p");
  check("highlight-mark", q2p.querySelector("mark.search-hit") !== null && q2p.querySelector("mark.search-hit").textContent === "Кот", q2p.textContent);
  check("highlight-full-text", q2p.textContent === "Кот", q2p.textContent);

  await type("КОТ");
  check("case-insensitive", rows().length === 2, String(rows().length));

  await type("франц");
  check("answer-match", rows().length === 1 && rows()[0].dataset.cardId === "c3", rows().map((li) => li.dataset.cardId).join(","));

  await type("кот");
  await setFilter("known");
  check("search-over-filter", rows().length === 1 && rows()[0].dataset.cardId === "c2", rows().map((li) => li.dataset.cardId).join(","));
  await setFilter("all");

  await type("zzz");
  const msg = $("#card-rows .empty-row").textContent;
  check("no-match-msg", msg.includes("ничего не найдено") && msg.includes("zzz"), msg);

  $("#card-search-clear").click(); await sleep(300);
  check("clear-click", rows().length === 4 && inp.value === "" && !$("#card-search-clear").classList.contains("is-visible"), String(rows().length));

  await type("париж");
  inp.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })); await sleep(300);
  check("esc-clears", rows().length === 4 && inp.value === "" && state.searchQuery === "" && !$("#card-search-clear").classList.contains("is-visible"), String(rows().length));

  await type("н");
  const c4q = rows().find((li) => li.dataset.cardId === "c4").querySelector("p");
  check("multi-match-marks", c4q.querySelectorAll("mark.search-hit").length === 2, String(c4q.querySelectorAll("mark.search-hit").length));
  $("#card-search-clear").click(); await sleep(200);

  await type("кот");
  $$("#deck-list .deck-item")[1].click(); await sleep(500);
  check("deck-switch-hides", $("#card-search-row").classList.contains("hidden") && inp.value === "");
  $$("#deck-list .deck-item")[0].click(); await sleep(500);
  check("deck-switch-clears", rows().length === 4 && inp.value === "" && state.searchQuery === "");

  const units = [];
  units.push(searchMatches({ question: "Abc", answer: "Xy" }, "ab") === true);
  units.push(searchMatches({ question: "Abc", answer: "Xy" }, "xy") === true);
  units.push(searchMatches({ question: "Abc", answer: "Xy" }, "") === true);
  units.push(searchMatches({ question: "Abc", answer: "Xy" }, "zz") === false);
  check("unit-match", units.every(Boolean), JSON.stringify(units));

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

  await sleep(1000);
  check("menu-open-b", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);

  check("search-not-persisted", $("#card-search").value === "" && state.searchQuery === "");
  check("rows-after-reload", $$("#card-rows li[data-card-id]").length === 4, String($$("#card-rows li[data-card-id]").length));
  check("clear-hidden-b", !$("#card-search-clear").classList.contains("is-visible"));

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
  Write-Output ("=== SEARCH TOTAL: A {0} checks / {1} fails, B {2} checks / {3} fails ===" -f $results.Count, $failsA, $resultsB.Count, $failsB)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}


























