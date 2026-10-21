# VM 하네스 (W0-e 소유, G §8-6)

맥에서 VMware Fusion 의 Windows 11 Arm VM 을 **창 없이** 다룬다. 사용자 준비는 `SETUP-ko.md`.

| 파일 | 어디서 | 누가 |
|---|---|---|
| `vm.sh` | 맥 | 에이전트. VM 은 이것으로만 다룬다 |
| `cgwindows.swift` | 맥 | `vm.sh` 가 Fusion 창 수를 잰다(창을 만들지 않는다) |
| `winprep-admin.ps1` | VM, 관리자 1회 | 에이전트가 사용자 관리자 SSH 로 한 번 |
| `winseal.ps1` | VM | `install` 은 관리자 1회, `status`·`canary` 는 표준 사용자 `tester` |
| `winrun.ps1` | VM, `tester` | `vm.sh` 가 SSH 로 부른다(지문 대조·gradle·`schtasks /IT`·캡처) |
| `Canary.java` | VM·러너 | 봉인 카나리아(JDK 단일 파일 실행) |
| `tests/` | 맥·러너 | `test-vm-sh.sh`(가짜 vmrun·ssh), 러너 예행에서 `fake-vmrun.sh` 재사용 |

## 묶음 실행(§8-6 "VM 몫은 갈래 끝 한 번")

```bash
cat > "$SCRATCH/vm-plan.txt" <<'EOF'
push
info
gradle :desktopApp:windowsTest
gui -- C:\work\runs\<run>\...\AingCheck.exe --selfcheck=C:\work\out.json
EOF
multiplatform/scripts/vm/vm.sh batch "$SCRATCH/vm-plan.txt"   # 언제나 down 까지 한다. 첫 실패의 코드로 끝난다
```

- 잠금 `/tmp/aingcheck-vm.lock` 을 못 잡으면 **기다리지 않고 75** 로 끝난다. 그대로 보고한다.
- `push` 는 임시 인덱스 스냅숏이라 커밋 안 한 새 파일까지 간다. 손님이 받은 파일의 지문을 다시 계산해 맥 값과 대조한다(어긋나면 1).
- `gradle` 은 손님에서 봉인 카나리아 짝(봉인 JDK = 방화벽 거부, 비봉인 JDK = 거부 아님)이 통과해야만 돈다(아니면 90). Gradle 은 비봉인 JDK, 시험 JVM 은 `-PtestJavaExecutable=<봉인 JDK>\bin\java.exe` 로 간다 — **메인 빌드(W0-a)가 이 속성을 `Test.executable` 로 받아야 한다**.
- `vmrun -gp` 는 기본 금지(64). 하네스 전용 시험 계정 `aingvm-*` + `AINGCHECK_VM_ALLOW_GP=1` 일 때만.
- 끝나면 보고에 `vm.sh status` 와 `pgrep -fl vmware-vmx` 를 붙인다.
