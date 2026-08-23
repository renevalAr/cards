param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp  = "$env:TEMP\opencode"
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromeExe)) { $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" }
$prof = Join-Path $tmp ("data-prof-" + [guid]::NewGuid().ToString("N"))
$p = Start-Process -FilePath $chromeExe -ArgumentList @(
  "--headless=new", "--remote-debugging-port=$(if ($DebugPort -gt 0) { $DebugPort } else { 9344 })",
  "--user-data-dir=$prof", "--no-first-run", "--window-size=1280,900", "about:blank"
) -PassThru

$ws = $null
try {
  Start-Sleep -Milliseconds 2500
  Add-Type -AssemblyName System.Net.Http
  $targets = Invoke-RestMethod "http://127.0.0.1:$(if ($DebugPort -gt 0) { $DebugPort } else { 9344 })/json"
  $wsUrl = ($targets | Where-Object { $_.type -eq "page" } | Select-Object -First 1).webSocketDebuggerUrl
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ct = [System.Threading.CancellationToken]::None
  $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()
  $script:n = 0

  function Send-Ws($o) {
    $script:n++; $o.id = $script:n
    $b = [Text.Encoding]::UTF8.GetBytes(($o | ConvertTo-Json -Compress -Depth 8))
    $ws.SendAsync([ArraySegment[byte]]::new($b), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
  }
  function Recv-Ws {
    $buf = New-Object byte[] (8MB)
    while ($true) {
      $ms = New-Object System.IO.MemoryStream
      do { $seg = [ArraySegment[byte]]::new($buf); $r = $ws.ReceiveAsync($seg, $ct).Result
           if ($r.Count -eq 0) { throw "ws closed" }
           $ms.Write($buf, 0, $r.Count) } while (-not $r.EndOfMessage)
      $m = [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
      if ($m.PSObject.Properties["id"]) { return $m }
    }
  }
  function EvalRaw($expr) {
    Send-Ws @{ method = "Runtime.evaluate"; params = @{ expression = $expr; returnByValue = $true; awaitPromise = $true } }
    return Recv-Ws
  }
  function Eval($expr) {
    $m = EvalRaw $expr
    if ($m.result.PSObject.Properties["exceptionDetails"]) {
      throw ("page exc: " + ($m.result.exceptionDetails.exception.description))
    }
    return $m.result.result.value
  }

  Send-Ws @{ method = "Page.enable"; params = @{} } | Out-Null
  Recv-Ws | Out-Null
  $seedJs = "(function(){window.addEventListener('error',function(e){(window.__errs=window.__errs||[]).push(String(e.message));});var t=new Date();function k(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')} localStorage.clear(); localStorage.setItem('flashcards-onboarded','1'); localStorage.setItem('flashcards-app-v1', JSON.stringify({decks:[{id:'d1',name:'Альфа'},{id:'d2',name:'Бета'}], cards:[{id:'c1',deckId:'d1',question:'alpha',answer:'one',status:'new'},{id:'c2',deckId:'d1',question:'beta',answer:'two',status:'known'},{id:'c3',deckId:'d2',question:'gamma',answer:'three',status:'unknown'}], selectedDeckId:'d1', today:{date:k(t),known:0,unknown:0}, history:{}, sessions:[]})); })()"
  Send-Ws @{ method = "Page.addScriptToEvaluateOnNewDocument"; params = @{ source = $seedJs } } | Out-Null
  Recv-Ws | Out-Null
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/index.html" } } | Out-Null
  Recv-Ws | Out-Null
  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $v = Eval "(function(){return [document.readyState, typeof state, !!document.getElementById('card-rows'), typeof handleImportText].join(String.fromCharCode(124))})()"
      if ("$v" -eq "complete|object|True|function") { $ready = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 400
  }
  Write-Output ("APP ERRORS: " + (Eval "JSON.stringify(window.__errs||'none')"))
  if (-not $ready) { throw "app not ready" }

  $scenario = @'
(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const q = (id) => document.getElementById(id);
  const res = [];
  const check = (s, ok, d) => res.push({ step: s, ok: !!ok, detail: String(d == null ? "" : d) });
  await sleep(600);
  q("menu-close").click(); await sleep(300);

  // UI wiring
  openSettingsModal(); await sleep(300);
  check("ui-settings-buttons", !!q("export-all-btn") && !!q("export-csv-btn") && !!q("import-btn") && !q("import-file").hidden === false);
  closeSettingsModal(); await sleep(250);

  // Export payload builder (unit): full base shape
  const payload = buildBackupPayload();
  check("exp-shape", payload.v === 2 && payload.kind === "base" && payload.decks.length === 2 && payload.cards.length === 3,
    JSON.stringify({v:payload.v,k:payload.kind,d:payload.decks.length,c:payload.cards.length}));

  // Deck export payload (unit via capture of downloadBlob)
  let captured = null;
  const origDl = window.downloadBlob;
  window.downloadBlob = (name, text) => { captured = { name, text }; };
  exportDeckJson("d1");
  window.downloadBlob = origDl;
  const deckPayload = JSON.parse(captured.text);
  check("exp-deck-payload", deckPayload.kind === "deck" && deckPayload.deck.name === "Альфа" && deckPayload.cards.length === 2, captured.name);
  check("exp-deck-filename", /^колода-альфа-\d{4}-\d{2}-\d{2}\.json$/.test(captured.name), captured.name);

  // CSV round-trip
  window.downloadBlob = (name, text) => { captured = { name, text }; };
  exportBaseCsv();
  window.downloadBlob = origDl;
  const csvLines = captured.text.split(/\r?\n/).filter(Boolean);
  check("exp-csv-header", csvLines[0] === "deck;question;answer;status", csvLines[0]);
  check("exp-csv-rows", csvLines.length === 4, "lines=" + csvLines.length);
  const parsedCsv = parseImportCsv(captured.text);
  const csvTotal = [...parsedCsv.cardsByDeck.values()].reduce((n, a) => n + a.length, 0);
  check("csv-roundtrip", parsedCsv.kind === "csv" && csvTotal === 3, "total=" + csvTotal);

  // CSV quoted field with ; inside
  const tricky = 'deck;question;answer;status\r\nАльфа;"вопрос; с точкой";"ответ ""в кавычках""";new';
  const pTricky = parseImportCsv(tricky);
  const tCard = pTricky.cardsByDeck.get("Альфа")[0];
  check("csv-quoting", tCard.question === "вопрос; с точкой" && tCard.answer === 'ответ "в кавычках"', JSON.stringify(tCard));

  // CSV merge into existing decks by name + dedupe identical row
  applyImport(parsedCsv, "merge"); await sleep(300);
  check("csv-merge-counts", state.decks.length === 2 && state.cards.length === 3,
    "decks=" + state.decks.length + " cards=" + state.cards.length);
  check("csv-toast-ok", !q("storage-alert").hidden && q("storage-alert").classList.contains("is-ok"), q("storage-alert").textContent);

  // JSON deck-file import: dialog opens with summary, then merge by name (idempotent second time)
  const deckFile = JSON.stringify({ v: 2, kind: "deck", deck: { id: "x9", name: "Дельта" }, cards: [{ question: "dq1", answer: "da1", status: "new" }, { question: "alpha", answer: "one", status: "new" }] });
  handleImportText(deckFile, "delta.json"); await sleep(300);
  check("imp-dialog-open", q("data-backdrop").classList.contains("is-open") && q("data-text").textContent.includes("Дельта"), q("data-text").textContent);
  q("data-merge").click(); await sleep(350);
  const delta = state.decks.find((d) => d.name === "Дельта");
  check("imp-deck-merged", !!delta && delta.id !== "x9", delta ? delta.id : "none");
  const deltaCards = cardsInDeck(delta.id);
  check("imp-deck-dedupe-vs-other-deck", deltaCards.length === 2, "cards=" + deltaCards.length);
  // re-import same file -> same deck, no new cards
  handleImportText(deckFile, "delta.json"); await sleep(200);
  q("data-merge").click(); await sleep(350);
  check("imp-deck-idempotent", state.decks.filter((d) => d.name === "Дельта").length === 1 && cardsInDeck(delta.id).length === 2,
    "decks=" + state.decks.length + " cards=" + cardsInDeck(delta.id).length);

  // Base JSON import dialog opens; replace is tested later with a tiny file (real overwrite)
  const baseFile = JSON.stringify(buildBackupPayload());
  handleImportText(baseFile, "backup.json"); await sleep(200);
  check("imp-base-dialog", q("data-backdrop").classList.contains("is-open"));
  q("data-cancel").click(); await sleep(250);

  // Base merge from a foreign snapshot: new deck + overlapping card deduped per target deck
  const foreign = { v: 2, kind: "base", decks: [{ id: "f1", name: "Альфа" }, { id: "f2", name: "Иностранная" }], cards: [
    { id: "fc1", deckId: "f1", question: "alpha", answer: "one", status: "new" },
    { id: "fc2", deckId: "f1", question: "новый вопрос", answer: "новый ответ", status: "known" },
    { id: "fc3", deckId: "f2", question: "fq", answer: "fa", status: "unknown" } ], today: null, history: {}, sessions: [] };
  handleImportText(JSON.stringify(foreign), "foreign.json"); await sleep(200);
  q("data-merge").click(); await sleep(400);
  check("imp-merge-twin-mapped", state.decks.length === 4, "decks=" + state.decks.length);
  const alphaDeck = state.decks.find((d) => d.name === "Альфа");
  check("imp-merge-dedupe-in-twin", cardsInDeck(alphaDeck.id).length === 3, "alpha cards=" + cardsInDeck(alphaDeck.id).length);
  check("imp-merge-new-deck-cards", cardsInDeck(state.decks.find((d) => d.name === "Иностранная").id).length === 1,
    "ino cards=" + cardsInDeck(state.decks.find((d) => d.name === "Иностранная").id).length);

  // Real REPLACE with a tiny foreign base
  const tiny = { v: 2, kind: "base", decks: [{ id: "z1", name: "Один" }], cards: [
    { id: "zc1", deckId: "z1", question: "tq1", answer: "ta1", status: "new" },
    { id: "zc2", deckId: "z1", question: "tq2", answer: "ta2", status: "known" } ], today: null, history: {}, sessions: [] };
  handleImportText(JSON.stringify(tiny), "tiny.json"); await sleep(200);
  q("data-replace").click(); await sleep(350);
  check("imp-base-replace-real", state.decks.length === 1 && state.decks[0].name === "Один" && state.cards.length === 2,
    "decks=" + state.decks.length + " cards=" + state.cards.length);
  check("imp-base-replace-selected", state.selectedDeckId === state.decks[0].id);

  // Bad file -> warn toast, no crash
  handleImportText("{ broken json !!!", "bad.json"); await sleep(250);
  check("imp-bad-warn", q("storage-alert").classList.contains("is-warn") && !q("storage-alert").hidden, q("storage-alert").textContent.slice(0, 24));
  check("imp-bad-no-dialog", !q("data-backdrop").classList.contains("is-open"));

  // sessions cap at 200
  for (let i = 0; i < 205; i++) recordSession(state.selectedDeckId, 1, 0);
  saveState();
  check("sessions-cap-200", state.sessions.length === 200, "len=" + state.sessions.length);

  // Esc cascade covers data layer when focus on body
  handleImportText(deckFile, "delta.json"); await sleep(150);
  document.activeElement.blur();
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })); await sleep(300);
  check("esc-data-layer", !q("data-backdrop").classList.contains("is-open"));

  check("no-errors", Array.isArray(window.__errs) ? window.__errs.length === 0 : true, JSON.stringify(window.__errs || []));
  return JSON.stringify(res);
})()
'@

  Send-Ws @{ method = "Runtime.evaluate"; params = @{ expression = $scenario; returnByValue = $true; awaitPromise = $true } }
  $resp = Recv-Ws
  if ($resp.result.PSObject.Properties["exceptionDetails"]) {
    Write-Output ("SCENARIO EXC: " + ($resp.result.exceptionDetails.exception.description))
  }
  $json = $resp.result.result.value
  $arr = $json | ConvertFrom-Json
  foreach ($r in $arr) {
    $mark = if ($r.ok) { "[PASS]" } else { "[FAIL]" }
    Write-Output "$mark $($r.step)  $($r.detail)"
  }
}
catch {
  Write-Output ("HARNESS ERROR: " + $_.Exception.Message)
}
finally {
  if ($p) { try { $p.Kill() } catch {} }
  Start-Sleep -Milliseconds 300
  if (Test-Path $prof) { Remove-Item $prof -Recurse -Force -ErrorAction SilentlyContinue }
}










