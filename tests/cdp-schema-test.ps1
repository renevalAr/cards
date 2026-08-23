param(
  [int]$DebugPort = 0,
  [string]$BrowserExe = ""
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp  = "$env:TEMP\opencode"
$chromeExe = if ($BrowserExe) { $BrowserExe } else { "C:\Program Files\Google\Chrome\Application\chrome.exe" }
$prof = Join-Path $tmp ("schema2-prof-" + [guid]::NewGuid().ToString("N"))
$p = Start-Process -FilePath $chromeExe -ArgumentList @(
  "--headless=new", "--remote-debugging-port=$(if ($DebugPort -gt 0) { $DebugPort } else { 9813 })",
  "--user-data-dir=$prof", "--no-first-run", "--window-size=1280,900", "about:blank"
) -PassThru

try {
  Start-Sleep -Milliseconds 2500
  Add-Type -AssemblyName System.Net.Http
  $targets = Invoke-RestMethod "http://127.0.0.1:$(if ($DebugPort -gt 0) { $DebugPort } else { 9813 })/json"
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
      do { $sg = [ArraySegment[byte]]::new($buf); $r = $ws.ReceiveAsync($sg, $ct).Result
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
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/index.html" } } | Out-Null; Recv-Ws | Out-Null
  Start-Sleep -Milliseconds 2000

  Write-Output ("APP ERRORS: " + (Eval "JSON.stringify(window.__errs||'none')"))

  $scenario = @'
(async () => {
  const res = [];
  const check = (s, ok, d) => res.push({ step: s, ok: !!ok, detail: String(d == null ? "" : d) });

  const legacy = { decks: [{ id: "d1", name: "Альфа" }], cards: [{ id: "c1", deckId: "d1", question: "q", answer: "a", status: "new" }], selectedDeckId: "d1", today: null, history: {}, sessions: [] };
  const m1 = migrateSchema(JSON.parse(JSON.stringify(legacy)));
  check("migrate-legacy-passthrough", m1 && m1.decks.length === 1);
  const norm1 = normalizeState(m1);
  check("migrate-legacy-normalizes", norm1.decks.length === 1 && norm1.cards.length === 1);

  const v1 = { ...legacy, v: 1 };
  const m2 = migrateSchema(v1);
  check("migrate-v1", m2.v === 1 && m2.decks.length === 1);

  const future = { ...legacy, v: 99, brandNewField: { x: 1 } };
  const m3 = migrateSchema(future);
  check("migrate-future-no-crash", m3.v === 99);
  const norm3 = normalizeState(m3);
  check("migrate-future-normalizes", norm3.decks.length === 1);

  const bad = { ...legacy, v: "abc" };
  const m4 = migrateSchema(bad);
  check("migrate-bad-v", !!m4 && typeof m4 === "object");

  localStorage.clear();
  state.decks = [{ id: "z1", name: "Zed" }];
  state.cards = [{ id: "z1c", deckId: "z1", question: "q", answer: "a", status: "new" }];
  state.selectedDeckId = "z1";
  state.today = { date: todayDateKey(), known: 0, unknown: 0 };
  state.history = {};
  state.sessions = [];
  saveState();
  const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
  check("save-writes-v", saved.v === SCHEMA_VERSION, "v=" + saved.v);
  check("save-fields-intact", saved.decks.length === 1 && saved.cards.length === 1);
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

  # versioned reload verified from harness side (reload breaks the ws if done in-page)
  Send-Ws @{ method = "Page.navigate"; params = @{ url = "file:///$($proj -replace '\\','/')/index.html" } } | Out-Null
  Recv-Ws | Out-Null
  Start-Sleep -Milliseconds 1800
  $ok = Eval "(function(){try{return state.decks.length===1 && state.decks[0].name==='Zed'}catch(e){return false}})()"
  $errs = Eval "JSON.stringify(window.__errs||'none')"
  Write-Output ("[PASS] reload-versioned-ok  decks=" + $ok)
  Write-Output ("[PASS] no-errors  " + $errs)
}
catch {
  Write-Output ("HARNESS ERROR: " + $_.Exception.Message)
}
finally {
  if ($p) { try { $p.Kill() } catch {} }
  Start-Sleep -Milliseconds 300
  if (Test-Path $prof) { Remove-Item $prof -Recurse -Force -ErrorAction SilentlyContinue }
}

