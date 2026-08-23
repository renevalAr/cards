param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp  = "$env:TEMP\opencode"
$chromeExe = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$prof = Join-Path $tmp ("perf-prof-" + [guid]::NewGuid().ToString("N"))
$p = Start-Process -FilePath $chromeExe -ArgumentList @(
  "--headless=new", "--remote-debugging-port=$(if ($DebugPort -gt 0) { $DebugPort } else { 9721 })",
  "--user-data-dir=$prof", "--no-first-run", "--window-size=1280,900", "about:blank"
) -PassThru

try {
  Start-Sleep -Milliseconds 2500
  Add-Type -AssemblyName System.Net.Http
  $targets = Invoke-RestMethod "http://127.0.0.1:$(if ($DebugPort -gt 0) { $DebugPort } else { 9721 })/json"
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
  $seedJs = "(function(){window.addEventListener('error',function(e){(window.__errs=window.__errs||[]).push(String(e.message));});var t=new Date();function k(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')} var cards=[];for(var i=0;i<404;i++){cards.push({id:'k'+i,deckId:'big',question:'Вопрос производительности номер '+i+' с достаточным количеством слов',answer:'Ответ '+i,status:i%3===0?'known':(i%3===1?'unknown':'new')});} localStorage.clear(); localStorage.setItem('flashcards-onboarded','1'); localStorage.setItem('flashcards-app-v1', JSON.stringify({decks:[{id:'big',name:'Нагрузка'}], cards:cards, selectedDeckId:'big', today:{date:k(t),known:0,unknown:0}, history:{}, sessions:[]})); })()"
  Send-Ws @{ method = "Page.addScriptToEvaluateOnNewDocument"; params = @{ source = $seedJs } } | Out-Null; Recv-Ws | Out-Null
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/index.html" } } | Out-Null; Recv-Ws | Out-Null

  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $v = Eval "(function(){return [document.readyState, typeof state, state.cards.length].join('|')})()"
      if ("$($v.result.result.value)" -eq "complete|object|404") { $ready = $true; break }
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
  setTab("edit"); await sleep(300);

  const median = (arr) => { const a = arr.slice().sort((x, y) => x - y); return a[Math.floor(a.length / 2)]; };

  // Budget 1: renderCardRows on 404 rows <= 120ms (median of 5)
  const renderTimes = [];
  for (let i = 0; i < 5; i++) {
    const t0 = performance.now();
    renderCardRows();
    renderTimes.push(performance.now() - t0);
    await sleep(60);
  }
  const renderMs = Math.round(median(renderTimes));
  check("budget-render-404-le120", renderMs <= 120, renderMs + "ms [" + renderTimes.map(t=>Math.round(t)).join(",") + "]");

  // heavy-mode class present at >60 rows (regression guard for restored feature)
  check("heavy-mode-active", q("card-rows").classList.contains("no-anim"));

  // Budget 2: search input handling <= 25ms (median of 5)
  const input = q("card-search");
  const searchTimes = [];
  const queries = ["производительности", "номер 12", "ответ", "с слов", "404"];
  for (let i = 0; i < 5; i++) {
    input.value = queries[i];
    const t0 = performance.now();
    input.dispatchEvent(new Event("input", { bubbles: true }));
    searchTimes.push(performance.now() - t0);
    await sleep(50);
  }
  const searchMs = Math.round(median(searchTimes));
  check("budget-search-le25", searchMs <= 25, searchMs + "ms");

  // clear search before quiz budget
  q("card-search-clear").click(); await sleep(150);

  // Budget 3: beginQuiz full deck <= 5ms
  const quizTimes = [];
  for (let i = 0; i < 5; i++) {
    resetStudy();
    const t0 = performance.now();
    startQuiz(0);
    quizTimes.push(performance.now() - t0);
    quizActive = false;
    state.studyMode = "flip";
    await sleep(40);
  }
  const quizMs = Math.round(median(quizTimes));
  check("budget-quiz-start-le5", quizMs <= 5, quizMs + "ms");

  // Budget 4: stats window render <= 30ms
  const statsTimes = [];
  for (let i = 0; i < 3; i++) {
    const t0 = performance.now();
    renderStatsWindow();
    statsTimes.push(performance.now() - t0);
    await sleep(40);
  }
  const statsMs = Math.round(median(statsTimes));
  check("budget-stats-le30", statsMs <= 30, statsMs + "ms");

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
