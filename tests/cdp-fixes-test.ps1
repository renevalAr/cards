param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp  = "$env:TEMP\opencode"
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromeExe)) { $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" }
$prof = Join-Path $tmp ("fixes-prof-" + [guid]::NewGuid().ToString("N"))
$p = Start-Process -FilePath $chromeExe -ArgumentList @(
  "--headless=new", "--remote-debugging-port=$(if ($DebugPort -gt 0) { $DebugPort } else { 9342 })",
  "--user-data-dir=$prof", "--no-first-run", "--window-size=1280,900", "about:blank"
) -PassThru

$results = New-Object System.Collections.Generic.List[object]
$ws = $null
try {
  Start-Sleep -Milliseconds 2500
  Add-Type -AssemblyName System.Net.Http
  $targets = Invoke-RestMethod "http://127.0.0.1:$(if ($DebugPort -gt 0) { $DebugPort } else { 9342 })/json"
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
    $buf = New-Object byte[] (4MB)
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
  $seedJs = "(function(){window.addEventListener('error',function(e){(window.__errs=window.__errs||[]).push(String(e.message));});var t=new Date();function k(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')} localStorage.clear(); localStorage.setItem('flashcards-onboarded','1'); localStorage.setItem('flashcards-app-v1', JSON.stringify({decks:[{id:'d1',name:'Альфа'},{id:'d2',name:'Бета'}], cards:[{id:'c1',deckId:'d1',question:'alpha',answer:'one',status:'new'},{id:'c2',deckId:'d1',question:'beta',answer:'two',status:'new'}], selectedDeckId:'d1', today:{date:k(t),known:0,unknown:0}, history:{}, sessions:[]})); })()"
  Send-Ws @{ method = "Page.addScriptToEvaluateOnNewDocument"; params = @{ source = $seedJs } } | Out-Null
  Recv-Ws | Out-Null
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/index.html" } } | Out-Null
  Recv-Ws | Out-Null
  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $v = Eval "(function(){return [document.readyState, typeof state, !!document.getElementById('card-rows')].join(String.fromCharCode(124))})()"
      if ("$v" -eq "complete|object|True") { $ready = $true; break }
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
  q("menu-close").click(); await sleep(400);

  check("F7-bulk-hint", q("bulk-hint").textContent.includes("первый знак"), q("bulk-hint").textContent);

  setTab("study"); await sleep(300);
  startStudyShuffle();
  state.studyOrder = ["c1", "c2"]; state.studyIndex = 0;
  showStudyCard(); await sleep(200);
  const msOrig = moveStudy;
  moveStudy = function () {};
  flipCard(); await sleep(120);
  markStatus("known"); markStatus("known"); markStatus("known");
  await sleep(50);
  check("F1-no-known-spam", getTodayStats().known === 0 && getTodayStats().unknown === 1,
    "k=" + getTodayStats().known + " u=" + getTodayStats().unknown);
  check("D-single-event-per-card", getTodayStats().known + getTodayStats().unknown === 1,
    "events=" + (getTodayStats().known + getTodayStats().unknown));
  beginRound(["c1"]); state.studyIndex = 0; showStudyCard();
  markStatus("known"); await sleep(50);
  check("F10-round-reset-counts", getTodayStats().known === 1, "k=" + getTodayStats().known);
  moveStudy = msOrig;

  const spanEl = document.createElement("span");
  document.body.appendChild(spanEl);
  countUp(spanEl, 1500); await sleep(750);
  check("F9-countup-9999", spanEl.textContent === "1500", spanEl.textContent);
  spanEl.remove();

  const desc = Object.getOwnPropertyDescriptor(Storage.prototype, "setItem");
  Storage.prototype.setItem = function () { throw new Error("quota"); };
  saveState(); await sleep(100);
  const alertShown = !q("storage-alert").hidden;
  Object.defineProperty(Storage.prototype, "setItem", desc);
  check("F2-quota-alert-shown", alertShown && q("storage-alert").getAttribute("role") === "alert", "shown=" + alertShown);
  saveState(); await sleep(100);

  openBulkInput(); await sleep(300);
  if (document.activeElement) document.activeElement.blur();
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })); await sleep(350);
  check("F4a-esc-bulk-on-body", !q("bulk-backdrop").classList.contains("is-open"));
  openLibrary(); await sleep(300);
  if (document.activeElement) document.activeElement.blur();
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })); await sleep(350);
  check("F4b-esc-library-on-body", !q("library-backdrop").classList.contains("is-open"));
  openStats(); await sleep(400);
  if (document.activeElement) document.activeElement.blur();
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })); await sleep(400);
  check("F4c-esc-stats-on-body", !q("stats-backdrop").classList.contains("is-open"));
  openMenu(); await sleep(300);
  if (document.activeElement) document.activeElement.blur();
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })); await sleep(350);
  check("F4d-esc-menu-on-body", !q("menu-backdrop").classList.contains("is-open"));
  q("menu-close").click(); await sleep(300);

  setTab("edit"); await sleep(200);
  q("card-search").value = "zzz";
  q("card-search").dispatchEvent(new Event("input", { bubbles: true }));
  await sleep(150);
  const emptyMsg = q("card-rows").textContent.includes("ничего не найдено");
  finishDeleteCard("c1"); finishDeleteCard("c2"); await sleep(250);
  const clearedInput = q("card-search").value === "";
  q("card-question").value = "gamma"; q("card-answer").value = "three";
  q("card-form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
  await sleep(300);
  const rowsNow = document.querySelectorAll("#card-rows li[data-card-id]");
  check("A-search-cleared", emptyMsg && clearedInput, "msg=" + emptyMsg + " cleared=" + clearedInput);
  check("A-new-card-visible", rowsNow.length === 1 && rowsNow[0].textContent.includes("gamma"), "rows=" + rowsNow.length);

  const ext = JSON.parse(localStorage.getItem(STORAGE_KEY));
  ext.decks.find((d) => d.id === "d1").name = "Гамма";
  localStorage.setItem(STORAGE_KEY, JSON.stringify(ext));
  window.dispatchEvent(new StorageEvent("storage", { key: STORAGE_KEY }));
  await sleep(400);
  check("E-cross-tab-reload", q("deck-title").textContent === "Гамма", q("deck-title").textContent);

  openLibrary(); await sleep(300);
  const addBtns = Array.from(document.querySelectorAll("#library-list button"));
  const freeBtn = addBtns.find((b) => b.textContent.trim() === "Добавить");
  freeBtn.click(); await sleep(500);
  const decksAfterOne = state.decks.length;
  closeLibrary(); openLibrary(); await sleep(300);
  const btnsAgain = Array.from(document.querySelectorAll("#library-list button"));
  const marked = btnsAgain.filter((b) => b.disabled || b.textContent.includes("Добавлено"));
  const freeLeft = btnsAgain.filter((b) => !b.disabled && b.textContent.trim() === "Добавить").length;
  check("F6-library-guard", decksAfterOne === state.decks.length && marked.length >= 1 && freeLeft >= 1,
    "decks=" + state.decks.length + " marked=" + marked.length + " free=" + freeLeft);
  closeLibrary(); await sleep(200);

  try { localStorage.removeItem(ONBOARD_KEY); } catch (e) {}
  openMenu(); await sleep(400);
  let spyCalls = 0;
  const origPos = positionTourTip;
  window.positionTourTip = function (...args) { spyCalls++; return origPos.apply(this, args); };
  hideTour(); showTour(); await sleep(200);
  window.dispatchEvent(new Event("resize")); await sleep(150);
  window.positionTourTip = origPos;
  check("G-tour-resize-reposition", spyCalls >= 1, "calls=" + spyCalls);
  hideTour(); finishTour(); closeMenu(); await sleep(200);

  check("no-errors", Array.isArray(window.__errs) ? window.__errs.length === 0 : true,
    JSON.stringify(window.__errs || []));
  return JSON.stringify(res);
})()
'@

  $mid = Send-Ws @{ method = "Runtime.evaluate"; params = @{ expression = $scenario; returnByValue = $true; awaitPromise = $true } }
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

$fails = @($results | Where-Object { -not $_.ok }).Count
if ($results.Count -eq 0) { Write-Output "=== FIXES TOTAL: no results captured ===" }
else { Write-Output "=== FIXES TOTAL: $($results.Count) checks / $fails fails ===" }















