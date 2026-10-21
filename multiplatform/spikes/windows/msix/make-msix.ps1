# W0-e ②(D-E15 러너 몫): createDistributable 앱 이미지 → 레이아웃 → makeappx pack → 시험용 자체 서명 → WACK.
# 덤으로(필수 아님) 러너에 설치해 패키지 안에서 selfcheck·홈 폴더 읽기·%LOCALAPPDATA% 쓰기 위치를 기록한다.
# 서명 키는 러너에서 그때 만들고 저장소·산출물에 남기지 않는다. 게시자는 시험용 CN 이다(Partner Center 값 아님).
# 사용: pwsh -File make-msix.ps1 -AppImage <dir with AingSpike.exe> -Arch x64|arm64 -Version 1.0.N.0 -Out <dir> [-SkipWack] [-SkipInstall]
param(
    [Parameter(Mandatory = $true)][string]$AppImage,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Arch,
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+\.0$')][string]$Version,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Publisher = 'CN=AingCheck Spike Test',
    [switch]$SkipWack,
    [switch]$RequireWack,
    [switch]$SkipInstall
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$r = [ordered]@{ arch = $Arch; version = $Version; publisher = $Publisher }
$kitArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }

function Save([int]$code) {
    $json = $r | ConvertTo-Json -Depth 8
    Set-Content -Encoding utf8 -Path (Join-Path $Out 'msix.json') -Value $json
    Write-Output $json
    exit $code
}

function Find-KitTool([string]$name) {
    $root = 'C:\Program Files (x86)\Windows Kits\10\bin'
    Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName (Join-Path $kitArch $name) } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}

# 주의: PowerShell 변수는 대소문자를 가리지 않는다 — 지역 변수를 $out 으로 두면 스크립트 인자 $Out 을 가린다.
function Run([string]$exe, [string[]]$argv, [string]$log) {
    $captured = & $exe @argv 2>&1
    $code = $LASTEXITCODE
    Set-Content -Encoding utf8 -Path (Join-Path $Out $log) -Value (($captured | ForEach-Object { "$_" }) -join "`n")
    return $code
}

$makeappx = Find-KitTool 'makeappx.exe'
$signtool = Find-KitTool 'signtool.exe'
$r.makeappx = $makeappx
$r.signtool = $signtool
if (-not $makeappx -or -not $signtool) { $r.error = 'Windows SDK 도구 없음'; Save 1 }
if (-not (Test-Path (Join-Path $AppImage 'AingSpike.exe'))) { $r.error = "앱 이미지에 AingSpike.exe 없음: $AppImage"; Save 1 }

# 1) 레이아웃: 앱 이미지 그대로 + 매니페스트 + 로고
$layout = Join-Path $Out 'layout'
Remove-Item -Recurse -Force $layout -ErrorAction SilentlyContinue
Copy-Item -Recurse -Path $AppImage -Destination $layout
$assets = Join-Path $layout 'Assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
Add-Type -AssemblyName System.Drawing
foreach ($spec in @(@('StoreLogo.png', 50), @('Square44x44Logo.png', 44), @('Square150x150Logo.png', 150))) {
    $bmp = New-Object System.Drawing.Bitmap $spec[1], $spec[1]
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 124, 77, 255))
    $g.Dispose()
    $bmp.Save((Join-Path $assets $spec[0]), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
$template = Get-Content (Join-Path $PSScriptRoot 'AppxManifest.template.xml') -Raw
$manifest = $template.Replace('{{PUBLISHER}}', $Publisher).Replace('{{VERSION}}', $Version).Replace('{{ARCH}}', $Arch)
Set-Content -Encoding utf8 -Path (Join-Path $layout 'AppxManifest.xml') -Value $manifest
$r.layoutFiles = (Get-ChildItem -Recurse -File $layout).Count
$r.layoutBytes = (Get-ChildItem -Recurse -File $layout | Measure-Object -Sum Length).Sum

# 2) makeappx pack
$msix = Join-Path $Out "AingSpike_$Arch.msix"
$sw = [Diagnostics.Stopwatch]::StartNew()
$r.packExit = Run $makeappx @('pack', '/o', '/d', $layout, '/p', $msix) 'makeappx-pack.log'
$r.packMs = $sw.ElapsedMilliseconds
if ($r.packExit -ne 0 -or -not (Test-Path $msix)) { $r.error = 'makeappx pack 실패'; Save 1 }
$r.msixBytes = (Get-Item $msix).Length
Copy-Item $msix (Join-Path $Out "AingSpike_$Arch.unsigned.msix")

# 3) 시험용 자체 서명(인증서는 CurrentUser\My 에만, 파일로 내보내지 않는다)
$cert = New-SelfSignedCertificate -Type Custom -Subject $Publisher -KeyUsage DigitalSignature -FriendlyName 'AingCheck Spike Test' `
    -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') -NotAfter (Get-Date).AddDays(2)
$r.certThumbprint = $cert.Thumbprint
$r.signExit = Run $signtool @('sign', '/fd', 'SHA256', '/sha1', $cert.Thumbprint, '/s', 'My', $msix) 'signtool-sign.log'
if ($r.signExit -ne 0) { $r.error = 'signtool sign 실패'; Save 1 }

# 4) WACK
$appcert = 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe'
$r.wack = [ordered]@{ available = (Test-Path $appcert) }
if (-not $SkipWack -and (Test-Path $appcert)) {
    $report = Join-Path $Out 'wack-report.xml'
    Run $appcert @('reset') 'wack-reset.log' | Out-Null
    $sw.Restart()
    $r.wack.exit = Run $appcert @('test', '-appxpackagepath', $msix, '-reportoutputpath', $report) 'wack-test.log'
    $r.wack.ms = $sw.ElapsedMilliseconds
    if (Test-Path $report) {
        [xml]$x = Get-Content $report -Raw
        $r.wack.overall = $x.REPORT.OVERALL_RESULT
        $r.wack.failed = @($x.SelectNodes('//TEST[RESULT="FAIL"]') | ForEach-Object { $_.NAME })
        $r.wack.warnings = @($x.SelectNodes('//TEST[RESULT="WARNING"]') | ForEach-Object { $_.NAME })
        $r.wack.testCount = @($x.SelectNodes('//TEST')).Count
    } else {
        $r.wack.overall = 'NO_REPORT'
    }
}

# 5) (필수 아님) 러너에 설치 → 패키지 안에서 selfcheck
if (-not $SkipInstall) {
    $inst = [ordered]@{}
    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPeople', 'LocalMachine')
        $store.Open('ReadWrite'); $store.Add($cert); $store.Close()
        $probeDir = Join-Path $env:USERPROFILE '.claude'
        New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
        $probe = Join-Path $probeDir 'aingspike-probe.txt'
        Set-Content -NoNewline -Encoding ascii -Path $probe -Value 'aingspike home probe'
        $inst.probeSha256 = (Get-FileHash -Algorithm SHA256 $probe).Hash.ToLower()
        Add-AppxPackage -Path $msix
        $pkg = Get-AppxPackage -Name 'AingCheck.Spike'
        $inst.installed = [bool]$pkg
        $inst.packageFullName = $pkg.PackageFullName
        $inst.installLocation = $pkg.InstallLocation
        $sc = Join-Path $Out 'selfcheck-msix.json'
        $writeProbe = Join-Path $env:LOCALAPPDATA 'aingspike-probe\write.txt'
        Remove-Item $writeProbe -ErrorAction SilentlyContinue
        $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\aingspike.exe'
        $inst.aliasExists = Test-Path $alias
        $p = Start-Process -FilePath $alias -ArgumentList @("--selfcheck=$sc", "--read-probe=$probe", "--write-probe=$writeProbe") -PassThru -WindowStyle Hidden
        $inst.selfcheckFinished = $p.WaitForExit(120000)
        if (Test-Path $sc) {
            $j = Get-Content $sc -Raw | ConvertFrom-Json
            $inst.selfcheckExit = $j.exitCode
            $inst.package = $j.env.package
            $inst.readProbe = ($j.checks | Where-Object { $_.id -eq 'readProbe' })
            $inst.writeProbe = ($j.checks | Where-Object { $_.id -eq 'writeProbe' })
        } else {
            $inst.selfcheckExit = 'no output file'
            $hit = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Recurse -Filter 'selfcheck-msix.json' -ErrorAction SilentlyContinue | Select-Object -First 1
            $inst.selfcheckFoundAt = $hit.FullName
        }
        $inst.writeProbeAtRealPath = Test-Path $writeProbe
        $redir = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Recurse -Filter 'write.txt' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*aingspike-probe*' } | Select-Object -First 1
        $inst.writeProbeRedirectedTo = $redir.FullName
        Remove-AppxPackage -Package $pkg.PackageFullName
        $inst.removed = -not [bool](Get-AppxPackage -Name 'AingCheck.Spike')
    } catch {
        $inst.error = $_.Exception.Message
    }
    $r.install = $inst
}

Remove-Item -Path ("Cert:\CurrentUser\My\" + $cert.Thumbprint) -ErrorAction SilentlyContinue
Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Thumbprint -eq $cert.Thumbprint } | Remove-Item -ErrorAction SilentlyContinue

# WACK 은 x64 러너에만 있다(windows-11-arm 이미지에는 App Certification Kit 이 없다 — env.json tools.appcert).
# -RequireWack 이면 WACK PASS 까지 요구, 아니면 도구가 있을 때만 결과를 요구한다(없으면 wack.available=false 로 남긴다).
$wackOk = if ($SkipWack) { $true } elseif ($r.wack.available) { $r.wack.overall -eq 'PASS' } else { -not $RequireWack }
$r.ok = ($r.packExit -eq 0) -and ($r.signExit -eq 0) -and $wackOk
if ($r.ok) { Save 0 } else { Save 1 }
