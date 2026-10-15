import Foundation

// MARK: - 맥 앱 판(版) — Developer ID(brew·DMG) / 맥 앱스토어 (v0.3.51)
//
// 같은 소스에서 맥 앱이 **두 벌** 나간다.
//  · `.developerID` — 지금까지의 판. 번들 `kingcheck`, 샌드박스 없음, brew·DMG 로 스스로 업데이트한다.
//  · `.appStore`    — 맥 앱스토어 판. 번들 `com.yehsung.aingcheck`(아이폰 앱과 유니버설 구매), App Sandbox,
//                     업데이트는 앱스토어가 한다.
//
// 가르는 것은 **컴파일 플래그 하나**다: 앱스토어 패키징 스크립트가 `swift build -Xswiftc -DCHECK_MAS` 로 빌드한다.
// 기본 빌드·`swift test`·아이폰 Xcode 빌드는 언제나 `.developerID` 다(그쪽 동작은 한 톨도 바뀌지 않는다).
//
// ## 이 파일은 **판정표**다 — 그리고 판정표만으로는 모자란다
// 런타임에 "이 판은 무엇을 하는가"를 묻는 자리는 전부 아래 `MacEdition` 의 속성을 본다. 그래서 기본 빌드의 테스트가
// `.appStore` 값을 주입해 앱스토어 판의 갈래(업데이트 안내 끔 · 공지 링크 거름 · 동의 전 스캔 금지 …)를 그대로 돌려 본다.
// 하지만 **바이너리에서 코드 자체가 사라져야 하는** 경로가 따로 있다: 자가 업데이트(brew·DMG 교체 스크립트·GitHub 폴링)와
// 외부 프로세스 실행(로그인 셸 · `codex app-server` · `agy` · `/usr/bin/security`). 표가 "안 한다"고 말해도 코드가 남아
// 있으면 심사관은 바이너리에서 그 문자열을 본다(심사 지침 2.4.5(vii) · 2.5.2). 그 경로는 `#if !CHECK_MAS` 로 **물리적으로**
// 지우고, 소스 계약 테스트(V0351MacAppStoreEditionTests)가 그 울타리가 제자리에 있는지 되묻는다.

/// 맥 앱이 어느 판으로 빌드됐는가. **판정표** — 앱스토어 판이 끄거나 바꾸는 것들이 전부 여기 한 곳에 있다.
package enum MacEdition: String, CaseIterable, Equatable, Sendable {
    /// brew·DMG 로 나가는 판(번들 `kingcheck`).
    case developerID
    /// 맥 앱스토어 판(번들 `com.yehsung.aingcheck`).
    case appStore

    /// 지금 이 바이너리의 판. **컴파일 시점에 정해진다**(`-Xswiftc -DCHECK_MAS`).
    package static let current: MacEdition = {
        #if CHECK_MAS
        return .appStore
        #else
        return .developerID
        #endif
    }()

    /// 이 판의 번들 식별자(진단·다른 판 감지용 — 앱이 자기 번들 ID 를 서버로 보내지는 않는다).
    package var bundleIdentifier: String {
        switch self {
        case .developerID: return "kingcheck"
        case .appStore: return "com.yehsung.aingcheck"
        }
    }

    /// 같은 맥에서 동시에 돌면 안 되는 **다른 판**의 번들 식별자.
    ///
    /// 앱스토어 판만 본다 — 둘이 함께 켜지면 같은 맥이 서버에 기기 두 대로 잡히고(기기 ID 가 컨테이너마다 따로다),
    /// 전역 단축키 하나에 두 앱이 함께 근무를 토글한다(Carbon 핫키는 겹쳐도 둘 다 받는다). Developer ID 판은 지금 그대로
    /// 둔다(그쪽 동작은 바꾸지 않는다는 결정 — 앱스토어 판이 생기기 전 설치본은 이 표를 모른다).
    package var otherEditionBundleIdentifiers: [String] {
        switch self {
        case .developerID: return []
        case .appStore: return [MacEdition.developerID.bundleIdentifier]
        }
    }

    /// 같은 맥에 **설치된 앱스토어 판**(앱스토어가 설치한 사본 — 영수증이 있다)이 있으면 이 판이 **물러나는가**(v0.3.53).
    ///
    /// 물러남 = 근무·단축키·감시를 하나도 켜지 않고 안내 창 하나만 띄운다(실행 중에 앱스토어 판이 켜지면 근무를 마무리하고
    /// 그 모드로 다시 뜬다). 두 판이 함께 돌면 같은 맥이 서버에 기기 두 대로 잡혀 토큰이 두 번 집계되고, 전역 단축키 하나에
    /// 두 앱이 함께 근무를 토글한다 — 설치는 못 막으니(앱스토어 설치기 · DMG 드래그) 실행을 막는다.
    /// Developer ID 판만 물러난다. 앱스토어 판의 동작은 0.3.52 심사본 그대로다(다른 판이 돌면 한 번 알리는 경고만 있다) — 판정·창·
    /// 지우기 코드는 그 판에서 **컴파일되지 않는다**(`#if !CHECK_MAS` — `AppStoreEditionRetirement`).
    package var retiresWhenAppStoreEditionInstalled: Bool { self == .developerID }

    // MARK: 업데이트 (심사 지침 2.4.5(vii) — 앱스토어 앱은 앱스토어로만 업데이트한다)

    /// 이 판이 **스스로 새 버전을 알리고 설치하는가**: brew upgrade · DMG 자가 교체 · GitHub 릴리스 폴링 ·
    /// 서버 `app_latest_release` 감시 · "새 버전" 배너 · 캐릭터 말풍선 · 메뉴바 점.
    /// 앱스토어 판은 전부 끈다 — 업데이트는 앱스토어가 한다. 서버 공지 카드는 판과 무관하게 남는다(링크만 거른다).
    package var updatesItself: Bool { self == .developerID }

    // MARK: 샌드박스에서 못 하는 것 (외부 프로세스)

    /// Codex 계정 사용량 프로브(로그인 셸로 PATH·CODEX_HOME 을 묻고 `codex app-server` 를 띄운다).
    /// 샌드박스의 자식 프로세스는 부모의 샌드박스를 물려받아 셸 설정도 `~/.codex` 쓰기도 막힌다 — 그리고 남의 실행 파일을
    /// 띄우는 것 자체가 심사 지침 2.5.2 다. 앱스토어 판은 계정값 없이 **로컬 기록만** 센다(서버 '계정 우선' 규칙의 입력이
    /// 없을 뿐, 같은 사람의 brew 판 맥이 있으면 그쪽 계정값이 그대로 쓰인다).
    package var probesCodexAccount: Bool { self == .developerID }

    /// Claude 리밋(남의 키체인 항목 `Claude Code-credentials` 를 시스템 도구 `/usr/bin/security` 로 읽는다).
    ///
    /// ★ 2026-10-14 결정: 앱스토어 판에도 **남긴다** — 사용자가 "AI 리밋은 예외 권한으로 기능 그대로 신청"을 골랐고, 샌드박스
    ///   실측에서 상속 샌드박스 안의 `security` 가 프롬프트 없이 읽었다. Codex 리밋처럼 **AI 기록 읽기 동의 뒤에만** 돈다.
    ///   심사에서 문제가 되면 이 한 줄을 `self == .developerID` 로 바꾼다(러너가 이 값을 본다).
    package var readsClaudeLimits: Bool { true }

    /// 안티그래비티 리밋(`agy` CLI 를 띄운다). 앱스토어 판에서 뺀다.
    package var readsAntigravityLimits: Bool { self == .developerID }

    /// Codex 리밋(`~/.codex/auth.json` 을 **읽기만** 해서 제공자에게 사용률을 묻는다).
    ///
    /// ★ 2026-10-14 결정: 앱스토어 판에도 **남긴다.** 사용자가 "토큰 집계·AI 리밋은 예외 권한으로 신청(기능 그대로, 반려 위험
    ///   감수)"을 골랐고, 이 리더는 외부 프로세스 없이 파일 하나를 읽는 것이라 `/.codex/` 읽기 전용 임시 예외 하나로 돈다.
    ///   대신 **AI 기록 읽기 동의**(`asksBeforeReadingAITools`) 뒤에만 돈다. 심사에서 이 리더가 문제가 되면 이 한 줄을
    ///   `self == .developerID` 로 바꾸면 앱스토어 판에서 통째로 빠진다(러너가 이 값을 본다).
    package var readsCodexLimits: Bool { true }

    // MARK: 동의 (심사 지침 2.4.5(iii) · 5.1.1(ii) · 2.5.14)

    /// 로그인 시 자동 실행을 **사용자가 켰을 때만** 등록하는가. 앱스토어 판은 기본 꺼짐이고 첫 실행에 한 번 묻는다
    /// (2.4.5(iii) "may not auto-launch … at startup or login without consent"). Developer ID 판은 지금처럼 기본 켜짐이다.
    package var asksBeforeLaunchAtLogin: Bool { self == .appStore }

    /// AI 도구의 로컬 사용 기록(`~/.claude`·`~/.codex`·`~/.gemini`·Orca)을 **동의를 받은 뒤에만** 읽는가.
    /// 앱스토어 판은 첫 실행 안내에서 [허용]을 누르거나 설정에서 켜기 전까지 한 바이트도 읽지 않는다(스캔·리밋·진단 전부).
    package var asksBeforeReadingAITools: Bool { self == .appStore }

    /// 첫 실행 안내(로그인 시 자동 실행 + AI 기록 읽기 동의를 한 화면에서 묻는다)를 띄우는 판인가.
    package var showsFirstRunConsent: Bool { asksBeforeLaunchAtLogin || asksBeforeReadingAITools }

    // MARK: 키체인

    /// 세션 토큰을 담는 키체인 generic password 의 service.
    ///
    /// 앱스토어 판은 **다른 이름**을 쓴다. 같은 맥에 brew 판이 있으면 그 판이 만든 `kingcheck` 항목이 로그인 키체인에 있고,
    /// 그 항목의 ACL 은 Developer ID 서명을 믿는다 — 앱스토어 판이 같은 이름으로 찾으면 접근 허용 창이 뜨거나 `SecItem`
    /// 호출이 멈춘다(이 저장소가 남의 항목에서 실제로 겪었다). 나아가 쓰기가 실패하면 금고 규약("쓰기 실패 ⇒ 지운다")이 brew 판의
    /// 항목을 지워 그 판을 로그아웃시킬 수 있다. 이름을 가르면 두 판이 서로의 항목을 **아예 건드리지 않는다**(대가: 앱스토어 판으로
    /// 옮겨 오는 사람은 한 번 다시 로그인한다 — 어차피 샌드박스 컨테이너는 빈 상태로 시작한다).
    package var keychainService: String {
        switch self {
        case .developerID: return "kingcheck"
        case .appStore: return "kingcheck.mas"
        }
    }

    // MARK: 서버 공지 링크

    /// 서버 공지 카드가 이 링크를 QR·캡션으로 보여 줘도 되는가.
    ///
    /// 앱스토어 판은 **앱스토어 주소만** 남긴다(https · 앱스토어 상품 페이지 호스트). 공지 한 행은 모든 빌드에 가므로 운영자가
    /// "brew 로 업데이트하세요"·"DMG 받기" 공지를 걸면 앱스토어 판에 바깥 설치 경로가 뜬다 — 2.4.5(vii) 의 취지에 어긋난다.
    /// 본문·제목은 그대로 보인다(거르는 것은 링크와 그 버튼 문구뿐이다). Developer ID 판은 지금처럼 전부 보여 준다.
    package func allowsNoticeLink(_ link: String) -> Bool {
        switch self {
        case .developerID:
            return true
        case .appStore:
            guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
                  components.scheme?.lowercased() == "https",
                  components.user == nil, components.password == nil,
                  let host = components.host?.lowercased()
            else { return false }
            return Self.appStoreLinkHosts.contains(host)
        }
    }

    /// 앱스토어 판이 공지 링크로 받아 주는 호스트. 앱스토어 상품 페이지 하나뿐이다 — 호스트는 `CheckAppLinks.iosAppStore` 에서
    /// 뽑는다(앱스토어 주소는 그 파일 한 곳에만 적는다는 계약 — V0340).
    package static var appStoreLinkHosts: Set<String> {
        Set([CheckAppLinks.iosAppStore.host?.lowercased()].compactMap { $0 })
    }
}

extension AppNotice {
    /// 이 판에서 보여 줄 공지. 링크가 이 판에서 허용되지 않으면 **링크와 그 버튼 문구만** 떼고 제목·본문은 그대로 둔다
    /// (QR 판도 캡션도 사라지고, 카드 높이는 QR 없는 예산으로 접힌다 — `AppNoticeCard.qrImage` 가 nil 을 낸다).
    /// id 는 그대로라 닫음 표식(기기별)이 판과 무관하게 같은 공지를 가리킨다.
    package func filtered(for edition: MacEdition) -> AppNotice {
        guard let link = linkURL, !edition.allowsNoticeLink(link) else { return self }
        return AppNotice(id: id, title: title, body: body, linkURL: nil, linkLabel: nil)
    }
}

// MARK: - AI 도구 기록 읽기 동의 (앱스토어 판)

/// 앱스토어 판의 **AI 도구 기록 읽기 동의**. 키 하나(이 맥의 UserDefaults — 샌드박스에서는 컨테이너)에 산다.
///
/// 값이 없으면 **동의 안 함**이다(앱스토어 판). 첫 실행 안내의 [허용] 또는 설정의 스위치만 켠다.
/// Developer ID 판은 키를 **읽지도 않고** 언제나 허용이다 — 그 판의 동작(토큰 집계는 늘 켜짐 · 끄는 길은 운영자의 서버 수집
/// 설정)은 바뀌지 않는다.
///
/// 끄면 **읽지도 올리지도 않는다**: 토큰 스캔(`TokenUsageStore`)·업로드·일별 업로드·스캔 하트비트·Codex 진단·리밋 읽기가
/// 전부 이 판정을 본다. 화면에서 감추는 게 아니다.
package enum AIToolDataConsent {
    /// 동의 키(Bool). 없으면 거절로 읽는다.
    package static let key = "check.mas.aiToolDataConsent"

    /// 이 판에서 지금 AI 도구 기록을 읽어도 되는가.
    package static func isAllowed(edition: MacEdition, defaults: UserDefaults) -> Bool {
        guard edition.asksBeforeReadingAITools else { return true }
        return defaults.bool(forKey: key)
    }
}

// MARK: - 실제 홈 (샌드박스 컨테이너가 아니라)

#if os(macOS)
/// AI 도구 기록을 찾을 **사용자의 진짜 홈 폴더**.
///
/// 샌드박스 안에서는 `FileManager.homeDirectoryForCurrentUser` · `NSHomeDirectory()` · `$HOME` · `~` 확장이 전부
/// **컨테이너**(`~/Library/Containers/<번들ID>/Data`)를 가리킨다. 그 아래에는 `.claude` 가 없으니 스캐너는 오류 없이
/// 0 을 내고, 업로드 가드(합계 0 은 올리지 않는다)가 그 0 을 조용히 삼켜 그 사람은 순위판에서 소리 없이 사라진다.
/// 그래서 앱스토어 판은 **암호 데이터베이스**(`getpwuid_r`)에서 홈을 읽는다 — 샌드박스가 바꾸지 않는 값이다.
/// 엔타이틀먼트의 읽기 전용 임시 예외(`/.claude/`·`/.codex/`·`/.gemini/`·`/Library/Application Support/orca/`)는
/// **이 진짜 홈에 대한 상대 경로**라, 여기서 구한 홈 아래 경로만 열린다.
///
/// Developer ID 판은 지금 그대로 `homeDirectoryForCurrentUser` 다(샌드박스가 없어 같은 값이지만, 동작을 한 글자도 바꾸지 않는다).
package enum AIToolHome {
    /// 이 판에서 AI 도구 기록을 찾을 홈.
    package static func current(edition: MacEdition = .current) -> URL {
        switch edition {
        case .developerID: return FileManager.default.homeDirectoryForCurrentUser
        case .appStore: return realHome()
        }
    }

    /// 사용자의 진짜 홈. 암호 DB → (없으면) 컨테이너 경로에서 잘라 냄 → (그것도 아니면) 프로세스 홈.
    package static func realHome() -> URL {
        resolve(passwdHome: passwdHomeDirectory(), processHome: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// 순수 판정(테스트가 컨테이너 경로를 직접 먹인다).
    ///  ① 암호 DB 의 홈이 절대 경로면 그것.
    ///  ② 아니면 프로세스 홈이 샌드박스 컨테이너(`…/Library/Containers/<id>/Data`)일 때 그 앞부분.
    ///  ③ 둘 다 아니면 프로세스 홈 그대로.
    package static func resolve(passwdHome: String?, processHome: URL) -> URL {
        if let passwdHome, passwdHome.hasPrefix("/"), passwdHome.count > 1 {
            return URL(fileURLWithPath: passwdHome, isDirectory: true)
        }
        let path = processHome.path
        if let marker = path.range(of: containerMarker), marker.lowerBound > path.startIndex {
            return URL(fileURLWithPath: String(path[..<marker.lowerBound]), isDirectory: true)
        }
        return processHome
    }

    /// 샌드박스 컨테이너 경로의 표지.
    package static let containerMarker = "/Library/Containers/"

    /// 암호 DB 의 이 사용자 홈(`getpwuid_r` — 스레드 안전판). 못 읽으면 nil.
    package static func passwdHomeDirectory() -> String? {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        let suggested = sysconf(Int32(_SC_GETPW_R_SIZE_MAX))
        var buffer = [CChar](repeating: 0, count: suggested > 0 ? suggested : 4096)
        let status = getpwuid_r(getuid(), &record, &buffer, buffer.count, &result)
        guard status == 0, result != nil, let directory = record.pw_dir else { return nil }
        let home = String(cString: directory)
        return home.isEmpty ? nil : home
    }
}
#endif
