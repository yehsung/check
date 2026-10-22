import Foundation
import Testing
@testable import check

// v0.3.61 원클릭 업데이트 — 8갈래 나눠 받기(`pfetch`) · brew 미리 받기 · DMG 받기 단계.
//
// 문자열이 아니라 **실제 zsh 로 돌린다.** 프로덕션 상수(`UpdateRunner.pfetchFunction` · `brewUpgradeScript` ·
// `brewSpawnWrapper` · `dmgUpdateScript`)를 그대로 쓰고, 바깥 세계만 가짜로 바꾼다:
//  · 가짜 curl — 테스트가 임시 폴더에 쓰는 실행 스크립트(PATH 맨 앞). 실제 curl 이 받는 옵션(-D · -w · -r · -o · -L ·
//    --speed-limit …)을 받아들이고 **모르는 옵션이면 2 로 죽는다**(실제 curl 과 같은 종료코드). 픽스처의 바이트 범위를 내주고,
//    탐색에는 302 블록(가짜 Content-Range 가 섞인) + 206 블록 머리를 쓴다 — "마지막 응답 블록" 을 읽는지 잰다.
//    시나리오는 환경변수로 가른다(FAKE_NORANGE · FAKE_STALL_ONCE · FAKE_BADCUT_ONCE · FAKE_TRICKLE_END · FAKE_DEAD ·
//    FAKE_SHORT_ALWAYS · FAKE_OVERLONG · FAKE_WHOLE_RC · FAKE_CR_NAME · FAKE_PIECE_MODE · FAKE_TOTAL_TEXT · FAKE_TOTAL_CHANGES ·
//    FAKE_PROBE_SLEEP_AT — 각 뜻은 `fakeCurl` 주석). 끊김 갈래는 실제 curl 처럼 **받은 앞부분만 쓰고 28 로 끝나면서 `-D` 머리와
//    `-w` 코드는 정상으로** 낸다(문턱에 걸려 끊긴 연결) — 이어 받기가 그 앞부분을 쓰는지 잰다.
//  · 가짜 시계 — 시한(120초)은 실제로 기다리지 않는다. 시험 래퍼가 `wait` 를 감싸 바퀴가 끝날 때마다 zsh 의 `SECONDS` 를
//    앞으로 민다(`runPfetch(clockJump:)`). 운영 함수는 한 글자도 바꾸지 않는다 — 환경변수 훅이 없다.
//  · 가짜 brew · 가짜 open — 호출을 차례대로 적고, 준비된 JSON · 캐시 경로를 내준다. 앱 경로도 실험실 안의 없는 경로라
//    가짜 open 이 어긋나도 실제 앱이 뜨지 않는다.
//  · 가짜 cat · 가짜 shasum — 진짜 도구로 일하면서 잇기·지문 검사의 **순간**을 적는다(그때 OUT·캐시 이름이 보였는가).
//    두 벌을 겹치는 시험은 가짜 shasum 이 표식 파일로 차례를 못박는다.
// 네트워크 · 실제 brew · 사용자 Homebrew 캐시 · 화면을 건드리지 않는다(`sandbox-exec … deny network-outbound` 아래에서 초록).

@Suite("0.3.61 원클릭 업데이트 나눠 받기 — 가짜 curl · 가짜 brew 로 실제 zsh 실행")
struct V0361UpdatePrefetchTests {

    // MARK: - A. pfetch

    @Test func pfetch_정상_8조각은_픽스처와_같은_바이트를_남기고_조각을_치운다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        // 가짜 cat 이 조각을 이을 때마다 OUT 이 그 이름으로 보이는지 적는다 — 잇기는 `OUT.part` 에서 하고 다 맞을 때만 mv 로 OUT.
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_CAT_PROBE": lab.outFile.path])

        #expect(run.status == 0, "pfetch 가 실패했다: \(run.output)")
        #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData, "받은 바이트가 픽스처와 다르다")
        #expect(lab.names(in: lab.out) == ["a.bin"], "OUT 옆에 잔재가 있다: \(lab.names(in: lab.out))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 조각이 남았다: \(lab.names(in: lab.tmp))")
        #expect(lab.lines("catprobe") == Array(repeating: "absent", count: 8),
                "잇는 동안 OUT 이 그 이름으로 보였다(반쪽 파일이 OUT 으로 보이는 순간): \(lab.lines("catprobe"))")

        // 탐색 1회(원래 주소로) · 조각 8개(크기 ceil(전체/8)) — 전부 **서명된 최종 주소**로.
        let calls = lab.calls()
        #expect(calls.filter { $0.hasPrefix("probe ") } == ["probe 1 \(PrefetchLab.originURL)"])
        let pieces = calls.filter { $0.hasPrefix("piece ") }
        #expect(Set(pieces) == Set(PrefetchLab.ranges(total: 9_000_001, parts: 8).map {
            "piece \($0) \(PrefetchLab.finalURL(1))"
        }), "조각 범위·주소가 설계와 다르다: \(pieces)")
        #expect(pieces.count == 8)

        // 실제 curl 에 넘기는 옵션(설계서 A 의 두 명령) — 멎은 연결을 끊는 장치와 https 고정이 빠지면 안 된다.
        let argv = lab.curlArgv()
        let probe = try #require(argv.first { $0.contains("-r 0-0") })
        #expect(probe.hasPrefix("argv -fsS -L --proto =https --proto-redir =https --tlsv1.2 --connect-timeout 15 --max-time 30 -r 0-0 -o "))
        #expect(probe.contains(" -w %{http_code} %{url_effective} \(PrefetchLab.originURL)"))
        let pieceArgv = argv.filter { !$0.contains("-r 0-0") }
        #expect(pieceArgv.count == 8)
        for line in pieceArgv {
            // 갇힌 연결(초당 0.5MB 이하)을 3초 만에 끊는 문턱 — 초당 1MB · 3초. 예전 문턱(64KB · 12초)은 그런 연결을 안 끊었다.
            // `-f` 는 없다(코드를 직접 본다). 첫 바퀴의 `--max-time` 은 min(90, 남은 시간) = 90.
            #expect(line.hasPrefix("argv -sS --proto =https --tlsv1.2 --connect-timeout 10 --speed-limit 1048576 --speed-time 3 --max-time 90 -r "),
                    "조각 명령이 설계와 다르다: \(line)")
            #expect(!line.contains(" -L "), "조각이 리다이렉트를 다시 따라간다: \(line)")
            // 조각마다 응답 머리(-D)와 코드(-w)를 받아 요청한 범위와 맞춰 본다(검토 지적 수리 — 크기만 보면 내용이 틀려도 통과한다).
            #expect(line.contains(" -D \(lab.tmp.path)/aing-check-pfetch."), "조각의 응답 머리를 받지 않는다: \(line)")
            #expect(line.hasSuffix(" -w %{http_code} \(PrefetchLab.finalURL(1))"), "조각의 응답 코드를 받지 않는다: \(line)")
        }

        #expect(run.output.contains("나눠 받기 끝: 9000001 bytes · 8갈래 · "), "\(run.output)")
        #expect(run.output.contains("초 · 1바퀴 · 다시 받은 조각 0개\n"), "\(run.output)")
        lab.expectNoSignature(run.output)
    }

    @Test func pfetch_Range_를_안_받는_원본이면_0이_아니고_OUT_도_잔재도_없다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_NORANGE": "1"])

        #expect(run.status != 0, "Range 를 안 받는데 성공이라 했다: \(run.output)")
        #expect(lab.names(in: lab.out).isEmpty, "OUT(또는 .part)이 생겼다: \(lab.names(in: lab.out))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 폴더가 남았다: \(lab.names(in: lab.tmp))")
        #expect(lab.calls().filter { $0.hasPrefix("piece ") }.isEmpty, "Range 를 안 받는 원본에 조각을 보냈다")
        #expect(run.output.contains("나눠 받기 폴백: Range 를 받지 않습니다(HTTP 200) · "), "\(run.output)")
        #expect(run.output.contains("초 · 0바퀴\n"), "\(run.output)")
        lab.expectNoSignature(run.output)
    }

    // ★ 이어 받기(2026-10-21 실측 수리): 갇힌 연결이 문턱에 걸려 28 로 끊겨도 그때까지 받은 앞부분은 맞는 바이트다(머리가 맞으니까).
    // 그것을 버리고 처음부터 받으면(예전) 갇힌 연결에 또 걸릴 때마다 처음으로 돌아간다. 둘째 바퀴는 새 서명 주소로 **받은 데서부터**
    // 요청한다 — 요청 범위를 글자로 못박는다(처음부터 다시 받아도 OUT 은 맞으니 OUT 만 보면 초록이다).
    @Test func pfetch_끊긴_조각은_받은_데서부터_새_서명_주소로_이어_받는다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let (a, b) = PrefetchLab.bounds(PrefetchLab.ranges(total: 9_000_001, parts: 8)[3])
        let half = (b - a + 1) / 2
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_STALL_ONCE": "\(a)"])

        #expect(run.status == 0, "끊긴 조각을 이어 받지 못했다: \(run.output)")
        #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData, "이어 붙인 바이트가 픽스처와 다르다")
        #expect(lab.names(in: lab.out) == ["a.bin"])
        #expect(lab.names(in: lab.tmp).isEmpty)
        let calls = lab.calls()
        // 둘째 바퀴 전에 탐색을 한 번 더 한다(서명 주소 만료·403 대비) — 그리고 이어 받기는 **그 새 주소**로 간다.
        #expect(calls.filter { $0.hasPrefix("probe ") }.count == 2, "재탐색이 없다: \(calls)")
        #expect(lab.pieceCalls(endingAt: b)
                == ["piece \(a)-\(b) \(PrefetchLab.finalURL(1))", "piece \(a + half)-\(b) \(PrefetchLab.finalURL(2))"],
                "끊긴 조각을 받은 데서부터 새 주소로 잇지 않았다: \(calls)")
        // 덜 받은 조각만 다시 받는다(맞은 일곱은 한 번씩).
        #expect(calls.filter { $0.hasPrefix("piece ") }.count == 9)
        #expect(run.output.contains("초 · 2바퀴 · 다시 받은 조각 1개\n"), "\(run.output)")
        lab.expectNoSignature(run.output)
    }

    // curl 종료 코드는 판정에 쓰지 않는다 — 0 으로 끝났는데 짧아도(연결이 조용히 닫힘) 머리가 맞으면 받은 만큼 잇고 나머지만 받는다.
    @Test func pfetch_짧게_끝난_조각도_종료_코드와_상관없이_나머지만_받는다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let (a, b) = PrefetchLab.bounds(PrefetchLab.ranges(total: 9_000_001, parts: 8)[5])
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_SHORT_ALWAYS": "\(a)"])

        #expect(run.status == 0, "\(run.output)")
        #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData)
        #expect(lab.pieceCalls(endingAt: b) == ["piece \(a)-\(b) \(PrefetchLab.finalURL(1))", "piece \(b)-\(b) \(PrefetchLab.finalURL(2))"],
                "모자란 한 바이트만 받지 않았다: \(lab.calls())")
        #expect(run.output.contains("초 · 2바퀴 · 다시 받은 조각 1개\n"), "\(run.output)")
    }

    // 갇힌 연결에 거듭 걸려도 바퀴마다 받은 만큼 쌓인다 — 한 조각이 시도마다 1/4 씩만 주면 4바퀴에 완성된다.
    @Test func pfetch_시도마다_조금씩_받는_조각은_여러_바퀴에_걸쳐_완성된다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let (a, b) = PrefetchLab.bounds(PrefetchLab.ranges(total: 9_000_001, parts: 8)[2])
        let quarter = (b - a + 1 + 3) / 4
        let run = try lab.runPfetch(url: PrefetchLab.originURL,
                                    env: ["FAKE_TRICKLE_END": "\(b)", "FAKE_TRICKLE_BYTES": "\(quarter)"])

        #expect(run.status == 0, "\(run.output)")
        #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData)
        #expect(lab.names(in: lab.tmp).isEmpty)
        #expect(lab.pieceCalls(endingAt: b) == (0..<4).map { "piece \(a + $0 * quarter)-\(b) \(PrefetchLab.finalURL($0 + 1))" },
                "바퀴마다 받은 데서부터 잇지 않았다: \(lab.calls())")
        #expect(lab.calls().filter { $0.hasPrefix("probe ") }.count == 4, "바퀴마다 다시 탐색하지 않았다: \(lab.calls())")
        #expect(lab.calls().filter { $0.hasPrefix("piece ") }.count == 8 + 3)
        #expect(run.output.contains("초 · 4바퀴 · 다시 받은 조각 3개\n"), "\(run.output)")
    }

    // 한 바퀴 동안 한 바이트도 늘지 않으면 더 돌아도 소용없다 — 폴백(호출자가 지금 동작으로). OUT · .part · 임시 폴더가 남지 않는다.
    @Test func pfetch_한_바퀴_동안_0바이트면_폴백하고_아무것도_남기지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let (a, b) = PrefetchLab.bounds(PrefetchLab.ranges(total: 9_000_001, parts: 8)[5])
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_DEAD": "\(a)"])

        #expect(run.status != 0, "아무것도 못 받는 조각을 받아들였다: \(run.output)")
        #expect(lab.names(in: lab.out).isEmpty, "OUT(또는 .part)이 남았다: \(lab.names(in: lab.out))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 조각이 남았다: \(lab.names(in: lab.tmp))")
        // 첫 바퀴엔 다른 일곱이 늘어 둘째 바퀴로 간다. 둘째 바퀴에 0 이면 거기서 멈춘다(셋째는 없다).
        #expect(lab.pieceCalls(endingAt: b) == ["piece \(a)-\(b) \(PrefetchLab.finalURL(1))", "piece \(a)-\(b) \(PrefetchLab.finalURL(2))"],
                "\(lab.calls())")
        #expect(lab.calls().filter { $0.hasPrefix("probe ") }.count == 2)
        #expect(run.output.contains("나눠 받기 폴백: 한 바퀴 동안 받은 것이 없습니다 · "), "\(run.output)")
        #expect(run.output.contains("초 · 2바퀴\n"), "\(run.output)")
        lab.expectNoSignature(run.output)
    }

    // ★ 이어 받기의 전제는 "머리가 맞으면 앞부분도 맞다" 다. 끊긴 시도의 머리가 어긋나면(Range 를 무시하는 캐시가 0번부터의 본문을
    // 내다 끊김) 그 바이트를 잇지 않고 버린다 — 이었다면 다음 바퀴가 그 뒤부터 이어 받아 **크기는 맞고 내용이 틀린** OUT 이 된다.
    // 그래서 OUT 을 바이트로 비교하고, 둘째 바퀴 요청이 처음부터(a-b)인지 본다.
    // 한 줄에서 이어 받는 요청(s > 0)에 200 + 본문 전체가 오면 그것도 받지 않는다(200 은 s = 0 일 때만 본문이 곧 답이다).
    @Test func pfetch_끊긴_시도의_머리가_어긋나면_그_바이트는_잇지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001, label: "badcut")
        let (a, b) = PrefetchLab.bounds(PrefetchLab.ranges(total: 9_000_001, parts: 8)[3])
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_BADCUT_ONCE": "\(a)"])

        #expect(run.status == 0, "\(run.output)")
        #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData, "머리가 어긋난 앞부분을 이어 붙였다")
        #expect(lab.pieceCalls(endingAt: b) == ["piece \(a)-\(b) \(PrefetchLab.finalURL(1))", "piece \(a)-\(b) \(PrefetchLab.finalURL(2))"],
                "머리가 어긋난 바이트를 받은 것으로 셌다: \(lab.calls())")
        #expect(run.output.contains("초 · 2바퀴 · 다시 받은 조각 1개\n"), "\(run.output)")

        let single = try PrefetchLab(fixtureSize: 300_000, label: "resume200")
        let resumed = try single.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_STALL_ONCE": "0", "FAKE_PIECE_MODE": "code200"])
        #expect(resumed.status != 0, "이어 받는 요청에 온 200 전체 본문을 이어 붙였다: \(resumed.output)")
        #expect(single.calls().filter { $0.hasPrefix("piece ") }
                == ["piece 0-299999 \(PrefetchLab.finalURL(1))", "piece 150000-299999 \(PrefetchLab.finalURL(2))"],
                "\(single.calls())")
        #expect(resumed.output.contains("나눠 받기 폴백: 한 바퀴 동안 받은 것이 없습니다 · "), "\(resumed.output)")
        #expect(single.names(in: single.out).isEmpty)
        #expect(single.names(in: single.tmp).isEmpty)
    }

    // 머리가 맞는데 본문이 요청보다 길면(조각 파일이 기대보다 커짐) 그 파일은 더는 맞출 수 없다 — 바로 폴백한다.
    @Test func pfetch_조각_파일이_기대보다_커지면_바로_폴백한다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let (a, b) = PrefetchLab.bounds(PrefetchLab.ranges(total: 9_000_001, parts: 8)[2])
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_OVERLONG": "\(a)"])

        #expect(run.status != 0, "\(run.output)")
        #expect(run.output.contains("나눠 받기 폴백: 조각 2 의 크기가 기대보다 큽니다(\(b - a + 2) > \(b - a + 1)) · "), "\(run.output)")
        #expect(run.output.contains("초 · 1바퀴\n"), "\(run.output)")
        #expect(lab.calls().filter { $0.hasPrefix("probe ") }.count == 1, "커진 조각을 두고 바퀴를 더 돌았다: \(lab.calls())")
        #expect(lab.calls().filter { $0.hasPrefix("piece ") }.count == 8)
        #expect(lab.names(in: lab.out).isEmpty)
        #expect(lab.names(in: lab.tmp).isEmpty)
    }

    // ★ 시한 120초 — 바퀴가 몇 번이든 그 안에서 끝난다(`pfetchWorstCaseSeconds` 와 감시 시한의 전제). 실제로 기다리지 않고 가짜 시계로 잰다:
    // 바퀴가 끝날 때마다(`wait`) 시계를 앞으로 민다. 한 조각은 시도마다 1,000바이트만 줘서(0바이트 폴백에 안 걸리게) 끝나지 않는다.
    //  · 30초씩 — 넷째 바퀴 뒤 남은 0초: 다섯째 바퀴의 재탐색을 보내지 않는다(탐색 4회).
    //  · 29초씩 + 다섯째 탐색이 2초 걸림 — 남은 4초로 탐색은 가지만 끝나고 남은 2초: 조각을 보내지 않는다.
    // 그리고 `--max-time` 은 탐색 min(30, 남은) · 조각 min(90, 남은) — 시한을 넘어 도는 curl 이 없다.
    @Test func pfetch_시한을_다_쓰면_새_바퀴를_시작하지_않고_curl_도_시한을_넘지_않는다() throws {
        let (a, b) = PrefetchLab.bounds(PrefetchLab.ranges(total: 9_000_001, parts: 8)[3])
        for (jump, slowProbe, probes, pieceTimes, reason) in [
            (30, false, [30, 30, 30, 30], [90, 90, 60, 30], "다시 탐색: 시간이 다 됐습니다"),
            (29, true, [30, 30, 30, 30, 4], [90, 90, 62, 33], "시간이 다 됐습니다"),
        ] {
            let lab = try PrefetchLab(fixtureSize: 9_000_001, label: "jump\(jump)")
            var env = ["FAKE_TRICKLE_END": "\(b)", "FAKE_TRICKLE_BYTES": "1000"]
            if slowProbe { env["FAKE_PROBE_SLEEP_AT"] = "5"; env["FAKE_PROBE_SLEEP_SECS"] = "2" }
            let run = try lab.runPfetch(url: PrefetchLab.originURL, env: env, clockJump: jump)

            #expect(run.status != 0, "\(jump): \(run.output)")
            #expect(run.output.contains("나눠 받기 폴백: \(reason) · "), "\(jump): \(run.output)")
            #expect(run.output.contains("초 · 5바퀴\n"), "\(jump): \(run.output)")
            // 값은 가짜 시계가 정한다. 다만 한 바퀴가 실제로 1초를 넘기면(부하) `SECONDS` 가 1 더 가 남은 시간이 1 줄 수 있어
            // 각 값은 [기대-1, 기대] 안이면 맞다 — 개수는 정확히 같아야 한다(고정 30·90 이나 시한 검사 누락은 그 폭을 한참 넘는다).
            let argv = lab.curlArgv()
            let probeTimes = argv.filter { $0.contains(" -r 0-0 ") }.map(PrefetchLab.maxTime)
            #expect(PrefetchLab.within1(probeTimes, of: probes),
                    "\(jump): 탐색의 --max-time 이 min(30, 남은 시간)이 아니다: \(probeTimes) — 기대 \(probes)")
            let slowTimes = argv.filter { $0.contains("-\(b) -o ") }.map(PrefetchLab.maxTime)
            #expect(PrefetchLab.within1(slowTimes, of: pieceTimes),
                    "\(jump): 조각의 --max-time 이 min(90, 남은 시간)이 아니다: \(slowTimes) — 기대 \(pieceTimes)")
            #expect(lab.pieceCalls(endingAt: b).count == 4, "\(jump): \(lab.calls())")
            #expect(lab.pieceCalls(endingAt: b).first == "piece \(a)-\(b) \(PrefetchLab.finalURL(1))")
            #expect(lab.names(in: lab.out).isEmpty, "\(jump)")
            #expect(lab.names(in: lab.tmp).isEmpty, "\(jump)")
        }
    }

    // 안전핀 — 시한과 0바이트 검사를 다 지나도(바퀴마다 조금씩은 는다) 40바퀴를 넘기지 않는다.
    // 한 줄 100바이트를 시도마다 1바이트씩 주면 100바퀴가 걸린다 — 40바퀴째에서 멈추고 41번째 요청은 없다.
    @Test func pfetch_40바퀴를_넘기면_폴백한다() throws {
        let lab = try PrefetchLab(fixtureSize: 100)
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_TRICKLE_END": "99", "FAKE_TRICKLE_BYTES": "1"])

        #expect(run.status != 0, "\(run.output)")
        #expect(run.output.contains("나눠 받기 폴백: 40바퀴 안에 끝나지 않았습니다 · "), "\(run.output)")
        #expect(run.output.contains("초 · 40바퀴\n"), "\(run.output)")
        #expect(lab.pieceCalls(endingAt: 99) == (0..<40).map { "piece \($0)-99 \(PrefetchLab.finalURL($0 + 1))" }, "\(lab.calls())")
        #expect(lab.calls().filter { $0.hasPrefix("probe ") }.count == 40)
        #expect(lab.names(in: lab.out).isEmpty)
        #expect(lab.names(in: lab.tmp).isEmpty)
    }

    // 리다이렉트 끝이 https 가 아니면(`--proto-redir '=https'` 를 지나 온 값이라도) 그 주소로 조각을 보내지 않는다.
    @Test func pfetch_최종_주소가_https_가_아니면_조각을_보내지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_FINAL_BASE": "http://objects.example.invalid"])

        #expect(run.status != 0, "https 가 아닌 최종 주소를 받아들였다: \(run.output)")
        #expect(lab.calls().filter { $0.hasPrefix("piece ") }.isEmpty, "https 가 아닌 주소로 조각을 보냈다: \(lab.calls())")
        #expect(lab.names(in: lab.out).isEmpty)
        #expect(lab.names(in: lab.tmp).isEmpty)
        #expect(run.output.contains("최종 주소가 https 가 아닙니다"), "\(run.output)")
    }

    // 크기는 **마지막 응답 블록**에서만 읽는다. 앞 블록(302)의 Content-Range 를 주워 쓰면 전체를 1바이트로 알고
    // 1바이트짜리 OUT 을 "완전하다"고 돌려준다(DMG 는 검증에서, brew 는 지문에서 걸리지만 그건 우연이다).
    @Test func pfetch_마지막_응답_블록에_Content_Range_가_없으면_앞_블록_값을_쓰지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_NO_FINAL_CR": "1"])

        #expect(run.status != 0, "앞 블록의 Content-Range 를 썼다: \(run.output)")
        #expect(lab.calls().filter { $0.hasPrefix("piece ") }.isEmpty, "\(lab.calls())")
        #expect(lab.names(in: lab.out).isEmpty)
        #expect(run.output.contains("Content-Range 가 없습니다"), "\(run.output)")
    }

    // `OUT.part` 를 만든 **뒤에** 실패하면(잇는 도중 디스크가 찬 경우) 반쪽 파일을 남기지 않는다.
    @Test func pfetch_잇다가_실패하면_OUT_도_part_도_조각도_남지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_CAT_FAIL": "1"])

        #expect(run.status != 0, "잇기가 실패했는데 성공이라 했다: \(run.output)")
        #expect(lab.names(in: lab.out).isEmpty, "반쪽 파일이 남았다: \(lab.names(in: lab.out))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 조각이 남았다: \(lab.names(in: lab.tmp))")
        #expect(run.output.contains("조각을 잇지 못했습니다"), "\(run.output)")
    }

    // 잇기가 **0 을 돌려주면서** 짧게 쓴 경우(조각 검사 뒤의 마지막 그물) — 이은 크기가 전체와 다르면 OUT 을 만들지 않는다.
    @Test func pfetch_이은_크기가_전체와_다르면_OUT_을_만들지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_CAT_SHORT": "1"])

        #expect(run.status != 0, "짧게 이은 파일을 완전하다고 했다: \(run.output)")
        #expect(lab.names(in: lab.out).isEmpty, "OUT(또는 .part)이 남았다: \(lab.names(in: lab.out))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 조각이 남았다: \(lab.names(in: lab.tmp))")
        #expect(run.output.contains("나눠 받기 폴백: 이은 크기가 다릅니다"), "\(run.output)")
    }

    // ★ 검토 지적 수리: 크기만 맞으면 성공으로 보던 구멍. Range 를 잘못 다루는 중간자(TLS 를 가로채는 프록시 · 캐시)가 조각마다
    // **첫 조각 본문을 되풀이**하면, 전체가 8의 배수일 때 조각 크기가 전부 같아 내용이 틀린 OUT 이 "완전하다"로 나갔다.
    // 조각마다 코드와 마지막 블록의 Content-Range 를 요청한 범위·전체와 맞춰 본다. 갈래마다 한 가지씩 어긋나게 한다:
    //  · samebody    — 206 + 첫 조각의 머리·본문을 되풀이(범위가 다르다)
    //  · samebody200 — 같은 되풀이를 200 으로(여러 갈래에 200 은 받지 않는다)
    //  · wrongtotal  — 본문·범위는 맞는데 전체 크기가 다르다(그사이 자산이 바뀌었다)
    //  · nocr        — 206 인데 Content-Range 가 없다
    // 어긋난 응답은 한 바이트도 잇지 않는다 — 그래서 그 바퀴에 늘어난 바이트가 없으면 거기서 폴백한다. samebody 는 첫 조각(0번)만
    // 진짜로 맞아 첫 바퀴에 그것만 늘고, 둘째 바퀴(새 서명 주소)에 나머지 일곱을 **처음부터** 다시 요청했다가 0 이라 멈춘다.
    // 나머지 셋은 첫 바퀴부터 0 이라 첫 바퀴에서 멈춘다.
    @Test func pfetch_조각_응답의_코드나_Content_Range_가_요청과_다르면_받지_않는다() throws {
        let total = 9_000_000                       // 8의 배수 — 조각 크기가 전부 같아 크기 검사로는 못 거른다
        let ranges = PrefetchLab.ranges(total: total, parts: 8)
        for (mode, rounds) in [("samebody", 2), ("samebody200", 1), ("wrongtotal", 1), ("nocr", 1)] {
            let lab = try PrefetchLab(fixtureSize: total, label: mode)
            let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_PIECE_MODE": mode])

            #expect(run.status != 0, "\(mode): 요청과 다른 조각을 받아들였다: \(run.output)")
            #expect(lab.names(in: lab.out).isEmpty, "\(mode): OUT(또는 .part)이 남았다: \(lab.names(in: lab.out))")
            #expect(lab.names(in: lab.tmp).isEmpty, "\(mode): 임시 조각이 남았다: \(lab.names(in: lab.tmp))")
            let pieces = lab.calls().filter { $0.hasPrefix("piece ") }
            var expected = ranges.map { "piece \($0) \(PrefetchLab.finalURL(1))" }
            if rounds == 2 { expected += ranges.dropFirst().map { "piece \($0) \(PrefetchLab.finalURL(2))" } }
            #expect(pieces.sorted() == expected.sorted(), "\(mode): \(pieces)")
            #expect(lab.calls().filter { $0.hasPrefix("probe ") }.count == rounds, "\(mode): \(lab.calls())")
            #expect(run.output.contains("나눠 받기 폴백: 한 바퀴 동안 받은 것이 없습니다 · "), "\(mode): \(run.output)")
            #expect(run.output.contains("초 · \(rounds)바퀴\n"), "\(mode): \(run.output)")
        }
    }

    // 한 줄(a=0, b=전체-1)이면 200 + 전체 본문도 받는다 — 요청 범위가 곧 전체라 본문이 그대로 답이다.
    @Test func pfetch_한_줄이면_200_전체_응답도_받는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_PIECE_MODE": "code200"])

        #expect(run.status == 0, "\(run.output)")
        #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData)
        #expect(lab.calls().filter { $0.hasPrefix("piece ") } == ["piece 0-299999 \(PrefetchLab.finalURL(1))"])
        #expect(run.output.contains("초 · 1바퀴 · 다시 받은 조각 0개\n"), "\(run.output)")
    }

    // latest/download 주소는 재탐색 사이에 새 릴리스로 바뀔 수 있다 — 전체 크기가 바뀌면 다른 자산의 조각을 섞지 않고 폴백한다.
    @Test func pfetch_재탐색에서_전체_크기가_바뀌면_폴백한다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let (a, _) = PrefetchLab.bounds(PrefetchLab.ranges(total: 9_000_001, parts: 8)[3])
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_STALL_ONCE": "\(a)", "FAKE_TOTAL_CHANGES": "1"])

        #expect(run.status != 0, "\(run.output)")
        #expect(run.output.contains("나눠 받기 폴백: 받는 사이 전체 크기가 바뀌었습니다 · "), "\(run.output)")
        #expect(run.output.contains("초 · 2바퀴\n"), "\(run.output)")
        #expect(lab.calls().filter { $0.hasPrefix("piece ") }.count == 8, "크기가 바뀐 뒤에도 조각을 더 받았다: \(lab.calls())")
        #expect(lab.calls().filter { $0.hasPrefix("probe ") }.count == 2)
        #expect(lab.names(in: lab.out).isEmpty)
        #expect(lab.names(in: lab.tmp).isEmpty)
    }

    // Content-Range 의 전체 크기가 숫자가 아니거나(`*` 는 RFC 의 '모름') 0 이거나 터무니없이 길면 조각을 보내지 않는다.
    // 이 검사가 없으면 산술식이 `*`·글자에서 죽어(set -u) 사유 로그도 없이 임시 폴더를 남긴다(검토 실측).
    @Test func pfetch_Content_Range_전체_크기가_이상하면_조각을_보내지_않는다() throws {
        for (label, text, reason) in [
            ("star", "*", "전체 크기를 모릅니다"),
            ("word", "abc", "전체 크기를 모릅니다"),
            ("empty", "", "전체 크기를 모릅니다"),
            ("zero", "0", "전체 크기가 이상합니다(0)"),
            ("long", "1234567890123", "전체 크기가 이상합니다(1234567890123)"),
        ] {
            let lab = try PrefetchLab(fixtureSize: 300_000, label: label)
            let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_TOTAL_TEXT": text])

            #expect(run.status != 0, "\(label): \(run.output)")
            #expect(lab.calls().filter { $0.hasPrefix("piece ") }.isEmpty, "\(label): \(lab.calls())")
            #expect(run.output.contains("나눠 받기 폴백: \(reason)"), "\(label): \(run.output)")
            #expect(lab.names(in: lab.out).isEmpty, "\(label)")
            #expect(lab.names(in: lab.tmp).isEmpty, "\(label): 임시 폴더가 남았다: \(lab.names(in: lab.tmp))")
        }
    }

    // 경계를 양쪽에서 잰다 — 8MB(8,388,608) 미만은 한 줄, 8MB 부터 8갈래. 머리 이름은 소문자(HTTP/2)로 대소문자 무시를 함께 잰다.
    @Test func pfetch_8MB_미만은_한_줄로_받고_8MB_부터_8갈래다() throws {
        for (size, parts) in [(8_388_607, 1), (8_388_608, 8)] {
            let lab = try PrefetchLab(fixtureSize: size, label: "\(size)")
            let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_CR_NAME": "content-range"])
            #expect(run.status == 0, "\(size): \(run.output)")
            #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData, "\(size) 바이트가 다르다")
            let pieces = lab.calls().filter { $0.hasPrefix("piece ") }
            #expect(Set(pieces) == Set(PrefetchLab.ranges(total: size, parts: parts).map {
                "piece \($0) \(PrefetchLab.finalURL(1))"
            }), "\(size) 바이트를 \(parts)갈래로 받지 않았다: \(pieces)")
            #expect(pieces.count == parts)
            #expect(run.output.contains("\(parts)갈래"), "\(run.output)")
            #expect(lab.names(in: lab.tmp).isEmpty)
        }
    }

    // 서명된 최종 주소(sig=…)와 원래 주소의 쿼리(token=…)가 로그 파일에 남으면 그 토큰으로 자산을 받을 수 있다.
    // 성공·폴백 두 갈래의 로그를 다 본다. 대조군: 쿼리를 뗀 주소는 로그에 **있다**(아무것도 안 적어서 초록이 되지 않게).
    @Test func pfetch_로그에_서명_쿼리가_남지_않는다() throws {
        let ok = try PrefetchLab(fixtureSize: 100_000, label: "ok")
        let good = try ok.runPfetch(url: PrefetchLab.originURL)
        #expect(good.status == 0, "\(good.output)")
        let bad = try PrefetchLab(fixtureSize: 100_000, label: "bad")
        let failed = try bad.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_DEAD": "0"])
        #expect(failed.status != 0, "\(failed.output)")
        for log in [good.output, failed.output] {
            #expect(!log.contains("SECRET"), "서명 토큰이 로그에 남았다:\n\(log)")
            #expect(!log.contains("token="), "원래 주소의 쿼리가 로그에 남았다:\n\(log)")
            #expect(!log.contains("sig="), "서명된 최종 주소가 로그에 남았다:\n\(log)")
            #expect(!log.contains("objects.example.invalid"), "서명된 최종 주소가 로그에 남았다:\n\(log)")
            #expect(log.contains("나눠 받기 시작: https://github.example.invalid/aing-check.zip\n"), "쿼리를 뗀 주소가 로그에 없다:\n\(log)")
        }
    }

    @Test func pfetch_함수와_brew_스크립트가_zsh_로_파싱된다() throws {
        for (name, text) in [("pfetch", UpdateRunner.pfetchFunction), ("brew", UpdateRunner.brewUpgradeScript)] {
            let lab = try PrefetchLab(fixtureSize: 1, label: name)
            let file = lab.root.appendingPathComponent("\(name).zsh")
            try text.write(to: file, atomically: true, encoding: .utf8)
            let run = try runProcess("/bin/zsh", ["-n", file.path], env: lab.environment)
            #expect(run.status == 0, "\(name) 를 zsh 가 파싱하지 못했다: \(run.output)")
        }
        // 두 스크립트는 같은 함수를 **이어 붙여** 품는다(값을 끼우지 않는 상수 연결).
        #expect(UpdateRunner.brewUpgradeScript.hasPrefix(UpdateRunner.pfetchFunction + "\n"))
        #expect(UpdateRunner.dmgUpdateScript.hasPrefix(UpdateRunner.pfetchFunction + "\n"))
    }

    // MARK: - B. brew 미리 받기

    @Test func brew_미리_받기가_맞으면_캐시에_지문_맞는_파일을_넣고_순서는_update_info_cache_upgrade_open() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let run = try lab.runBrew(sha: lab.fixtureSHA)

        #expect(run.status == 0, "\(run.output)")
        #expect(try Data(contentsOf: lab.brewCache) == lab.fixtureData, "캐시 파일이 픽스처와 다르다")
        #expect(lab.names(in: lab.brewCache.deletingLastPathComponent()) == [lab.brewCache.lastPathComponent],
                "캐시 폴더에 잔재가 있다: \(lab.names(in: lab.brewCache.deletingLastPathComponent()))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 파일이 남았다: \(lab.names(in: lab.tmp))")

        let seq = lab.sequence()
        #expect(seq.filter { !$0.hasPrefix("curl ") } == [
            "brew update [auto=unset]",
            "brew info --cask --json=v2 aing-check [auto=1]",
            "brew --cache --cask aing-check [auto=1]",
            "brew upgrade --cask aing-check [auto=unset]",
            "cache-at-upgrade \(lab.fixtureSHA)",          // brew 가 upgrade 하는 순간 지문 맞는 파일이 이미 그 자리에 있다
            "open -a \(lab.appPath)",
        ], "호출 차례가 다르다: \(seq)")
        // 내려받기는 --cache 와 upgrade **사이**에서만 일어난다.
        let cacheAt = try #require(seq.firstIndex { $0.hasPrefix("brew --cache") })
        let upgradeAt = try #require(seq.firstIndex { $0.hasPrefix("brew upgrade") })
        let curlAt = seq.indices.filter { seq[$0].hasPrefix("curl ") }
        #expect(curlAt.count == 9)
        #expect(curlAt.allSatisfy { $0 > cacheAt && $0 < upgradeAt })
        #expect(run.output.contains("미리 받기: "), "\(run.output)")
        #expect(run.output.contains("· 성공(0.3.62)"), "\(run.output)")
    }

    @Test func brew_지문이_틀리면_캐시에_넣지_않고_upgrade_는_그대로() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let other = String(repeating: "ab", count: 32)          // 모양은 맞는(64자리 소문자 16진) 다른 지문
        let run = try lab.runBrew(sha: other)

        #expect(run.status == 0, "\(run.output)")
        #expect(!FileManager.default.fileExists(atPath: lab.brewCache.path), "지문이 틀린 파일을 brew 캐시에 넣었다")
        #expect(lab.names(in: lab.brewCache.deletingLastPathComponent()).isEmpty, "받다 만 파일이 캐시 폴더에 남았다")
        #expect(lab.calls().filter { $0.hasPrefix("probe ") }.count == 1, "받기를 시도하지 않아 지문 검사가 헛돈다")
        let seq = lab.sequence().filter { !$0.hasPrefix("curl ") }
        #expect(seq.suffix(3) == ["brew upgrade --cask aing-check [auto=unset]", "cache-at-upgrade none", "open -a \(lab.appPath)"])
        #expect(run.output.contains("실패(지문 불일치"), "\(run.output)")
    }

    // cask 가 준 지문·주소의 **모양**이 틀리면 받지도 않는다(받아도 넣을 수 없거나, https 가 아닌 곳에서 받게 된다).
    @Test func brew_지문이나_주소_모양이_틀리면_받지_않고_upgrade_는_그대로() throws {
        let sha = try PrefetchLab(fixtureSize: 300_000, label: "sha").fixtureSHA
        for (label, badSHA, url, reason) in [
            ("upper", sha.uppercased(), PrefetchLab.caskURL, "지문이 소문자 16진이 아님"),
            ("short", String(sha.dropLast()), PrefetchLab.caskURL, "지문이 64자리가 아님"),
            ("http", sha, "http://github.example.invalid/aing-check-0.3.62.zip", "주소가 https 가 아님"),
        ] {
            let lab = try PrefetchLab(fixtureSize: 300_000, label: label)
            let run = try lab.runBrew(sha: badSHA, url: url)
            #expect(run.status == 0, "\(label): \(run.output)")
            #expect(lab.calls().isEmpty, "\(label): 모양이 틀린데 받았다: \(lab.calls())")
            #expect(!FileManager.default.fileExists(atPath: lab.brewCache.path), "\(label)")
            #expect(lab.sequence().suffix(3) == ["brew upgrade --cask aing-check [auto=unset]", "cache-at-upgrade none",
                                                 "open -a \(lab.appPath)"], "\(label): \(lab.sequence())")
            #expect(run.output.contains("건너뜀(\(reason))"), "\(label): \(run.output)")
        }
    }

    @Test func brew_이미_최신이면_내려받지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runBrew(sha: lab.fixtureSHA, installed: "0.3.62")

        #expect(run.status == 0, "\(run.output)")
        #expect(lab.calls().isEmpty, "올릴 것이 없는데 내려받았다: \(lab.calls())")
        #expect(!FileManager.default.fileExists(atPath: lab.brewCache.path))
        #expect(lab.sequence().filter { $0.hasPrefix("brew upgrade") || $0.hasPrefix("open ") }.count == 2,
                "upgrade · open 은 그대로 가야 한다: \(lab.sequence())")
        #expect(run.output.contains("건너뜀(이미 0.3.62"), "\(run.output)")
    }

    @Test func brew_캐시에_이미_있으면_내려받지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        try FileManager.default.createDirectory(at: lab.brewCache.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = Data("brew 가 이미 받아 둔 파일".utf8)
        try existing.write(to: lab.brewCache)
        let run = try lab.runBrew(sha: lab.fixtureSHA)

        #expect(run.status == 0, "\(run.output)")
        #expect(lab.calls().isEmpty, "캐시에 있는데 내려받았다: \(lab.calls())")
        #expect(try Data(contentsOf: lab.brewCache) == existing, "brew 가 쓸 캐시 파일을 덮어썼다")
        #expect(lab.sequence().contains("brew upgrade --cask aing-check [auto=unset]"))
        #expect(run.output.contains("캐시에 이미 있음"), "\(run.output)")
    }

    @Test func brew_나눠_받기가_실패해도_upgrade_는_그대로() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runBrew(sha: lab.fixtureSHA, env: ["FAKE_NORANGE": "1"])

        #expect(run.status == 0, "\(run.output)")
        #expect(!FileManager.default.fileExists(atPath: lab.brewCache.path))
        #expect(lab.names(in: lab.brewCache.deletingLastPathComponent()).isEmpty, "받다 만 파일이 캐시 폴더에 남았다")
        let seq = lab.sequence().filter { !$0.hasPrefix("curl ") }
        #expect(seq.suffix(3) == ["brew upgrade --cask aing-check [auto=unset]", "cache-at-upgrade none", "open -a \(lab.appPath)"],
                "미리 받기 실패가 upgrade 를 막았다: \(seq)")
        #expect(run.output.contains("실패(나눠 받기"), "\(run.output)")
    }

    // 지금 의미(`brew update && brew upgrade …`) 그대로 — 탭을 못 갱신했으면 낡은 탭으로 upgrade 하지 않는다.
    @Test func brew_update_가_실패하면_멈춘다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runBrew(sha: lab.fixtureSHA, env: ["FAKE_BREW_UPDATE_RC": "3"])

        #expect(run.status == 3, "update 의 종료코드를 그대로 돌려줘야 한다: \(run.status)")
        #expect(lab.sequence() == ["brew update [auto=unset]"], "update 가 실패했는데 더 갔다: \(lab.sequence())")
        #expect(lab.calls().isEmpty)
    }

    // `upgrade && open` — 업그레이드가 실패하면 앱을 다시 열지 않는다(지금 의미).
    @Test func brew_upgrade_가_실패하면_앱을_열지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runBrew(sha: lab.fixtureSHA, installed: "0.3.62", env: ["FAKE_BREW_UPGRADE_RC": "1"])
        #expect(run.status == 1)
        #expect(lab.sequence().contains("brew upgrade --cask aing-check [auto=unset]"))
        #expect(!lab.sequence().contains { $0.hasPrefix("open ") }, "업그레이드가 실패했는데 앱을 열었다")
    }

    // ★ 불변식 2(검증 없이 brew 캐시에 넣지 않는다)를 **과정**에서 잰다 — 끝 상태만 보면 "캐시 이름으로 받고 그 자리에서 재다가
    // 틀리면 지우는" 코드도 초록이다(검토 T06a). 그 순간 스크립트가 죽으면 brew 는 지문이 틀린 캐시를 다시 받지 않고 실패한다.
    // 가짜 shasum 이 대상 경로와 그 순간 CACHE 가 있는지를 적는다: 대상은 캐시와 **같은 폴더**(mv 가 원자적이게)의
    // **숨김 고유 이름**(`.aing-check-part.XXXXXX` — brew 의 `<url sha>--*` glob 에 안 걸리게)이고, 그때 CACHE 는 없다.
    @Test func brew_지문_검사는_캐시_이름_밖의_숨김_고유_이름에서_한다() throws {
        for (label, mismatch) in [("ok", false), ("bad", true)] {
            let lab = try PrefetchLab(fixtureSize: 300_000, label: label)
            let run = try lab.runBrew(sha: mismatch ? String(repeating: "ab", count: 32) : lab.fixtureSHA)
            #expect(run.status == 0, "\(label): \(run.output)")

            let checks = lab.lines("shasum")
            #expect(checks.count == 1, "\(label): 지문 검사가 정확히 한 번이 아니다: \(checks)")
            let check = try #require(checks.first)
            let target = URL(fileURLWithPath: String(try #require(check.components(separatedBy: " cache=").first)))
            #expect(check.hasSuffix(" cache=absent"), "\(label): 지문을 재는 동안 캐시 이름에 파일이 보였다: \(check)")
            #expect(target.deletingLastPathComponent().path == lab.brewCache.deletingLastPathComponent().path,
                    "\(label): 캐시와 다른 폴더에서 쟀다(mv 가 원자적이지 않다): \(check)")
            #expect(target.lastPathComponent.hasPrefix(".aing-check-part."), "\(label): 숨김 고유 이름이 아니다: \(check)")
            #expect(target.lastPathComponent != ".aing-check-part.XXXXXX", "\(label): 이름이 고유하지 않다: \(check)")
            if mismatch {
                #expect(lab.names(in: lab.brewCache.deletingLastPathComponent()).isEmpty, "\(label): 잔재가 남았다")
            } else {
                #expect(try Data(contentsOf: lab.brewCache) == lab.fixtureData)
                #expect(lab.names(in: lab.brewCache.deletingLastPathComponent()) == [lab.brewCache.lastPathComponent])
            }
        }
    }

    // ★ 검토 지적 수리(고정 이름의 경합): 감시 600초 뒤 다시 눌러 두 벌이 겹친 상황. A 는 맞는 바이트, B 는 크기만 맞고 내용이 틀린
    // 바이트를 받는다. 가짜 shasum 이 차례를 못박는다 — A 는 자기 파일을 잰 뒤 B 가 잴 때까지 기다리고, B 는 잰 뒤 A 가 upgrade 할 때까지
    // 기다린다. 받는 이름이 고정(`<CACHE>.aing-check-part`)이면 그사이 B 가 같은 이름에 자기 바이트를 써 넣고, A 는 **자기가 검증한
    // 경로**를 mv 해 B 의 바이트를 캐시에 넣는다(검토 실측 그대로). 이름이 실행마다 고유하면 캐시에는 A 의 맞는 바이트만 들어간다.
    @Test func brew_두_벌이_겹쳐도_검증_안_된_바이트는_캐시에_들어가지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        try lab.writeBrewFixture(sha: lab.fixtureSHA, installed: "0.3.61")
        let bad = lab.root.appendingPathComponent("fixture-bad.bin")
        try PrefetchLab.bytes(300_000, seed: 0xBAD5EED).write(to: bad)
        let script = ["-c", UpdateRunner.brewUpgradeScript, "aing-check-update",
                      lab.bin.appendingPathComponent("brew").path, UpdateRunner.caskName, lab.appPath]

        let a = try ChildProcess("/bin/zsh", script, env: lab.environment.merging(["FAKE_ROLE": "A"]) { $1 })
        let hashedA = lab.state.appendingPathComponent("hashed-A")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !FileManager.default.fileExists(atPath: hashedA.path) { Thread.sleep(forTimeInterval: 0.02) }
        #expect(FileManager.default.fileExists(atPath: hashedA.path), "A 가 지문 검사에 닿지 못했다")
        let runB = try runProcess("/bin/zsh", script,
                                  env: lab.environment.merging(["FAKE_ROLE": "B", "FAKE_FIXTURE": bad.path]) { $1 })
        let runA = a.finish()

        #expect(runA.status == 0, "\(runA.output)")
        #expect(runB.status == 0, "\(runB.output)")
        #expect(runA.output.contains("· 성공(0.3.62)"), "A: \(runA.output)")
        #expect(runB.output.contains("실패(지문 불일치"), "B: \(runB.output)")
        #expect(lab.lines("shasum").count == 2, "두 벌이 각각 한 번씩 재야 한다: \(lab.lines("shasum"))")
        #expect(try Data(contentsOf: lab.brewCache) == lab.fixtureData, "검증 안 된 바이트가 brew 캐시에 들어갔다")
        #expect(!lab.sequence().contains { $0.hasPrefix("cache-at-upgrade ") && $0 != "cache-at-upgrade \(lab.fixtureSHA)" },
                "brew 가 upgrade 하는 순간 지문이 틀린 캐시를 봤다: \(lab.sequence())")
        #expect(lab.names(in: lab.brewCache.deletingLastPathComponent()) == [lab.brewCache.lastPathComponent],
                "캐시 폴더에 잔재가 남았다: \(lab.names(in: lab.brewCache.deletingLastPathComponent()))")
    }

    // ★ 검토 지적 수리(잔재): 잇는 도중 죽으면(종료·로그아웃) 받던 파일이 캐시 폴더에 남는다. 그 이름이 `<url sha>--` 로 시작하면
    // brew 의 캐시 찾기(`downloads/<url sha>--*` 에서 `.incomplete` 만 뺀다)가 그것을 캐시 본체로 집는다(검토 실측). 숨김 이름이어야 한다.
    // 가짜 cat 이 잇는 도중 미리 받기 서브셸을 SIGKILL 로 죽인다 — 스크립트 본체는 살아 upgrade 로 간다(지금 동작).
    @Test func brew_잇다가_죽어도_brew_가_집을_이름의_잔재를_남기지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runBrew(sha: lab.fixtureSHA, env: ["FAKE_CAT_KILL": "1"])

        #expect(run.status == 0, "\(run.output)")
        let dir = lab.brewCache.deletingLastPathComponent()
        let left = lab.names(in: dir)
        #expect(!left.isEmpty, "죽인 흔적이 없다 — 시나리오가 헛돈다: \(run.output)")
        let brewGlob = String(lab.brewCache.lastPathComponent.prefix { $0 != "-" }) + "--"
        #expect(left.allSatisfy { !$0.hasPrefix(brewGlob) }, "brew 가 캐시 본체로 집을 이름의 잔재가 남았다: \(left)")
        #expect(left.allSatisfy { $0.hasPrefix(".aing-check-part.") }, "\(left)")
        #expect(lab.sequence().suffix(3) == ["brew upgrade --cask aing-check [auto=unset]", "cache-at-upgrade none", "open -a \(lab.appPath)"],
                "\(lab.sequence())")
    }

    // 고유 이름이라 죽은 실행의 숨김 조각은 다음 실행이 치운다 — **60분 넘은 것만**(미리 받기의 최악은 120초라 그건 반드시 죽은 것).
    // 막 생긴 것(겹친 다른 실행의 것일 수 있다)과 brew 자신의 파일은 건드리지 않는다.
    @Test func brew_죽은_실행의_숨김_조각은_60분_넘은_것만_지운다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let dir = lab.brewCache.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = Date().addingTimeInterval(-2 * 3600)
        for (name, date) in [(".aing-check-part.OLD111", old), (".aing-check-part.OLD111.part", old),
                             (".aing-check-part.NEW222", Date()), ("deadbeef--other-1.0.zip", old)] {
            let url = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let run = try lab.runBrew(sha: lab.fixtureSHA)

        #expect(run.status == 0, "\(run.output)")
        #expect(try Data(contentsOf: lab.brewCache) == lab.fixtureData)
        #expect(lab.names(in: dir) == [".aing-check-part.NEW222", lab.brewCache.lastPathComponent, "deadbeef--other-1.0.zip"].sorted(),
                "\(lab.names(in: dir))")
    }

    // `brew --cache` 출력이 여러 줄이면(경고가 섞이는 등) 그 값을 경로로 쓰지 않는다. 첫 줄은 절대경로라 절대경로 방어에 먼저 걸리지 않는다.
    @Test func brew_cache_출력이_여러_줄이면_받지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runBrew(sha: lab.fixtureSHA, env: ["FAKE_BREW_CACHE_OUT": "\(lab.brewCache.path)\n/second/line"])

        #expect(run.status == 0, "\(run.output)")
        #expect(lab.calls().isEmpty, "여러 줄 캐시 자리로 받았다: \(lab.calls())")
        #expect(run.output.contains("건너뜀(캐시 자리가 여러 줄)"), "\(run.output)")
        #expect(lab.sequence().suffix(3) == ["brew upgrade --cask aing-check [auto=unset]", "cache-at-upgrade none", "open -a \(lab.appPath)"],
                "\(lab.sequence())")
    }

    // 빈 값이나 상대경로면 작업 폴더에 폴더를 만들고 받게 된다 — 받지 않는다. 작업 폴더를 실험실로 둔다(방어가 빠져도 저장소에 안 생기게).
    @Test func brew_cache_출력이_절대경로가_아니면_받지_않는다() throws {
        for (label, value) in [("empty", ""), ("relative", "relative/x.zip")] {
            let lab = try PrefetchLab(fixtureSize: 300_000, label: label)
            let run = try lab.runBrew(sha: lab.fixtureSHA, env: ["FAKE_BREW_CACHE_OUT": value], cwd: lab.root)

            #expect(run.status == 0, "\(label): \(run.output)")
            #expect(lab.calls().isEmpty, "\(label): 절대경로가 아닌 캐시 자리로 받았다: \(lab.calls())")
            #expect(run.output.contains("건너뜀(캐시 자리를 모름)"), "\(label): \(run.output)")
            #expect(!FileManager.default.fileExists(atPath: lab.root.appendingPathComponent("relative").path), "\(label)")
            #expect(lab.sequence().suffix(3) == ["brew upgrade --cask aing-check [auto=unset]", "cache-at-upgrade none",
                                                 "open -a \(lab.appPath)"], "\(label): \(lab.sequence())")
        }
    }

    // 래퍼는 값을 끼우지 않는다(`dmgSpawnWrapperInterpolatesNothing` 과 같은 모양).
    @Test func brew_래퍼는_아무_값도_끼우지_않는다() {
        let wrapper = UpdateRunner.brewSpawnWrapper
        #expect(wrapper == #"nohup zsh -c "$1" aing-check-update "$2" "$3" "$4" >>"$5" 2>&1 &"#)
        for literal in ["/Applications", "https://", "/opt/homebrew", "/usr/local", "aing-check.app", "Library", "brew", "'"] {
            #expect(!wrapper.contains(literal), "래퍼에 값이 글자로 들어 있다: \(literal)")
        }
    }

    // 래퍼 + 인자를 **실제로** 던져 본다: `$1`…`$5` 가 한 자리씩 맞아야 brew 가 cask 이름을, open 이 앱 경로를 받는다.
    // `detachedSpawn` 이 zsh 에 넘기는 인자 배열(`brewSpawnCommandArguments`)을 **그대로** 쓴다 — 시험이 `["-c", 래퍼] + 인자` 를
    // 스스로 다시 만들면 소스에서 argv0 를 빠뜨려도 초록이다(검토 T12b). 앱 경로·로그 자리만 실험실로 바꾼다
    // (실제 로그·실제 앱을 건드리지 않게) — 나머지는 프로덕션 인자 그대로다.
    @Test func brew_래퍼와_인자를_실제로_던지면_자리가_맞는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        try lab.writeBrewFixture(sha: lab.fixtureSHA, installed: "0.3.61")
        let brew = lab.bin.appendingPathComponent("brew").path
        var argv = UpdateRunner.brewSpawnCommandArguments(brew: brew)
        try #require(argv.count == 8, "zsh 에 넘길 인자 수가 다르다(래퍼 $1…$5 가 밀린다): \(argv.count)")
        #expect(argv[0] == "-c")
        #expect(argv[1] == UpdateRunner.brewSpawnWrapper)
        #expect(argv[3] == UpdateRunner.brewUpgradeScript)       // 래퍼의 $1
        #expect(argv[6] == UpdateRunner.appPath)                 // 래퍼의 $4
        #expect(argv[7] == UpdateRunner.logPath)                 // 래퍼의 $5
        let log = lab.root.appendingPathComponent("update.log")
        argv[6] = lab.appPath
        argv[7] = log.path
        let run = try runProcess("/bin/zsh", argv, env: lab.environment)
        #expect(run.status == 0, "\(run.output)")

        // nohup 으로 떨어져 나간 셸이 끝날 때까지(가짜 open 이 마지막 줄을 적을 때까지) 기다린다.
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !lab.sequence().contains(where: { $0.hasPrefix("open ") }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(lab.sequence().filter { !$0.hasPrefix("curl ") } == [
            "brew update [auto=unset]",
            "brew info --cask --json=v2 aing-check [auto=1]",
            "brew --cache --cask aing-check [auto=1]",
            "brew upgrade --cask aing-check [auto=unset]",
            "cache-at-upgrade \(lab.fixtureSHA)",
            "open -a \(lab.appPath)",
        ], "래퍼 자리가 어긋났다: \(lab.sequence())")
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(text.contains("[aing-check-update] ---- brew 업데이트 시작"), "로그가 $5 자리로 가지 않았다:\n\(text)")
        #expect(text.contains("미리 받기: "), "\(text)")
    }

    // MARK: - C. DMG 받기 단계 (그 뒤의 검증 단계는 CheckUpdateCheckTests 가 글자로 잰다)

    @Test func dmg_받기는_나눠_받기가_되면_단일_curl_을_부르지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runDMGDownloadStage()

        #expect(run.status == 0, "\(run.output)")
        #expect(try Data(contentsOf: lab.dmgCapture) == lab.fixtureData)
        #expect(lab.calls().filter { $0.hasPrefix("whole ") }.isEmpty, "나눠 받기가 됐는데 단일 curl 로 또 받았다")
        #expect(lab.calls().filter { $0.hasPrefix("piece ") }.count == 1)
        #expect(lab.stateLines() == ["stage=start", "stage=download"], "\(lab.stateLines())")
        #expect(lab.names(in: lab.tmp).isEmpty, "자물쇠·임시 폴더가 남았다: \(lab.names(in: lab.tmp))")
        #expect(run.output.contains("받음: 300000 bytes"), "\(run.output)")
        lab.expectNoSignature(run.output)
    }

    @Test func dmg_나눠_받기가_안_되면_기존_단일_curl_그대로_받는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runDMGDownloadStage(env: ["FAKE_NORANGE": "1"])

        #expect(run.status == 0, "\(run.output)")
        #expect(try Data(contentsOf: lab.dmgCapture) == lab.fixtureData)
        #expect(lab.calls().filter { $0.hasPrefix("whole ") } == ["whole \(PrefetchLab.originURL)"])
        // 기존 명령 **그대로** — 한 글자도 바뀌지 않았다(옵션·순서·대상).
        let whole = try #require(lab.curlArgv().first { $0.hasPrefix("argv -fL ") })
        #expect(whole.hasPrefix("argv -fL --proto =https --tlsv1.2 --connect-timeout 20 --max-time 420 -o \(lab.tmp.path)/aing-check-update."))
        #expect(whole.hasSuffix("/a.dmg \(PrefetchLab.originURL)"))
        #expect(lab.stateLines() == ["stage=start", "stage=download"], "\(lab.stateLines())")
        #expect(lab.names(in: lab.tmp).isEmpty)
    }

    // ★ 검토 지적 수리(불변식 1): 나눠 받기가 크기만 맞고 내용이 틀린 파일을 "완전하다"고 돌려주면, DMG 경로에는 지문이 없어서
    // 기존 단일 curl 로 떨어지지 못하고 검증(image)에서 업데이트가 실패로 끝났다(검토 실측: whole-curl-calls 0). 조각 응답을
    // 요청 범위와 맞춰 보게 고친 뒤에는 나눠 받기가 0 아님을 돌려주고 **기존 단일 curl 그대로** 받는다.
    @Test func dmg_나눠_받은_조각이_요청과_다르면_기존_단일_curl_로_받는다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_000)        // 8의 배수 — 되풀이한 조각도 크기는 전부 맞다
        let run = try lab.runDMGDownloadStage(env: ["FAKE_PIECE_MODE": "samebody"])

        #expect(run.status == 0, "\(run.output)")
        #expect(lab.calls().filter { $0.hasPrefix("whole ") } == ["whole \(PrefetchLab.originURL)"],
                "내용이 틀린 나눠 받기를 믿고 단일 curl 로 떨어지지 않았다: \(lab.calls())")
        #expect(try Data(contentsOf: lab.dmgCapture) == lab.fixtureData, "검증 단계로 넘어간 파일이 원본과 다르다")
        #expect(run.output.contains("나눠 받기 폴백: "), "\(run.output)")
        #expect(lab.stateLines() == ["stage=start", "stage=download"], "\(lab.stateLines())")
        #expect(lab.names(in: lab.tmp).isEmpty)
    }

    // DMG 래퍼 + 인자를 **실제로** 던져 본다(brew 와 같은 까닭 — `detachedSpawnDMG` 는 시험에서 불리지 않는다).
    // `dmgSpawnCommandArguments` 의 결과를 그대로 쓰고, 스크립트 자리(래퍼의 $1)만 인자를 적기만 하는 탐침으로, 로그 자리($8)만
    // 실험실로 바꾼다 — 실제 DMG 스크립트는 돌지 않는다. 번들 경로는 일부러 악의적인 글자로 — 한 토막 그대로 와야 한다.
    @MainActor
    @Test func dmg_래퍼와_인자를_실제로_던지면_자리가_맞는다() throws {
        let lab = try PrefetchLab(fixtureSize: 1)
        let nasty = lab.root.appendingPathComponent("It's \"My\" Apps; rm -rf ~/x $(whoami)/aing-check.app").path
        let runner = UpdateRunner(
            fileExists: { _ in false },
            directoryContents: { _ in [] },
            resolvePath: { $0 },
            isWritable: { _ in true },
            bundlePath: nasty,
            processID: 4242,
            currentBuild: 100,
            readState: { _ in nil },
            clearState: { _ in },
            spawn: { _ in Issue.record("스폰하지 않는다"); return false },
            spawnDMG: { _ in Issue.record("스폰하지 않는다"); return false },
            watchdogSleep: { _ in }
        )
        let plan = try #require(runner.dmgUpdatePlan())
        var argv = UpdateRunner.dmgSpawnCommandArguments(plan)
        try #require(argv.count == 11, "zsh 에 넘길 인자 수가 다르다(래퍼 $1…$8 이 밀린다): \(argv.count)")
        #expect(argv[0] == "-c")
        #expect(argv[1] == UpdateRunner.dmgSpawnWrapper)
        #expect(argv[3] == UpdateRunner.dmgUpdateScript)         // 래퍼의 $1
        #expect(argv[10] == UpdateRunner.logPath)                // 래퍼의 $8
        let log = lab.root.appendingPathComponent("dmg-wrapper.log")
        argv[3] = #"print -r -- "0=<$0>"; i=1; for a in "$@"; do print -r -- "$i=<$a>"; i=$(( i + 1 )); done; print -r -- "argc=$#""#
        argv[10] = log.path
        let run = try runProcess("/bin/zsh", argv, env: lab.environment)
        #expect(run.status == 0, "\(run.output)")

        // nohup 으로 떨어져 나간 셸이 끝날 때까지(마지막 줄을 적을 때까지) 기다린다.
        func lines() -> [String] {
            ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !lines().contains(where: { $0.hasPrefix("argc=") }) { Thread.sleep(forTimeInterval: 0.05) }
        #expect(lines() == [
            "0=<aing-check-update>",
            "1=<\(nasty)>",                                // 번들 경로 — 손대지 않은 그대로
            "2=<\(UpdateRunner.dmgURL)>",
            "3=<4242>",
            "4=<\(UpdateRunner.codeRequirement)>",
            "5=<100>",
            "6=<\(UpdateRunner.statePath)>",
            "argc=6",
        ], "래퍼 자리가 어긋났다: \(lines())")
    }

    @Test func dmg_둘_다_안_되면_download_실패를_상태_파일에_적는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runDMGDownloadStage(env: ["FAKE_NORANGE": "1", "FAKE_WHOLE_RC": "6"])

        #expect(run.status == 1, "\(run.output)")
        #expect(!FileManager.default.fileExists(atPath: lab.dmgCapture.path))
        // `$?` 는 기존 단일 curl 의 종료코드다(배너 문구는 단계 이름으로 고른다).
        #expect(lab.stateLines() == ["stage=start", "stage=download", "error=download code=6"], "\(lab.stateLines())")
        #expect(UpdateProgress.parse(try String(contentsOf: lab.statePath, encoding: .utf8)).failedStep == "download")
        #expect(lab.names(in: lab.tmp).isEmpty, "실패 뒤 정리(trap)가 돌지 않았다: \(lab.names(in: lab.tmp))")
    }

    // MARK: - E. 버전

    // v0.3.62: 버전 고정(0.3.61 / 114)과 "맨 위 섹션" 단언은 다음 버전이 올라가며 거짓이 됐다 — 그 두 사실은 이제
    // `V0363StickerArtTests.swift` 의 `v0363VersionAndChangelog` 가 그 둘을 든다(릴리스마다 넘겨받는 관행).
    // 여기는 0.3.61 섹션의 **내용**과, 이 파일이 재는 나눠 받기가 실린 하한(114)만 남긴다.
    @Test("CHANGELOG 0.3.61 은 세 줄 이하(사용자 말투) · 빌드는 114 이상")
    func versionAndChangelog() throws {
        let root = CheckCoreSourceLayout.repoRoot
        let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
        let afterKey = squashed.components(separatedBy: "<key>CFBundleVersion</key><string>").dropFirst().first ?? ""
        let buildNumber = Int(afterKey.prefix { $0.isNumber })
        #expect((buildNumber ?? 0) >= 114, "빌드 번호가 나눠 받기가 실린 하한(114) 아래다: \(String(describing: buildNumber))")
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.61\n") })
        let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        #expect((1...3).contains(items.count), "항목 \(items)")
        #expect(items.contains { $0.contains("업데이트") })
        #expect(items.allSatisfy { $0.count <= 40 }, "배너 폭에서 잘릴 만큼 긴 줄이 있다: \(items)")
        for banned in ["brew", "curl", "Range", "8갈래", "pfetch", "GitHub", "MB", "초"] {
            #expect(!section.contains(banned), "사용자 문구에 내부 구조·숫자('\(banned)')가 있다")
        }
        #expect(changelog.range(of: "## 0.3.61")!.lowerBound < changelog.range(of: "## 0.3.60")!.lowerBound,
                "0.3.61 섹션이 0.3.60 보다 아래에 있다")
    }
}

// MARK: - 실험실

/// 한 시나리오의 작업 폴더 — 가짜 도구(bin) · 픽스처 · TMPDIR · 기록. 폴더는 테스트 신원으로 이름을 정해 재실행이 덮어쓴다
/// (`CheckTestScratch.directory` — UUID 폴더를 쌓지 않는다).
private struct PrefetchLab {
    static let originURL = "https://github.example.invalid/aing-check.zip?token=SECRET-ORIGIN"
    static let caskURL = "https://github.example.invalid/aing-check-0.3.62.zip"
    static func finalURL(_ n: Int) -> String { "https://objects.example.invalid/asset.bin?sig=SECRET-\(n)" }

    /// 설계서의 조각 범위(크기 ceil(전체/N), 마지막 조각은 남은 만큼) — `a-b` 문자열.
    static func ranges(total: Int, parts: Int) -> [String] {
        let size = (total + parts - 1) / parts
        return (0..<parts).map { i in "\(i * size)-\(min((i + 1) * size, total) - 1)" }
    }

    /// `a-b` → (a, b).
    static func bounds(_ range: String) -> (Int, Int) {
        let parts = range.split(separator: "-").map { Int($0)! }
        return (parts[0], parts[1])
    }

    /// 가짜 curl 이 받은 인자 한 줄의 `--max-time` 값(없거나 숫자가 아니면 -1).
    static func maxTime(_ argvLine: String) -> Int {
        guard let r = argvLine.range(of: "--max-time ") else { return -1 }
        return Int(argvLine[r.upperBound...].prefix { $0 != " " }) ?? -1
    }

    /// 개수가 같고 값마다 [기대-1, 기대] 안인가(가짜 시계 시험 — 실제 시간 1초 미끄러짐만 허용).
    static func within1(_ observed: [Int], of expected: [Int]) -> Bool {
        observed.count == expected.count && zip(observed, expected).allSatisfy { $0 <= $1 && $0 >= $1 - 1 }
    }

    let root: URL
    let fixtureData: Data

    var bin: URL { root.appendingPathComponent("bin", isDirectory: true) }
    var tmp: URL { root.appendingPathComponent("tmp", isDirectory: true) }
    var state: URL { root.appendingPathComponent("state", isDirectory: true) }
    var out: URL { root.appendingPathComponent("out", isDirectory: true) }
    var outFile: URL { out.appendingPathComponent("a.bin") }
    var fixture: URL { root.appendingPathComponent("fixture.bin") }
    var brewJSON: URL { root.appendingPathComponent("info.json") }
    /// brew 캐시 자리 — 부모 폴더가 **없는** 채로 시작한다(스크립트가 만들어야 한다).
    var brewCache: URL { root.appendingPathComponent("cache/downloads/0123abcd--aing-check-0.3.62.zip") }
    /// `open -a` 대상 — 실험실 안의 없는 경로다(가짜 open 이 어긋나도 실제 앱이 뜨지 않는다).
    var appPath: String { root.appendingPathComponent("NoSuch/aing-check.app").path }
    var dmgCapture: URL { root.appendingPathComponent("captured.dmg") }
    var statePath: URL { state.appendingPathComponent("update.state") }
    /// 픽스처의 sha256(소문자 16진 64자리) — 시스템 `shasum` 으로 잰다(스크립트가 쓰는 것과 같은 도구).
    let fixtureSHA: String

    init(fixtureSize: Int, label: String = "", function: String = #function) throws {
        root = CheckTestScratch.directory(label, function: function)
        let fm = FileManager.default
        for dir in [root.appendingPathComponent("bin"), root.appendingPathComponent("tmp"),
                    root.appendingPathComponent("state"), root.appendingPathComponent("out")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        fixtureData = Self.bytes(fixtureSize, seed: UInt64(fixtureSize) &* 0x9E37_79B9_7F4A_7C15)
        try fixtureData.write(to: root.appendingPathComponent("fixture.bin"))
        fixtureSHA = sha256Hex(of: root.appendingPathComponent("fixture.bin"))
        for (name, text) in [("curl", fakeCurl), ("brew", fakeBrew), ("open", fakeOpen), ("cat", fakeCat), ("shasum", fakeShasum)] {
            let url = root.appendingPathComponent("bin/\(name)")
            try text.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    /// 결정적 의사난수 바이트(xorshift) — 조각 순서가 뒤섞이면 반드시 달라진다.
    static func bytes(_ n: Int, seed: UInt64) -> Data {
        var x = seed | 1
        var data = Data(count: n)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for i in 0..<n {
                x ^= x << 13; x ^= x >> 7; x ^= x << 17
                p[i] = UInt8(truncatingIfNeeded: x >> 29)
            }
        }
        return data
    }

    var environment: [String: String] {
        [
            "PATH": "\(bin.path):/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": tmp.path,
            "HOME": root.path,                       // 사용자 홈(~/Library/Caches/Homebrew 포함)을 건드리지 않는다
            "FAKE_STATE": state.path,
            "FAKE_FIXTURE": fixture.path,
            "FAKE_BREW_JSON": brewJSON.path,
            "FAKE_BREW_CACHE": brewCache.path,
        ]
    }

    /// `pfetch URL OUT` 를 **호출자와 같은 조건**(`set -u` · `$M`)으로 직접 부른다 — 서브셸로 감싸지 않아
    /// 함수 안의 `set -u` 위반도 빨갛게 드러난다.
    ///
    /// `clockJump` — **가짜 시계**. 시한(120초)을 실제로 기다리지 않으려고, 바퀴의 `wait` 를 감싸 바퀴가 끝날 때마다 zsh 의
    /// `SECONDS` 를 그만큼 앞으로 민다(대입하면 그 값부터 다시 센다 — 바퀴 안의 실제 몇십 ms 는 버려진다). 함수 본문은 그대로다:
    /// 운영 코드에 환경변수 훅을 넣지 않고, 함수를 다른 시한으로 다시 정의하지도 않는다. 시계를 0 에서 시작해 숫자가 결정적이다.
    func runPfetch(url: String, env: [String: String] = [:], clockJump: Int? = nil) throws -> ProcessRun {
        let clock = clockJump.map {
            "FAKE_NOW=0\nwait() { builtin wait \"$@\"; FAKE_NOW=$(( FAKE_NOW + \($0) )); SECONDS=$FAKE_NOW; }\nSECONDS=0\n"
        } ?? ""
        let script = "set -u\nM=\"[aing-check-update]\"\n" + UpdateRunner.pfetchFunction + "\n" + clock + "pfetch \"$1\" \"$2\"\n"
        return try runProcess("/bin/zsh", ["-c", script, "aing-check-update", url, outFile.path],
                              env: environment.merging(env) { $1 })
    }

    /// `brew info --cask --json=v2` 모양의 JSON(null 칸이 섞인 — 실제 출력처럼).
    func writeBrewFixture(sha: String, installed: String, url: String = PrefetchLab.caskURL) throws {
        let json = """
            {"formulae":[],"casks":[{"token":"aing-check","full_token":"yehsung/check/aing-check","desc":null,\
            "url":"\(url)","version":"0.3.62","installed":"\(installed)",\
            "sha256":"\(sha)","caveats":null,"conflicts_with":null,"auto_updates":null,"depends_on":{},"artifacts":[]}]}
            """
        try json.write(to: brewJSON, atomically: true, encoding: .utf8)
    }

    /// brew 스크립트를 프로덕션 모양 그대로(`zsh -c <스크립트> argv0 brew cask 앱`) 돌린다.
    func runBrew(sha: String, installed: String = "0.3.61", url: String = PrefetchLab.caskURL,
                 env: [String: String] = [:], cwd: URL? = nil) throws -> ProcessRun {
        try writeBrewFixture(sha: sha, installed: installed, url: url)
        return try runProcess("/bin/zsh", ["-c", UpdateRunner.brewUpgradeScript, "aing-check-update",
                                           bin.appendingPathComponent("brew").path, UpdateRunner.caskName, appPath],
                              env: environment.merging(env) { $1 }, cwd: cwd)
    }

    /// DMG 스크립트의 **앞부분만**(시작 ~ "받음" 로그 줄) 돌리고 받은 파일을 `$7` 로 복사한다. 그 뒤 단계(hdiutil · spctl ·
    /// codesign · 교체)는 실행하지 않는다 — 끝나면 스크립트의 `trap cleanup EXIT` 가 자물쇠·임시 폴더를 치운다.
    func runDMGDownloadStage(env: [String: String] = [:]) throws -> ProcessRun {
        let script = UpdateRunner.dmgUpdateScript
        let marker = try #require(script.range(of: #"echo "$M 받음: "#), "DMG 스크립트에서 받음 로그 줄을 못 찾았다")
        let lineEnd = try #require(script[marker.upperBound...].firstIndex(of: "\n"))
        let stage = String(script[..<lineEnd]) + "\ncp \"$TMP/a.dmg\" \"$7\"\n"
        let dest = root.appendingPathComponent("Apps/aing-check.app").path
        return try runProcess("/bin/zsh", ["-c", stage, "aing-check-update", dest, Self.originURL, "", "req", "100",
                                           statePath.path, dmgCapture.path],
                              env: environment.merging(env) { $1 })
    }

    func lines(_ name: String) -> [String] {
        let text = (try? String(contentsOf: state.appendingPathComponent(name), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }
    /// 가짜 curl 이 적은 요청(`probe n 주소` · `piece a-b 주소` · `whole 주소`).
    func calls() -> [String] { lines("calls") }
    /// 끝이 `b` 인 조각 요청들(차례대로) — 이어 받기는 시작이 바뀌고 끝은 그대로라 끝으로 한 조각의 시도를 모은다.
    func pieceCalls(endingAt b: Int) -> [String] {
        calls().filter { $0.hasPrefix("piece ") && $0.contains("-\(b) ") }
    }
    /// 가짜 curl 이 받은 인자 그대로(`argv …`).
    func curlArgv() -> [String] { lines("curl.argv") }
    /// 가짜 brew · open · curl 이 적은 차례.
    func sequence() -> [String] { lines("seq") }
    func stateLines() -> [String] {
        ((try? String(contentsOf: statePath, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func names(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    func expectNoSignature(_ log: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!log.contains("SECRET"), "서명·토큰 쿼리가 로그에 남았다:\n\(log)", sourceLocation: sourceLocation)
    }
}

private struct ProcessRun {
    let status: Int32
    let output: String
}

/// 자식 프로세스를 돌리고 stdout+stderr 를 모은다. 60초 안에 안 끝나면 끊는다(멈춘 시험이 스위트를 붙잡지 않게).
private func runProcess(_ path: String, _ arguments: [String], env: [String: String], cwd: URL? = nil) throws -> ProcessRun {
    try ChildProcess(path, arguments, env: env, cwd: cwd).finish()
}

/// 띄워 두고 나중에 거두는 자식 프로세스 — 두 실행을 겹치게 하는 시험이 쓴다. 출력은 뒤에서 읽어 파이프가 막히지 않게 한다.
private final class ChildProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var collected = Data()
    private let done = DispatchSemaphore(value: 0)

    init(_ path: String, _ arguments: [String], env: [String: String], cwd: URL? = nil) throws {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = env
        if let cwd { process.currentDirectoryURL = cwd }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let handle = pipe.fileHandleForReading
        DispatchQueue.global().async { [self] in
            let data = handle.readDataToEndOfFile()
            lock.lock(); collected = data; lock.unlock()
            done.signal()
        }
    }

    /// 끝나기를 기다려 거둔다. `timeout` 안에 안 끝나면 끊는다.
    func finish(timeout: TimeInterval = 60) -> ProcessRun {
        if done.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            _ = done.wait(timeout: .now() + 5)
        }
        process.waitUntilExit()
        lock.lock(); defer { lock.unlock() }
        return ProcessRun(status: process.terminationStatus, output: String(decoding: collected, as: UTF8.self))
    }
}

private func sha256Hex(of url: URL) -> String {
    let run = try? runProcess("/usr/bin/shasum", ["-a", "256", url.path], env: ["PATH": "/usr/bin:/bin"])
    return String((run?.output ?? "").prefix { $0 != " " })
}

// MARK: - 가짜 도구

/// 가짜 curl. 실제 curl 이 받는 옵션만 받아들이고(모르면 2 — 실제 curl 과 같은 종료코드), 픽스처의 바이트 범위를 내준다.
///  · 탐색(`-L` · `-D` · `-r 0-0`): 302 블록(가짜 `Content-Range: bytes 0-0/1` 이 섞인) + 206 블록 머리를 쓰고, `-w` 자리에
///    `206 <서명된 최종 주소 — 탐색마다 sig 번호가 는다>` 를 낸다. FAKE_NORANGE 면 200 + 본문 전체(Range 무시 서버).
///    탐색은 `-L` 이 붙은 `-D` 요청으로 가른다(조각도 `-D` 를 받는다). FAKE_TOTAL_TEXT 면 206 블록 Content-Range 의 전체 크기
///    글자를 그것으로 바꾸고(`*` · `0` · 글자), FAKE_TOTAL_CHANGES 면 두 번째 탐색부터 전체 크기를 1 늘려 알린다(그사이 자산이 바뀜).
///    FAKE_PROBE_SLEEP_AT=<n> 이면 n 번째 탐색이 FAKE_PROBE_SLEEP_SECS 초 동안 쉰다(탐색이 시간을 먹는 경우).
///  · 조각(`-r a-b`, `-L` 없음): 그 범위를 내고 `-D` 에 `HTTP/2 206` + `content-range: bytes a-b/전체` 를, `-w %{http_code}` 자리에
///    코드를 낸다. FAKE_PIECE_MODE 로 응답을 어긋나게 한다:
///      samebody    — Range 를 무시하는 캐시가 첫 206(0번 조각)의 머리·본문을 조각마다 되풀이(크기 ceil(전체/8))
///      samebody200 — 같은 되풀이를 200 으로(Content-Range 없음)
///      wrongtotal  — 본문·범위는 맞고 전체 크기만 +1
///      nocr        — 206 인데 Content-Range 가 없다
///      code200     — 범위를 무시하고 200 + 본문 전체
///    **끊김 갈래** — 실제 curl 처럼 받은 앞부분만 쓰고 28 로 끝나되 `-D` 머리와 `-w` 코드는 그대로 낸다(문턱에 걸려 끊긴 연결):
///      FAKE_STALL_ONCE=<시작 바이트>   그 바이트에서 시작하는 첫 요청 한 번만 절반을 쓰고 28
///      FAKE_BADCUT_ONCE=<시작 바이트>  첫 요청 한 번만 **머리가 어긋난** 응답(0번부터의 본문 · `bytes 0-…`)의 절반을 쓰고 28
///      FAKE_TRICKLE_END=<끝 바이트>    그 바이트로 끝나는 요청마다 FAKE_TRICKLE_BYTES 바이트만 쓰고 28(남은 게 그 이하면 다 쓰고 0)
///                                       — 이어 받기는 시작이 바뀌고 끝은 그대로라 끝으로 가른다
///      FAKE_DEAD=<시작 바이트>          그 바이트에서 시작하는 요청마다 0바이트를 쓰고 28
///    그 밖에: FAKE_SHORT_ALWAYS=<시작 바이트> 면 그 시작의 요청마다 한 바이트 모자라게 쓰고 **0**(짧게 끝나도 종료코드는 성공),
///    FAKE_OVERLONG=<시작 바이트> 면 요청보다 한 바이트 더 쓰고 0(머리는 맞다).
///  · 단일(`-r` 없음): 본문 전체. FAKE_WHOLE_RC 면 그 코드로 실패.
private let fakeCurl = #"""
    #!/bin/zsh
    set -u
    S="$FAKE_STATE"; FIX="$FAKE_FIXTURE"
    print -r -- "argv $*" >> "$S/curl.argv"
    range="" out="" hdr="" url="" wfmt="" follow=""
    while [ $# -gt 0 ]; do
      case "$1" in
        (-r|-o|-D|-w|--proto|--proto-redir|--connect-timeout|--max-time|--speed-limit|--speed-time)
          [ $# -ge 2 ] || { print -u2 "fake curl: $1 에 값이 없다"; exit 2; }
          case "$1" in (-r) range="$2" ;; (-o) out="$2" ;; (-D) hdr="$2" ;; (-w) wfmt="$2" ;; esac
          shift 2 ;;
        (-L|-fL) follow=1; shift ;;
        (-f|-s|-S|-sS|-fsS|--tlsv1.2) shift ;;
        (-*) print -u2 "fake curl: 모르는 옵션 $1"; exit 2 ;;
        (*) [ -z "$url" ] || { print -u2 "fake curl: 주소가 둘"; exit 2; }; url="$1"; shift ;;
      esac
    done
    [ -n "$url" ] && [ -n "$out" ] || { print -u2 "fake curl: 주소나 -o 가 없다"; exit 2; }
    total=$(stat -f %z "$FIX")
    serve() { if [ "$2" -gt 0 ]; then tail -c +$(( $1 + 1 )) "$FIX" | head -c "$2" > "$out"; else : > "$out"; fi; }
    if [ -n "$hdr" ] && [ -n "$follow" ]; then
      [ "$range" = "0-0" ] || { print -u2 "fake curl: 탐색 범위가 0-0 이 아니다"; exit 2; }
      n=$(( $(cat "$S/probes" 2>/dev/null || print 0) + 1 )); print $n > "$S/probes"
      final="${FAKE_FINAL_BASE:-https://objects.example.invalid}/asset.bin?sig=SECRET-$n"
      print -r -- "probe $n $url" >> "$S/calls"
      print -r -- "curl probe" >> "$S/seq"
      if [ "${FAKE_PROBE_SLEEP_AT:-x}" = "$n" ]; then sleep "$FAKE_PROBE_SLEEP_SECS"; fi
      if [ -n "${FAKE_NORANGE:-}" ]; then
        printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: %s\r\n\r\n' "$final" "$total" > "$hdr"
        cat "$FIX" > "$out"
        printf '200 %s' "$final"
        exit 0
      fi
      ctotal="${FAKE_TOTAL_TEXT-$total}"
      if [ -n "${FAKE_TOTAL_CHANGES:-}" ] && [ "$n" -ge 2 ]; then ctotal=$(( total + 1 )); fi
      if [ -n "${FAKE_NO_FINAL_CR:-}" ]; then
        printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Range: bytes 0-0/1\r\n\r\nHTTP/2 206\r\ncontent-length: 1\r\n\r\n' "$final" > "$hdr"
      else
        printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Range: bytes 0-0/1\r\n\r\nHTTP/2 206\r\n%s: bytes 0-0/%s\r\ncontent-length: 1\r\n\r\n' "$final" "${FAKE_CR_NAME:-Content-Range}" "$ctotal" > "$hdr"
      fi
      serve 0 1
      printf '206 %s' "$final"
      exit 0
    fi
    if [ -z "$range" ]; then
      [ -z "$hdr" ] || { print -u2 "fake curl: 단일 받기에 -D 가 있다"; exit 2; }
      print -r -- "whole $url" >> "$S/calls"
      print -r -- "curl whole" >> "$S/seq"
      if [ -n "${FAKE_WHOLE_RC:-}" ]; then print -u2 "curl: (${FAKE_WHOLE_RC}) 가짜 실패"; exit "$FAKE_WHOLE_RC"; fi
      cat "$FIX" > "$out"
      exit 0
    fi
    [ -z "$follow" ] || { print -u2 "fake curl: 조각이 리다이렉트를 따라간다"; exit 2; }
    [ -z "$wfmt" ] || [ "$wfmt" = '%{http_code}' ] || { print -u2 "fake curl: 조각의 -w 가 다르다: $wfmt"; exit 2; }
    a="${range%-*}"; b="${range#*-}"; len=$(( b - a + 1 ))
    print -r -- "piece $range $url" >> "$S/calls"
    print -r -- "curl piece" >> "$S/seq"
    code=206; cr="bytes $a-$b/$total"; from=$a; count=$len; rc=0
    case "${FAKE_PIECE_MODE:-}" in
      (samebody) count=$(( (total + 7) / 8 )); from=0; cr="bytes 0-$(( count - 1 ))/$total" ;;
      (samebody200) count=$(( (total + 7) / 8 )); from=0; code=200; cr="" ;;
      (wrongtotal) cr="bytes $a-$b/$(( total + 1 ))" ;;
      (nocr) cr="" ;;
      (code200) code=200; cr=""; from=0; count=$total ;;
      ('') ;;
      (*) print -u2 "fake curl: 모르는 FAKE_PIECE_MODE"; exit 2 ;;
    esac
    promised=$count
    if [ "${FAKE_STALL_ONCE:-x}" = "$a" ] && [ ! -e "$S/stalled" ]; then
      : > "$S/stalled"; count=$(( count / 2 )); rc=28
    elif [ "${FAKE_BADCUT_ONCE:-x}" = "$a" ] && [ ! -e "$S/badcut" ]; then
      : > "$S/badcut"; from=0; promised=$len; cr="bytes 0-$(( len - 1 ))/$total"; count=$(( len / 2 )); rc=28
    elif [ "${FAKE_TRICKLE_END:-x}" = "$b" ] && [ "$count" -gt "$FAKE_TRICKLE_BYTES" ]; then
      count=$FAKE_TRICKLE_BYTES; rc=28
    elif [ "${FAKE_DEAD:-x}" = "$a" ]; then
      count=0; rc=28
    elif [ "${FAKE_SHORT_ALWAYS:-x}" = "$a" ]; then
      count=$(( count - 1 ))
    elif [ "${FAKE_OVERLONG:-x}" = "$a" ]; then
      count=$(( count + 1 ))
    fi
    if [ -n "$hdr" ]; then
      if [ -n "$cr" ]; then
        printf 'HTTP/2 %s\r\ncontent-range: %s\r\ncontent-length: %s\r\n\r\n' "$code" "$cr" "$promised" > "$hdr"
      else
        printf 'HTTP/2 %s\r\ncontent-length: %s\r\n\r\n' "$code" "$promised" > "$hdr"
      fi
    fi
    serve "$from" "$count"
    [ -z "$wfmt" ] || printf '%s' "$code"
    if [ "$rc" -eq 28 ]; then print -u2 "curl: (28) Operation too slow. Less than 1048576 bytes/sec transferred the last 3 seconds"; fi
    exit "$rc"
    """#

/// 가짜 brew. 호출을 차례대로 적고(`HOMEBREW_NO_AUTO_UPDATE` 값까지), 준비된 JSON · 캐시 경로를 낸다.
/// upgrade 하는 순간 캐시 자리에 무엇이 있는지(지문)를 적는다 — brew 가 그 파일을 쓸 수 있었는지 재는 자리다.
/// FAKE_BREW_CACHE_OUT 이 **있으면**(빈 값 포함) `--cache` 가 그 글자를 그대로 낸다(여러 줄 · 빈 값 · 상대경로).
/// FAKE_ROLE 이 있으면 upgrade 뒤에 `upgraded-<역할>` 표식을 남긴다(두 벌을 겹치는 시험의 차례 맞추기 — 가짜 shasum 참고).
/// 지문은 진짜 `/usr/bin/shasum` 으로 잰다 — 가짜 shasum 의 기록에 섞이지 않게.
private let fakeBrew = #"""
    #!/bin/zsh
    set -u
    S="$FAKE_STATE"
    print -r -- "brew $* [auto=${HOMEBREW_NO_AUTO_UPDATE:-unset}]" >> "$S/seq"
    case "${1:-}" in
      (update) exit "${FAKE_BREW_UPDATE_RC:-0}" ;;
      (info) cat "$FAKE_BREW_JSON"; exit 0 ;;
      (--cache) print -r -- "${FAKE_BREW_CACHE_OUT-$FAKE_BREW_CACHE}"; exit 0 ;;
      (upgrade)
        if [ -e "$FAKE_BREW_CACHE" ]; then
          g="$(/usr/bin/shasum -a 256 "$FAKE_BREW_CACHE")"; print -r -- "cache-at-upgrade ${g%% *}" >> "$S/seq"
        else
          print -r -- "cache-at-upgrade none" >> "$S/seq"
        fi
        [ -z "${FAKE_ROLE:-}" ] || : > "$S/upgraded-$FAKE_ROLE"
        exit "${FAKE_BREW_UPGRADE_RC:-0}" ;;
    esac
    exit 1
    """#

/// 가짜 cat — 평소엔 진짜 cat 그대로. pfetch 가 조각(`…/aing-check-pfetch.*/p<n>`)을 이을 때만 갈래를 탄다:
///  · FAKE_CAT_PROBE=<경로> — 이을 때마다 그 경로(OUT)가 그 이름으로 보이는지(present/absent) `catprobe` 에 적는다.
///  · FAKE_CAT_FAIL  — 10바이트만 쓰고 1 로 죽는다(잇는 도중 디스크가 찬 경우). `OUT.part` 가 생긴 **뒤의** 실패 갈래.
///  · FAKE_CAT_SHORT — 10바이트만 쓰고 **0** 을 돌려준다(짧게 쓰고도 성공이라 한 경우 — 이은 크기 검사만 잡는다).
///  · FAKE_CAT_KILL  — 10바이트만 쓰고 부모(미리 받기 서브셸)를 SIGKILL 로 죽인다(잇는 도중 종료·로그아웃).
private let fakeCat = #"""
    #!/bin/zsh
    if [ $# -eq 1 ] && [[ "$1" == *aing-check-pfetch.*/p[0-9]* ]]; then
      if [ -n "${FAKE_CAT_PROBE:-}" ]; then
        if [ -e "$FAKE_CAT_PROBE" ]; then print -r -- present >> "$FAKE_STATE/catprobe"; else print -r -- absent >> "$FAKE_STATE/catprobe"; fi
      fi
      if [ -n "${FAKE_CAT_FAIL:-}" ]; then head -c 10 "$1"; exit 1; fi
      if [ -n "${FAKE_CAT_SHORT:-}" ]; then head -c 10 "$1"; exit 0; fi
      if [ -n "${FAKE_CAT_KILL:-}" ]; then head -c 10 "$1"; kill -9 "$PPID"; exit 1; fi
    fi
    exec /bin/cat "$@"
    """#

/// 가짜 shasum — 진짜 `/usr/bin/shasum` 으로 재고, 잰 대상(마지막 인자)과 **그 순간 brew 캐시 자리에 파일이 있는지**를
/// `shasum` 에 적는다(불변식 2: 검증은 캐시 이름 밖에서 끝나야 한다). FAKE_ROLE 이 있으면 두 벌의 차례를 못박는다:
///  · A — 잰 뒤 `hashed-A` 를 남기고 `hashed-B` 가 생길 때까지(최대 30초) 결과를 쥐고 기다린다(검증과 mv 사이를 넓힌다).
///  · B — 잰 뒤 `hashed-B` 를 남기고 `upgraded-A` 가 생길 때까지 기다린다(A 가 mv·upgrade 를 다 마칠 때까지).
private let fakeShasum = #"""
    #!/bin/zsh
    t="${@[-1]}"
    if [ -e "$FAKE_BREW_CACHE" ]; then c=present; else c=absent; fi
    print -r -- "${FAKE_ROLE:+$FAKE_ROLE }$t cache=$c" >> "$FAKE_STATE/shasum"
    r="$(/usr/bin/shasum "$@")"; rc=$?
    w=0
    case "${FAKE_ROLE:-}" in
      (A) : > "$FAKE_STATE/hashed-A"
          while [ ! -e "$FAKE_STATE/hashed-B" ] && [ "$w" -lt 300 ]; do sleep 0.1; w=$(( w + 1 )); done ;;
      (B) : > "$FAKE_STATE/hashed-B"
          while [ ! -e "$FAKE_STATE/upgraded-A" ] && [ "$w" -lt 300 ]; do sleep 0.1; w=$(( w + 1 )); done ;;
    esac
    print -r -- "$r"
    exit "$rc"
    """#

/// 가짜 open — 적기만 한다(아무것도 띄우지 않는다).
private let fakeOpen = #"""
    #!/bin/zsh
    print -r -- "open $*" >> "$FAKE_STATE/seq"
    """#
