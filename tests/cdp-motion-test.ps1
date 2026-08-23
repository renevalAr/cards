param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)
$ErrorActionPreference = "Stop"
$chrome = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$port = $(if ($DebugPort -gt 0) { $DebugPort } else { 9350 })
$udir = "C:\Users\Lenovo\AppData\Local\Temp\opencode\cdp-motion-profile"
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

  $scenario = '(async () => {
  const res = [];
  const check = (step, cond, detail) => res.push({ step, ok: !!cond, detail: detail === undefined ? "" : String(detail) });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const rect = (el) => el.getBoundingClientRect();
  const fireP = (el, x, y) => el.dispatchEvent(new PointerEvent("pointermove", { bubbles: true, pointerType: "mouse", clientX: x, clientY: y }));

  await sleep(700);
  $("#menu-close").click(); await sleep(350);

  $("#tab-edit").click(); await sleep(250);
  const tbtn = $("#bulk-btn");
  tbtn.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerType: "mouse", clientX: rect(tbtn).left + 5, clientY: rect(tbtn).top + 5 }));
  check("M1:ripple", !!tbtn.querySelector(".ripple"));
  await sleep(650);
  const delays = $$("#card-rows li[data-card-id]").slice(0, 3).map((li) => li.style.animationDelay);
  check("M2:stagger", delays[0] === "0ms" && delays[1] === "30ms" && delays[2] === "60ms", delays.join(","));

  $("#tab-study").click(); await sleep(450);
  const fc = document.getElementById("flashcard");
  fireP(fc, rect(fc).left + rect(fc).width * 0.9, rect(fc).top + rect(fc).height * 0.2);
  check("M3:tilt-set", (fc.style.transform || "").includes("rotateY"), fc.style.transform);

  const rr = rect(fc);
  const fireTilt = (x, y) => { fc.dispatchEvent(new PointerEvent("pointermove", { bubbles: true, pointerType: "mouse", clientX: x, clientY: y })); void document.body.offsetWidth; };
  // удержание у правого края
  const series = [];
  for (let i = 0; i <= 16; i += 1) {
    fireTilt(rr.right - 1 - i * 0.8, rr.top + rr.height / 2);
    const mmn = /rotateY\((-?[\d.]+)deg\)/.exec(fc.style.transform || "");
    series.push(mmn ? parseFloat(mmn[1]) : null);
  }
  const dropN = series.filter((a) => a === null).length;
  const maxAbs = Math.max.apply(null, series.map((a) => a === null ? 0 : Math.abs(a)));
  let stepMax = 0;
  for (let i = 1; i < series.length; i += 1) if (series[i] !== null && series[i-1] !== null) stepMax = Math.max(stepMax, Math.abs(series[i] - series[i-1]));
  check("M14:tilt-edge-stable", dropN === 0 && maxAbs <= 3.51 && stepMax <= 0.4, "drop=" + dropN + " max=" + maxAbs.toFixed(2) + " step=" + stepMax.toFixed(2));
  // осцилляция поперёк кромки карты (внутри зоны обёртки) — эффект не должен гаснуть
  let flicker = 0;
  for (let i = 0; i < 12; i += 1) {
    const x = rr.right + (i % 2 === 0 ? 3 : -3);
    fireTilt(x, rr.top + rr.height * 0.35);
    if (!fc.style.transform) flicker += 1;
  }
  check("M14c:no-flicker-at-border", flicker === 0 && !!fc.style.transform, "flicker=" + flicker);
  // выход за пределы обёртки — сброс
  fireTilt(rr.right + 40, rr.top + rr.height / 2);
  const outEv = new PointerEvent("pointermove", { bubbles: true, pointerType: "mouse", clientX: rr.right + 60, clientY: rr.top + rr.height / 2 });
  document.body.dispatchEvent(outEv);
  void fc.offsetWidth;
  check("M14b:tilt-clear-outside", fc.style.transform === "");
  $("#tab-edit").click(); await sleep(300);
  const inp = $("#card-search");
  inp.value = "альфа"; inp.dispatchEvent(new Event("input", { bubbles: true })); await sleep(90);
  check("M4:pulse-on", $("#card-rows").classList.contains("pulse-marks"));
  const cb = $(".search-clear"); const cs = getComputedStyle(cb); const ir = rect(inp); const cr = rect(cb);
  check("M4b:clear-inside", cs.position === "absolute" && cr.left >= ir.left && cr.right <= ir.right + 1, cs.position);
  const markEl = $("mark.search-hit");
  const pulseAnims = document.getAnimations({ subtree: true }).filter((a) => { try { return a.animationName === "hit-pulse"; } catch (e) { return false; } });
  let scaleNow = 0;
  if (pulseAnims.length) { pulseAnims.forEach((a) => { a.pause(); a.currentTime = 60; }); void document.body.offsetWidth; scaleNow = parseFloat(getComputedStyle(markEl).transform.replace("matrix(", "").split(",")[0]); pulseAnims.forEach((a) => a.play()); }
  check("M4c:pulse-pop", scaleNow > 1.05, "scale=" + scaleNow.toFixed(3));
  inp.value = ""; inp.dispatchEvent(new Event("input", { bubbles: true })); await sleep(1300);

  $("#tab-study").click(); await sleep(400);
  $("#study-mode-quiz").click(); await sleep(250);
  $(''[data-qlen="0"]'').click(); await sleep(300);
  $(''#quiz-options .quiz-option[data-ok="0"]'').click(); await sleep(120);
  check("M5:wrong-flash", !!$("#quiz-options .quiz-option.is-wrong"));
  for (let g = 0; g < 12; g += 1) {
    if ($("#summary-backdrop").classList.contains("is-open")) break;
    const nb = $("#quiz-next");
    if (!nb.classList.contains("hidden")) nb.click();
    else $(''#quiz-options .quiz-option[data-ok="1"]'').click();
    await sleep(200);
  }
  check("M6:summary-open", $("#summary-backdrop").classList.contains("is-open"));
  $("#summary-menu").click(); await sleep(450);
  $("#menu-study-btn").click(); await sleep(500);
  $("#study-mode-quiz").click(); await sleep(250);
  $(''[data-qlen="0"]'').click(); await sleep(300);
  for (let g = 0; g < 12; g += 1) {
    if ($("#summary-backdrop").classList.contains("is-open")) break;
    const nb = $("#quiz-next");
    if (!nb.classList.contains("hidden")) nb.click();
    else $(''#quiz-options .quiz-option[data-ok="1"]'').click();
    await sleep(180);
  }
  const layer = $(".confetti-layer");
  check("M7:confetti-spawn", !!layer && layer.children.length >= 40, layer ? String(layer.children.length) : "none");
  check("M7b:hundred", /не знаю 0/.test($("#summary-line").textContent), $("#summary-line").textContent);
  document.getAnimations({ subtree: true }).forEach((a) => { try { a.finish(); } catch (e) {} });
  $("#summary-menu").click(); await sleep(500);

  openStats(); await sleep(140);
  const midVal = Number($("#stats-total").textContent);
  await sleep(900);
  check("M8:countup-final", Number($("#stats-total").textContent) === state.cards.length, midVal + "->" + $("#stats-total").textContent);
  closeStats(); await sleep(300);
  openStats(); await sleep(1100);
  const heights = $$(".stats-day i").map((i) => parseInt(i.style.height));
  check("M9:bars-grown", heights.length === 7 && heights.every((h) => h >= 2), heights.join(","));
  closeStats(); await sleep(250);
  openMenu(); await sleep(80);
  check("M10:menu-stagger", getComputedStyle($(".menu-cover").children[1]).animationDelay === "0.07s");
  closeMenu(); await sleep(250);
  check("M11:doodle-empty", !!$("#empty-state .doodle") && !!$("#study-empty .doodle"));

  $("#menu-study-btn").click(); await sleep(500);
  $("#tab-edit").click(); await sleep(350);
  const rows = () => $$("#card-rows li[data-card-id]").map((li) => li.dataset.cardId);
  const beforeOrder = rows();
  const srcLi = $$("#card-rows li[data-card-id]").find((li) => li.dataset.cardId === beforeOrder[1]);
  const dstLi = $$("#card-rows li[data-card-id]")[0];
  srcLi.dispatchEvent(new Event("dragstart", { bubbles: true }));
  const overEv = new Event("dragover", { bubbles: true, cancelable: true });
  overEv.clientY = rect(dstLi).top + 4;
  dstLi.dispatchEvent(overEv);
  check("M12:indicator", dstLi.classList.contains("drop-above"), dstLi.className);
  const dropEv = new Event("drop", { bubbles: true });
  dropEv.clientY = rect(dstLi).top + 4;
  dstLi.dispatchEvent(dropEv);
  await sleep(250);
  const afterOrder = rows();
  check("M12b:reordered", afterOrder[0] === beforeOrder[1] && afterOrder[1] === beforeOrder[0], beforeOrder.join(",") + " -> " + afterOrder.join(","));
  check("M12c:persistence", JSON.stringify(state.cards.slice(0, 4).map((c) => c.id)) === JSON.stringify(afterOrder));

  const sbVals = [document.body, document.documentElement, document.querySelector(".main")].map((el) => getComputedStyle(el).scrollbarWidth);
  res.push({ step: "M13:scrollbar-css", ok: sbVals.some((v) => v === "thin"), detail: "vals=" + sbVals.join("|") });
  check("Z:no-errors", window.__errors.length === 0, JSON.stringify(window.__errors.slice(0, 3)));
  return JSON.stringify(res);
})()



';
  $r = Invoke-Cdp $ws "Runtime.evaluate" @{ expression = $scenario; awaitPromise = $true; returnByValue = $true }
  if ($r.exceptionDetails) { Write-Output ("EXCEPTION: " + $r.exceptionDetails.exception.description) }
  $results = $r.result.value | ConvertFrom-Json
  $fails = @($results | Where-Object { -not $_.ok }).Count
  $results | ForEach-Object { $mark = if ($_.ok) { "PASS" } else { "FAIL" }; Write-Output ("[{0}] {1}  {2}" -f $mark, $_.step, $_.detail) }
  Write-Output ("=== MOTION TOTAL: {0} checks / {1} fails ===" -f $results.Count, $fails)
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}













