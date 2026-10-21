# W0-e: 러너 환경 기록(A-X14·D-E24 대화형 세션, 도구 유무). 판정이 아니라 기록이다 — 종료 코드는 스크립트 오류일 때만 0 이 아니다.
# 사용: pwsh -File env-report.ps1 -Out <dir>
param(
    [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Out | Out-Null

function Try-Get([scriptblock]$b) {
    try { & $b } catch { "error: $($_.Exception.Message)" }
}

$os = Get-CimInstance Win32_OperatingSystem
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$hostArch = $env:PROCESSOR_ARCHITECTURE
$kitArch = if ($hostArch -eq 'ARM64') { 'arm64' } else { 'x64' }

function Find-KitTool([string]$name) {
    $root = 'C:\Program Files (x86)\Windows Kits\10\bin'
    if (-not (Test-Path $root)) { return $null }
    $hits = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName (Join-Path $kitArch $name) } |
        Where-Object { Test-Path $_ }
    return ($hits | Select-Object -First 1)
}

# schtasks /IT 탐침: 현재 사용자의 대화형 세션에서 작업이 도는가(vm.sh gui 와 같은 방식)
function Probe-InteractiveTask {
    $marker = Join-Path $Out 'schtasks-it.json'
    $script = Join-Path $env:RUNNER_TEMP 'aingspike-it-probe.ps1'
    if (-not $env:RUNNER_TEMP) { $script = Join-Path $Out 'aingspike-it-probe.ps1' }
    @"
`$p = Get-Process -Id `$PID
[ordered]@{ sessionId = `$p.SessionId; userInteractive = [Environment]::UserInteractive; user = [Environment]::UserName } |
  ConvertTo-Json -Compress | Set-Content -Encoding utf8 -Path '$marker'
"@ | Set-Content -Encoding utf8 -Path $script
    $tn = "aingspike-it-$PID"
    $create = & schtasks.exe /Create /TN $tn /SC ONCE /ST 23:59 /IT /F /TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`"" 2>&1
    $createCode = $LASTEXITCODE
    $run = & schtasks.exe /Run /TN $tn 2>&1
    $runCode = $LASTEXITCODE
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path $marker) -and $sw.Elapsed.TotalSeconds -lt 90) { Start-Sleep -Milliseconds 500 }
    $result = if (Test-Path $marker) { Get-Content $marker -Raw | ConvertFrom-Json } else { $null }
    $query = (& schtasks.exe /Query /TN $tn /V /FO LIST 2>&1) | Where-Object { $_ -match '^(Status|Last Run Time|Last Result|Logon Mode|Run As User):' }
    & schtasks.exe /Delete /TN $tn /F 2>&1 | Out-Null
    [ordered]@{
        createExit = $createCode; createOut = ($create -join ' ')
        runExit = $runCode; runOut = ($run -join ' ')
        ranWithin90s = [bool]$result
        secondsToMarker = $(if ($result) { [math]::Round($sw.Elapsed.TotalSeconds, 1) } else { $null })
        taskQuery = ($query -join ' | ')
        result = $result
    }
}

# 화면 캡처 탐침(D-E24): 대화형 데스크톱이 있으면 픽셀이 나온다
function Probe-Screenshot {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $png = Join-Path $Out 'screen.png'
        $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
        $colors = New-Object 'System.Collections.Generic.HashSet[int]'
        $nonBlack = 0; $samples = 0
        for ($x = 0; $x -lt $b.Width; $x += 16) {
            for ($y = 0; $y -lt $b.Height; $y += 16) {
                $c = $bmp.GetPixel($x, $y); $samples++
                [void]$colors.Add($c.ToArgb())
                if (($c.R + $c.G + $c.B) -gt 30) { $nonBlack++ }
            }
        }
        $g.Dispose(); $bmp.Dispose()
        [ordered]@{ ok = $true; width = $b.Width; height = $b.Height; sampledPixels = $samples; distinctColors = $colors.Count; nonBlackSamples = $nonBlack }
    } catch {
        [ordered]@{ ok = $false; error = $_.Exception.Message }
    }
}

$explorer = @(Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object { $_.SessionId })
$report = [ordered]@{
    os = [ordered]@{ caption = $os.Caption; version = $os.Version; build = $os.BuildNumber; arch = $os.OSArchitecture; processorArch = $hostArch }
    user = $identity.Name
    isAdmin = $isAdmin
    processSessionId = (Get-Process -Id $PID).SessionId
    userInteractive = [Environment]::UserInteractive
    explorerSessions = $explorer
    querySession = (Try-Get { (& query.exe session 2>&1) -join "`n" })
    firewall = @(Try-Get { Get-NetFirewallProfile | ForEach-Object { [ordered]@{ name = $_.Name; enabled = [string]$_.Enabled; defaultOutbound = [string]$_.DefaultOutboundAction } } })
    tools = [ordered]@{
        makeappx = Find-KitTool 'makeappx.exe'
        signtool = Find-KitTool 'signtool.exe'
        mt = Find-KitTool 'mt.exe'
        appcert = $(if (Test-Path 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe') { 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe' } else { $null })
        candle = (Try-Get { (Get-Command candle.exe -ErrorAction Stop).Source })
        wixEnv = $env:WIX
        sshd = (Try-Get { (Get-Service sshd -ErrorAction Stop).Status.ToString() })
    }
    netfx35 = (Try-Get { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction Stop).Install })
    developerMode = (Try-Get { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction Stop).AllowDevelopmentWithoutDevLicense })
    interactiveTask = (Probe-InteractiveTask)
    screenshot = (Probe-Screenshot)
}
$json = $report | ConvertTo-Json -Depth 8
Set-Content -Encoding utf8 -Path (Join-Path $Out 'env.json') -Value $json
Write-Output $json
