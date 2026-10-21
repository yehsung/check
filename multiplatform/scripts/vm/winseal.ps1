# Windows 망 봉인(G §8-6, H M-5). 시험 전용 JDK 경로의 java.exe·javaw.exe 에 상시 아웃바운드 차단 규칙을 둔다.
# - install : 관리자 1회(winprep-admin.ps1 이 부른다). 방화벽 프로필을 켜고 규칙을 만든다.
# - status  : 표준 사용자. 봉인 JDK 의 두 실행 파일에 켜진 아웃바운드 차단 규칙이 있는지(읽기 권한이 없으면 2).
# - canary  : 표준 사용자. 짝으로 잰다 — 봉인 JDK = DENIED(3), 비봉인 JDK = DENIED 가 아님(연결 시도가 방화벽에 안 막힘).
# 시험 JVM 은 봉인 JDK 로만, Gradle 은 비봉인 JDK 로 돈다. 규칙을 켜고 끄는 일은 시험마다 하지 않는다(표준 사용자는 못 한다).
# 종료 코드: 0 통과 · 1 판정 실패 · 2 판정 불가(망 없음 등) · 5 관리자 아님 · 64 사용법
param(
    [Parameter(Mandatory = $true)][ValidateSet('install', 'status', 'canary')][string]$Action,
    [string]$SealedJdk,
    [string]$OpenJdk,
    [string]$Target = '1.1.1.1:443',
    [string]$RuleGroup = 'AingCheck Seal'
)
$ErrorActionPreference = 'Stop'

function Emit($obj, [int]$code) {
    Write-Output ($obj | ConvertTo-Json -Depth 6 -Compress)
    exit $code
}

function Get-Config {
    $p = 'C:\ProgramData\aingcheck\vm.json'
    if (Test-Path $p) { return (Get-Content $p -Raw | ConvertFrom-Json) }
    return $null
}

$cfg = Get-Config
if (-not $SealedJdk -and $cfg) { $SealedJdk = $cfg.SealedJdk }
if (-not $OpenJdk -and $cfg) { $OpenJdk = $cfg.GradleJdk }
if (-not $SealedJdk) { Emit @{ error = '-SealedJdk 가 없고 vm.json 도 없다' } 64 }
$SealedJdk = [IO.Path]::GetFullPath($SealedJdk)
$programs = @('java.exe', 'javaw.exe') | ForEach-Object { Join-Path $SealedJdk (Join-Path 'bin' $_) }

switch ($Action) {
    'install' {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) { Emit @{ error = 'install 은 관리자 PowerShell 에서 한 번 돌린다' } 5 }
        if (-not (Test-Path $programs[0])) { Emit @{ error = "봉인 JDK 에 java.exe 가 없다: $($programs[0])" } 64 }
        Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True
        Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        $made = foreach ($prog in $programs) {
            $name = "AingCheck-Seal-" + ((Split-Path $prog -Leaf) -replace '\.exe$', '') + '-' + ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($prog.ToLowerInvariant()))).Replace('-', '').Substring(0, 8))
            New-NetFirewallRule -Name $name -DisplayName $name -Group $RuleGroup -Direction Outbound -Action Block -Program $prog -Profile Any -Enabled True | Out-Null
            [ordered]@{ name = $name; program = $prog }
        }
        Emit ([ordered]@{ action = 'install'; rules = @($made); profiles = @(Get-NetFirewallProfile | ForEach-Object { [ordered]@{ name = $_.Name; enabled = [string]$_.Enabled } }) }) 0
    }
    'status' {
        # 규칙 묶음 이름이 아니라 프로그램 경로로 찾는다(arm64·x64 묶음을 따로 만들어도 같은 판정).
        try {
            $info = foreach ($prog in $programs) {
                $rules = @(Get-NetFirewallApplicationFilter -Program $prog -ErrorAction SilentlyContinue | Get-NetFirewallRule -ErrorAction Stop)
                $blocking = @($rules | Where-Object { [string]$_.Enabled -eq 'True' -and [string]$_.Action -eq 'Block' -and [string]$_.Direction -eq 'Outbound' })
                [ordered]@{ program = $prog; rules = @($rules | ForEach-Object { $_.Name }); blocking = $blocking.Count }
            }
            $covered = -not ($info | Where-Object { $_.blocking -lt 1 })
            $profilesOn = -not (Get-NetFirewallProfile | Where-Object { [string]$_.Enabled -ne 'True' })
            $ok = $covered -and $profilesOn
            Emit ([ordered]@{ action = 'status'; programs = @($info); allProgramsCovered = $covered; profilesOn = $profilesOn; ok = $ok }) ($(if ($ok) { 0 } else { 1 }))
        } catch {
            Emit ([ordered]@{ action = 'status'; ok = $null; error = "읽기 실패(권한?): $($_.Exception.Message)" }) 2
        }
    }
    'canary' {
        if (-not $OpenJdk) { Emit @{ error = '-OpenJdk 가 없고 vm.json 도 없다' } 64 }
        $hostPort = $Target.Split(':')
        $src = Join-Path $PSScriptRoot 'Canary.java'
        function Probe([string]$jdk) {
            $java = Join-Path $jdk 'bin\java.exe'
            $out = & $java $src $hostPort[0] $hostPort[1] 2>&1
            $code = $LASTEXITCODE
            $line = ($out | Where-Object { "$_".StartsWith('{') } | Select-Object -Last 1)
            $parsed = $null
            if ($line) { try { $parsed = $line | ConvertFrom-Json } catch { } }
            [ordered]@{ java = $java; exit = $code; result = $parsed.result; ms = $parsed.ms; error = $parsed.error }
        }
        $sealed = Probe $SealedJdk
        $open = Probe ([IO.Path]::GetFullPath($OpenJdk))
        # 봉인 JDK 가 연결되면 새는 것(1). 봉인 JDK 가 방화벽에 막히고 비봉인 JDK 는 방화벽에 안 막히면 봉인(0).
        # 그 밖(망 자체가 없음·비봉인도 막힘)은 봉인을 증명하지 못한다(2) — 게이트는 0 일 때만 돈다.
        $code = if ($sealed.exit -eq 0) { 1 } elseif ($sealed.exit -eq 3 -and $open.exit -ne 3 -and $open.exit -ne 2) { 0 } else { 2 }
        $verdict = switch ($code) { 0 { 'sealed' } 1 { 'LEAK: 봉인 JDK 가 연결됐다' } 2 { '판정 불가: 봉인 JDK 가 방화벽 거부가 아니거나 비봉인 JDK 도 막혔다' } }
        Emit ([ordered]@{ action = 'canary'; target = $Target; sealed = $sealed; open = $open; verdict = $verdict }) $code
    }
}
