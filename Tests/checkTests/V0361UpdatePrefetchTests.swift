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
//    시나리오는 환경변수로 가른다(FAKE_NORANGE · FAKE_STALL_ONCE · FAKE_SHORT_ALWAYS · FAKE_WHOLE_RC · FAKE_CR_NAME).
//  · 가짜 brew · 가짜 open — 호출을 차례대로 적고, 준비된 JSON · 캐시 경로를 내준다. 앱 경로도 실험실 안의 없는 경로라
//    가짜 open 이 어긋나도 실제 앱이 뜨지 않는다.
// 네트워크 · 실제 brew · 사용자 Homebrew 캐시 · 화면을 건드리지 않는다(`sandbox-exec … deny network-outbound` 아래에서 초록).

@Suite("0.3.61 원클릭 업데이트 나눠 받기 — 가짜 curl · 가짜 brew 로 실제 zsh 실행")
struct V0361UpdatePrefetchTests {

    // MARK: - A. pfetch

    @Test func pfetch_정상_8조각은_픽스처와_같은_바이트를_남기고_조각을_치운다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let run = try lab.runPfetch(url: PrefetchLab.originURL)

        #expect(run.status == 0, "pfetch 가 실패했다: \(run.output)")
        #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData, "받은 바이트가 픽스처와 다르다")
        #expect(lab.names(in: lab.out) == ["a.bin"], "OUT 옆에 잔재가 있다: \(lab.names(in: lab.out))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 조각이 남았다: \(lab.names(in: lab.tmp))")

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
            #expect(line.hasPrefix("argv -fsS --proto =https --tlsv1.2 --connect-timeout 15 --speed-limit 65536 --speed-time 12 --max-time 90 -r "),
                    "조각 명령이 설계와 다르다: \(line)")
            #expect(!line.contains(" -L "), "조각이 리다이렉트를 다시 따라간다: \(line)")
        }

        #expect(run.output.contains("나눠 받기 끝: 9000001 bytes · 8갈래"), "\(run.output)")
        #expect(run.output.contains("재시도한 조각 0개"), "\(run.output)")
        lab.expectNoSignature(run.output)
    }

    @Test func pfetch_Range_를_안_받는_원본이면_0이_아니고_OUT_도_잔재도_없다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_NORANGE": "1"])

        #expect(run.status != 0, "Range 를 안 받는데 성공이라 했다: \(run.output)")
        #expect(lab.names(in: lab.out).isEmpty, "OUT(또는 .part)이 생겼다: \(lab.names(in: lab.out))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 폴더가 남았다: \(lab.names(in: lab.tmp))")
        #expect(lab.calls().filter { $0.hasPrefix("piece ") }.isEmpty, "Range 를 안 받는 원본에 조각을 보냈다")
        #expect(run.output.contains("나눠 받기 폴백: Range 를 받지 않습니다(HTTP 200)"), "\(run.output)")
        lab.expectNoSignature(run.output)
    }

    @Test func pfetch_멎은_조각은_새_서명_주소로_한_번_더_받아_성공한다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let stalled = PrefetchLab.ranges(total: 9_000_001, parts: 8)[3]
        let start = String(stalled.prefix { $0 != "-" })
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_STALL_ONCE": start])

        #expect(run.status == 0, "한 번 멎은 조각을 다시 받지 못했다: \(run.output)")
        #expect(try Data(contentsOf: lab.outFile) == lab.fixtureData)
        #expect(lab.names(in: lab.tmp).isEmpty)
        let calls = lab.calls()
        // 재시도 전에 탐색을 한 번 더 한다(서명 주소 만료·403 대비) — 그리고 재시도는 **그 새 주소**로 간다.
        #expect(calls.filter { $0.hasPrefix("probe ") }.count == 2, "재탐색이 없다: \(calls)")
        #expect(calls.filter { $0.hasPrefix("piece \(stalled) ") }
                == ["piece \(stalled) \(PrefetchLab.finalURL(1))", "piece \(stalled) \(PrefetchLab.finalURL(2))"],
                "멎은 조각의 재시도가 새 서명 주소로 가지 않았다: \(calls)")
        // 틀린 조각만 다시 받는다(맞은 일곱은 한 번씩).
        #expect(calls.filter { $0.hasPrefix("piece ") }.count == 9)
        #expect(run.output.contains("재시도한 조각 1개"), "\(run.output)")
        lab.expectNoSignature(run.output)
    }

    @Test func pfetch_두_번_다_짧은_조각이면_0이_아니고_OUT_도_조각도_남지_않는다() throws {
        let lab = try PrefetchLab(fixtureSize: 9_000_001)
        let short = PrefetchLab.ranges(total: 9_000_001, parts: 8)[5]
        let start = String(short.prefix { $0 != "-" })
        let run = try lab.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_SHORT_ALWAYS": start])

        #expect(run.status != 0, "두 번 다 짧은 조각을 받아들였다: \(run.output)")
        #expect(lab.names(in: lab.out).isEmpty, "OUT(또는 .part)이 남았다: \(lab.names(in: lab.out))")
        #expect(lab.names(in: lab.tmp).isEmpty, "임시 조각이 남았다: \(lab.names(in: lab.tmp))")
        let calls = lab.calls()
        #expect(calls.filter { $0.hasPrefix("piece \(short) ") }.count == 2, "재시도가 정확히 한 번이 아니다: \(calls)")
        #expect(calls.filter { $0.hasPrefix("probe ") }.count == 2)
        #expect(run.output.contains("두 번 다 어긋났습니다"), "\(run.output)")
        lab.expectNoSignature(run.output)
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
        let failed = try bad.runPfetch(url: PrefetchLab.originURL, env: ["FAKE_SHORT_ALWAYS": "0"])
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

    // 래퍼는 값을 끼우지 않는다(`dmgSpawnWrapperInterpolatesNothing` 과 같은 모양).
    @Test func brew_래퍼는_아무_값도_끼우지_않는다() {
        let wrapper = UpdateRunner.brewSpawnWrapper
        #expect(wrapper == #"nohup zsh -c "$1" aing-check-update "$2" "$3" "$4" >>"$5" 2>&1 &"#)
        for literal in ["/Applications", "https://", "/opt/homebrew", "/usr/local", "aing-check.app", "Library", "brew", "'"] {
            #expect(!wrapper.contains(literal), "래퍼에 값이 글자로 들어 있다: \(literal)")
        }
    }

    // 래퍼 + 인자를 **실제로** 던져 본다: `$1`…`$5` 가 한 자리씩 맞아야 brew 가 cask 이름을, open 이 앱 경로를 받는다.
    // 앱 경로·로그 자리만 실험실로 바꾸고(실제 로그·실제 앱을 건드리지 않게) 나머지는 프로덕션 인자 그대로다.
    @Test func brew_래퍼와_인자를_실제로_던지면_자리가_맞는다() throws {
        let lab = try PrefetchLab(fixtureSize: 300_000)
        try lab.writeBrewFixture(sha: lab.fixtureSHA, installed: "0.3.61")
        var args = UpdateRunner.brewUpgradeArguments(brew: lab.bin.appendingPathComponent("brew").path)
        #expect(args.count == 6)
        #expect(args[4] == UpdateRunner.appPath)
        #expect(args[5] == UpdateRunner.logPath)
        let log = lab.root.appendingPathComponent("update.log")
        args[4] = lab.appPath
        args[5] = log.path
        let run = try runProcess("/bin/zsh", ["-c", UpdateRunner.brewSpawnWrapper] + args, env: lab.environment)
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

    @Test("버전 0.3.61 / 114 · CHANGELOG 0.3.61 은 맨 위 세 줄 이하(사용자 말투)")
    func versionAndChangelog() throws {
        let root = CheckCoreSourceLayout.repoRoot
        let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
        #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.61</string>"))
        #expect(squashed.contains("<key>CFBundleVersion</key><string>114</string>"))
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
                "0.3.61 이 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
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
        for (name, text) in [("curl", fakeCurl), ("brew", fakeBrew), ("open", fakeOpen), ("cat", fakeCat)] {
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
    func runPfetch(url: String, env: [String: String] = [:]) throws -> ProcessRun {
        let script = "set -u\nM=\"[aing-check-update]\"\n" + UpdateRunner.pfetchFunction + "\npfetch \"$1\" \"$2\"\n"
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
                 env: [String: String] = [:]) throws -> ProcessRun {
        try writeBrewFixture(sha: sha, installed: installed, url: url)
        return try runProcess("/bin/zsh", ["-c", UpdateRunner.brewUpgradeScript, "aing-check-update",
                                           bin.appendingPathComponent("brew").path, UpdateRunner.caskName, appPath],
                              env: environment.merging(env) { $1 })
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
private func runProcess(_ path: String, _ arguments: [String], env: [String: String]) throws -> ProcessRun {
    final class Box: @unchecked Sendable {
        let process = Process()
    }
    let box = Box()
    box.process.executableURL = URL(fileURLWithPath: path)
    box.process.arguments = arguments
    box.process.environment = env
    let pipe = Pipe()
    box.process.standardOutput = pipe
    box.process.standardError = pipe
    box.process.standardInput = FileHandle.nullDevice
    try box.process.run()
    let guardItem = DispatchWorkItem { if box.process.isRunning { box.process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: guardItem)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    box.process.waitUntilExit()
    guardItem.cancel()
    return ProcessRun(status: box.process.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

private func sha256Hex(of url: URL) -> String {
    let run = try? runProcess("/usr/bin/shasum", ["-a", "256", url.path], env: ["PATH": "/usr/bin:/bin"])
    return String((run?.output ?? "").prefix { $0 != " " })
}

// MARK: - 가짜 도구

/// 가짜 curl. 실제 curl 이 받는 옵션만 받아들이고(모르면 2 — 실제 curl 과 같은 종료코드), 픽스처의 바이트 범위를 내준다.
///  · 탐색(`-D` + `-r 0-0`): 302 블록(가짜 `Content-Range: bytes 0-0/1` 이 섞인) + 206 블록 머리를 쓰고, `-w` 자리에
///    `206 <서명된 최종 주소 — 탐색마다 sig 번호가 는다>` 를 낸다. FAKE_NORANGE 면 200 + 본문 전체(Range 무시 서버).
///  · 조각(`-r a-b`): 그 범위를 낸다. FAKE_STALL_ONCE=<시작 바이트> 면 처음 한 번은 절반만 쓰고 28(멎음),
///    FAKE_SHORT_ALWAYS=<시작 바이트> 면 매번 한 바이트 모자라게 쓰고 0.
///  · 단일(`-r` 없음): 본문 전체. FAKE_WHOLE_RC 면 그 코드로 실패.
private let fakeCurl = #"""
    #!/bin/zsh
    set -u
    S="$FAKE_STATE"; FIX="$FAKE_FIXTURE"
    print -r -- "argv $*" >> "$S/curl.argv"
    range="" out="" hdr="" url=""
    while [ $# -gt 0 ]; do
      case "$1" in
        (-r|-o|-D|-w|--proto|--proto-redir|--connect-timeout|--max-time|--speed-limit|--speed-time)
          [ $# -ge 2 ] || { print -u2 "fake curl: $1 에 값이 없다"; exit 2; }
          case "$1" in (-r) range="$2" ;; (-o) out="$2" ;; (-D) hdr="$2" ;; esac
          shift 2 ;;
        (-f|-s|-S|-L|-fsS|-fL|--tlsv1.2) shift ;;
        (-*) print -u2 "fake curl: 모르는 옵션 $1"; exit 2 ;;
        (*) [ -z "$url" ] || { print -u2 "fake curl: 주소가 둘"; exit 2; }; url="$1"; shift ;;
      esac
    done
    [ -n "$url" ] && [ -n "$out" ] || { print -u2 "fake curl: 주소나 -o 가 없다"; exit 2; }
    total=$(stat -f %z "$FIX")
    serve() { tail -c +$(( $1 + 1 )) "$FIX" | head -c "$2" > "$out"; }
    if [ -n "$hdr" ]; then
      [ "$range" = "0-0" ] || { print -u2 "fake curl: 탐색 범위가 0-0 이 아니다"; exit 2; }
      n=$(( $(cat "$S/probes" 2>/dev/null || print 0) + 1 )); print $n > "$S/probes"
      final="${FAKE_FINAL_BASE:-https://objects.example.invalid}/asset.bin?sig=SECRET-$n"
      print -r -- "probe $n $url" >> "$S/calls"
      print -r -- "curl probe" >> "$S/seq"
      if [ -n "${FAKE_NORANGE:-}" ]; then
        printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: %s\r\n\r\n' "$final" "$total" > "$hdr"
        cat "$FIX" > "$out"
        printf '200 %s' "$final"
        exit 0
      fi
      if [ -n "${FAKE_NO_FINAL_CR:-}" ]; then
        printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Range: bytes 0-0/1\r\n\r\nHTTP/2 206\r\ncontent-length: 1\r\n\r\n' "$final" > "$hdr"
      else
        printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Range: bytes 0-0/1\r\n\r\nHTTP/2 206\r\n%s: bytes 0-0/%s\r\ncontent-length: 1\r\n\r\n' "$final" "${FAKE_CR_NAME:-Content-Range}" "$total" > "$hdr"
      fi
      serve 0 1
      printf '206 %s' "$final"
      exit 0
    fi
    if [ -z "$range" ]; then
      print -r -- "whole $url" >> "$S/calls"
      print -r -- "curl whole" >> "$S/seq"
      if [ -n "${FAKE_WHOLE_RC:-}" ]; then print -u2 "curl: (${FAKE_WHOLE_RC}) 가짜 실패"; exit "$FAKE_WHOLE_RC"; fi
      cat "$FIX" > "$out"
      exit 0
    fi
    a="${range%-*}"; b="${range#*-}"; len=$(( b - a + 1 ))
    print -r -- "piece $range $url" >> "$S/calls"
    print -r -- "curl piece" >> "$S/seq"
    if [ "${FAKE_STALL_ONCE:-x}" = "$a" ] && [ ! -e "$S/stalled" ]; then
      : > "$S/stalled"
      serve "$a" $(( len / 2 ))
      print -u2 "curl: (28) Operation too slow. Less than 65536 bytes/sec transferred the last 12 seconds"
      exit 28
    fi
    if [ "${FAKE_SHORT_ALWAYS:-x}" = "$a" ]; then
      serve "$a" $(( len - 1 ))
      exit 0
    fi
    serve "$a" "$len"
    exit 0
    """#

/// 가짜 brew. 호출을 차례대로 적고(`HOMEBREW_NO_AUTO_UPDATE` 값까지), 준비된 JSON · 캐시 경로를 낸다.
/// upgrade 하는 순간 캐시 자리에 무엇이 있는지(지문)를 적는다 — brew 가 그 파일을 쓸 수 있었는지 재는 자리다.
private let fakeBrew = #"""
    #!/bin/zsh
    set -u
    S="$FAKE_STATE"
    print -r -- "brew $* [auto=${HOMEBREW_NO_AUTO_UPDATE:-unset}]" >> "$S/seq"
    case "${1:-}" in
      (update) exit "${FAKE_BREW_UPDATE_RC:-0}" ;;
      (info) cat "$FAKE_BREW_JSON"; exit 0 ;;
      (--cache) print -r -- "$FAKE_BREW_CACHE"; exit 0 ;;
      (upgrade)
        if [ -e "$FAKE_BREW_CACHE" ]; then
          g="$(shasum -a 256 "$FAKE_BREW_CACHE")"; print -r -- "cache-at-upgrade ${g%% *}" >> "$S/seq"
        else
          print -r -- "cache-at-upgrade none" >> "$S/seq"
        fi
        exit "${FAKE_BREW_UPGRADE_RC:-0}" ;;
    esac
    exit 1
    """#

/// 가짜 cat — 평소엔 진짜 cat 그대로. FAKE_CAT_FAIL 이면 pfetch 의 조각(`…/aing-check-pfetch.*/p<n>`)을 이을 때 10바이트만
/// 쓰고 1 로 죽는다(잇는 도중 디스크가 찬 경우). `OUT.part` 가 생긴 **뒤의** 실패 갈래를 재는 유일한 자리다.
private let fakeCat = #"""
    #!/bin/zsh
    if [ -n "${FAKE_CAT_FAIL:-}" ] && [ $# -eq 1 ] && [[ "$1" == *aing-check-pfetch.*/p[0-9]* ]]; then
      head -c 10 "$1"
      exit 1
    fi
    exec /bin/cat "$@"
    """#

/// 가짜 open — 적기만 한다(아무것도 띄우지 않는다).
private let fakeOpen = #"""
    #!/bin/zsh
    print -r -- "open $*" >> "$FAKE_STATE/seq"
    """#
