param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp  = "$env:TEMP\opencode"
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromeExe)) { $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" }
$prof = Join-Path $tmp ("img-prof-" + [guid]::NewGuid().ToString("N"))
$p = Start-Process -FilePath $chromeExe -ArgumentList @(
  "--headless=new", "--remote-debugging-port=$(if ($DebugPort -gt 0) { $DebugPort } else { 9357 })",
  "--user-data-dir=$prof", "--no-first-run", "--window-size=1280,900", "about:blank"
) -PassThru

try {
  Start-Sleep -Milliseconds 2500
  Add-Type -AssemblyName System.Net.Http
  $targets = Invoke-RestMethod "http://127.0.0.1:$(if ($DebugPort -gt 0) { $DebugPort } else { 9357 })/json"
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
  $seedJs = "(function(){window.addEventListener('error',function(e){(window.__errs=window.__errs||[]).push(String(e.message));});var t=new Date();function k(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')} localStorage.clear(); indexedDB.deleteDatabase('flashcards-images'); localStorage.setItem('flashcards-onboarded','1'); localStorage.setItem('flashcards-app-v1', JSON.stringify({decks:[{id:'d1',name:'Альфа'}], cards:[{id:'c1',deckId:'d1',question:'привет',answer:'один',status:'new'},{id:'c2',deckId:'d1',question:'мир',answer:'два',status:'new'}], selectedDeckId:'d1', today:{date:k(t),known:0,unknown:0}, history:{}, sessions:[]})); })()"
  Send-Ws @{ method = "Page.addScriptToEvaluateOnNewDocument"; params = @{ source = $seedJs } } | Out-Null; Recv-Ws | Out-Null
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/index.html" } } | Out-Null; Recv-Ws | Out-Null

  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $v = Eval "(function(){return [document.readyState, typeof state, typeof compressImageFile].join('|')})()"
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

  // helper: synthetic photo file 1200x900
  async function makeFile() {
    const c = document.createElement("canvas");
    c.width = 1200; c.height = 900;
    const x = c.getContext("2d");
    const g = x.createLinearGradient(0,0,1200,900);
    g.addColorStop(0,"#e85d04"); g.addColorStop(1,"#156d8a");
    x.fillStyle = g; x.fillRect(0,0,1200,900);
    const blob = await new Promise((r) => c.toBlob(r, "image/png"));
    return new File([blob], "photo.png", { type: "image/png" });
  }

  // DB roundtrip
  await imgPut("tx1", "data:image/webp;base64,AAAA");
  const got = await imgGet("tx1");
  check("db-roundtrip", got === "data:image/webp;base64,AAAA");
  await imgDelete("tx1");
  check("db-delete", (await imgGet("tx1")) === undefined);

  // GC of orphaned images
  await imgPut("orphan-a", "data:image/webp;base64,AAAA");
  await imgPut("orphan-b", "data:image/webp;base64,BBBB");
  const gcRemoved = await imgGcOrphans(["live-1", "orphan-a"]);
  check("gc-removes-orphans", gcRemoved >= 1 && (await imgGet("orphan-b")) === undefined, "removed=" + gcRemoved);
  check("gc-keeps-live", (await imgGet("orphan-a")) !== undefined);
  await imgDelete("orphan-a");

  // strong compression: max side <=480 and webp preferred
  const file = await makeFile();
  const du = await compressImageFile(file);
  const dims = await new Promise((resolve) => {
    const im = new Image();
    im.onload = () => resolve(im.naturalWidth + "x" + im.naturalHeight);
    im.src = du;
  });
  const [wS, hS] = dims.split("x").map(Number);
  check("compress-format", /^(data:image\/webp|data:image\/jpeg)/.test(du), du.slice(0, 22));
  check("compress-max-side-480", Math.max(wS, hS) <= 480, dims);

  // form flow: handle file -> preview appears
  setTab("edit"); await sleep(200);
  await handleImageFile(file); await sleep(100);
  check("form-preview", !q("image-preview").classList.contains("hidden") && q("image-thumb").src.startsWith("data:image"));
  check("form-pending", pendingImage === du);

  // save new card with image -> stored under its id
  q("card-question").value = "с картинкой";
  q("card-answer").value = "да";
  q("card-form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
  await sleep(400);
  const imgCard = state.cards.find((c) => c.question === "с картинкой");
  check("save-new-card", !!imgCard);
  const storedDu = imgCard ? await imgGet(imgCard.id) : null;
  check("image-stored-by-id", storedDu === du, storedDu ? storedDu.slice(0, 22) : "none");

  // list row thumbnail appended
  await sleep(250);
  const rowThumbs = document.querySelectorAll("#card-rows .row-thumb").length;
  check("row-thumb", rowThumbs >= 1, "thumbs=" + rowThumbs);

  // study face shows the picture for that card, hidden for plain card
  setTab("study"); await sleep(400);
  startStudyShuffle();
  const idxImg = state.studyOrder.findIndex((e) => e === imgCard.id);
  state.studyIndex = idxImg >= 0 ? idxImg : 0;
  showStudyCard(); await sleep(350);
  const faceImg = q("face-img-front");
  const shownForImgCard = currentStudyCards()[state.studyIndex].id === imgCard.id;
  if (shownForImgCard) {
    check("face-img-shown", !faceImg.classList.contains("hidden") && faceImg.src.startsWith("data:image"));
  } else {
    check("face-img-hidden-for-other", faceImg.classList.contains("hidden") || faceImg.src === "");
  }
  resetStudy(); setTab("edit"); await sleep(250);

  // edit flow: existing image loads into preview, remove + save deletes key
  startEditCard(imgCard.id); await sleep(350);
  check("edit-preview-loaded", !q("image-preview").classList.contains("hidden"));
  q("image-clear").click(); await sleep(80);
  check("edit-preview-cleared", q("image-preview").classList.contains("hidden") && pendingImage === "__remove__");
  q("card-form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
  await sleep(450);
  const afterRemove = await imgGet(imgCard.id);
  check("remove-persists", afterRemove === undefined, String(afterRemove));

  // deleting a card cleans IDB too
  q("card-question").value = "временная"; q("card-answer").value = "x";
  await handleImageFile(file); await sleep(60);
  q("card-form").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
  await sleep(350);
  const tempCard = state.cards.find((c) => c.question === "временная");
  finishDeleteCard(tempCard.id); await sleep(350);
  check("delete-cleans-idb", (await imgGet(tempCard.id)) === undefined);

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






