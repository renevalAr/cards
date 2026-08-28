param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9360 })
$udir = "$env:TEMP\opencode\cdp-wave2-profile"
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
      { id: "d2", name: "Вторая" }
    ],
    cards: [
      { id: "c1", deckId: "d1", question: "альфа", answer: "раз", status: "known" },
      { id: "c2", deckId: "d1", question: "бета", answer: "два", status: "new" },
      { id: "c3", deckId: "d1", question: "гамма", answer: "три", status: "new" },
      { id: "c4", deckId: "d1", question: "дельта", answer: "четыре", status: "new" }
    ],
    selectedDeckId: "d1",
    tab: "edit",
    today: { date: today, known: 2, unknown: 0 },
    history: {},
    sessions: []
  }));
  localStorage.setItem("flashcards-onboarded", "1");
  localStorage.setItem("flashcards-palette", "ember");
  localStorage.setItem("flashcards-mode", "light");
} catch (e) {}
window.__errors = [];
window.addEventListener("error", function (e) { window.__errors.push((e.error && e.error.stack) || String(e.message)); });
'@
  Invoke-Cdp $ws "Page.enable" @{} | Out-Null
  Invoke-Cdp $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = $seed } | Out-Null
  Invoke-Cdp $ws "Emulation.setDeviceMetricsOverride" @{ width = 1280; height = 800; deviceScaleFactor = 1; mobile = $false } | Out-Null
  Invoke-Cdp $ws "Page.navigate" @{ url = $url } | Out-Null
  Start-Sleep -Seconds 3

  $scenario = @'
(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const rect = (el) => el.getBoundingClientRect();

  await sleep(700);
  $("#menu-close").click(); await sleep(350);

  const ind = $(".tabs .tab-indicator");
  const at = $(".tab.is-active");
  check("W1:tab-indicator", !!ind && Math.abs(parseFloat(ind.style.left) - (at.offsetLeft + 8)) < 2 && parseFloat(ind.style.width) > 20, ind ? ind.style.left + "/" + ind.style.width : "none");

  const marker = $(".deck-list .deck-marker");
  const actDeck = $(".deck-item.is-active");
  const mrect = rect(marker), lrect = rect($("#deck-list"));
  const visibleInside = mrect.left >= lrect.left && mrect.width > 2;
  check("W2:deck-marker", !!marker && marker.classList.contains("is-on") && Math.abs(parseFloat(marker.style.top) - actDeck.offsetTop) < 2 && visibleInside, "left=" + Math.round(mrect.left) + " listLeft=" + Math.round(lrect.left));

  $("#tab-study").click(); await sleep(60);
  check("W3:panel-right", getComputedStyle($("#panel-study")).animationName === "rise-right");
  await sleep(400);
  $("#tab-edit").click(); await sleep(60);
  check("W3b:panel-left", getComputedStyle($("#panel-edit")).animationName === "rise-left");
  await sleep(350);

  $("#tab-study").click(); await sleep(450);
  $("#flashcard").classList.remove("is-flipped","was-flipped"); state.flipped=false;
  await sleep(600);
  $("#flashcard").click(); await sleep(25);
  document.getAnimations({ subtree: true }).forEach((a) => { try { if (!a.animationName) { a.pause(); a.currentTime = 520; } } catch (e) {} });
  void document.body.offsetWidth;
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  const itf = getComputedStyle($(".flashcard-inner")).transform;
  const cosA = parseFloat(itf.split(",")[0].replace("matrix3d(","").replace("matrix(",""));
  const angle = Math.round(Math.acos(Math.min(1, Math.abs(cosA))) * 180 / Math.PI);
  check("W4:overshoot", angle >= 1 && angle <= 7, angle + "\u00B0 off-180");
  document.getAnimations({ subtree: true }).forEach((a) => { try { a.play(); } catch (e) {} });
  await sleep(750);

  await sleep(140);
  const visStamp = $(".face.back .stamp");
  check("W5:stamp-slap", getComputedStyle(visStamp).animationName === "stamp-slap", getComputedStyle(visStamp).animationName + " (back visible)");
  await sleep(700);

  $("#study-mode-quiz").click(); await sleep(250);
  $('[data-qlen="10"]').click(); await sleep(300);
  $('#quiz-options .quiz-option[data-ok="0"]').click(); await sleep(120);
  check("W6:no-sheen-wrong", !$("#quiz-fill").parentElement.classList.contains("sheen"));
  $("#quiz-next").click(); await sleep(250);
  $('#quiz-options .quiz-option[data-ok="1"]').click(); await sleep(120);
  check("W6b:sheen-correct", $("#quiz-fill").parentElement.classList.contains("sheen"));
  for (let g = 0; g < 14; g += 1) {
    if ($("#summary-backdrop").classList.contains("is-open")) break;
    const nb = $("#quiz-next");
    if (!nb.classList.contains("hidden")) nb.click();
    else $('#quiz-options .quiz-option[data-ok="1"]').click();
    await sleep(190);
  }
  $("#summary-menu").click(); await sleep(450);

  $("#tab-edit").click(); await sleep(300);
  $("#save-card-btn").click(); await sleep(120);
  check("W7:field-error", !!$("#card-question.field-error") && !!$("#card-answer.field-error"));
  await sleep(650);

  $("#card-question").value = "новая";
  $("#card-answer").value = "карточка";
  $("#save-card-btn").click(); await sleep(120);
  const freshLi = $('li[data-card-id]:not([data-card-id="c1"]):not([data-card-id="c2"]):not([data-card-id="c3"]):not([data-card-id="c4"])');
  check("W8:row-new", !!freshLi && freshLi.classList.contains("row-new"), freshLi ? "yes" : "none");
  await sleep(950);

  const delTarget = freshLi || $("li[data-card-id]");
  const delId = delTarget.dataset.cardId;
  delTarget.querySelector(".row-actions button:last-child").click(); await sleep(350);
  $("#modal-ok").click(); await sleep(230);
  const outLi = document.querySelector(`li[data-card-id="${delId}"]`);
  check("W9:fade-phase", !!outLi && outLi.style.opacity === "0", outLi ? "op=" + outLi.style.opacity : "gone-already");
  check("W9b:collapse-class", !!outLi && outLi.classList.contains("row-out"), outLi ? "row-out" : "none");
  await sleep(450);
  check("W9b:removed", !document.querySelector(`li[data-card-id="${delId}"]`));

  $("#bulk-btn").click(); await sleep(300);
  $("#bulk-input").value = "вопрос = ответ";
  $("#bulk-ok").click(); await sleep(150);
  const fb = $("#bulk-feedback");
  check("W10:fb-show", fb.classList.contains("show") && !!fb.querySelector(".fb-check"), fb.className);
  $("#bulk-cancel").click(); await sleep(250);

  $("#menu-back-btn").click(); await sleep(300);
  $("#menu-cards-btn").click(); await sleep(120);
  const delays = $$("#deck-pick-list .deck-pick-item").slice(0, 2).map((r) => r.style.animationDelay);
  check("W11:picker-cascade", delays[0] === "0ms" && delays[1] === "25ms", delays.join(","));
  $("#deck-pick-cancel").click(); await sleep(250);

  $("#menu-close").click(); await sleep(200);
  const yd = new Date(); yd.setDate(yd.getDate() - 1);
  state.history.d1 = {};
  state.history.d1[dateKey(yd)] = { known: 1, unknown: 0 };
  state.history.d1[todayDateKey()] = { known: 1, unknown: 0 };
  openMenu(); await sleep(300);
  check("W12:flame", !!$("#menu-streak .flame"), $("#menu-streak").textContent.trim().slice(0, 30));

  $("#menu-stats-btn").click(); await sleep(400);
  const dayCol = $(".stats-day");
  check("W13:sticker-attr", !!dayCol && dayCol.dataset.count !== undefined, dayCol ? "count=" + dayCol.dataset.count : "none");
  closeStats(); await sleep(250);

  $("#menu-close").click(); await sleep(250);
  $$("#deck-list .deck-item")[1].click(); await sleep(60);
  check("W14:crossfade", $("#workspace").classList.contains("crossfade"));
  await sleep(400);

  for (let i = 0; i < 60; i += 1) state.cards.push({ id: "pad" + i, deckId: state.selectedDeckId, question: "pad " + i, answer: "x", status: "new" });
  render(); await sleep(200);
  const mainEl = $(".main");
  mainEl.scrollTop = 160; mainEl.dispatchEvent(new Event("scroll")); await sleep(150);
  const bp = mainEl.style.backgroundPosition;
  check("W15:parallax", bp.includes("-19"), bp);

  check("Z:no-errors", window.__errors.length === 0, JSON.stringify(window.__errors.slice(0, 3)));
  return JSON.stringify(res);
})()
'@
  $r = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenario; awaitPromise = $true; returnByValue = $true }
  if ($r.exceptionDetails) { Write-Output ("EXCEPTION: " + $r.exceptionDetails.exception.description) }
  $results = $r.result.value | ConvertFrom-Json
  $fails = @($results | Where-Object { -not $_.ok }).Count
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  Write-Output ("=== WAVE2 TOTAL: {0} checks / {1} fails ===" -f $results.Count, $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}


















