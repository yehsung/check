import Foundation

/// 폰 앱·위젯이 함께 보는 **공용 저장소**(App Group 컨테이너 + 공용 UserDefaults suite).
///
/// 값은 `ios/project.yml` 의 `com.apple.security.application-groups` 와 글자 그대로 같다(`CheckMobileIdentifiers.appGroupID`).
/// 파일(위젯 스냅샷 · 할 일)은 컨테이너 폴더에, 비밀이 아닌 계정 값(userID · 이메일)은 공용 suite 에 둔다.
/// 토큰은 여기 두지 않는다 — 키체인(`AingKeychain`)이다.
public enum AingAppGroup {
    public static let identifier = CheckMobileIdentifiers.appGroupID

    /// App Group 컨테이너. entitlement 가 없는 프로세스(macOS `swift test` 등)에서는 nil 이다.
    public static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// 공용 저장소 한 벌. **주입 가능한 값**이라 테스트·데모는 임시 폴더와 전용 suite 를 쓴다
/// (실제 App Group 을 테스트가 더럽히면 다음 실행의 위젯이 가짜 사람을 그린다).
public struct AingSharedStorage: Sendable, Equatable {
    /// 공용 파일 폴더(위젯 스냅샷 · 할 일 파일).
    public let directory: URL
    /// 공용 UserDefaults suite 이름. nil 이면 `.standard`.
    public let defaultsSuiteName: String?
    /// 진짜 App Group 컨테이너인가(false = 위젯이 이 폴더를 못 읽는다 — 서명 안 된 빌드·테스트·데모).
    public let isAppGroup: Bool

    public init(directory: URL, defaultsSuiteName: String?, isAppGroup: Bool) {
        self.directory = directory
        self.defaultsSuiteName = defaultsSuiteName
        self.isAppGroup = isAppGroup
    }

    /// 앱·위젯 프로덕션 조립. 컨테이너를 못 얻으면(엔타이틀먼트 없는 빌드) 앱 자신의 Application Support 로 접는다 —
    /// 앱은 그대로 돌고 위젯만 "앱에서 로그인해 주세요"를 본다(틀린 데이터를 보이는 것보다 낫다).
    public static func live(fileManager: FileManager = .default) -> AingSharedStorage {
        if let container = AingAppGroup.containerURL(fileManager: fileManager) {
            return AingSharedStorage(
                directory: container.appendingPathComponent("aing-check", isDirectory: true),
                defaultsSuiteName: AingAppGroup.identifier,
                isAppGroup: true
            )
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return AingSharedStorage(
            directory: base.appendingPathComponent("aing-check-shared", isDirectory: true),
            defaultsSuiteName: nil,
            isAppGroup: false
        )
    }

    /// 테스트·데모용: 임시 폴더 + 이름을 가진 전용 suite. 같은 이름이면 같은 저장소다.
    public static func temporary(name: String, fileManager: FileManager = .default) -> AingSharedStorage {
        let safe = name.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
        return AingSharedStorage(
            directory: fileManager.temporaryDirectory.appendingPathComponent("aing-shared-\(safe)", isDirectory: true),
            defaultsSuiteName: "com.yehsung.aingcheck.scratch.\(safe)",
            isAppGroup: false
        )
    }

    /// 공용 UserDefaults. suite 를 못 열면 `.standard`(값이 앱 밖으로 안 나갈 뿐 앱은 돈다).
    public var defaults: UserDefaults {
        guard let defaultsSuiteName else { return .standard }
        return UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    }

    /// 위젯이 읽는 유일한 파일(`WidgetSnapshot`).
    public var widgetSnapshotURL: URL {
        directory.appendingPathComponent("widget-snapshot.json", isDirectory: false)
    }

    /// 사용자별 할 일 파일(`TodoSharedFile`). 이름 규칙은 맥 `TodoFileStore.defaultURL` 과 같다(`todos.<uid>.json`).
    public func todoFileURL(userID: String?) -> URL {
        TodoSharedFile.url(in: directory, userID: userID)
    }

    /// 폴더를 만든다(없으면). 실패는 삼킨다 — 쓰기 쪽이 다시 실패를 본다.
    public func ensureDirectory(fileManager: FileManager = .default) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// 공용 suite 에 두는 키(비밀 아님). 로그아웃은 `userScopedKeys` 를 지운다.
public enum AingSharedKeys {
    /// 로그인한 사용자 id. 위젯은 이 값으로 할 일 파일을 고른다.
    public static let userID = "aingcheck.session.userID"
    /// 로그인 이메일(로그인 중 프로필 표시 · 세션 만료 뒤 로그인 화면 채우기). 스스로 로그아웃하면 지운다.
    public static let email = "aingcheck.session.email"
    /// 마지막 register_device 성공 시각(1시간 스로틀).
    public static let deviceRegisteredAt = "aingcheck.device.registeredAt"
    /// 마지막 register_device 에 실은 값의 서명(빌드·APNs 토큰이 바뀌면 스로틀을 무시하고 다시 보낸다).
    public static let deviceRegisteredSignature = "aingcheck.device.registeredSignature"
    /// 마지막으로 받은 APNs 토큰(hex 소문자). 실행 사이에 유지해 foreground 재등록이 토큰을 잃지 않게 한다.
    public static let apnsToken = "aingcheck.push.apnsToken"

    /// 로그아웃·만료 때 지우는 키. 이메일은 만료 뒤 다시 들어올 때 채우려고 여기서 빼고, 스스로 로그아웃할 때만 따로 지운다.
    /// APNs 토큰은 기기 값이라 남긴다.
    public static let userScopedKeys: [String] = [userID, deviceRegisteredAt, deviceRegisteredSignature]
}
