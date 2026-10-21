# VM 1회 준비(관리자). SETUP-ko.md 를 마친 뒤 에이전트가 SSH(사용자 관리자 계정 + 공개키)로 한 번 돌린다. 몇 번 돌려도 같다(멱등).
# 하는 일(-Steps 로 고를 수 있다, 기본 전부):
#   Accounts   시험용 로컬 표준 계정 tester + 하네스 관리자 aingadmin. 비밀번호는 무작위로 만들고 화면·파일에 남기지 않는다
#   TesterSsh  tester 프로필을 만들고 관리자 공개키를 tester 의 authorized_keys 로 복사(권한: tester 읽기, SYSTEM·Administrators 전체)
#   Autologon  tester 자동 로그인(비밀번호는 LSA 비밀로 — 레지스트리 평문 DefaultPassword 는 지운다). 화면 잠금·절전 끔
#   DevMode    개발자 모드(느슨한 레이아웃 MSIX 등록용)
#   Jdk        Microsoft Build of OpenJDK 21: Gradle 용(열림)과 시험 전용(봉인) 두 벌 × arm64·x64(D-E30 에뮬레이션용)
#   Seal       winseal.ps1 install — 봉인 JDK 의 java.exe·javaw.exe 아웃바운드 상시 차단(H M-5)
#   WorkDir    C:\work\runs (tester 수정 권한)
#   Config     C:\ProgramData\aingcheck\vm.json (경로 모음, Users 읽기)
#   Git        Git for Windows(winget) · Sdk  Windows SDK(makeappx·signtool·WACK, winget) · Korean  한국어 언어 구성 요소
# 망이 필요하다(JDK·winget). 사용자 비밀은 읽지 않는다. 출력은 JSON 한 줄.
param(
    [string[]]$Steps = @('Accounts', 'TesterSsh', 'Autologon', 'DevMode', 'Jdk', 'Seal', 'WorkDir', 'Config', 'Git', 'Sdk', 'Korean'),
    [string]$Tester = 'tester',
    [string]$HarnessAdmin = 'aingadmin',
    [string]$PublicKeyFile = 'C:\ProgramData\ssh\administrators_authorized_keys',
    [string]$Root = 'C:\aingcheck',
    [string]$SealedRoot = 'C:\Program Files\aingcheck',
    [string]$WorkRoot = 'C:\work\runs'
)
$ErrorActionPreference = 'Stop'
# powershell -File 로 부르면 "A,B" 가 한 문자열로 온다 — 쉼표로 다시 나눈다.
$Steps = @($Steps | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Output '{"error":"관리자 PowerShell(또는 관리자 SSH)에서 돌린다"}'; exit 5 }
$result = [ordered]@{}
function Want([string]$s) { return $Steps -contains $s }

function New-RandomPassword {
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[+/=]', 'x') + 'A1!'
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class AingPrep {
    [DllImport("userenv.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int CreateProfile(string pszUserSid, string pszUserName, StringBuilder pszProfilePath, uint cchProfilePath);

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, uint DesiredAccess, out IntPtr PolicyHandle);
    [DllImport("advapi32.dll")] static extern uint LsaStorePrivateData(IntPtr PolicyHandle, ref LSA_UNICODE_STRING KeyName, ref LSA_UNICODE_STRING PrivateData);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr PolicyHandle);
    [DllImport("advapi32.dll")] static extern uint LsaNtStatusToWinError(uint status);

    static LSA_UNICODE_STRING Str(string s) {
        var u = new LSA_UNICODE_STRING();
        u.Buffer = Marshal.StringToHGlobalUni(s);
        u.Length = (ushort)(s.Length * 2);
        u.MaximumLength = (ushort)(s.Length * 2 + 2);
        return u;
    }
    // Sysinternals Autologon 과 같은 자리(LSA 비밀 "DefaultPassword")에 쓴다.
    public static uint StoreDefaultPassword(string password) {
        var attrs = new LSA_OBJECT_ATTRIBUTES();
        IntPtr policy;
        uint st = LsaOpenPolicy(IntPtr.Zero, ref attrs, 0x00000020 /* POLICY_CREATE_SECRET */, out policy);
        if (st != 0) return LsaNtStatusToWinError(st);
        var key = Str("DefaultPassword");
        var data = Str(password);
        try { st = LsaStorePrivateData(policy, ref key, ref data); }
        finally { Marshal.FreeHGlobal(key.Buffer); Marshal.FreeHGlobal(data.Buffer); LsaClose(policy); }
        return st == 0 ? 0 : LsaNtStatusToWinError(st);
    }
}
'@

function Ensure-User([string]$name, [string]$group, [bool]$resetIfExists) {
    $u = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    $pw = New-RandomPassword
    $secure = ConvertTo-SecureString $pw -AsPlainText -Force
    if (-not $u) {
        New-LocalUser -Name $name -Password $secure -PasswordNeverExpires -AccountNeverExpires -Description 'aing-check VM harness' | Out-Null
        $created = $true
    } elseif ($resetIfExists) {
        Set-LocalUser -Name $name -Password $secure
        $created = $false
    } else {
        $pw = $null
        $created = $false
    }
    $groupName = (Get-LocalGroup -SID $group).Name
    if (-not (Get-LocalGroupMember -Group $groupName -Member $name -ErrorAction SilentlyContinue)) { Add-LocalGroupMember -Group $groupName -Member $name }
    return @{ password = $pw; created = $created; sid = (Get-LocalUser -Name $name).SID.Value }
}

$testerPassword = $null
if (Want 'Accounts') {
    # 이미 있는 tester 의 비밀번호는 자동 로그인을 같이 고칠 때만 바꾼다(아니면 LSA 비밀과 어긋난다).
    $t = Ensure-User $Tester 'S-1-5-32-545' (Want 'Autologon')          # Users
    $a = Ensure-User $HarnessAdmin 'S-1-5-32-544' $false                # Administrators — 키로만 들어간다
    $testerPassword = $t.password
    $adminsName = (Get-LocalGroup -SID 'S-1-5-32-544').Name
    $testerIsAdmin = [bool](Get-LocalGroupMember -Group $adminsName -Member $Tester -ErrorAction SilentlyContinue)
    if ($testerIsAdmin) { Remove-LocalGroupMember -Group $adminsName -Member $Tester; $testerIsAdmin = $false }
    $result.accounts = [ordered]@{ tester = [ordered]@{ created = $t.created; sid = $t.sid; admin = $testerIsAdmin }; harnessAdmin = [ordered]@{ created = $a.created; sid = $a.sid } }
}

if (Want 'TesterSsh') {
    $sid = (Get-LocalUser -Name $Tester).SID.Value
    $profileKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
    $profilePath = if (Test-Path $profileKey) { (Get-ItemProperty $profileKey).ProfileImagePath } else { $null }
    $hr = $null
    if (-not $profilePath) {
        $sb = New-Object Text.StringBuilder 260
        $hr = [AingPrep]::CreateProfile($sid, $Tester, $sb, 260)
        $profilePath = $sb.ToString()
    }
    if (-not (Test-Path $PublicKeyFile)) { throw "공개키 파일이 없다: $PublicKeyFile (SETUP-ko.md 의 공개키 등록)" }
    $sshDir = Join-Path $profilePath '.ssh'
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    $ak = Join-Path $sshDir 'authorized_keys'
    Copy-Item -Force $PublicKeyFile $ak
    & icacls.exe $ak /inheritance:r /grant:r "*S-1-5-18:F" "*S-1-5-32-544:F" "*${sid}:R" | Out-Null
    $result.testerSsh = [ordered]@{ profilePath = $profilePath; createProfileHr = $hr; authorizedKeys = $ak; keyLines = @(Get-Content $ak | Where-Object { $_ -match '^ssh-' }).Count; acl = ((& icacls.exe $ak) -join ' ') }
}

if (Want 'Autologon') {
    if (-not $testerPassword) {
        # 비밀번호를 모르므로 새로 정한다(파일·화면에 남기지 않는다).
        $testerPassword = New-RandomPassword
        Set-LocalUser -Name $Tester -Password (ConvertTo-SecureString $testerPassword -AsPlainText -Force)
    }
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $rc = [AingPrep]::StoreDefaultPassword($testerPassword)
    Set-ItemProperty $wl -Name AutoAdminLogon -Value '1'
    Set-ItemProperty $wl -Name DefaultUserName -Value $Tester
    Set-ItemProperty $wl -Name DefaultDomainName -Value $env:COMPUTERNAME
    Remove-ItemProperty $wl -Name DefaultPassword -ErrorAction SilentlyContinue
    & powercfg.exe /change standby-timeout-ac 0 | Out-Null
    & powercfg.exe /change monitor-timeout-ac 0 | Out-Null
    & powercfg.exe /change hibernate-timeout-ac 0 | Out-Null
    New-Item -Force -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' | Out-Null
    Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name NoLockScreen -Value 1 -Type DWord
    $result.autologon = [ordered]@{ lsaStoreWinError = $rc; plaintextPasswordInRegistry = [bool](Get-ItemProperty $wl -Name DefaultPassword -ErrorAction SilentlyContinue) }
}

if (Want 'DevMode') {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    New-Item -Force -Path $k | Out-Null
    Set-ItemProperty $k -Name AllowDevelopmentWithoutDevLicense -Value 1 -Type DWord
    $result.devMode = (Get-ItemProperty $k).AllowDevelopmentWithoutDevLicense
}

function Install-Jdk([string]$arch, [string]$dest) {
    $url = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-$arch.zip"
    $dl = Join-Path $env:TEMP "aingprep-jdk-$arch"
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    $zip = Join-Path $dl 'jdk.zip'
    if (-not (Test-Path $zip)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip }
    # Windows PowerShell 5.1 은 octet-stream 응답의 .Content 를 바이트 배열로 준다 — 파일로 받아 글로 읽는다(러너 run 39592962558 실측).
    $shaFile = Join-Path $dl 'jdk.sha256sum.txt'
    Invoke-WebRequest -UseBasicParsing -Uri "$url.sha256sum.txt" -OutFile $shaFile
    $expected = (((Get-Content -Raw $shaFile).Trim()) -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { Remove-Item $zip; throw "JDK $arch SHA256 불일치" }
    if (-not (Test-Path (Join-Path $dest 'bin\java.exe'))) {
        $x = Join-Path $dl 'x'
        Remove-Item -Recurse -Force $x -ErrorAction SilentlyContinue
        Expand-Archive -Path $zip -DestinationPath $x
        $inner = Get-ChildItem $x -Directory | Select-Object -First 1
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
        Move-Item $inner.FullName $dest
    }
    # 다른 아키텍처 JDK(x64 손님에서 arm64 등)는 실행이 안 될 수 있다 — 설치는 하고 버전 확인 실패만 기록한다.
    # java -version 은 stderr 로 쓴다 — 5.1 에서 Stop 이면 그 줄이 예외가 되므로 이 호출만 Continue 로 본다.
    $ver = try {
        $ErrorActionPreference = 'Continue'
        $lines = & (Join-Path $dest 'bin\java.exe') -version 2>&1
        if ($LASTEXITCODE -eq 0) { (($lines | Select-Object -First 1) | Out-String).Trim() } else { "exit $LASTEXITCODE" }
    } catch { "실행 불가: $($_.Exception.Message.Split([Environment]::NewLine)[0])" } finally { $ErrorActionPreference = 'Stop' }
    return [ordered]@{ path = $dest; sha256 = $actual; version = $ver }
}

$paths = [ordered]@{
    GradleJdk = Join-Path $Root 'jdk21-arm64'
    SealedJdk = Join-Path $SealedRoot 'jdk21-arm64-sealed'
    GradleJdkX64 = Join-Path $Root 'jdk21-x64'
    SealedJdkX64 = Join-Path $SealedRoot 'jdk21-x64-sealed'
    WorkRoot = $WorkRoot
    Tester = $Tester
}

if (Want 'Jdk') {
    $result.jdk = [ordered]@{
        gradleArm64 = Install-Jdk 'aarch64' $paths.GradleJdk
        sealedArm64 = Install-Jdk 'aarch64' $paths.SealedJdk
        gradleX64 = Install-Jdk 'x64' $paths.GradleJdkX64
        sealedX64 = Install-Jdk 'x64' $paths.SealedJdkX64
    }
}

if (Want 'Seal') {
    $seal = Join-Path $PSScriptRoot 'winseal.ps1'
    $result.seal = @(
        (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $seal -Action install -SealedJdk $paths.SealedJdk -RuleGroup 'AingCheck Seal arm64' | Out-String).Trim(),
        (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $seal -Action install -SealedJdk $paths.SealedJdkX64 -RuleGroup 'AingCheck Seal x64' | Out-String).Trim()
    )
}

if (Want 'WorkDir') {
    New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
    & icacls.exe $WorkRoot /grant "${Tester}:(OI)(CI)M" | Out-Null
    $result.workDir = $WorkRoot
}

if (Want 'Config') {
    $cfgDir = 'C:\ProgramData\aingcheck'
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    $paths | ConvertTo-Json | Set-Content -Encoding utf8 -Path (Join-Path $cfgDir 'vm.json')
    $result.config = Join-Path $cfgDir 'vm.json'
}

function Winget([string]$id) {
    $out = & winget.exe install --id $id -e --silent --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
    return [ordered]@{ id = $id; exit = $LASTEXITCODE; tail = (($out | Select-Object -Last 3) -join ' ') }
}
if (Want 'Git') { $result.git = Winget 'Git.Git' }
if (Want 'Sdk') { $result.sdk = Winget 'Microsoft.WindowsSDK.10.0.26100' }
if (Want 'Korean') {
    try { Install-Language -Language ko-KR | Out-Null; $result.korean = 'installed' } catch { $result.korean = "error: $($_.Exception.Message)" }
}

Write-Output ($result | ConvertTo-Json -Depth 6 -Compress)
