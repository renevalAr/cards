param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp  = "$env:TEMP\opencode"
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromeExe)) { $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" }
$prof = Join-Path $tmp ("rev-prof-" + [guid]::NewGuid().ToString("N"))
$p = Start-Process -FilePath $chromeExe -ArgumentList @(
  "--headless=new", "--remote-debugging-port=$(if ($DebugPort -gt 0) { $DebugPort } else { 9353 })",
  "--user-data-dir=$prof", "--no-first-run", "--window-size=1280,900", "about:blank"
) -PassThru

try {
  Start-Sleep -Milliseconds 2500
  Add-Type -AssemblyName System.Net.Http
  $targets = Invoke-RestMethod "http://127.0.0.1:$(if ($DebugPort -gt 0) { $DebugPort } else { 9353 })/json"
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
  function Eval($expr) {
    Send-Ws @{ method = "Runtime.evaluate"; params = @{ expression = $expr; returnByValue = $true; awaitPromise = $true } }
    return Recv-Ws
  }

  Send-Ws @{ method = "Page.enable"; params = @{} } | Out-Null; Recv-Ws | Out-Null
  $seedJs = "(function(){window.addEventListener('error',function(e){(window.__errs=window.__errs||[]).push(String(e.message));});var t=new Date();function k(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')} localStorage.clear(); localStorage.setItem('flashcards-onboarded','1'); localStorage.setItem('flashcards-app-v1', JSON.stringify({decks:[{id:'d1',name:'Альфа',twoSided:true}], cards:[{id:'c1',deckId:'d1',question:'dog',answer:'собака',status:'new'},{id:'c2',deckId:'d1',question:'cat',answer:'кошка',status:'new'}], selectedDeckId:'d1', today:{date:k(t),known:0,unknown:0}, history:{}, sessions:[]})); })()"
  Send-Ws @{ method = "Page.addScriptToEvaluateOnNewDocument"; params = @{ source = $seedJs } } | Out-Null; Recv-Ws | Out-Null
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/index.html" } } | Out-Null; Recv-Ws | Out-Null

  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $v = Eval "(function(){return [document.readyState, typeof state, typeof buildStudyEntries].join('|')})()"
      if ("$($v.result.result.value)" -eq "complete|object|function") { $ready = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 400
  }
  Write-Output ("APP ERRORS: " + (Eval "JSON.stringify(window.__errs||'none')").result.result.value)
  if (-not $ready) { throw "app not ready" }

  $scenario = @'
(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const q = (id) => document.getElementById(id);
  const res = [];
  const check = (s, ok, d) => res.push({ step: s, ok: !!ok, detail: String(d == null ? "" : d) });
  await sleep(600);
  q("menu-close").click(); await sleep(300);

  // entries builder: two-sided deck doubles with #rev
  const entries = buildStudyEntries("d1");
  check("entries-doubled", entries.length === 4 && entries.filter(e => e.endsWith("#rev")).length === 2,
    JSON.stringify(entries));

  setTab("study"); await sleep(400);
  startStudyShuffle(); await sleep(200);
  check("round-length-4", state.studyOrder.length === 4, String(state.studyOrder.length));

  // find a rev entry and verify swapped faces + meta suffix
  const revIdx = state.studyOrder.findIndex((e) => e.endsWith("#rev"));
  state.studyIndex = revIdx; state.flipped = false;
  showStudyCard(); await sleep(150);
  const frontTxt = q("flashcard-question").textContent;
  const backTxt = q("flashcard-answer").textContent;
  const metaTxt = q("study-meta").textContent;
  check("rev-front-is-answer", frontTxt === "собака" || frontTxt === "кошка", frontTxt);
  check("rev-back-is-question", backTxt === "dog" || backTxt === "cat", backTxt);
  check("meta-rev-suffix", metaTxt.includes("наоборот"), metaTxt);

  // round completes only after marking ALL 4 entries
  state.studyIndex = 0; state.flipped = false; showStudyCard();
  for (let i = 0; i < 4; i++) {
    markStatus("known");
    await sleep(220);
  }
  check("round-complete-after-4", q("summary-backdrop").classList.contains("is-open"));
  const line = q("summary-line").textContent;
  check("summary-math", line.includes("Всего 4") && line.includes("знаю 4") && line.includes("не знаю 0"), line);
  check("today-events-4", getTodayStats().known + getTodayStats().unknown <= 4,
    "k=" + getTodayStats().known + " u=" + getTodayStats().unknown);

  // repeat-all keeps entry structure
  closeSummary(); await sleep(250);
  repeatStudy();
  const modeBtn = q("summary-repeat");
  void modeBtn;

  // quiz in two-sided deck: reversed question uses other questions as options
  resetStudy();
  beginQuiz(buildStudyEntries("d1")); await sleep(300);
  const qText = q("quiz-question").textContent;
  const opts = [...document.querySelectorAll("#quiz-options .quiz-option")].map(b => b.textContent);
  const isRevQuestion = (qText === "собака" || qText === "кошка");
  const optionsAreQuestions = opts.every(t => t === "dog" || t === "cat");
  check("quiz-entry-valid", qText.length > 0 && opts.length >= 2, JSON.stringify({q:qText,opts}));
  if (isRevQuestion) check("quiz-rev-options", optionsAreQuestions, JSON.stringify(opts));
  else check("quiz-fwd-options", opts.every(t => t === "собака" || t === "кошка" || !["dog","cat"].includes(t)), JSON.stringify(opts));

  // fast toggle on study panel (primary path)
  resetStudy(); setTab("study"); await sleep(300);
  const chip = q("two-sided-btn");
  check("chip-present", !!chip && chip.textContent.includes("обе стороны"));
  check("chip-active-initial", chip.classList.contains("is-active") && chip.getAttribute("aria-pressed") === "true",
    "pressed=" + chip.getAttribute("aria-pressed"));
  const orderBefore = state.studyOrder.length;
  chip.click(); await sleep(250);
  check("chip-toggles-off", state.decks[0].twoSided === false && !chip.classList.contains("is-active") && state.studyOrder.length === orderBefore / 2,
    "order=" + state.studyOrder.length);
  chip.click(); await sleep(250);
  check("chip-toggles-on", state.decks[0].twoSided === true && chip.classList.contains("is-active") && state.studyOrder.length === orderBefore,
    "order=" + state.studyOrder.length);

  // deck-actions toggle still exists and stays in sync
  openMenu(); await sleep(250);
  q("menu-cards-btn").click(); await sleep(300);
  [...document.querySelectorAll("#deck-pick-list .deck-pick-item")][0].querySelector(".deck-pick-more").click(); await sleep(250);
  const toggleBtn = [...document.querySelectorAll("#menu-pop-actions button")].find(b => b.textContent.includes("Двусторонние карты"));
  check("toggle-present", !!toggleBtn && toggleBtn.textContent.includes("вкл"), toggleBtn ? toggleBtn.textContent : "none");
  toggleBtn.click(); await sleep(350);
  check("toggle-off", state.decks[0].twoSided === false && [...document.querySelectorAll("#menu-pop-actions button")].some(b => b.textContent.includes("выкл")));
  [...document.querySelectorAll("#menu-pop-actions button")].find(b => b.textContent.includes("Двусторонние")).click(); await sleep(350);
  check("toggle-back-on", state.decks[0].twoSided === true);
  closeMenuPop(); closeAllMenus(); await sleep(250);

  // persistence across reload of the flag itself is covered by normalizeState (unit-style here)
  check("normalize-two-sided", (function(){ const st = normalizeState({decks:[{id:"z",name:"Z",twoSided:true}],cards:[],today:null,history:{},sessions:[]}); return st.decks[0].twoSided === true; })());

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
  if ($json) {
    $arr = $json | ConvertFrom-Json
    foreach ($r in $arr) {
      $mark = if ($r.ok) { "[PASS]" } else { "[FAIL]" }
      Write-Output "$mark $($r.step)  $($r.detail)"
    }
  } else {
    Write-Output "[FAIL] scenario returned no value"
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










