import Foundation
import CheckMobileShared

/// 모바일 테스트가 만드는 UserDefaults 스위트와 임시 폴더의 뿌리. 맥 쪽 `CheckTestScratch` 의 짝이고,
/// 이제 **같은 레버 두 개**를 다 쓴다: 이름이 $TMPDIR 절대 경로라 plist 가 ~/Library/Preferences 로 안 새고,
/// 이름을 테스트 신원에서 뽑아 개수가 유계다.
///
/// **왜 $TMPDIR 로 옮길 수 있었나 (2026-09-22 정정)** — 앞선 판의 주석은 "모바일은 못 옮긴다"고 적었다.
/// 근거로 든 것은 `AingSharedStorage.temporary(name:)` 의 `safe` 필터(`AingAppGroup.swift:54`)가 이름에서
/// `/` 를 걸러낸다는 것이었고, 그건 사실이다. 그런데 막힌 것은 **그 편의 생성자 하나**일 뿐이다 —
/// `AingSharedStorage.init(directory:defaultsSuiteName:isAppGroup:)` 는 public 이라 테스트가 스위트 이름을
/// 직접 줄 수 있다. 프로덕션 필터는 손대지 않은 채(`Sources/` 는 이 작업의 담당이 아니다) 테스트만 비켜 간다.
///
/// **그 전엔 실제로 어땠나(실측)** — 앞선 판도 이름은 유계였다. `BaseSignUpConfirmTests` 를 두 번 돌려
/// 받은 파일은 `…makeHarness-createTeam-responder--L98-0-1bmqazhbm8r16.plist` 꼴인데, 꼬리
/// `1bmqazhbm8r16` 은 난수가 아니라 `fingerprint("makeHarness(createTeam:responder:)-L98-0")` 다
/// (파이썬으로 FNV-1a 를 다시 계산해 7개 이름이 글자까지 일치했다). 실행마다 개수가 는 것은 이름이
/// 난수여서가 아니라, `BaseStub.nextStorageIndex` 가 주는 **일련번호를 어느 테스트가 집어 가느냐가
/// 병렬 스케줄에 따라 달라서** — 1회차는 {0,1,6,9}, 2회차는 {2,4,7} 이 더 생겼다. 상한은 그 자리를 부른
/// 횟수(13)라 무한히 늘지는 않지만, **상한이 0 이 아닌 것 자체가** 회귀 게이트를 막았다:
/// "~/Library/Preferences 항목 수가 안 는다"는 단언은 새 파일이 하나라도 생기면 못 건다.
///
/// **왜 "끝나고"가 아니라 "시작할 때" 지우는가** — removePersistentDomain 도 파일 직접 삭제도 cfprefsd 를
/// 못 이긴다. 2026-09-22 실측: rpd + removeItem 을 둘 다 부르는데도 1,110개가 값을 품은 채 되살아났다
/// (테스트가 끝난 뒤 cfprefsd 가 자기 메모리 사본을 다시 flush 한다). 그래서 정리를 앞으로 옮긴다.
///
/// **주의: 유계 이름은 같은 타깃을 동시에 두 번 돌리면 공유된다.** 스위트 이름을 pid 로 가를 수는 없다 —
/// 가르는 순간 다시 무계가 되기 때문이다. 대신 `root` 가 pid 폴더라 **파일 자리**는 갈리고,
/// 2시간 지난 남의 판만 치운다(맥 쪽과 같은 장치).
enum MobileTestScratch {

    /// 프로세스당 한 번 계산 = 프로세스당 한 번 청소. static let 이라 스레드 안전하다(swift_once).
    static let root: URL = {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("check-mobile-tests", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        // 지난 실행이 남긴 판만 치운다. 2시간 컷오프 — 지금 도는 다른 테스트 프로세스를 안 날린다.
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

    /// 유계 이름. 예전엔 `AingSharedStorage.temporary(name:)` 에 넣는 짧은 이름이었고 지금은 경로 조각이다.
    ///
    /// `label` 은 **한 테스트가 저장소를 둘 이상 쓸 때** 서로 안 겹치게 하는 꼬리표다. 안 붙이면 두
    /// 저장소가 같은 것이 되어, 예컨대 `BaseSessionHardeningTests.installationIDSurvivesBrokenKeychain`
    /// 의 `otherStorage.defaults.string(...) == nil` 처럼 **서로 다름을 전제한 단언**이 조용히 무의미해진다.
    /// `@Test(arguments:)` 파라미터화 테스트는 같은 #function 으로 동시에 도니 인자값을 label 에 넣어라.
    ///
    /// 호출자는 반드시 `function: String = #function` 을 파라미터로 받아 여기까지 **이어 넘겨야** 한다.
    /// 헬퍼 본문에서 그냥 부르면 #function 이 그 헬퍼 이름으로 굳어 파일 안 모든 테스트가 한 저장소를 공유한다.
    static func name(_ label: String = "", function: String = #function) -> String {
        slug(function, label)
    }

    /// 유계 이름을 가진 임시 저장소. 파일 폴더와 UserDefaults 스위트가 둘 다 `root` 안에 떨어진다.
    ///
    /// `AingSharedStorage.temporary(name:)` 를 안 지나는 이유는 머리 주석에 있다(그 함수는 이름에서 `/` 를
    /// 걸러내 스위트를 ~/Library/Preferences 로 돌려보낸다). 나머지 세 값의 뜻은 그 함수와 같다.
    static func storage(_ label: String = "", function: String = #function) -> AingSharedStorage {
        let suite = suitePath(label, function: function)
        let storage = AingSharedStorage(
            directory: root.appendingPathComponent("s-" + slug(function, label), isDirectory: true),
            defaultsSuiteName: suite,
            isAppGroup: false
        )
        // 못 열면 `AingSharedStorage.defaults` 가 **조용히 .standard 로 접는다** — 그러면 테스트끼리
        // 값이 섞이고도 초록이다. 접히기 전에 여기서 죽는 편이 낫다.
        precondition(UserDefaults(suiteName: suite) != nil, "스크래치 스위트를 못 열었다: \(suite)")
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: storage.directory)
        storage.ensureDirectory()
        return storage
    }

    /// 유계 이름을 가진 격리 UserDefaults. `AingSharedStorage` 가 필요 없는 자리(예: 화면 모드 저장소)용.
    static func defaults(_ label: String = "", function: String = #function) -> UserDefaults {
        let suite = suitePath(label, function: function)
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("스크래치 스위트를 못 열었다: \(suite)")
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// `defaults(_:function:)`·`storage(_:function:)` 가 쓰는 스위트 이름(=절대 경로).
    /// tearDown 이 이름을 알아야 할 때 쓴다.
    static func suiteName(_ label: String = "", function: String = #function) -> String {
        suitePath(label, function: function)
    }

    private static func suitePath(_ label: String, function: String) -> String {
        root.appendingPathComponent("d-" + slug(function, label)).path
    }

    /// 유계 이름을 가진 임시 폴더(파일용). 재실행이 같은 폴더를 덮어쓴다.
    static func directory(_ label: String = "", function: String = #function) -> URL {
        let url = root.appendingPathComponent("f-" + slug(function, label), isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 파일 이름 한 조각으로 쓸 수 있는 글자(ASCII 영숫자 · `-` `_`)만 남기면서
    /// 서로 다른 테스트가 서로 다른 이름을 갖도록 만든다.
    ///
    /// 한국어 테스트 이름이 이 저장소에 흔한데 비ASCII 는 여기서 통째로 버려진다 — 그대로 넘기면
    /// 서로 다른 한국어 테스트가 전부 같은 빈 이름으로 무너진다. 그래서 버려질 글자가 하나라도 있으면
    /// 원본의 지문을 붙여 신원을 되살린다.
    private static func slug(_ function: String, _ label: String) -> String {
        let raw = function.replacingOccurrences(of: "()", with: "")
            + (label.isEmpty ? "" : "-" + label)

        var mapped = ""
        var lastWasDash = false
        for character in raw {
            let keep = character.isASCII && (character.isLetter || character.isNumber
                || character == "-" || character == "_")
            if keep {
                mapped.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                mapped.append("-")
                lastWasDash = true
            }
        }
        while mapped.hasPrefix("-") { mapped.removeFirst() }
        while mapped.hasSuffix("-") { mapped.removeLast() }

        // 손실이 있었으면(=글자가 바뀌었거나 잘렸으면) 원본 지문을 붙인다. 손실이 없으면 mapped == raw 라
        // 이름만으로 이미 유일하다.
        let lossless = (mapped == raw) && mapped.count <= 80
        if lossless { return mapped }
        // 한국어 이름은 필터를 지나면 구분자만 남는다(`설정이_저장된다` → `_`). 그런 머리는 읽는 데
        // 보탬이 안 되니 버리고 지문만 쓴다.
        var head = mapped.count <= 60 ? mapped : String(mapped.prefix(60))
        if head.allSatisfy({ $0 == "-" || $0 == "_" }) { head = "" }
        return head.isEmpty ? "t-\(fingerprint(raw))" : "\(head)-\(fingerprint(raw))"
    }

    /// FNV-1a 64비트. **프로세스 간에 값이 변하지 않는 것**이 여기서 유일하게 중요한 성질이다.
    /// Swift 의 `hashValue` 는 실행마다 시드가 달라(2026-09-22 실측: 같은 문자열이 두 실행에서
    /// -5473928194107074901 / -2053000808844451785) 쓰면 이름이 다시 무계가 된다 — 바로 이 파일이 막으려는 병이다.
    private static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }
}
