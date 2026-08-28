param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9270 })
$udir = "$env:TEMP\opencode\cdp-quiz-profile"
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
    decks: [{ id: "d1", name: "Математика" }],
    cards: [
      { id: "c1", deckId: "d1", question: "1+1", answer: "2", status: "new" },
      { id: "c2", deckId: "d1", question: "2+2", answer: "4", status: "new" },
      { id: "c3", deckId: "d1", question: "3+3", answer: "6", status: "new" },
      { id: "c4", deckId: "d1", question: "столица России", answer: "Москва", status: "new" },
      { id: "c5", deckId: "d1", question: "столица Франции", answer: "Париж", status: "new" },
      { id: "c6", deckId: "d1", question: "5 умножить на 5", answer: "25", status: "new" }
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

  await sleep(800);
  check("menu-open", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);
  $("#tab-study").click(); await sleep(500);

  check("flip-default", !$("#flip-area").classList.contains("hidden") && $("#study-mode-flip").classList.contains("is-active"));
  $("#study-mode-quiz").click(); await sleep(400);
  check("quiz-entry", $("#flip-area").classList.contains("hidden") && !$("#quiz-start").classList.contains("hidden") && $("#study-mode-quiz").classList.contains("is-active"));
  check("length-buttons", $$("#quiz-start [data-qlen]").map((b) => b.dataset.qlen).join(",") === "5,10,0");

  $('[data-qlen="5"]').click(); await sleep(400);
  check("quiz-started", !$("#quiz-area").classList.contains("hidden") && $("#quiz-start").classList.contains("hidden"));
  check("meta-q1", /вопрос 1 из 5/.test($("#quiz-meta").textContent), $("#quiz-meta").textContent);
  const opts = $$("#quiz-options .quiz-option");
  check("options-count", opts.length === 4, String(opts.length));
  check("options-unique", new Set(opts.map((o) => o.textContent)).size === 4);
  check("one-right", opts.filter((o) => o.dataset.ok === "1").length === 1);

  $('#quiz-options .quiz-option[data-ok="1"]').click(); await sleep(250);
  check("right-styled", $('#quiz-options .quiz-option[data-ok="1"]').classList.contains("is-right"));
  check("next-shown", !$("#quiz-next").classList.contains("hidden"));
  check("stats-known", getTodayStats().known === 1, String(getTodayStats().known));
  check("meta-verdict", /верно 1/.test($("#quiz-meta").textContent), $("#quiz-meta").textContent);

  document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })); await sleep(250);
  check("arrows-idle-in-quiz", /вопрос 2 из 5|вопрос 1 из 5/.test($("#quiz-meta").textContent) && $("#quiz-next").classList.contains("hidden") === false);

  $("#quiz-next").click(); await sleep(300);
  check("meta-q2", /вопрос 2 из 5/.test($("#quiz-meta").textContent), $("#quiz-meta").textContent);
  $$('#quiz-options .quiz-option[data-ok="0"]')[0].click(); await sleep(250);
  check("wrong-styled", $$("#quiz-options .quiz-option")[0].classList.contains("is-dim") || $$("#quiz-options .quiz-option.is-wrong").length === 1);
  check("reveal-right", $("#quiz-options .quiz-option.is-right") !== null);
  check("stats-unknown", getTodayStats().unknown === 1, String(getTodayStats().unknown));

  for (let guard = 0; guard < 14; guard += 1) {
    if ($("#summary-backdrop").classList.contains("is-open")) break;
    const nb = $("#quiz-next");
    if (!nb.classList.contains("hidden")) nb.click();
    else $('#quiz-options .quiz-option[data-ok="1"]').click();
    await sleep(220);
  }
  check("summary-open", $("#summary-backdrop").classList.contains("is-open"));
  const line = $("#summary-line").textContent;
  const um = line.match(/не знать (\d+)/) || line.match(/не знаю (\d+)/);
  const km = line.match(/знаю (\d+)/);
  check("summary-line-format", line.indexOf("Всего 5") === 0 && !!um && !!km, line);
  const unknownCount = um ? Number(um[1]) : 0;
  const knownCount = km ? Number(km[1]) : 0;
  check("summary-math", knownCount + unknownCount === 5 && knownCount >= 1 && unknownCount >= 1, line);
  check("repeat-mode-quiz", $("#summary-repeat").dataset.mode === "quiz" && $("#summary-repeat").textContent === "Повторить неизученное", $("#summary-repeat").dataset.mode);
  check("session-recorded", state.sessions.length === 1 && state.sessions[0].known === knownCount, String(state.sessions.length));

  $("#summary-repeat").click(); await sleep(500);
  check("retry-length", !$("#quiz-area").classList.contains("hidden") && new RegExp("вопрос 1 из " + unknownCount + "\\b").test($("#quiz-meta").textContent), $("#quiz-meta").textContent);

  for (let guard = 0; guard < 10; guard += 1) {
    if ($("#summary-backdrop").classList.contains("is-open")) break;
    const nb = $("#quiz-next");
    if (!nb.classList.contains("hidden")) nb.click();
    else $('#quiz-options .quiz-option[data-ok="1"]').click();
    await sleep(220);
  }
  check("retry-summary", $("#summary-backdrop").classList.contains("is-open"));
  check("retry-all-clean", /знаю \d+ · не знаю 0/.test($("#summary-line").textContent), $("#summary-line").textContent);
  check("repeat-mode-quizall", $("#summary-repeat").dataset.mode === "quiz-all" && $("#summary-repeat").textContent === "Пройти ещё раз", $("#summary-repeat").dataset.mode);

  $("#summary-menu").click(); await sleep(500);
  check("menu-after-summary", $("#menu-backdrop").classList.contains("is-open"));

  $("#menu-close").click(); await sleep(400);
  $("#tab-study").click(); await sleep(500);
  $("#study-mode-quiz").click(); await sleep(300);
  $('[data-qlen="10"]').click(); await sleep(300);
  check("qfs-clamp", /из 6/.test($("#quiz-meta").textContent), $("#quiz-meta").textContent);

  $("#quiz-focus-btn").click(); await sleep(400);
  check("qfs-open", $("#focus-backdrop").classList.contains("is-open") && $("#focus-wrap").contains($("#quiz-area")));
  const wr = $("#focus-wrap").getBoundingClientRect();
  const ar = $("#quiz-area").getBoundingClientRect();
  check("qfs-sheet-fills", Math.abs(wr.width - ar.width) <= 2 && Math.abs(wr.height - ar.height) <= 2, Math.round(wr.width) + "x" + Math.round(wr.height) + " vs " + Math.round(ar.width) + "x" + Math.round(ar.height));
  const sheetBg = getComputedStyle($("#quiz-area")).backgroundColor;
  check("qfs-sheet-opaque", sheetBg !== "rgba(0, 0, 0, 0)" && sheetBg !== "transparent", sheetBg);
  check("qfs-controls-hidden", $("#focus-controls").classList.contains("hidden"));
  const qs = getComputedStyle($("#focus-wrap"), "::before");
  check("qfs-shadow", qs.backgroundColor !== "rgba(0, 0, 0, 0)" && qs.backgroundColor !== "transparent", qs.backgroundColor);
  check("qfs-bigfont", parseFloat(getComputedStyle($("#quiz-question")).fontSize) >= 30, getComputedStyle($("#quiz-question")).fontSize);

  const barBefore = $("#quiz-fill").style.width;
  $('#quiz-options .quiz-option[data-ok="1"]').click(); await sleep(250);
  const barAfter = $("#quiz-fill").style.width;
  check("qfs-bar-progress", barBefore === "0%" && parseFloat(barAfter) > 0, barBefore + " -> " + barAfter);
  const metaSaved = $("#quiz-meta").textContent;

  $("#focus-exit").click(); await sleep(400);
  check("qfs-exit-home", !$("#focus-backdrop").classList.contains("is-open") && $("#study-board").contains($("#quiz-area")) && !$("#focus-controls").classList.contains("hidden"));
  check("qfs-progress-saved", $("#quiz-meta").textContent === metaSaved && !$("#quiz-next").classList.contains("hidden"), $("#quiz-meta").textContent);

  $("#quiz-focus-btn").click(); await sleep(300);
  $("#focus-backdrop").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })); await sleep(300);
  check("qfs-esc-closes", !$("#focus-backdrop").classList.contains("is-open") && $("#study-board").contains($("#quiz-area")));
  $("#quiz-focus-btn").click(); await sleep(300);

  for (let guard = 0; guard < 14; guard += 1) {
    if ($("#summary-backdrop").classList.contains("is-open")) break;
    const nb = $("#quiz-next");
    if (!nb.classList.contains("hidden")) nb.click();
    else $('#quiz-options .quiz-option[data-ok="1"]').click();
    await sleep(220);
  }
  check("qfs-summary-over", $("#summary-backdrop").classList.contains("is-open") && $("#focus-backdrop").classList.contains("is-open") && $("#summary-backdrop").style.zIndex === "66");

  $("#summary-repeat").click(); await sleep(400);
  check("qfs-retry-in-fs", !$("#summary-backdrop").classList.contains("is-open") && $("#focus-backdrop").classList.contains("is-open") && $("#focus-wrap").contains($("#quiz-area")) && /вопрос 1 из 6/.test($("#quiz-meta").textContent), $("#quiz-meta").textContent);

  for (let guard = 0; guard < 14; guard += 1) {
    if ($("#summary-backdrop").classList.contains("is-open")) break;
    const nb = $("#quiz-next");
    if (!nb.classList.contains("hidden")) nb.click();
    else $('#quiz-options .quiz-option[data-ok="1"]').click();
    await sleep(220);
  }
  check("qfs-summary2-over", $("#summary-backdrop").classList.contains("is-open") && $("#focus-backdrop").classList.contains("is-open"));

  $("#summary-menu").click(); await sleep(500);
  check("qfs-menu-exits", $("#menu-backdrop").classList.contains("is-open") && !$("#focus-backdrop").classList.contains("is-open") && $("#study-board").contains($("#quiz-area")));

  const units = [];
  const built = buildOptions({ id: "z", answer: "X" }, [
    { id: "a", answer: "A" }, { id: "b", answer: "B" }, { id: "c", answer: "C" }, { id: "d", answer: "D" },
  ]);
  units.push(built.length === 4 && new Set(built.map((o) => o.text)).size === 4);
  units.push(built.some((o) => o.ok && o.text === "X"));
  units.push(built.filter((o) => o.ok).length === 1);
  check("unit-buildoptions", units.every(Boolean), JSON.stringify(units));

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
  check("menu-open-b", $("#menu-backdrop").classList.contains("is-open"));
  $("#menu-close").click(); await sleep(400);
  $("#tab-study").click(); await sleep(500);

  check("mode-reset-flip", !$("#flip-area").classList.contains("hidden") && $("#quiz-area").classList.contains("hidden") && $("#study-mode-flip").classList.contains("is-active"));
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
  Write-Output ("=== QUIZ TOTAL: A {0} checks / {1} fails, B {2} checks / {3} fails ===" -f $results.Count, $failsA, $resultsB.Count, $failsB)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}






























