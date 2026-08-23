param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp  = "$env:TEMP\opencode"
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromeExe)) { $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" }
$prof = Join-Path $tmp ("tts-prof-" + [guid]::NewGuid().ToString("N"))
$p = Start-Process -FilePath $chromeExe -ArgumentList @(
  "--headless=new", "--remote-debugging-port=$(if ($DebugPort -gt 0) { $DebugPort } else { 9351 })",
  "--user-data-dir=$prof", "--no-first-run", "--autoplay-policy=no-user-gesture-required",
  "--window-size=1280,900", "about:blank"
) -PassThru

$ws = $null
try {
  Start-Sleep -Milliseconds 2500
  Add-Type -AssemblyName System.Net.Http
  $targets = Invoke-RestMethod "http://127.0.0.1:$(if ($DebugPort -gt 0) { $DebugPort } else { 9351 })/json"
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
  $seedJs = "(function(){window.addEventListener('error',function(e){(window.__errs=window.__errs||[]).push(String(e.message));});var t=new Date();function k(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')} localStorage.clear(); localStorage.setItem('flashcards-onboarded','1'); localStorage.setItem('flashcards-app-v1', JSON.stringify({decks:[{id:'d1',name:'Альфа'}], cards:[{id:'c1',deckId:'d1',question:'привет',answer:'один',status:'new'},{id:'c2',deckId:'d1',question:'мир',answer:'два',status:'new'}], selectedDeckId:'d1', today:{date:k(t),known:0,unknown:0}, history:{}, sessions:[]})); })()"
  Send-Ws @{ method = "Page.addScriptToEvaluateOnNewDocument"; params = @{ source = $seedJs } } | Out-Null; Recv-Ws | Out-Null
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/index.html" } } | Out-Null; Recv-Ws | Out-Null

  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $v = Eval "(function(){return [document.readyState, typeof state, typeof speakFace].join('|')})()"
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

  setTab("study"); await sleep(400);

  const spans = [...document.querySelectorAll(".face-speak")];
  check("ui-two-icons", spans.length === 2 && spans[0].dataset.side === "front" && spans[1].dataset.side === "back",
    "n=" + spans.length);
  const svgStroke = spans[0].querySelector("svg").getAttribute("stroke");
  check("ui-stroke-currentcolor", svgStroke === "currentColor", svgStroke);
  const iconColor = getComputedStyle(spans[0]).color;
  const inkVar = getComputedStyle(document.documentElement).getPropertyValue("--ink").trim();
  const decode = (cssCol) => { const c = document.createElement("canvas"); c.width = c.height = 1; const x = c.getContext("2d"); x.fillStyle = cssCol; x.fillRect(0,0,1,1); return [...x.getImageData(0,0,1,1).data].join(","); };
  let iconRgb = "", inkRgb = "";
  try { iconRgb = decode(iconColor); inkRgb = decode(inkVar); } catch(e) {}
  check("ui-theme-color", iconRgb !== "" && iconRgb === inkRgb, "icon=" + iconRgb + " ink=" + inkRgb);

  check("api-exists", typeof speechSynthesis !== "undefined" && typeof SpeechSynthesisUtterance === "function");

  const longText = Array.from({length: 12}, (_, i) => "строка номер " + (i+1) + " с достаточным количеством слов для переноса").join("\n");
  state.cards[0].question = longText;
  showStudyCard(); await sleep(250);
  const face = document.querySelector("#flashcard .face.front");
  const ft = document.getElementById("flashcard-question");
  const btnRect = spans[0].getBoundingClientRect();
  const ftRect = ft.getBoundingClientRect();
  check("long-text-inside-face", ft.scrollWidth <= ft.clientWidth + 1,
    "sw=" + ft.scrollWidth + "/" + ft.clientWidth);
  const range = document.createRange();
  range.selectNodeContents(ft);
  const lineRects = [...range.getClientRects()].filter((r) => r.width > 0);
  const bandLines = lineRects.filter((r) => r.top < btnRect.bottom && r.bottom > btnRect.top);
  const worstR = bandLines.length ? Math.max(...bandLines.map((r) => r.right)) : ftRect.left;
  check("text-clear-of-icon", worstR <= btnRect.left + 2,
    "bandLines=" + bandLines.length + " worstR=" + Math.round(worstR) + " btnL=" + Math.round(btnRect.left));
  const faceRect = face.getBoundingClientRect();
  check("icon-in-face", btnRect.right <= faceRect.right + 1 && btnRect.top >= faceRect.top - 1);

  const beforeFlip = document.getElementById("flashcard").classList.contains("is-flipped");
  spans[0].click(); await sleep(150);
  const stillFront = !document.getElementById("flashcard").classList.contains("is-flipped");
  const speaking1 = speechSynthesis.speaking || speechSynthesis.pending;
  check("no-flip-on-speak", stillFront && !beforeFlip);
  check("speak-front", speaking1);

  flipCard(); await sleep(200);
  spans[1].click(); await sleep(150);
  const speakingBack = speechSynthesis.speaking || speechSynthesis.pending;
  const flippedNow = document.getElementById("flashcard").classList.contains("is-flipped");
  check("speak-back", flippedNow && speakingBack);
  stopSpeech(); await sleep(120);
  check("stop-cancels", !speechSynthesis.speaking && !speechSynthesis.pending);

  const savedOrder = state.studyOrder.slice();
  state.studyOrder = []; state.studyIndex = 0;
  check("empty-guard", speakFace("front") === false);
  state.studyOrder = savedOrder;

  enterFocusMode(); await sleep(300);
  const inFocus = document.querySelectorAll("#focus-wrap .face-speak").length;
  exitFocusMode(); await sleep(250);
  check("focus-carries-icons", inFocus === 2, "n=" + inFocus);

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







