# A-X13: packageMsi 산출물을 조용히 설치 → 설치된 exe 로 --selfcheck → 이번 빌드인지(빌드 시각·SHA) → 조용히 제거 → 파일이 사라졌는지.
# 사용: pwsh -File msi-roundtrip.ps1 -Msi <file.msi> -BuildInfo <buildinfo.json> -Out <dir>
param(
    [Parameter(Mandatory = $true)][string]$Msi,
    [Parameter(Mandatory = $true)][string]$BuildInfo,
    [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$expected = Get-Content $BuildInfo -Raw | ConvertFrom-Json
$r = [ordered]@{ msi = (Split-Path $Msi -Leaf); msiBytes = (Get-Item $Msi).Length }

function Invoke-Msi([string[]]$argv, [int]$timeoutSec = 600) {
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argv -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit($timeoutSec * 1000)) { $p.Kill(); return -1 }
    return $p.ExitCode
}

function Find-Installed {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'AingSpike\AingSpike.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AingSpike\AingSpike.exe'),
        (Join-Path $env:ProgramFiles 'AingSpike\AingSpike.exe')
    )
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    $hit = Get-ChildItem -Path $env:LOCALAPPDATA, $env:ProgramFiles -Filter 'AingSpike.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$r.installExit = Invoke-Msi @('/i', "`"$Msi`"", '/qn', '/norestart', '/l*v', "`"$(Join-Path $Out 'msi-install.log')`"")
$r.installMs = $sw.ElapsedMilliseconds
$exe = Find-Installed
$r.installedExe = $exe
$r.uninstallEntry = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.DisplayName -like 'AingSpike*' } |
    ForEach-Object { [ordered]@{ name = $_.DisplayName; version = $_.DisplayVersion; location = $_.InstallLocation } })

$selfcheckOk = $false
if ($exe) {
    $sc = Join-Path $Out 'selfcheck-msi.json'
    Remove-Item $sc -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $exe -ArgumentList "--selfcheck=`"$sc`"" -PassThru -WindowStyle Hidden
    $finished = $p.WaitForExit(120000)
    $r.selfcheckExit = if ($finished) { $p.ExitCode } else { 'timeout' }
    if (Test-Path $sc) {
        $j = Get-Content $sc -Raw | ConvertFrom-Json
        $r.selfcheck = [ordered]@{
            exitCode = $j.exitCode
            buildTime = $j.build.buildTime; expectedBuildTime = $expected.buildTime
            gitSha = $j.build.gitSha; expectedGitSha = $expected.gitSha
            javaRuntime = $j.env.javaRuntime; osArch = $j.env.osArch; javaHome = $j.env.javaHome
            jnidispatchPath = ($j.checks | Where-Object { $_.id -eq 'jna' }).detail.jnidispatchPath
        }
        $selfcheckOk = ($j.exitCode -eq 0) -and ($j.build.buildTime -eq $expected.buildTime) -and ($j.build.gitSha -eq $expected.gitSha) -and ($r.selfcheckExit -eq 0)
    } else {
        $r.selfcheck = 'no output file'
    }
}
$r.selfcheckMatchesThisBuild = $selfcheckOk

$sw.Restart()
$r.uninstallExit = Invoke-Msi @('/x', "`"$Msi`"", '/qn', '/norestart', '/l*v', "`"$(Join-Path $Out 'msi-uninstall.log')`"")
$r.uninstallMs = $sw.ElapsedMilliseconds
$r.exeGoneAfterUninstall = if ($exe) { -not (Test-Path $exe) } else { $null }

$r.ok = ($r.installExit -eq 0) -and [bool]$exe -and $selfcheckOk -and ($r.uninstallExit -eq 0) -and ($r.exeGoneAfterUninstall -eq $true)
$json = $r | ConvertTo-Json -Depth 6
Set-Content -Encoding utf8 -Path (Join-Path $Out 'msi.json') -Value $json
Write-Output $json
if (-not $r.ok) { exit 1 }
