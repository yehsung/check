# VM 손님 쪽 실행기(표준 사용자 tester 로, SSH 를 거쳐 vm.sh 가 부른다). 관리자 권한이 필요한 일은 하지 않는다.
#   verify-tree  -RunDir D                 받은 파일의 지문을 다시 계산해 맥이 보낸 값(.aingcheck-push.json)과 대조
#   gradle       -RunDir D -ArgsB64 B [-Arch arm64|x64]   봉인 카나리아 → gradlew.bat --offline --no-daemon (종료 코드 그대로)
#   gui          -RunDir D -ArgsB64 B [-TimeoutSec N]     schtasks /IT 로 대화형 세션에서 실행(종료 코드 그대로)
#   capture      -RunDir D -Out NAME.png                  대화형 세션에서 화면 캡처(gui 경유)
#   capture-here -Out P                                   (gui 작업 안에서만) 지금 세션의 화면을 PNG 로
#   info                                                  세션·사용자·권한 기록
# 인자는 base64(UTF-8 JSON 문자열 배열)로 받는다 — ssh → cmd → powershell 인용 지옥과 주입을 피한다.
# 지문: 파일마다 git blob SHA-1, "sha 경로\n" 를 경로의 UTF-8 바이트 순으로 이어 SHA-256. vm.sh digest_dir 와 같은 식이다.
param(
    [Parameter(Mandatory = $true)][ValidateSet('verify-tree', 'gradle', 'gui', 'capture', 'capture-here', 'info')][string]$Action,
    [string]$RunDir,
    [string]$ArgsB64,
    [string]$Out,
    [ValidateSet('arm64', 'x64')][string]$Arch = 'arm64',
    [int]$TimeoutSec = 600
)
$ErrorActionPreference = 'Stop'

function Emit($obj) { Write-Output ($obj | ConvertTo-Json -Depth 6 -Compress) }

function Decode-Args([string]$b64) {
    if (-not $b64) { return @() }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    $arr = $json | ConvertFrom-Json
    return @($arr | ForEach-Object { [string]$_ })
}

function Get-Config {
    $p = 'C:\ProgramData\aingcheck\vm.json'
    if (-not (Test-Path $p)) { throw "vm.json 이 없다: $p (winprep-admin.ps1 을 먼저)" }
    return (Get-Content $p -Raw | ConvertFrom-Json)
}

function Get-TreeDigest([string]$root) {
    $root = [IO.Path]::GetFullPath($root).TrimEnd('\')
    $sha1 = [Security.Cryptography.SHA1]::Create()
    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($rel -eq '.aingcheck-push.json' -or $rel.StartsWith('.aingcheck-out/')) { continue }
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        $header = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
        $buf = New-Object byte[] ($header.Length + $bytes.Length)
        [Array]::Copy($header, 0, $buf, 0, $header.Length)
        [Array]::Copy($bytes, 0, $buf, $header.Length, $bytes.Length)
        $sha = ([BitConverter]::ToString($sha1.ComputeHash($buf))).Replace('-', '').ToLowerInvariant()
        $key = [BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($rel))
        $entries.Add("$key`t$sha $rel")
    }
    $arr = $entries.ToArray()
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    $sb = New-Object Text.StringBuilder
    foreach ($e in $arr) { [void]$sb.Append($e.Substring($e.IndexOf("`t") + 1)).Append("`n") }
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $digest = ([BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString())))).Replace('-', '').ToLowerInvariant()
    return [ordered]@{ digest = $digest; files = $arr.Length }
}

function Invoke-Interactive([string[]]$argv, [string]$runDir, [int]$timeoutSec) {
    if ($argv.Count -lt 1) { throw 'gui 에 실행할 명령이 없다' }
    $outDir = Join-Path $runDir '.aingcheck-out'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $wrapper = Join-Path $outDir "gui-$id.ps1"
    $exitFile = Join-Path $outDir "gui-$id.exit"
    $stdout = Join-Path $outDir "gui-$id.out"
    $stderr = Join-Path $outDir "gui-$id.err"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -Compress -InputObject @($argv))))
    @"
`$ErrorActionPreference = 'Continue'
`$argv = @(([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')) | ConvertFrom-Json) | ForEach-Object { [string]`$_ })
try {
    `$rest = @(`$argv | Select-Object -Skip 1)
    `$p = if (`$rest.Count -gt 0) {
        Start-Process -FilePath `$argv[0] -ArgumentList `$rest -PassThru -Wait -RedirectStandardOutput '$stdout' -RedirectStandardError '$stderr'
    } else {
        Start-Process -FilePath `$argv[0] -PassThru -Wait -RedirectStandardOutput '$stdout' -RedirectStandardError '$stderr'
    }
    Set-Content -Path '$exitFile' -Value `$p.ExitCode
} catch {
    Set-Content -Path '$stderr' -Value `$_.Exception.Message
    Set-Content -Path '$exitFile' -Value 99
}
"@ | Set-Content -Encoding utf8 -Path $wrapper
    $tn = "aingcheck-gui-$id"
    $tr = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$wrapper`""
    & schtasks.exe /Create /TN $tn /SC ONCE /ST 23:59 /IT /F /TR $tr | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "schtasks /Create 실패: $LASTEXITCODE" }
    & schtasks.exe /Run /TN $tn | Out-Null
    $runCode = $LASTEXITCODE
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while (-not (Test-Path $exitFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    & schtasks.exe /Delete /TN $tn /F | Out-Null
    if (Test-Path $stdout) { Get-Content $stdout | Write-Output }
    if (Test-Path $stderr) { Get-Content $stderr | ForEach-Object { [Console]::Error.WriteLine($_) } }
    if ($runCode -ne 0) { return 98 }
    if (-not (Test-Path $exitFile)) { [Console]::Error.WriteLine("gui: $timeoutSec 초 안에 끝나지 않았다(대화형 세션이 없나?)"); return 97 }
    return [int](Get-Content $exitFile -Raw).Trim()
}

switch ($Action) {
    'info' {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        Emit ([ordered]@{
            user = $id.Name
            isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            sessionId = (Get-Process -Id $PID).SessionId
            userInteractive = [Environment]::UserInteractive
            explorerSessions = @(Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object { $_.SessionId })
            arch = $env:PROCESSOR_ARCHITECTURE
            os = (Get-CimInstance Win32_OperatingSystem).Caption
            build = [Environment]::OSVersion.Version.ToString()
        })
        exit 0
    }
    'verify-tree' {
        $meta = Get-Content (Join-Path $RunDir '.aingcheck-push.json') -Raw | ConvertFrom-Json
        $d = Get-TreeDigest $RunDir
        $match = ($d.digest -eq $meta.digest) -and ($d.files -eq [int]$meta.files)
        Emit ([ordered]@{ tree = $meta.tree; commit = $meta.commit; digestMac = $meta.digest; digestVm = $d.digest; filesMac = $meta.files; filesVm = $d.files; match = $match })
        if ($match) { exit 0 } else { exit 1 }
    }
    'gradle' {
        $cfg = Get-Config
        $gradleJdk = if ($Arch -eq 'x64') { $cfg.GradleJdkX64 } else { $cfg.GradleJdk }
        $sealedJdk = if ($Arch -eq 'x64') { $cfg.SealedJdkX64 } else { $cfg.SealedJdk }
        $canary = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'winseal.ps1') -Action canary -SealedJdk $sealedJdk -OpenJdk $gradleJdk
        $canaryCode = $LASTEXITCODE
        [Console]::Error.WriteLine("winseal canary: $canary")
        if ($canaryCode -ne 0) { [Console]::Error.WriteLine('봉인이 증명되지 않아 시험을 돌리지 않는다'); exit 90 }
        $mp = Join-Path $RunDir 'multiplatform'
        $gradlew = Join-Path $mp 'gradlew.bat'
        if (-not (Test-Path $gradlew)) { [Console]::Error.WriteLine("gradlew.bat 이 없다: $gradlew"); exit 91 }
        $env:JAVA_HOME = $gradleJdk
        $env:AINGCHECK_NETWORK_SEALED = '1'
        $argv = @('--offline', '--no-daemon', "-PtestJavaExecutable=$(Join-Path $sealedJdk 'bin\java.exe')") + (Decode-Args $ArgsB64)
        Push-Location $mp
        try { & $gradlew @argv; $code = $LASTEXITCODE } finally { Pop-Location }
        exit $code
    }
    'gui' {
        exit (Invoke-Interactive (Decode-Args $ArgsB64) $RunDir $TimeoutSec)
    }
    'capture' {
        if (-not $Out -or $Out -match '[\\/:]') { [Console]::Error.WriteLine('-Out 은 파일 이름만(실행 폴더의 .aingcheck-out 에 쓴다)'); exit 64 }
        $target = Join-Path (Join-Path $RunDir '.aingcheck-out') $Out
        $argv = @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Action', 'capture-here', '-Out', $target)
        exit (Invoke-Interactive $argv $RunDir 120)
    }
    'capture-here' {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Emit ([ordered]@{ out = $Out; width = $b.Width; height = $b.Height; sessionId = (Get-Process -Id $PID).SessionId })
        exit 0
    }
}
