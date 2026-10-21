#!/bin/bash
# 시험용 가짜 ssh(맥 전용). 손님 파일계는 $FAKE_GUEST 아래 C:\ → $FAKE_GUEST/ 로 옮겨 흉내 낸다.
# verify-tree 는 vm.sh 와 **다른 구현**(파이썬)으로 지문을 다시 계산한다 — 같은 코드끼리 대조하는 거짓 초록을 피한다.
set -u
guest="${FAKE_GUEST:?FAKE_GUEST}"
while [ $# -gt 0 ]; do
    case "$1" in
        -i | -o) shift 2 ;;
        -T) shift ;;
        *@*) shift; break ;;
        *) shift ;;
    esac
done
remote="$*"
printf '%s\n' "$remote" >>"${FAKE_SSH_LOG:-/dev/null}"
map() {
    local p="${1//\\//}"
    p="${p#C:}"
    printf '%s%s' "$guest" "$p"
}
arg_of() { sed -n "s/.*$1 \"\\{0,1\\}\\([^\" ]*\\)\"\\{0,1\\}.*/\\1/p" <<<"$remote"; }

case "$remote" in
    "echo ok") echo ok ;;
    *"tar -xf -"*)
        dir="$(sed -n 's/.*mkdir \([^ ]*\) .*/\1/p' <<<"$remote")"
        d="$(map "$dir")"
        mkdir -p "$d"
        tar -xf - -C "$d"
        if [ "${FAKE_TAMPER:-0}" = 1 ]; then
            printf 'x' >>"$(find "$d" -type f ! -name .aingcheck-push.json | LC_ALL=C sort | head -1)"
        fi
        ;;
    *winrun.ps1*)
        run_dir="$(map "$(arg_of -RunDir)")"
        action="$(arg_of -Action)"
        case "$action" in
            verify-tree)
                python3 -I - "$run_dir" <<'PY'
import hashlib, json, os, sys
root = sys.argv[1]
ents = []
for dp, dn, fn in os.walk(root):
    for f in fn:
        full = os.path.join(dp, f)
        rel = os.path.relpath(full, root).replace(os.sep, "/")
        if rel == ".aingcheck-push.json" or rel.startswith(".aingcheck-out/"):
            continue
        data = open(full, "rb").read()
        sha = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
        ents.append((rel.encode("utf-8"), f"{sha} {rel}\n"))
ents.sort(key=lambda e: e[0])
digest = hashlib.sha256("".join(e[1] for e in ents).encode("utf-8")).hexdigest()
meta = json.load(open(os.path.join(root, ".aingcheck-push.json")))
match = digest == meta["digest"] and len(ents) == meta["files"]
print(json.dumps({"digestMac": meta["digest"], "digestVm": digest, "filesVm": len(ents), "match": match}))
sys.exit(0 if match else 1)
PY
                ;;
            gradle | gui)
                b64="$(arg_of -ArgsB64)"
                printf '%s' "$b64" | base64 -d >"${FAKE_GUEST_ARGS:-/dev/null}"
                printf '%s\n' "$remote" >"${FAKE_GUEST_ARGS:-/dev/null}.remote"
                exit "${FAKE_GRADLE_EXIT:-0}"
                ;;
            info) echo '{"user":"FAKE\\tester","isAdmin":false}' ;;
            *) echo "fake ssh: 모르는 action $action" >&2; exit 255 ;;
        esac
        ;;
    *) echo "fake ssh: 모르는 원격 명령: $remote" >&2; exit 255 ;;
esac
