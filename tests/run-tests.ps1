param(
  [switch]$Smoke,
  [int]$Parallel = 5,
  [ValidateSet("chrome", "edge")]
  [string]$Browser = "chrome",
  [string]$Filter = ""
)

$ErrorActionPreference = "Continue"
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projDir  = Split-Path -Parent $testsDir
$resultsDir = Join-Path $testsDir "results"
if (-not (Test-Path $resultsDir)) { New-Item -ItemType Directory -Path $resultsDir | Out-Null }
$failLog = Join-Path $resultsDir ("failures-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

$smokeSuites = @("unit", "full", "quiz", "data", "tts")
$portBase = $(if ($Browser -eq "edge") { 9700 } else { 9500 })

$suites = Get-ChildItem $testsDir -Filter "cdp-*-test.ps1" |
  Where-Object { $_.Name -match '^cdp-[a-z0-9-]+-test\.ps1$' } |
  ForEach-Object { $_.BaseName -replace '^cdp-', '' -replace '-test$', '' }

if ($Filter) { $suites = $suites | Where-Object { $_ -like "*$Filter*" } }
if ($Smoke)  { $suites = $suites | Where-Object { $smokeSuites -contains $_ } }
$suites = @($suites | Sort-Object)

if (-not $suites.Count) { Write-Output "no suites matched"; exit 2 }

$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if ($Browser -eq "edge") {
  $chromeExe = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
  if (-not (Test-Path $chromeExe)) { $chromeExe = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
}

$rows = New-Object System.Collections.Generic.List[object]
$jobs = @()
$nextPort = $portBase
$queue = New-Object System.Collections.Queue
$suites | ForEach-Object { $queue.Enqueue($_) }

function Start-SuiteJob([string]$name, [int]$port) {
  $outFile = Join-Path $resultsDir "_last-$name.out"
  $args_ = @(
    "-ExecutionPolicy", "Bypass", "-File", (Join-Path $testsDir "cdp-$name-test.ps1"),
    "-DebugPort", "$port", "-BrowserExe", $chromeExe
  )
  $job = Start-Job -ScriptBlock {
    param($testsDir, $name, $outFile, $args_)
    & powershell @args_ *> $outFile
  } -ArgumentList $testsDir, $name, $outFile, $args_
  return @{ Name = $name; Job = $job; Out = $outFile; Port = $port }
}

# suites need to accept -DebugPort/-BrowserExe; older ones ignore extra params via param block injection below
Write-Output ("RUNNER: {0} suites · parallel={1} · browser={2} · mode={3}" -f $suites.Count, $Parallel, $Browser, $(if ($Smoke) { "SMOKE" } else { "FULL" }))
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

while ($queue.Count -or $jobs) {
  while ($jobs.Count -lt $Parallel -and $queue.Count) {
    $n = $queue.Dequeue()
    $jobs += Start-SuiteJob $n $nextPort
    $nextPort += 7
  }
  Start-Sleep -Milliseconds 400
  foreach ($h in @($jobs)) {
    if ($h.Job.State -ne "Running") {
      Receive-Job $h.Job -ErrorAction SilentlyContinue | Out-Null
      Remove-Job $h.Job -Force -ErrorAction SilentlyContinue
      $out = Get-Content $h.Out -Raw -ErrorAction SilentlyContinue
      $pass = ([regex]::Matches($out, '\[PASS\]')).Count
      $fail = ([regex]::Matches($out, '\[FAIL\]')).Count
      if ($pass -eq 0 -and $fail -eq 0) {
        $m = [regex]::Match($out, '\[\{.*\}\]')
        if ($m.Success) {
          try { $arr = $m.Value | ConvertFrom-Json; $pass = @($arr | Where-Object { $_.ok }).Count; $fail = @($arr | Where-Object { -not $_.ok }).Count } catch {}
        }
      }
      if ($pass -eq 0 -and $fail -eq 0) {
        $m2 = [regex]::Match($out, '(\d+) checks / (\d+) fails')
        if ($m2.Success) { $pass = [int]$m2.Groups[1].Value; $fail = [int]$m2.Groups[2].Value }
      }
      $rows.Add([pscustomobject]@{ Suite = $h.Name; Pass = $pass; Fail = $fail })
      Write-Output ("{0,-14} pass={1,-4} fail={2}" -f $h.Name, $pass, $fail)
      if ($fail -gt 0) {
        Add-Content -LiteralPath $failLog -Value ("`r`n==== {0} · suite={1} · fail={2} ====" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $h.Name, $fail)
        ($out -split "`r?`n" | Where-Object { $_ -match '\[FAIL\]|EXC|Error' }) | ForEach-Object { Add-Content -LiteralPath $failLog -Value $_ }
      }
      $jobs = @($jobs | Where-Object { $_.Name -ne $h.Name })
    }
  }
}
$swTotal.Stop()

$tp = ($rows | Measure-Object Pass -Sum).Sum
$tf = ($rows | Measure-Object Fail -Sum).Sum
Write-Output ""
Write-Output ("GRAND TOTAL: {0} suites · pass={1} · fail={2} · {3}s · browser={4}" -f $rows.Count, $tp, $tf, [int]$swTotal.Elapsed.TotalSeconds, $Browser)
if ($tf -gt 0) { Write-Output ("failure log: " + $failLog) }
exit $(if ($tf -eq 0) { 0 } else { 1 })
