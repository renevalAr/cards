param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp  = "$env:TEMP\opencode"
$chromeExe = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$prof = Join-Path $tmp ("keys2-prof-" + [guid]::NewGuid().ToString("N"))
$p = Start-Process -FilePath $chromeExe -ArgumentList @(
  "--headless=new", "--remote-debugging-port=$(if ($DebugPort -gt 0) { $DebugPort } else { 9795 })",
  "--user-data-dir=$prof", "--no-first-run", "--window-size=1280,900", "about:blank"
) -PassThru

try {
  Start-Sleep -Milliseconds 2500
  Add-Type -AssemblyName System.Net.Http
  $targets = Invoke-RestMethod "http://127.0.0.1:$(if ($DebugPort -gt 0) { $DebugPort } else { 9795 })/json"
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
    $buf = New-Object byte[] (16MB)
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
    $r = EvalRaw $expr
    if ($r.result.PSObject.Properties["exceptionDetails"]) { throw ($r.result.exceptionDetails.exception.description) }
    return $r.result.result.value
  }

  Send-Ws @{ method = "Page.enable"; params = @{} } | Out-Null; Recv-Ws | Out-Null
  $seedJs = '(function(){window.addEventListener("error",function(e){(window.__errs=window.__errs||[]).push(String(e.message));});var t=new Date();function k(d){return d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0")} localStorage.clear(); localStorage.setItem("flashcards-onboarded","1"); var decks=[{id:"d1",name:"Альфа"},{id:"d2",name:"Бета"}]; var cards=[]; ["w1","w2","w3","w4"].forEach(function(w,i){cards.push({id:"a"+i,deckId:"d1",question:w,answer:"A"+i,status:"new"})}); cards.push({id:"b0",deckId:"d2",question:"x1",answer:"y1",status:"new"}); localStorage.setItem("flashcards-app-v1", JSON.stringify({decks:decks,cards:cards,selectedDeckId:"d1",today:{date:k(t),known:0,unknown:0},history:{},sessions:[]})); })()'
  Send-Ws @{ method = "Page.addScriptToEvaluateOnNewDocument"; params = @{ source = $seedJs } } | Out-Null; Recv-Ws | Out-Null
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/frontend/index.html" } } | Out-Null; Recv-Ws | Out-Null

  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $v = Eval "(function(){return [document.readyState, typeof state].join('|')})()"
      if ("$v" -eq "complete|object") { $ready = $true; break }
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

  openMenu(); await sleep(300);
  q("menu-cards-btn").click(); await sleep(350);
  const rows = [...document.querySelectorAll("#deck-pick-list .deck-pick-item")];
  check("picker-structure", rows.length === 2 && !!rows[0].querySelector(".deck-pick-main") && !!rows[0].querySelector(".deck-pick-more"));
  const beforeDeck = state.selectedDeckId;
  rows.find((r) => r.textContent.includes("Бета")).querySelector(".deck-pick-main").click(); await sleep(450);
  check("picker-oneclick-open", state.selectedDeckId !== beforeDeck && state.selectedDeckId === "d2" && !q("deck-pick-backdrop").classList.contains("is-open"),
    "sel=" + state.selectedDeckId);
  q("menu-close").click(); await sleep(200);

  setTab("study"); await sleep(300);
  startQuiz(0); await sleep(350);
  const opts = [...document.querySelectorAll("#quiz-options .quiz-option")];
  check("quiz-hints", opts.every((o) => o.dataset.key >= "1" && o.dataset.key <= "4"), JSON.stringify(opts.map((o) => o.dataset.key)));
  const rightIdx = opts.findIndex((o) => o.dataset.ok === "1");
  document.dispatchEvent(new KeyboardEvent("keydown", { key: String(rightIdx + 1), bubbles: true }));
  await sleep(120);
  check("digit-right-picks", quizAnswered && opts[rightIdx].classList.contains("is-right"), "idx=" + rightIdx);
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "3" }));
  await sleep(100);
  check("digit-ignored-after-answer", [...document.querySelectorAll("#quiz-options .quiz-option.is-wrong")].length === 0);

  nextQuiz(); await sleep(250);
  const opts2 = [...document.querySelectorAll("#quiz-options .quiz-option")];
  const wrongIdx = opts2.findIndex((o) => o.dataset.ok !== "1");
  if (wrongIdx >= 0) {
    document.dispatchEvent(new KeyboardEvent("keydown", { key: String(wrongIdx + 1) }));
    await sleep(120);
    check("digit-wrong-marks", opts2[wrongIdx].classList.contains("is-wrong"));
  } else {
    check("digit-wrong-marks", true, "no wrong option this round");
  }

  finishQuiz(); await sleep(300);
  closeSummary(); await sleep(200);
  const errBefore = (window.__errs || []).length;
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "2" }));
  await sleep(80);
  check("digit-dead-outside-quiz", (window.__errs || []).length === errBefore);

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
  } else { Write-Output "[FAIL] scenario returned no value" }
}
catch {
  Write-Output ("HARNESS ERROR: " + $_.Exception.Message)
}
finally {
  if ($p) { try { $p.Kill() } catch {} }
  Start-Sleep -Milliseconds 300
  if (Test-Path $prof) { Remove-Item $prof -Recurse -Force -ErrorAction SilentlyContinue }
}

