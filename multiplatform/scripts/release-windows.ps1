# 아잉체크 Windows 포장·설치 확인(W6-b1, package.md §4-1). CI 러너(mp-release-windows.yml)와 VM(W0-e2 winrun.ps1)이 같은 판정을 쓴다 — 두 벌 금지.
# 규칙(버전 칸·매니페스트 렌더·신원·영수증·설치 대조·WACK 판정)의 정본은 desktopApp/packaging/release_win.py 하나다. 이 스크립트는 Windows 도구만 부른다.
# 뼈대는 spikes/windows/msix/make-msix.ps1(W0-e 러너 실측)과 ci/msi-roundtrip.ps1(--selfcheck=<파일> 대조)을 복사해 고친 것이다.
#
#   pack          -AppImage <dir> -Arch x64|arm64 -Identity dev|store -Out <dir> [-Wack require|auto|skip] [-GitSha <sha>] [-BuildTime <utc>] [-NoPri]
#                 → layout\ · AingCheck_<ver>_<arch>.msix(서명 안 함) · .dev-signed.msix + .dev-signed.cer(공개 인증서) · .receipt.json · pack.json
#   bundle        -In <dir> -Out <dir>   (In 아래 *.receipt.json 과 같은 이름의 서명 안 한 .msix 를 묶는다)
#                 → AingCheck_<ver>.msixbundle · .dev-signed.msixbundle + .dev-signed.cer · bundle.json
#   install-check -Package <msix|msixbundle|layoutDir> -Expect <receipt.json> -Out <dir> [-Register]
#                 → 설치 → 별칭 aingcheck.exe --selfcheck=<파일> → 대조 → 제거 → install-check.json{ok,…}. 종료 코드는 ok 에서만 나온다.
#
# 규약(★, release_win.py 머리와 같은 번호):
#   ★1 종료 코드를 믿지 않는다 — 산출물 안 값(앱 selfcheck · 설치된 jar sha256)으로 판정한다.
#   ★3 값은 argv 배열로 넘긴다(Invoke-Py · Start-Wait). 운영 anon 키는 이 스크립트가 다루지 않는다(CI 는 .invalid 로만 싼다).
#   ★4 서명 키는 실행마다 그때 만들고(CurrentUser\My) 쓰고 나면 지운다. 남는 것은 공개 인증서(.cer)뿐이고, 설치 확인은
#      설치된 Publisher·서명 지문이 그 .cer 과 같은지까지 본다.
param(
    [Parameter(Mandatory = $true, Position = 0)][ValidateSet('pack', 'bundle', 'install-check')][string]$Command,
    [string]$AppImage,
    [ValidateSet('x64', 'arm64')][string]$Arch,
    [ValidateSet('dev', 'store')][string]$Identity = 'dev',
    [string]$Out,
    [ValidateSet('require', 'auto', 'skip')][string]$Wack = 'auto',
    [string]$GitSha = $env:GITHUB_SHA,
    [string]$BuildTime = $env:BUILD_TIME,
    [switch]$NoPri,
    [string]$In,
    [string]$Package,
    [string]$Expect,
    [switch]$Register
)
$ErrorActionPreference = 'Stop'
$Packaging = (Resolve-Path (Join-Path $PSScriptRoot '..\desktopApp\packaging')).Path
$RW = Join-Path $Packaging 'release_win.py'
if (-not $Out) { throw '-Out 이 필요하다' }
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$KitArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }

function Save-Json($obj, [string]$path) {
    $json = $obj | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($path, $json + "`n", [Text.UTF8Encoding]::new($false))
    return $json
}

function Find-Python {
    foreach ($name in @('python', 'python3', 'py')) {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { continue }
        $v = & $cmd.Source -I -c 'import sys; print(sys.version_info[0])' 2>$null
        if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq '3') { return $cmd.Source }
    }
    throw 'python 3 이 없다(release_win.py 를 부를 수 없다)'
}
$Py = Find-Python

# release_win.py 하위 명령을 argv 로 부른다(★3). 마지막 JSON 줄과 종료 코드를 돌려준다.
function Invoke-Py([string[]]$argv) {
    $lines = @(& $Py -I $RW @argv 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $last = $lines | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1
    $json = if ($last) { $last | ConvertFrom-Json } else { $null }
    return [pscustomobject]@{ code = $code; json = $json; text = ($lines -join "`n") }
}

function Find-KitTool([string]$name) {
    $root = 'C:\Program Files (x86)\Windows Kits\10\bin'
    $versions = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending
    foreach ($a in @($KitArch, 'x64', 'x86') | Select-Object -Unique) {
        $hit = $versions | ForEach-Object { Join-Path $_.FullName (Join-Path $a $name) } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

# 주의: PowerShell 변수는 대소문자를 가리지 않는다 — 지역 변수를 $out 으로 두면 스크립트 인자 $Out 을 가린다(make-msix.ps1 의 교훈).
function Run-Tool([string]$exe, [string[]]$argv, [string]$log) {
    $captured = & $exe @argv 2>&1
    $code = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $Out $log), (($captured | ForEach-Object { "$_" }) -join "`n"), [Text.UTF8Encoding]::new($false))
    return $code
}

# Windows 명령줄 규칙으로 인용(CommandLineToArgvW) — PowerShell 5.1 에도 있는 ProcessStartInfo.Arguments 하나로 argv 를 넘긴다.
function Join-Argv([string[]]$argv) {
    ($argv | ForEach-Object {
        if ($_ -eq '' -or $_ -match '[\s"]') { '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' } else { $_ }
    }) -join ' '
}

function Start-Wait([string]$exe, [string[]]$argv, [int]$timeoutMs) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = Join-Argv $argv
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($timeoutMs)) { try { $p.Kill() } catch { }; return 'timeout' }
    return $p.ExitCode
}

function New-DevCert([string]$publisher, [string]$cerPath) {
    $cert = New-SelfSignedCertificate -Type Custom -Subject $publisher -KeyUsage DigitalSignature -FriendlyName 'AingCheck Dev Test (per run)' `
        -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') -NotAfter (Get-Date).AddDays(2)
    Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null  # 공개 인증서만(키 없음)
    return $cert
}

function Remove-DevCert([string]$thumb) {
    if (-not $thumb) { return }
    $path = "Cert:\CurrentUser\My\" + $thumb
    try { Remove-Item -Path $path -DeleteKey -ErrorAction Stop } catch { Remove-Item -Path $path -ErrorAction SilentlyContinue }
}

function Get-Signer([string]$path) {
    $sig = Get-AuthenticodeSignature -FilePath $path
    return [ordered]@{ status = "$($sig.Status)"; thumbprint = $sig.SignerCertificate.Thumbprint; subject = $sig.SignerCertificate.Subject }
}

# 서명 안 한 패키지를 복사해 이번 실행 인증서로 서명한다. 서명자 지문이 그 인증서와 같아야 ok(★4).
function Sign-Copy([string]$unsigned, [string]$signed, [string]$publisher, [string]$logName) {
    $s = [ordered]@{ signed = $signed; cer = [IO.Path]::ChangeExtension($signed, '.cer') }
    Copy-Item -Force $unsigned $signed
    $cert = New-DevCert $publisher $s.cer
    $s.thumbprint = $cert.Thumbprint
    $s.signExit = Run-Tool $script:Signtool @('sign', '/fd', 'SHA256', '/sha1', $cert.Thumbprint, '/s', 'My', $signed) $logName
    $s.signer = Get-Signer $signed
    $s.ok = ($s.signer.thumbprint -eq $cert.Thumbprint) -and ($s.signer.subject -eq $publisher)
    return @{ info = $s; cert = $cert }
}

function Import-AppxModule {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        try { Import-Module Appx -ErrorAction Stop; Get-AppxPackage -Name 'AingCheck.__probe__' | Out-Null }
        catch { Import-Module Appx -UseWindowsPowerShell -ErrorAction Stop }
    }
}

$Signtool = $null
$Makeappx = $null

function Invoke-Pack {
    $r = [ordered]@{ command = 'pack'; arch = $Arch; identity = $Identity; wackMode = $Wack; ok = $false }
    try {
        if (-not $AppImage -or -not $Arch) { throw 'pack 에는 -AppImage · -Arch 가 필요하다' }
        $script:Makeappx = Find-KitTool 'makeappx.exe'; $script:Signtool = Find-KitTool 'signtool.exe'; $makepri = Find-KitTool 'makepri.exe'
        $r.tools = [ordered]@{ makeappx = $script:Makeappx; signtool = $script:Signtool; makepri = $makepri }
        if (-not $script:Makeappx -or -not $script:Signtool) { throw 'Windows SDK 도구(makeappx·signtool) 없음' }
        $exe = Join-Path $AppImage 'AingCheck.exe'
        if (-not (Test-Path $exe)) { throw "앱 이미지에 AingCheck.exe 없음: $AppImage" }

        # 1) 앱 이미지 selfcheck(패키지 밖) — 영수증의 gitSha·buildTime·build 는 이 값이 이번 빌드와 같을 때만 쓴다(★1)
        $sc0 = Join-Path $Out 'selfcheck-appimage.json'
        Remove-Item $sc0 -ErrorAction SilentlyContinue
        $r.appImageSelfcheckExit = Start-Wait $exe @("--selfcheck=$sc0") 180000

        # 2) 레이아웃 = 앱 이미지 그대로 + 매니페스트 + Assets (+ resources.pri)
        $layout = Join-Path $Out 'layout'
        Remove-Item -Recurse -Force $layout -ErrorAction SilentlyContinue
        Copy-Item -Recurse -Path $AppImage -Destination $layout
        New-Item -ItemType Directory -Force -Path (Join-Path $layout 'Assets') | Out-Null
        Copy-Item -Path (Join-Path $Packaging 'assets\*') -Destination (Join-Path $layout 'Assets')
        $m = Invoke-Py @('manifest', '--identity', $Identity, '--arch', $Arch, '--out', (Join-Path $layout 'AppxManifest.xml'))
        if ($m.code -ne 0 -or -not $m.json.ok) { throw "매니페스트 렌더 실패: $($m.text)" }
        $r.msixVersion = $m.json.msixVersion
        $r.windowsVersion = $m.json.windowsVersion
        $r.identityName = $m.json.identity.name
        $publisher = $m.json.identity.publisher

        # 3) resources.pri — targetsize·altform-unplated 자산이 작업 표시줄에 쓰이려면 PRI 가 있어야 한다.
        #    앱 이미지(런타임·jar) 전체를 색인하지 않도록 매니페스트+Assets 만 있는 무대에서 만든다.
        if (-not $NoPri) {
            if (-not $makepri) { throw 'makepri.exe 없음(-NoPri 로 끌 수 있다)' }
            $pri = Join-Path $Out 'pri'
            $stage = Join-Path $pri 'stage'
            Remove-Item -Recurse -Force $pri -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $stage | Out-Null
            Copy-Item (Join-Path $layout 'AppxManifest.xml') $stage
            Copy-Item -Recurse (Join-Path $layout 'Assets') $stage
            $cfg = Join-Path $pri 'priconfig.xml'
            $r.priConfigExit = Run-Tool $makepri @('createconfig', '/cf', $cfg, '/dq', 'ko-KR', '/pv', '10.0.0', '/o') 'makepri-config.log'
            $r.priNewExit = Run-Tool $makepri @('new', '/pr', $stage, '/cf', $cfg, '/mn', (Join-Path $stage 'AppxManifest.xml'), '/of', (Join-Path $stage 'resources.pri'), '/o') 'makepri-new.log'
            if (-not (Test-Path (Join-Path $stage 'resources.pri'))) { throw "makepri 가 resources.pri 를 만들지 못했다(exit $($r.priNewExit))" }
            Copy-Item (Join-Path $stage 'resources.pri') $layout
        }

        # 4) makeappx pack(서명 안 함 — Store 제출본과 맥 다시 싸기의 기준)
        $base = "AingCheck_$($r.windowsVersion)_$Arch"
        $unsigned = Join-Path $Out "$base.msix"
        $r.packExit = Run-Tool $script:Makeappx @('pack', '/o', '/h', 'SHA256', '/d', $layout, '/p', $unsigned) 'makeappx-pack.log'
        if (-not (Test-Path $unsigned)) { throw "makeappx pack 산출물 없음(exit $($r.packExit))" }
        $r.unsigned = [ordered]@{ path = $unsigned; bytes = (Get-Item $unsigned).Length; sha256 = (Get-FileHash -Algorithm SHA256 $unsigned).Hash.ToLower() }

        # 5) dev 신원만: 이번 실행 인증서로 서명한 사본(설치 확인용). store 신원은 서명하지 않는다(Store 가 다시 서명).
        $cert = $null
        $signedOk = $true
        $wackTarget = $unsigned
        if ($Identity -eq 'dev') {
            $s = Sign-Copy $unsigned (Join-Path $Out "$base.dev-signed.msix") $publisher 'signtool-sign.log'
            $cert = $s.cert
            $r.devSigned = $s.info
            $signedOk = $s.info.ok
            $wackTarget = $s.info.signed
        }

        # 6) WACK(x64 러너에만 있다 — windows-11-arm 은 available=false 로 기록)
        $appcert = 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe'
        $available = Test-Path $appcert
        $report = Join-Path $Out 'wack-report.xml'
        Remove-Item $report -ErrorAction SilentlyContinue
        if ($Wack -ne 'skip' -and $available) {
            Run-Tool $appcert @('reset') 'wack-reset.log' | Out-Null
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r.wackExit = Run-Tool $appcert @('test', '-appxpackagepath', $wackTarget, '-reportoutputpath', $report) 'wack-test.log'
            $r.wackMs = $sw.ElapsedMilliseconds
        }
        if ($cert) { Remove-DevCert $cert.Thumbprint }  # 키는 남기지 않는다(★4)
        $w = Invoke-Py @('wack', '--mode', $Wack, '--available', ("$available".ToLower()), '--report', $report, '--out', (Join-Path $Out 'wack.json'))
        $r.wack = $w.json

        # 7) 영수증(aingcheck-windows-receipt/1) — 앱 selfcheck 가 이번 빌드와 다르면 여기서 멈춘다
        $receipt = Join-Path $Out "$base.receipt.json"
        $rc = Invoke-Py @('receipt', '--layout', $layout, '--selfcheck', $sc0, '--identity', $Identity, '--arch', $Arch,
            '--git-sha', $GitSha, '--build-time', $BuildTime, '--wack', (Join-Path $Out 'wack.json'), '--out', $receipt)
        $r.receipt = if ($rc.code -eq 0) { $receipt } else { $null }
        $r.receiptResult = $rc.json
        $r.ok = ($rc.code -eq 0) -and (Test-Path $receipt) -and $signedOk -and ($w.code -eq 0) -and [bool]$w.json.ok
    } catch {
        $r.error = $_.Exception.Message
    }
    Save-Json $r (Join-Path $Out 'pack.json') | Write-Output
    if ($r.ok) { exit 0 } else { exit 1 }
}

function Invoke-Bundle {
    $r = [ordered]@{ command = 'bundle'; ok = $false }
    try {
        if (-not $In) { throw 'bundle 에는 -In 이 필요하다' }
        $script:Makeappx = Find-KitTool 'makeappx.exe'; $script:Signtool = Find-KitTool 'signtool.exe'
        if (-not $script:Makeappx -or -not $script:Signtool) { throw 'Windows SDK 도구(makeappx·signtool) 없음' }
        $receipts = @(Get-ChildItem -Path $In -Recurse -File -Filter '*.receipt.json' | Sort-Object FullName)
        $plan = Invoke-Py (@('bundle-plan', '--out', (Join-Path $Out 'bundle-plan.json')) + @($receipts | ForEach-Object { $_.FullName }))
        if ($plan.code -ne 0) { throw "묶음 계획 거부: $($plan.text)" }
        $r.plan = $plan.json
        $stage = Join-Path $Out 'bundle-in'
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        foreach ($rcpt in $receipts) {
            $msix = $rcpt.FullName -replace '\.receipt\.json$', '.msix'
            if (-not (Test-Path $msix)) { throw "영수증 옆에 서명 안 한 패키지가 없다: $msix" }
            Copy-Item $msix $stage
        }
        $bundle = Join-Path $Out $plan.json.bundleName
        $r.bundleExit = Run-Tool $script:Makeappx @('bundle', '/o', '/bv', $plan.json.msixVersion, '/d', $stage, '/p', $bundle) 'makeappx-bundle.log'
        if (-not (Test-Path $bundle)) { throw "makeappx bundle 산출물 없음(exit $($r.bundleExit))" }
        $r.bundle = [ordered]@{ path = $bundle; bytes = (Get-Item $bundle).Length; sha256 = (Get-FileHash -Algorithm SHA256 $bundle).Hash.ToLower() }
        $signedPath = $bundle -replace '\.msixbundle$', '.dev-signed.msixbundle'
        $s = Sign-Copy $bundle $signedPath $plan.json.identity.publisher 'signtool-bundle.log'
        Remove-DevCert $s.cert.Thumbprint
        $r.devSigned = $s.info
        $r.ok = [bool]$s.info.ok
    } catch {
        $r.error = $_.Exception.Message
    }
    Save-Json $r (Join-Path $Out 'bundle.json') | Write-Output
    if ($r.ok) { exit 0 } else { exit 1 }
}

function Invoke-InstallCheck {
    $mode = if ($Register) { 'register' } elseif ($Package -match '\.msixbundle$') { 'bundle' } else { 'msix' }
    $r = [ordered]@{ command = 'install-check'; package = $Package; mode = $mode }
    $facts = [ordered]@{ mode = $mode; localAppData = $env:LOCALAPPDATA; selfcheckExit = $null; remainingAfterRemove = $null }
    $sc = Join-Path $Out 'selfcheck-installed.json'
    Remove-Item $sc -ErrorAction SilentlyContinue
    $trusted = $null
    $name = $null
    try {
        if (-not $Package -or -not $Expect) { throw 'install-check 에는 -Package · -Expect 가 필요하다' }
        Import-AppxModule
        $receipt = Get-Content -Raw -Encoding utf8 $Expect | ConvertFrom-Json
        $name = $receipt.identity.name
        $r.preexisting = @(Get-AppxPackage -Name $name).Count
        Get-AppxPackage -Name $name | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName }
        if ($mode -eq 'register') {
            Add-AppxPackage -Register (Join-Path $Package 'AppxManifest.xml')
        } else {
            $cer = [IO.Path]::ChangeExtension($Package, '.cer')
            if (-not (Test-Path $cer)) { throw "이번 실행 인증서(.cer)가 패키지 옆에 없다: $cer" }
            $trusted = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $cer
            $facts.expectedThumbprint = $trusted.Thumbprint
            $signer = Get-Signer $Package
            $r.signatureStatus = $signer.status
            $facts.signerThumbprint = $signer.thumbprint
            $facts.signerSubject = $signer.subject
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPeople', 'LocalMachine')
            $store.Open('ReadWrite'); $store.Add($trusted); $store.Close()
            Add-AppxPackage -Path $Package
        }
        $pkg = Get-AppxPackage -Name $name | Select-Object -First 1
        if (-not $pkg) { throw "설치 뒤 Get-AppxPackage -Name $name 가 비었다" }
        $r.packageFullName = $pkg.PackageFullName
        $r.installLocation = $pkg.InstallLocation
        $facts.packageFamilyName = $pkg.PackageFamilyName
        $facts.installedPublisher = $pkg.Publisher
        $jar = Join-Path $pkg.InstallLocation ($receipt.appJar.name -replace '/', '\')
        $facts.installedJarSha256 = if (Test-Path $jar) { (Get-FileHash -Algorithm SHA256 $jar).Hash.ToLower() } else { $null }
        $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\aingcheck.exe'
        for ($i = 0; $i -lt 30 -and -not (Test-Path $alias); $i++) { Start-Sleep -Seconds 1 }
        $r.aliasExists = Test-Path $alias
        $facts.selfcheckExit = Start-Wait $alias @("--selfcheck=$sc") 180000
    } catch {
        $r.error = $_.Exception.Message
    } finally {
        if ($name) {
            Get-AppxPackage -Name $name -ErrorAction SilentlyContinue | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }
            $facts.remainingAfterRemove = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue).Count
        }
        if ($trusted) {
            Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Thumbprint -eq $trusted.Thumbprint } | Remove-Item -ErrorAction SilentlyContinue
        }
    }
    $factsPath = Join-Path $Out 'install-facts.json'
    Save-Json $facts $factsPath | Out-Null
    $c = Invoke-Py @('check-install', '--expect', $Expect, '--selfcheck', $sc, '--facts', $factsPath, '--out', (Join-Path $Out 'install-check.json'))
    $r.ok = ($c.code -eq 0) -and [bool]$c.json.ok -and -not $r.error
    $r.failed = $c.json.failed
    Save-Json $r (Join-Path $Out 'install-run.json') | Write-Output
    if ($r.ok) { exit 0 } else { exit 1 }
}

switch ($Command) {
    'pack' { Invoke-Pack }
    'bundle' { Invoke-Bundle }
    'install-check' { Invoke-InstallCheck }
}
