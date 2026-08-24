param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9237 })
$udir = "C:\Users\Lenovo\AppData\Local\Temp\opencode\cdp-unit-profile"
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
localStorage.removeItem("flashcards-app-v1");
localStorage.setItem("flashcards-onboarded", "1");
window.__errors = [];
window.addEventListener("error", function (e) { window.__errors.push((e.error && e.error.stack) || String(e.message)); });
window.addEventListener("unhandledrejection", function (e) { window.__errors.push(String(e.reason)); });
'@
  $scenario = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });

  // --- dateKey / todayDateKey ---
  const d = new Date(2026, 7, 5);
  check("dateKey", dateKey(d) === "2026-08-05", dateKey(d));
  check("dateKey-pad", dateKey(new Date(2026, 0, 1)) === "2026-01-01", dateKey(new Date(2026, 0, 1)));
  check("todayDateKey", /^\d{4}-\d{2}-\d{2}$/.test(todayDateKey()) && todayDateKey() === dateKey(new Date()), todayDateKey());

  // --- uid ---
  const ids = new Set();
  for (let i = 0; i < 250; i++) ids.add(uid());
  check("uid-unique", ids.size === 250, String(ids.size));
  check("uid-string", Array.from(ids).every((id) => typeof id === "string" && id.length > 5));

  // --- shuffle ---
  const arr = Array.from({ length: 100 }, (_, i) => i);
  const sh = shuffle(arr);
  check("shuffle-length", sh.length === arr.length, String(sh.length));
  check("shuffle-perm", JSON.stringify([...sh].sort((a, b) => a - b)) === JSON.stringify(arr));
  const sorted1 = shuffle([1]);
  check("shuffle-single", sorted1.length === 1 && sorted1[0] === 1);
  check("shuffle-empty", shuffle([]).length === 0);

  // --- normalizeState garbage ---
  const base = normalizeState(null);
  check("ns-null", base.decks.length === 0 && base.cards.length === 0 && base.selectedDeckId === null && base.sessions.length === 0 && base.history !== null, JSON.stringify(base));
  check("ns-null-today", base.today.date === todayDateKey() && base.today.known === 0 && base.today.unknown === 0);
  const empty = normalizeState({});
  check("ns-empty", empty.decks.length === 0 && empty.cards.length === 0);
  const asString = normalizeState("garbage");
  check("ns-string", asString.decks.length === 0);

  // --- decks normalization ---
  const ns = normalizeState({
    decks: [
      { id: "a", name: "  Отряд  " },
      { id: "b", name: "   " },
      { id: "a", name: "Дубль" },
      { id: "c", name: "x".repeat(120) },
      "не-объект",
      null,
      { id: "d", name: 42 },
    ],
    cards: [],
  });
  check("ns-decks-count", ns.decks.length === 2, String(ns.decks.length));
  check("ns-decks-trim", ns.decks[0].name === "Отряд", ns.decks[0].name);
  check("ns-decks-dedup", !ns.decks.some((x) => x.name === "Дубль"));
  check("ns-decks-trunc", ns.decks[1].name.length === 80 && ns.decks[1].name === "x".repeat(80), String(ns.decks[1].name.length));

  // --- cards normalization ---
  const nc = normalizeState({
    decks: [{ id: "d1", name: "D" }],
    cards: [
      { id: "c1", deckId: "d1", question: " q ", answer: "a", status: "known" },
      { id: "c2", deckId: "nope", question: "x", answer: "y" },
      { id: "c3", deckId: "d1", question: "", answer: "y" },
      { id: "c4", deckId: "d1", question: "x", answer: "" },
      { id: "c5", deckId: "d1", question: "x", answer: "y", status: "bogus" },
      { id: "c1", deckId: "d1", question: "dup", answer: "dup" },
      { deckId: "d1", question: "no-id", answer: "a" },
      { id: "c6", deckId: "d1", question: "x", answer: "y", status: "unknown" },
    ],
  });
  check("ns-cards-count", nc.cards.length === 4, String(nc.cards.length));
  check("ns-cards-q", nc.cards[0].question === " q ", nc.cards[0].question);
  check("ns-cards-known", nc.cards.find((c) => c.id === "c1").status === "known");
  check("ns-cards-unknown", nc.cards.find((c) => c.id === "c6").status === "unknown");
  check("ns-cards-new", nc.cards.find((c) => c.id === "c5").status === "new");
  check("ns-cards-newid", nc.cards.some((c) => c.question === "no-id" && typeof c.id === "string" && c.id.length > 5));
  check("ns-cards-no-dup", nc.cards.filter((c) => c.id === "c1").length === 1);

  // --- selectedDeckId ---
  check("ns-selected-null", normalizeState({ decks: [{ id: "d1", name: "D" }], selectedDeckId: "zzz" }).selectedDeckId === null);
  check("ns-selected-ok", normalizeState({ decks: [{ id: "d1", name: "D" }], selectedDeckId: "d1" }).selectedDeckId === "d1");

  // --- today normalization ---
  const nt = normalizeState({ today: { date: "2020-01-02", known: -5, unknown: 3.7 } });
  check("ns-today", nt.today.date === "2020-01-02" && nt.today.known === 0 && nt.today.unknown === 3, JSON.stringify(nt.today));
  const nt2 = normalizeState({ today: { known: 1 } });
  check("ns-today-missing-date", nt2.today.date === todayDateKey(), nt2.today.date);

  // --- history normalization ---
  const nh = normalizeState({ history: { d1: { "2026-08-20": { known: 2, unknown: -1 }, bad: "x" }, d2: "no" } });
  check("ns-history", JSON.stringify(nh.history) === JSON.stringify({ d1: { "2026-08-20": { known: 2, unknown: 0 } } }), JSON.stringify(nh.history));
  check("ns-history-empty", JSON.stringify(normalizeState({ history: null }).history) === "{}");

  // --- sessions normalization ---
  const nss = normalizeState({ sessions: [{ deckId: "d1", date: "2026-08-20T12:00:00.000Z", known: 1, unknown: 1 }, { date: "x" }, "bad", { deckId: "d1", date: "2020", known: -2, unknown: 4 }] });
  check("ns-sessions-count", nss.sessions.length === 2, String(nss.sessions.length));
  check("ns-sessions-date", nss.sessions[0].date === "2026-08-20", nss.sessions[0].date);
  check("ns-sessions-clamp", nss.sessions[1].known === 0 && nss.sessions[1].unknown === 4, JSON.stringify(nss.sessions[1]));
  check("ns-sessions-array", normalizeState({ sessions: "no" }).sessions.length === 0);

  // --- splitBulkPair / parseBulkLines ---
  check("bulk-simple", JSON.stringify(splitBulkPair("вопрос = ответ")) === JSON.stringify(["вопрос", "ответ"]));
  check("bulk-spaces", JSON.stringify(splitBulkPair("  q  =  a  ")) === JSON.stringify(["q", "a"]));
  check("bulk-multi", JSON.stringify(splitBulkPair("a=b=c")) === JSON.stringify(["a", "b=c"]));
  check("bulk-no-sep", splitBulkPair("no separator") === null);
  check("bulk-leading", splitBulkPair("= x") === null);
  check("bulk-trailing", splitBulkPair("q =") === null);
  check("bulk-empty-q", splitBulkPair(" = a") === null);
  const pairs = parseBulkLines("one = 1\ntwo=2\n\nбез разделителя\nthree = 3\n");
  check("bulk-parse-count", pairs.length === 3, String(pairs.length));
  check("bulk-parse-order", JSON.stringify(pairs[0]) === JSON.stringify(["one", "1"]) && JSON.stringify(pairs[2]) === JSON.stringify(["three", "3"]), JSON.stringify(pairs));
  check("bulk-parse-empty", parseBulkLines("").length === 0 && parseBulkLines("\n \n").length === 0);

  // --- recordStudy / recordSession / stats ---
  state.history = {};
  state.sessions = [];
  recordStudy("d1", "known");
  recordStudy("d1", "known");
  recordStudy("d1", "unknown");
  recordStudy("d1", "bogus");
  check("record-study", state.history.d1[todayDateKey()].known === 2 && state.history.d1[todayDateKey()].unknown === 1, JSON.stringify(state.history));
  recordSession("d1", 2, -1);
  check("record-session", state.sessions.length === 1 && state.sessions[0].known === 2 && state.sessions[0].unknown === 0 && state.sessions[0].date === todayDateKey(), JSON.stringify(state.sessions));
  const all = getAllTimeStats();
  check("alltime-sum", all.known === 2 && all.unknown === 1, JSON.stringify(all));
  check("deck-history-missing", JSON.stringify(getDeckHistory("nope")) === "{}");
  check("deck-history-hit", getDeckHistory("d1") === state.history.d1);
  state.history = {};
  check("alltime-empty", JSON.stringify(getAllTimeStats()) === JSON.stringify({ known: 0, unknown: 0 }));

  // --- selectedDeck / cardsInDeck ---
  state.decks = [{ id: "x", name: "X" }, { id: "y", name: "Y" }];
  state.selectedDeckId = "x";
  check("selected-hit", selectedDeck().id === "x" && selectedDeck().name === "X");
  state.selectedDeckId = "zzz";
  check("selected-null", selectedDeck() === null);
  state.cards = [{ id: "c", deckId: "x", status: "new" }, { id: "d", deckId: "y", status: "new" }];
  check("cards-in-deck-x", cardsInDeck("x").length === 1, String(cardsInDeck("x").length));
  check("cards-in-deck-z", cardsInDeck("z").length === 0);

  // --- resetTodayIfNeeded ---
  state.today = { date: "1999-01-01", known: 5, unknown: 5 };
  resetTodayIfNeeded();
  check("reset-today", state.today.date === todayDateKey() && state.today.known === 0 && state.today.unknown === 0, JSON.stringify(state.today));
  const keep = state.today.known;
  resetTodayIfNeeded();
  check("reset-today-same-day", state.today.known === 0);

  // --- computeStreak / pluralDays ---
  const s0 = new Date();
  const s1 = new Date(s0); s1.setDate(s1.getDate() - 1);
  const s2 = new Date(s0); s2.setDate(s2.getDate() - 2);
  const s3 = new Date(s0); s3.setDate(s3.getDate() - 3);
  const day = (d) => dateKey(d);
  state.history = {};
  check("streak-empty", computeStreak() === 0, String(computeStreak()));
  state.history = { a: { [day(s0)]: { known: 1, unknown: 0 }, [day(s1)]: { known: 2, unknown: 0 } } };
  check("streak-2", computeStreak() === 2, String(computeStreak()));
  state.history.a[day(s2)] = { known: 1, unknown: 0 };
  state.history.a[day(s3)] = { known: 1, unknown: 0 };
  check("streak-4", computeStreak() === 4, String(computeStreak()));
  delete state.history.a[day(s2)];
  delete state.history.a[day(s1)];
  check("streak-gap", computeStreak() === 1, String(computeStreak()));
  state.history = { a: { [day(s1)]: { known: 1, unknown: 0 } } };
  check("streak-alive-today-zero", computeStreak() === 1, String(computeStreak()));
  state.history = { a: { [day(s1)]: { known: 0, unknown: 0 } } };
  check("streak-zero-day", computeStreak() === 0, String(computeStreak()));
  state.history = { a: { [day(s0)]: { known: 1, unknown: 0 } }, b: { [day(s1)]: { known: 1, unknown: 0 } } };
  check("streak-across-decks", computeStreak() === 2, String(computeStreak()));
  check("plural-days", pluralDays(1) === "день" && pluralDays(2) === "дня" && pluralDays(4) === "дня" && pluralDays(5) === "дней" && pluralDays(11) === "дней" && pluralDays(21) === "день" && pluralDays(22) === "дня", [pluralDays(1), pluralDays(2), pluralDays(5), pluralDays(11), pluralDays(21), pluralDays(22)].join("|"));

  // --- isRoundComplete ---
  state.studyOrder = ["a", "b"];
  sessionMarked = new Set(["a"]);
  check("round-not-complete", isRoundComplete() === false);
  sessionMarked = new Set(["a", "b"]);
  check("round-complete", isRoundComplete() === true);
  state.studyOrder = [];
  sessionMarked = new Set(["a"]);
  check("round-empty-order", isRoundComplete() === false);
  state.studyOrder = ["a"];
  sessionMarked = new Set(["a"]);
  check("round-single", isRoundComplete() === true);

  // --- badgeFor ---
  check("badge-known", badgeFor({ status: "known" }).className === "badge known" && badgeFor({ status: "known" }).textContent === "знаю");
  check("badge-unknown", badgeFor({ status: "unknown" }).className === "badge unknown" && badgeFor({ status: "unknown" }).textContent === "не знаю");
  check("badge-new", badgeFor({ status: "new" }).className === "badge" && badgeFor({ status: "new" }).textContent === "новая");

  // --- makeEl ---
  const el = makeEl("div", "x y", "text");
  check("makeel", el.tagName === "DIV" && el.className === "x y" && el.textContent === "text");
  const el2 = makeEl("span");
  check("makeel2", el2.tagName === "SPAN" && el2.className === "" && el2.textContent === "");
  const el3 = makeEl("p", "", "t");
  check("makeel3", el3.className === "" && el3.textContent === "t");

  // --- constants ---
  check("constants", STORAGE_KEY === "flashcards-app-v1" && MODE_KEY === "flashcards-mode" && PALETTE_KEY === "flashcards-palette" && ONBOARD_KEY === "flashcards-onboarded");
  check("valid-statuses", VALID_STATUSES.has("new") && VALID_STATUSES.has("known") && VALID_STATUSES.has("unknown") && VALID_STATUSES.size === 3);
  check("max-name", MAX_NAME_LENGTH === 80);

  // --- corrupt payload backup ---
  const corruptRaw = '{"v":1,"decks":[{"broken';
  state.decks = [];
  state.cards = [];
  localStorage.setItem(STORAGE_KEY, corruptRaw);
  localStorage.removeItem(CORRUPT_KEY);
  loadState();
  check("corrupt-backup", localStorage.getItem(CORRUPT_KEY) === corruptRaw, String(localStorage.getItem(CORRUPT_KEY)));
  check("corrupt-state-empty", state.decks.length === 0 && state.cards.length === 0);
  localStorage.setItem(STORAGE_KEY, JSON.stringify({ v: 1, decks: [{ id: "ok", name: "OK" }], cards: [], selectedDeckId: null, today: { date: todayDateKey(), known: 0, unknown: 0 }, history: {}, sessions: [] }));
  loadState();
  check("recover-after-corrupt", state.decks.length === 1 && state.decks[0].id === "ok");
  localStorage.removeItem(STORAGE_KEY);
  localStorage.removeItem(CORRUPT_KEY);
  check("demo-decks", DEMO_DECKS.length === 3 && DEMO_DECKS[0].cards.length === 30 && DEMO_DECKS[1].cards.length === 12 && DEMO_DECKS[2].cards.length === 15);

  check("no-errors", Array.isArray(window.__errors) && window.__errors.length === 0, JSON.stringify(window.__errors || []));
  return JSON.stringify(res);
})()
'@
  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3
  $res = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenario; awaitPromise = $true; returnByValue = $true }
  $results = $res.result.value | ConvertFrom-Json
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  $fails = @($results | Where-Object { -not $_.ok }).Count
  Write-Output ("=== UNIT TOTAL: {0} checks, {1} fails ===" -f $results.Count, $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}




















