# W0-e 러너 판정 모음. 각 단계의 outcome(환경변수 OUTCOME_*)과 보고서 JSON 을 한 표로 모은다.
# 필수 단계 중 하나라도 success 가 아니면 1 로 끝난다 — 실패도 수치와 함께 남는다(artifact).
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [Parameter(Mandatory = $true)][string]$Arch
)
$ErrorActionPreference = 'Stop'

function Read-Json([string]$name) {
    $p = Join-Path $Out $name
    if (Test-Path $p) { try { return (Get-Content $p -Raw | ConvertFrom-Json) } catch { return $null } }
    return $null
}

$steps = [ordered]@{
    'seal-canary'        = @{ outcome = $env:OUTCOME_SEAL; required = $true; what = 'winseal install + 짝 카나리아(봉인 JDK 차단 / 비봉인 JDK 연결)' }
    'gradle-test-sealed' = @{ outcome = $env:OUTCOME_TEST; required = $true; what = '탐침 단위 시험(봉인 JDK, AINGCHECK_NETWORK_SEALED=1)' }
    'smoke-classpath'    = @{ outcome = $env:OUTCOME_SMOKE_CP; required = $true; what = 'JNA 스모크(봉인 JDK + 클래스패스)' }
    'smoke-app-image'    = @{ outcome = $env:OUTCOME_SMOKE_APP; required = $true; what = 'JNA 스모크(jpackage 런처)' }
    'dpi-manifest'       = @{ outcome = $env:OUTCOME_DPI; required = $true; what = 'D-E22 런처 PerMonitorV2' }
    'msi-roundtrip'      = @{ outcome = $env:OUTCOME_MSI; required = $true; what = 'A-X13 packageMsi 조용한 설치·selfcheck·제거' }
    'msix-wack'          = @{ outcome = $env:OUTCOME_MSIX; required = $true; what = 'D-E15 makeappx·서명·WACK' }
    'vm-tree-digest'     = @{ outcome = $env:OUTCOME_VMTREE; required = $true; what = 'vm.sh 스냅숏 → Windows tar → winrun verify-tree 짝' }
    'ps-parse'           = @{ outcome = $env:OUTCOME_PSPARSE; required = $true; what = '모든 .ps1 이 pwsh 7·Windows PowerShell 5.1 에서 구문 오류 0' }
    'gradle-build'       = @{ outcome = $env:OUTCOME_BUILD; required = $true; what = 'assemble·createDistributable(packageMsi 결과는 msi-roundtrip 에)' }
    'env-report'         = @{ outcome = $env:OUTCOME_ENV; required = $false; what = '환경 기록' }
}

$env_ = Read-Json 'env.json'
$smoke = Read-Json 'smoke-cp.json'
$smokeApp = Read-Json 'smoke-app.json'
$dpi = Read-Json 'dpi.json'
$msi = Read-Json 'msi/msi.json'
$msix = Read-Json 'msix/msix.json'
$seal = Read-Json 'seal.json'

function Check-Of($report, [string]$id) { if ($report) { $report.checks | Where-Object { $_.id -eq $id } } }

$facts = [ordered]@{
    arch = $Arch
    os = $env_.os
    processSessionId = $env_.processSessionId
    explorerSessions = $env_.explorerSessions
    interactiveTaskRan = $env_.interactiveTask.ranWithin30s
    screenshot = $env_.screenshot
    session = (Check-Of $smoke 'session').detail
    getLastInputInfo = (Check-Of $smoke 'getLastInputInfo').detail
    registerHotKey = (Check-Of $smoke 'registerHotKey').detail
    dpapi = (Check-Of $smoke 'dpapi').detail
    shellNotifyIcon = (Check-Of $smoke 'shellNotifyIcon').detail
    appImageSmokeExit = $smokeApp.exitCode
    dpi = @($dpi.checks | ForEach-Object { [ordered]@{ id = $_.id; effective = $_.detail.effective; dpiAware = $_.detail.dpiAware; dpiAwareness = $_.detail.dpiAwareness } })
    msi = $msi
    msix = $msix
    seal = $seal
}

$failedRequired = @()
$rows = @()
foreach ($k in $steps.Keys) {
    $s = $steps[$k]
    $o = if ($s.outcome) { $s.outcome } else { 'not-run' }
    if ($s.required -and $o -ne 'success') { $failedRequired += $k }
    $rows += "| $k | $o | $(if ($s.required) { '필수' } else { '기록' }) | $($s.what) |"
}
$verdict = [ordered]@{ arch = $Arch; failedRequired = $failedRequired; steps = $steps; facts = $facts }
Set-Content -Encoding utf8 -Path (Join-Path $Out 'verdict.json') -Value ($verdict | ConvertTo-Json -Depth 10)

if ($env:GITHUB_STEP_SUMMARY) {
    $md = @("## W0-e Windows 탐침 — $Arch", '', '| 단계 | 결과 | 구분 | 무엇 |', '|---|---|---|---|') + $rows + @('', '```json', ($facts | ConvertTo-Json -Depth 6 -Compress), '```')
    Add-Content -Encoding utf8 -Path $env:GITHUB_STEP_SUMMARY -Value ($md -join "`n")
}
Write-Output ($verdict | ConvertTo-Json -Depth 10)
if ($failedRequired.Count -gt 0) { Write-Output "필수 실패: $($failedRequired -join ', ')"; exit 1 }
