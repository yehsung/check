# Windows 11 Arm VM 준비 절차 (사용자용)

VMware Fusion Pro 를 설치한 **다음**부터의 절차다. 한 번만 하면 된다. 끝나면 에이전트가 SSH 로 나머지(시험 계정·JDK·망 봉인·Git·SDK·한국어 입력기)를 채운다.

- 걸리는 시간: 1시간 안팎(Windows 설치·업데이트 대기 포함).
- 화면 이름은 Fusion·Windows 에 보이는 그대로 적었다. Fusion 은 영어 화면, Windows 는 한국어 설치본 기준이다.
- 이 문서의 명령은 **값을 하나도 숨기지 않는다**. 비밀번호는 어디에도 적지 않는다. SSH **공개키**만 VM 에 넣는다(공개키는 비밀이 아니다).
- 정본: G §3 U4·U5, §8-1(Home·Microsoft 계정·NAT), §8-6(VM 하네스). 에이전트용 사용법은 같은 폴더의 `README.md`.

---

## 0. 미리 정할 것

| 항목 | 값 |
|---|---|
| VM 이름 | `aing-win11-arm` (하네스 기본값. 바꾸면 에이전트에게 알려 준다) |
| 저장 위치 | Fusion 기본 `~/Virtual Machines.localized/` |
| 사양 | 메모리 8GB · 프로세서 4개 · 디스크 80GB(미리 할당하지 않음 = 씬) |
| 네트워크 | NAT — Fusion 의 **Share with my Mac** |
| TPM | Fusion vTPM(Windows 11 필수). VM 암호 비밀번호는 **Mac 키체인에 기억**시킨다 |
| Windows | **Windows 11 Home**, 설치 때 **본인 Microsoft 계정**으로 로그인 (제품 키 없이 설치) |

## 1. Windows 11 Arm64 ISO 받기

1. Mac 의 Safari 로 https://www.microsoft.com/en-us/software-download/windows11arm64 를 연다.
2. **Download Windows 11 Disk Image (ISO) for Arm-based PCs** 에서 판(Windows 11 (multi-edition ISO for Arm64))을 고르고 **Confirm**.
3. 언어에서 **Korean** 을 고르고 **Confirm** → **Download** 단추. 링크는 24시간만 유효하다.
4. 페이지에 함께 나오는 **SHA256** 값을 복사해 둔다. 받은 뒤 터미널에서 대조한다(두 줄이 같아야 한다).

   ```bash
   shasum -a 256 ~/Downloads/Win11_*Arm64*.iso
   ```

## 2. SSH 키 만들기 (Mac 터미널, 한 번)

에이전트는 키를 만들지도 읽지도 않는다. 사용자가 만들고, 하네스는 **경로만** 쓴다.

```bash
mkdir -p ~/.aing-check-secrets/vm && chmod 700 ~/.aing-check-secrets ~/.aing-check-secrets/vm
ssh-keygen -t ed25519 -N "" -C aingcheck-vm -f ~/.aing-check-secrets/vm/aingcheck_vm_ed25519
cat ~/.aing-check-secrets/vm/aingcheck_vm_ed25519.pub
```

마지막 줄(`ssh-ed25519 AAAA… aingcheck-vm`)이 **공개키**다. 7단계에서 VM 에 붙여 넣는다. `.pub` 이 없는 파일(개인키)은 어디에도 붙이지 않는다.

## 3. Fusion 에서 VM 만들기

1. Fusion 메뉴 **File > New…** → **Install from disc or image** → 1단계의 ISO 를 창에 끌어다 놓고 **Continue**.
2. **Choose Operating System** 에서 **Microsoft Windows > Windows 11 64-bit Arm** → **Continue**.
3. **Encryption** 화면(Windows 11 의 TPM 때문에 나온다)
   - **Only the files needed to support a TPM are encrypted** 를 고른다(디스크 전체 암호화가 아니다 — 빠르다).
   - **Auto-generate password** 를 켜거나, 직접 정한 비밀번호를 넣는다.
   - **Remember Password and store it in Mac's Keychain** 를 **반드시 켠다**. 하네스가 창 없이(`nogui`) VM 을 켤 때 이 키체인 항목을 써야 한다(A-X11). 끄면 매번 비밀번호 창이 뜬다.
   - **Continue**.
4. **Finish** 화면에서 **Customize Settings** 를 누르고, 이름을 `aing-win11-arm` 으로, 위치는 기본(**Virtual Machines**)으로 **Save**.
5. 설정 창(**Settings**)이 열린다. 아래를 바꾼다.
   - **Processors & Memory**: 프로세서 **4 processor cores**, 메모리 **8192 MB**.
   - **Hard Disk (NVMe)**: **Disk size 80.00 GB**, **Pre-allocate disk space** 는 **끈다**(씬 디스크) → **Apply**.
   - **Network Adapter**: **Share with my Mac** (NAT). Bridged 는 쓰지 않는다(VM 을 집 안 LAN 에 열지 않는다).
   - **Sharing**: 켜지 않는다(Arm Windows 손님은 공유 폴더를 지원하지 않는다).
6. 설정 창을 닫고 ▶(시작) 단추로 VM 을 켠다. "Press any key to boot from CD or DVD" 가 보이면 아무 키나 누른다.

## 4. Windows 설치

1. **Windows 설치** 화면: 언어 **한국어**, 시간·통화 **한국어(대한민국)**, 키보드 **Microsoft 입력기** → **다음**.
2. **Windows 11 설치** 를 고르고(옛 설치 방식 선택 화면이 나오면 기본값) **다음**.
3. **제품 키** 화면에서 **제품 키가 없음** 을 누른다.
4. 판 선택에서 **Windows 11 Home** → **다음**. 사용 조건 **동의**.
5. 디스크 화면에 80GB 디스크 하나(**드라이브 0 할당되지 않은 공간**)가 보이면 그대로 **다음**. 설치가 끝나면 저절로 다시 시작한다(몇 번 재시작한다).

## 5. 첫 설정(OOBE) — Microsoft 계정으로

1. **국가 또는 지역**: **대한민국** → **예**. **키보드 레이아웃**: **Microsoft 입력기** → **예**. 두 번째 키보드는 **건너뛰기**.
2. **네트워크에 연결합시다** 에서 목록이 비어 있으면(Arm Windows 에 VMware 네트워크 드라이버가 없어서다)
   - Fusion 메뉴 **Virtual Machine > Install VMware Tools** 를 누른다(가상 CD 가 들어간다).
   - Windows 화면의 **드라이버 설치** 를 누르고, VMware Tools 드라이브 안의 **vmxnet3** 폴더를 **폴더째** 고른다(드라이브 맨 위를 고르면 "문제가 발생했습니다" 가 난다는 보고가 있다).
   - 목록에 이더넷이 나타나고 연결되면 **다음**.
   - 그래도 안 되면 **Shift+F10**(Mac 키보드는 **fn+Shift+F10**)으로 명령 창을 열고 `OOBE\BYPASSNRO` 를 쳐서 다시 시작한 뒤, 이 2번을 다시 한다. 이 길에서도 **로컬 계정으로 넘어가지 말고** 망이 잡힌 뒤 Microsoft 계정으로 들어간다.
3. **이 디바이스의 이름 지정**: `aing-win11-arm` 처럼 영문으로 정하거나 **지금 건너뛰기**.
4. **Microsoft 계정 추가**: **본인 Microsoft 계정**으로 로그인한다(§8-1. 사용자 계정이 이 VM 의 관리자가 된다).
5. **PIN 만들기**: 만든다(로그인용. 하네스는 쓰지 않는다).
6. 개인 정보 설정 화면들은 전부 **아니요** 또는 끔으로 두고 **동의**. 휴대폰 연결·OneDrive 백업·Microsoft 365 권유는 **건너뛰기** / **지금은 안 함**.
7. 바탕 화면이 나오면 설치 끝.

## 6. VMware Tools 설치 (복사·붙여넣기, IP 보고)

1. 5단계에서 넣지 않았다면 Fusion 메뉴 **Virtual Machine > Install VMware Tools**.
2. **파일 탐색기 > 내 PC** 의 VMware Tools 드라이브(보통 **D:**)를 열어 **setup.exe** 를 실행한다. **setup.exe** 가 없으면 **시작** 단추를 오른쪽 클릭 → **터미널(관리자)** 에서 `D:\setup.ps1` 을 실행한다.
3. 기본값(**Typical**)으로 설치하고 **다시 시작**.
4. **설정 > Windows 업데이트 > 업데이트 확인** 을 한 번 돌리고, 요구하면 다시 시작한다.

## 7. OpenSSH 서버 켜기 · 공개키 등록 (관리자 PowerShell)

**시작** 단추를 오른쪽 클릭 → **터미널(관리자)** (또는 **Windows PowerShell(관리자)**) → **사용자 계정 컨트롤** 에서 **예**. 아래를 한 블록씩 붙여 넣는다(Mac 에서 복사한 글은 6단계 뒤로 VM 안에 붙여 넣을 수 있다).

```powershell
# 1) OpenSSH 서버 설치·자동 시작 (몇 분 걸린다)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# 2) 이 네트워크를 '개인'으로 — NAT 라 집 LAN 에는 열리지 않는다. 22번은 개인 프로필에만 연다
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Private
} else {
  Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Private
}
```

```powershell
# 3) 공개키 등록 — 작은따옴표 사이에 2단계의 .pub 한 줄을 그대로 붙여 넣는다
$pub = 'ssh-ed25519 AAAA…여기에 붙여 넣기… aingcheck-vm'
Set-Content -Path C:\ProgramData\ssh\administrators_authorized_keys -Value $pub -Encoding ascii
icacls.exe C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F'

# 4) 에이전트에게 알려 줄 값 두 개
$env:USERNAME
(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }).IPAddress
```

- 관리자 계정의 공개키는 `C:\ProgramData\ssh\administrators_authorized_keys` 에서 읽힌다(사용자 폴더의 `.ssh` 가 아니다). 그래서 위 경로에 넣는다.
- `icacls` 줄은 그 파일을 관리자·SYSTEM 만 읽게 한다. 이 권한이 넓으면 sshd 가 키를 무시한다.

## 8. Mac 에서 확인

Mac 터미널에서(사용자 이름·IP 는 7단계 4)의 출력):

```bash
ssh -i ~/.aing-check-secrets/vm/aingcheck_vm_ed25519 -o IdentitiesOnly=yes <사용자이름>@<IP> whoami
```

`aing-win11-arm\<사용자이름>` 처럼 한 줄이 나오면 된다. 처음 한 번 "Are you sure you want to continue connecting" 에 `yes`.

## 9. 끄고 스냅숏 `clean`

1. VM 안에서 **시작 > 전원 > 시스템 종료**.
2. Fusion 메뉴 **Virtual Machine > Snapshots…** → **Take Snapshot** → 이름 `clean` → **Take**.
   - Smart App Control 평가 실험(D-E23)과 설치 시험을 이 상태에서 다시 시작한다.
3. **Fusion 창을 닫는다**(VM 이 꺼진 상태). 하네스는 창 없이 VM 을 켠다. VM 이 켜져 있으면 하네스가 "이미 켜져 있다"(75)로 멈춘다.

## 10. 에이전트에게 넘길 것

- 7단계 4)의 **관리자 사용자 이름**(Microsoft 계정의 로컬 이름). IP 는 하네스가 다시 찾는다.
- VM 이름이나 위치를 바꿨다면 그 `.vmx` 경로.

그다음은 에이전트가 한다: 관리자 SSH 로 `winprep-admin.ps1` 을 한 번 돌려 시험용 **표준 계정 `tester`**·하네스 관리자 `aingadmin` 을 만들고(비밀번호는 무작위·어디에도 안 남김), `tester` 자동 로그인, 개발자 모드, JDK 21(Gradle 용·시험 전용 봉인 두 벌 × arm64·x64), **시험 전용 JDK 아웃바운드 상시 차단 규칙**, Git, Windows SDK, 한국어 입력기 구성 요소를 넣고, 스냅숏 `toolchain` 을 뜬다.

## 하지 않는 것

- VM 안에서 Claude·Codex·Google 계정으로 로그인하지 않는다(§8-8). 에이전트도 하지 않는다.
- 비밀번호·PIN·VM 암호 비밀번호를 파일이나 채팅에 적지 않는다.
- 공유 폴더·Bridged 네트워크를 켜지 않는다.
- `vmrun -gp`(손님 비밀번호를 명령줄에 싣는 방식)는 하네스가 기본으로 막는다.

## 문제가 생기면

| 증상 | 할 일 |
|---|---|
| 하네스가 VM 을 못 켠다(`vm.sh up` 69, 비밀번호 창) | 3단계 3)의 **Remember Password and store it in Mac's Keychain** 이 꺼져 있다. VM 이 꺼진 상태에서 **Settings > Encryption** 에서 다시 켠다. 그래도 안 되면 에이전트에게 알린다(A-X11 대안: 하네스 전용 키체인 항목 + `-vp`, ps 에 비밀번호가 보이는 위험이 있다) |
| `ssh` 가 `Permission denied (publickey)` | 7단계 3)을 다시 한다. 붙여 넣은 줄이 `ssh-ed25519` 로 시작하는 한 줄인지, `icacls` 를 돌렸는지 본다 |
| `ssh` 가 시간 초과 | VM 안에서 `Get-Service sshd` 가 Running 인지, 7단계 2)의 네트워크가 **개인**인지 본다 |
| IP 가 안 나온다 | 6단계(VMware Tools)를 마쳤는지 본다 |

## 출처

- Microsoft Windows 11 Arm64 ISO: https://www.microsoft.com/en-us/software-download/windows11arm64
- OpenSSH 서버(Windows): https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse , 관리자 키 위치: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
- Arm Windows 의 vmxnet3 드라이버·OOBE 우회(커뮤니티 보고): https://community.broadcom.com/vmware-cloud-foundation/discussion/fusion-13-windows-11-arm-installation-hangs-indicating-no-network-access , https://ucsd-igpp.atlassian.net/wiki/spaces/igppwiki/pages/7186801/How+to+install+Windows+11+on+M1+M2+Mac+using+VMware+Fusion+13
- Fusion Arm 손님 공유 폴더 미지원: https://knowledge.broadcom.com/external/article/315609
- 미확인(설치하며 확인): Fusion 25H2 의 정확한 화면 문구, Windows 11 26H2 OOBE 의 네트워크 화면 문구, VMware Tools 드라이브의 vmxnet3 하위 폴더 이름.
