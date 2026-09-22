import Foundation

/// 테스트가 만드는 모든 UserDefaults 스위트와 임시 폴더의 뿌리.
///
/// **왜 $TMPDIR 인가** — 스위트 이름을 절대 경로로 주면 CFPreferences 는 그 경로에 plist 를 쓴다.
/// ~/Library/Preferences 로 새지 않는다(V0327GomokuTestDefaults 2026-09-16 프로브, 그리고
/// 2026-09-22 에 $TMPDIR/check-v0327-defaults 에 1,111개가 실제로 쌓여 있는 것으로 재확인).
///
/// **왜 "끝나고"가 아니라 "시작할 때" 지우는가** — removePersistentDomain 도 파일 직접 삭제도
/// cfprefsd 를 못 이긴다. 2026-09-22 실측: GomokuTestDefaults.forget() 이 rpd + removeItem 을 둘 다
/// 부르는데도 1,110개가 100바이트로 남았고 그 안에 check.deviceID 같은 **값이 살아 있었다** — 테스트가
/// 끝난 뒤 cfprefsd 가 자기 메모리 사본을 다시 flush 했다는 뜻이다. 그래서 정리를 앞으로 옮긴다.
/// 남는 양이 1회 실행분으로 묶인다.
///
/// **왜 이름을 #function 에서 뽑는가** — 파일 수는 정리 방식이 아니라 *만든 스위트 이름의 개수* 에
/// 비례한다. UUID 이름은 실행마다 새 파일이고, 테스트 신원에서 뽑은 이름은 재실행이 같은 파일을
/// 덮어쓸 뿐이라 파일 수가 O(테스트 수) 로 묶인다.
/// (2026-09-22 사고: ~/Library/Preferences 의 check-* 454,595개가 cfprefsd 를 죽여 앱이 자기
/// UserDefaults 를 못 읽었고, 기기 ID 를 잃어 유령 기기로 순위표 토큰이 2배가 됐다.)
enum CheckTestScratch {

    /// 프로세스당 한 번 계산 = 프로세스당 한 번 청소. static let 이라 스레드 안전하다(swift_once).
    static let root: URL = {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("check-tests", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        // 지난 실행이 남긴 판만 치운다. 2시간 컷오프 — 지금 도는 다른 테스트 프로세스를 안 날린다.
        // 이 두 장치(pid 하위 폴더 + 컷오프)를 빼면 `swift test` 두 개를 동시에 돌릴 때 서로의
        // 스크래치를 지워 재현 불가능한 빨강이 된다.
        let cutoff = Date().addingTimeInterval(-2 * 3600)
        for name in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] {
            let url = base.appendingPathComponent(name)
            let at = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            if (at ?? .distantPast) < cutoff { try? fm.removeItem(at: url) }
        }

        let mine = base.appendingPathComponent("run-\(ProcessInfo.processInfo.processIdentifier)",
                                               isDirectory: true)
        try? fm.removeItem(at: mine)
        try? fm.createDirectory(at: mine, withIntermediateDirectories: true)
        return mine
    }()

    /// 격리 UserDefaults. 이름이 절대 경로라 plist 는 `root` 안에 떨어진다(Preferences 아님).
    ///
    /// `label` 은 **한 테스트가 스위트를 둘 이상 쓸 때** 서로 안 겹치게 하는 꼬리표다. 안 붙이면 두
    /// 스위트가 같은 이름이 되어 "서로 다른 저장소"를 전제한 단언이 조용히 무의미해진다.
    /// `@Test(arguments:)` 파라미터화 테스트도 같은 #function 으로 **동시에** 도니 인자값을 label 에 넣어라.
    ///
    /// 호출자는 반드시 `function: String = #function` 을 파라미터로 받아 여기까지 **이어 넘겨야** 한다.
    /// 헬퍼 본문에서 그냥 부르면 #function 이 그 헬퍼 이름으로 굳어 파일 안 모든 테스트가 한 스위트를 공유한다.
    static func defaults(_ label: String = "", function: String = #function) -> UserDefaults {
        let path = suitePath(label, function: function)
        let defaults = UserDefaults(suiteName: path)!
        defaults.removePersistentDomain(forName: path)   // 같은 프로세스 재사용 · 지난 실행 잔값 대비 초기화
        return defaults
    }

    /// `defaults(_:function:)` 가 쓰는 스위트 이름(=절대 경로). 끝나고 한 번 더 지우고 싶거나
    /// `(defaults, cleanUp)` 튜플을 유지해야 하는 호출자가 이름을 알아야 할 때 쓴다.
    static func suitePath(_ label: String = "", function: String = #function) -> String {
        root.appendingPathComponent("d-" + slug(function, label)).path
    }

    /// **이미 유계인 고정 이름을 자리만 옮긴다.** 옛 `UserDefaults(suiteName: "check-…")` 의 1:1 교체용.
    ///
    /// 왜 필요한가 — 고정 이름은 개수가 유계라 2026-09-22 사고(45만 개)의 원인은 아니지만, 그래도
    /// **~/Library/Preferences 에 새 항목을 만든다.** 그 폴더의 항목 수가 스위트 실행 전후로 늘지 않는 것을
    /// 회귀 테스트가 단언하므로(`PreferencesLeakGateTests`), 고정 이름도 전부 여기를 지나야 한다.
    /// `function` 을 이어 넘길 수 없는 자리(이름이 호출자에게서 문자열로 건너오는 헬퍼)를 위한 문이다.
    static func suitePath(named name: String) -> String {
        root.appendingPathComponent("n-" + slug(name, "")).path
    }

    /// **UUID 자리의 1:1 교체.** `"check-x-\(UUID().uuidString)"` 처럼 실행마다 새 이름을 만들던 자리에 쓴다.
    ///
    /// UUID 와 다른 점은 가짓수다: 이름이 `호출 자리 + 그 자리를 이번 실행에서 부른 횟수` 로 정해져,
    /// 한 번 실행에서 그 자리를 부른 만큼만 늘고 **다음 실행은 같은 이름들을 다시 쓴다**.
    /// (같은 장치가 `BaseStub.makeStorage` 에도 있다 — 모바일 타깃의 본보기.)
    ///
    /// `function`·`line` 은 **호출 지점**에서 평가되는 컴파일러 기본 인자다. 파일마다 있는 private 헬퍼
    /// (`isolatedSuite()` 같은 것)가 그냥 부르면 그 헬퍼의 신원이 들어오고, 일련번호가 병렬 테스트끼리
    /// 이름을 갈라 준다 — 그래서 호출자 서명을 하나도 안 고치고 UUID 를 걷어낼 수 있다.
    static func uniqueSuitePath(_ label: String = "",
                                function: String = #function,
                                line: Int = #line) -> String {
        let site = slug(function, label) + "-L\(line)"
        var index = 0
        siteCounterLock.lock()
        index = siteCounter[site, default: 0]
        siteCounter[site] = index + 1
        siteCounterLock.unlock()
        return root.appendingPathComponent("u-\(site)-\(index)").path
    }

    private nonisolated(unsafe) static var siteCounter = [String: Int]()
    private static let siteCounterLock = NSLock()

    /// 격리 임시 폴더(파일용). 이름이 테스트별로 고정이라 재실행이 같은 폴더를 덮어쓴다.
    static func directory(_ label: String = "", function: String = #function) -> URL {
        let url = root.appendingPathComponent("f-" + slug(function, label), isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func slug(_ function: String, _ label: String) -> String {
        let raw = function.replacingOccurrences(of: "()", with: "")
            + (label.isEmpty ? "" : "-" + label)
        let s = String(raw.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : "-"
        })
        // 길면 자르되, 자른 뒤에도 서로 갈리도록 원본의 지문을 붙인다.
        // `hashValue` 는 **프로세스마다 시드가 달라** 실행마다 다른 값이 나온다(2026-09-22 실측:
        // 같은 문자열이 두 실행에서 -5473928194107074901 / -2053000808844451785). 그걸 쓰면 이름이
        // 다시 무계가 되어 이 파일의 목적이 무너진다. 그래서 결정적 해시(FNV-1a)를 쓴다.
        return s.count <= 120 ? s : String(s.prefix(100)) + "-\(fingerprint(raw))"
    }

    /// FNV-1a 64비트. 프로세스 간에 값이 변하지 않는다 — 그게 여기서 유일하게 중요한 성질이다.
    private static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }
}
