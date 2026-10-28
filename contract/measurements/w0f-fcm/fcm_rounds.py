# 원본: 없음 (W0-f ⑤ FCM 토큰 운전 스크립트 — B§9-1 · B§9-4 · E-U6)
# 쓰는 법: python3 -I fcm_rounds.py <adb> <serial> <탐침 APK> [회수=10]   ·   python3 -I fcm_rounds.py --self-test(기기 없이 logcat 훑기 시험)
#   회차마다 새 토큰을 받는다(홀수 = 지우고 다시 설치, 짝수 = pm clear) → 탐침(FcmProbe)이 기기 안에서 잰 값만 받는다.
#   끝에 채널 실험(mode=notify) 한 번 → 판정(VERDICT) → 종료 코드(0 = 모두 맞음, 1 = 하나라도 어긋남).
# 토큰 원문은 기기 밖으로 나오지 않는다. 탐침이 내는 것은 길이·글자 집합·정규식 일치와 소금 붙인 SHA-256 앞 16자(h)뿐이다.
# h 는 이 프로세스 메모리에서만 서로 다름을 세는 데 쓰고, 출력·파일에 적지 않는다(소금도 이 실행이 끝나면 사라진다).
# logcat 은 파일로 받지 않는다 — 메모리에서 토큰 꼴 줄의 태그 수와, 그 줄에 이번 토큰(같은 h)이 있는지만 센다.
import hashlib
import json
import re
import secrets
import subprocess
import sys
import time

ADB = SERIAL = APK = None
ROUNDS = 10
PKG = "com.yehsung.aingcheck"
RUNNER = PKG + "/com.yehsung.aingcheck.w0f5.FcmProbe"
SALT = secrets.token_hex(16)
TOKEN_LIKE = re.compile(r"[A-Za-z0-9_\-]{16,}:APA91b[A-Za-z0-9_\-]{40,}")


def adb(*args, timeout=600):
    r = subprocess.run([ADB, "-s", SERIAL, *args], capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout, r.stderr


def instrument(mode):
    rc, out, err = adb("shell", "am", "instrument", "-w", "-r", "-e", "mode", mode, "-e", "salt", SALT, RUNNER, timeout=480)
    res = {}
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("INSTRUMENTATION_RESULT: "):
            k, _, v = line[len("INSTRUMENTATION_RESULT: "):].partition("=")
            res[k] = v
        elif line.startswith("INSTRUMENTATION_CODE: "):
            res["_code"] = line.split(": ", 1)[1]
        elif line.startswith("INSTRUMENTATION_FAILED") or line.startswith("INSTRUMENTATION_ABORTED"):
            res["_failed"] = line[:200]
    res["_adb_rc"] = rc
    return res


def salted(tok):
    return hashlib.sha256((SALT + "|" + tok).encode()).hexdigest()[:16]


def scan_log(log, lengths, hs):
    """토큰 꼴 줄의 태그별 수와, 줄 안 어느 자리든 길이 L 조각의 소금 해시가 hs 에 드는 줄 수."""
    tags = {}
    ours = 0
    for line in log.splitlines():
        if not TOKEN_LIKE.search(line):
            continue
        tag = line.split(":", 1)[0].strip()[:60]
        tags[tag] = tags.get(tag, 0) + 1
        if any(salted(line[i:i + L]) in hs for L in lengths for i in range(0, max(0, len(line) - L) + 1)):
            ours += 1
    return tags, ours


def self_test():
    """기기 없이: logcat 훑기가 이번 토큰(합성 — 진짜 토큰 아님)을 찾고, 다른 토큰 꼴 줄은 이번 것으로 세지 않는다."""
    fake = "f" * 22 + ":APA91b" + "Q_x-" * 28 + "Z"           # 142자 합성 토큰 꼴
    other = "g" * 22 + ":APA91b" + "R_y-" * 28 + "W"
    hs = {salted(fake)}
    log = "\n".join([
        "I/Finsky: token " + other,                          # 남의 토큰 꼴 — 태그만 센다
        "D/Probe: x=" + fake + " tail",                      # 이번 토큰 — 찾아야 한다
        "I/Other: nothing here",
    ])
    tags, ours = scan_log(log, [len(fake)], hs)
    fails = []
    if ours != 1:
        fails.append(f"이번 토큰이 든 줄 {ours} (기대 1)")
    if tags != {"I/Finsky": 1, "D/Probe": 1}:
        fails.append(f"태그 {tags}")
    tags2, ours2 = scan_log(log.replace(fake, other), [len(fake)], hs)
    if ours2 != 0:
        fails.append(f"이번 토큰이 없는데 {ours2}")
    print("SELF-TEST " + ("ok" if not fails else "fail " + json.dumps(fails, ensure_ascii=False)))
    return 0 if not fails else 1


def env():
    e = {}
    e["fingerprint"] = adb("shell", "getprop", "ro.build.fingerprint")[1].strip()
    e["sdk"] = adb("shell", "getprop", "ro.build.version.sdk")[1].strip()
    gms = adb("shell", "dumpsys", "package", "com.google.android.gms")[1]
    m = re.search(r"versionName=(\S+)", gms)
    e["gmsVersion"] = m.group(1) if m else None
    acc = adb("shell", "dumpsys", "account")[1]
    m = re.search(r"Accounts:\s*(\d+)", acc)          # 수만 — 계정 이름은 읽지 않는다
    e["deviceAccounts"] = int(m.group(1)) if m else None
    return e


def judge(rounds, notify, summary, before, after):
    """어긋난 까닭 목록(빈 목록 = 맞음). 서버 세 꼴(M1 CHECK · register_device_fcm · push-send)과 B§9-1 · B§9-4 의 기대."""
    bad = []
    if len(rounds) != ROUNDS:
        bad.append(f"회차 {len(rounds)}/{ROUNDS}")
    for r in rounds:
        n = r.get("round")
        if "error" in r or r.get("_code") != "-1" or "_failed" in r:
            bad.append(f"{n}: 탐침 실패 {r.get('error') or r.get('_failed') or r.get('_code')}")
            continue
        for k in ("jsForm", "pgForm", "btrimNoop", "stableWithinInstall", "headEqualsFid"):
            if r.get(k) != "true":
                bad.append(f"{n}: {k}={r.get(k)}")
        if not (33 <= int(r.get("minChar", -1)) and int(r.get("maxChar", 999)) <= 126):
            bad.append(f"{n}: 글자 범위 {r.get('minChar')}..{r.get('maxChar')}")
        if r.get("googleAccountsVisible") != "0":
            bad.append(f"{n}: 앱이 본 Google 계정 {r.get('googleAccountsVisible')}")
    if summary["distinctTokens"] != summary["tokens"] or summary["tokens"] != ROUNDS:
        bad.append(f"서로 다른 토큰 {summary['distinctTokens']}/{summary['tokens']}/{ROUNDS}")
    if summary["logcatLinesWithOurTokens"] != 0:
        bad.append(f"logcat 에 이번 토큰이 든 줄 {summary['logcatLinesWithOurTokens']}")
    for e, when in ((before, "앞"), (after, "뒤")):
        if e.get("deviceAccounts") != 0:
            bad.append(f"기기 계정 수({when}) {e.get('deviceAccounts')}")
    # B§9-4: 기준선(채널 있음)은 보이고, 없는 채널로 앱이 게시하면 버려지고, 채널을 만든 뒤엔 보인다.
    #        SDK notification 메시지가 없는 channel_id 를 가리키면 fcm_fallback_notification_channel 로 보인다.
    want = {"baselinePosted": "true", "missingPosted": "false", "messageChannelCreatedImplicitly": "false",
            "afterCreatePosted": "true", "sdkPostedChannels": "fcm_fallback_notification_channel",
            "noSuchChannelExistsAfter": "false", "fallbackExistsAfter": "true"}
    if "error" in notify or notify.get("_code") != "-1":
        bad.append(f"notify: 탐침 실패 {notify.get('error') or notify.get('_code')}")
    else:
        for k, v in want.items():
            if notify.get(k) != v:
                bad.append(f"notify: {k}={notify.get(k)} (기대 {v})")
    return bad


def main():
    global ADB, SERIAL, APK, ROUNDS
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()
    ADB, SERIAL, APK = sys.argv[1], sys.argv[2], sys.argv[3]
    ROUNDS = int(sys.argv[4]) if len(sys.argv) > 4 else 10
    before = env()
    print("ENV-BEFORE " + json.dumps(before, ensure_ascii=False), flush=True)
    hashes = []
    rounds = []
    for r in range(1, ROUNDS + 1):
        how = "reinstall" if r % 2 == 1 else "pm-clear"
        if how == "reinstall":
            adb("uninstall", PKG, timeout=120)
            rc, out, err = adb("install", APK, timeout=300)
            if rc != 0 or "Success" not in out:
                rounds.append({"round": r, "how": how, "error": "install 실패: " + (out + err)[-200:]})
                continue
        else:
            rc, out, err = adb("shell", "pm", "clear", PKG, timeout=120)
            if rc != 0 or "Success" not in out:
                rounds.append({"round": r, "how": how, "error": "pm clear 실패: " + (out + err)[-200:]})
                continue
        t0 = time.time()
        res = instrument("token")
        h = res.pop("h", None)
        if h:
            hashes.append(h)
        res["round"] = r
        res["how"] = how
        res["wallSeconds"] = round(time.time() - t0, 1)
        rounds.append(res)
        print(json.dumps(res, ensure_ascii=False), flush=True)

    # logcat(메모리에서만): 토큰 꼴 줄의 태그(내용 아님)와, 그 줄 안에 이번 토큰(같은 h)이 있는지
    lengths = sorted({int(x["len"]) for x in rounds if "len" in x})
    hs = set(hashes)
    rc, log, _ = adb("logcat", "-d", "-v", "tag", timeout=120)
    tags, ours = scan_log(log, lengths, hs)
    del log

    summary = {
        "rounds": len(rounds),
        "tokens": len(hashes),
        "distinctTokens": len(hs),
        "logcatTokenLikeLinesByTag": tags,
        "logcatLinesWithOurTokens": ours,
    }
    print("SUMMARY " + json.dumps(summary, ensure_ascii=False), flush=True)

    # B§9-4 채널 실험(토큰 없음). API 33+ 는 알림 권한을 먼저 준다.
    adb("shell", "pm", "grant", PKG, "android.permission.POST_NOTIFICATIONS", timeout=60)
    notify = instrument("notify")
    notify.pop("h", None)
    print("NOTIFY " + json.dumps(notify, ensure_ascii=False), flush=True)

    after = env()
    print("ENV-AFTER " + json.dumps(after, ensure_ascii=False), flush=True)
    bad = judge(rounds, notify, summary, before, after)
    print("VERDICT " + ("ok" if not bad else "fail " + json.dumps(bad, ensure_ascii=False)), flush=True)
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
