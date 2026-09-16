import Foundation

/// 착용 캐릭터를 **서버 기준**으로 맞출 때 무엇을 할지(순수 판정 — 스토어·네트워크 없이 값으로 잰다).
///
/// **왜 서버 기준인가**(v0.3.30, 폰과 공존): 0.3.16~0.3.29 의 맥은 실행·로그인 때마다 로컬 선택
/// (`check.character.selected`)을 `set_character` 로 **밀었다**. 기기가 맥 하나일 때는 그게 "오프라인에서 바꾼
/// 선택을 잃지 않는" 장치였지만, 폰에서 캐릭터를 바꿀 수 있게 되면 맥이 다음에 켜질 때 **말없이 되돌리는** 장치가
/// 된다. 그래서 이제 실행·로그인·팝오버 때는 **읽기만** 하고, 쓰기는 사용자가 이 맥에서 직접 고른 순간뿐이다.
///
/// **옮겨 가기(한 번만)**: 서버가 null 인 것은 두 가지로 읽힌다 — (가) 한 번도 안 밀었다 (나) 기본으로 되돌렸다.
/// 둘을 서버 값만으로는 가를 수 없어서, 이 버전으로 **처음** 판정할 때만 (가)로 읽어 로컬의 비기본 선택을 한 번
/// 밀고(0.3.13~ 사용자의 기존 선택 보존), 그 뒤로는 언제나 (나)로 읽는다. 그 1회 도장이 `migrationDefaultsKey` 다.
enum CharacterSyncDecision: Equatable {
    /// 로컬이 이미 목표와 같다 — 아무것도 안 한다(방송도 없다).
    case keep
    /// 로컬 선택을 이 id 로 바꾸고 방송한다(메뉴바·헤더·오버레이가 그 자리에서 다시 그려진다).
    case adopt(String)
    /// 옮겨 가기: 서버에 이 id 를 **한 번** 민다. 로컬은 건드리지 않는다.
    case migrate(String)

    /// 옮겨 가기 판정을 이미 끝냈는가의 도장(UserDefaults, Bool).
    /// 이름이 곧 진단 어휘다 — 이 키가 true 면 "이 맥은 서버를 따른다".
    static let migrationDefaultsKey = "check.character.serverAuthorityMigrated"

    /// 판정 본체.
    ///
    /// - serverID: `profiles.character`. nil·빈 문자열·공백 = 기본(아잉). 서버가 이미 그렇게 접지만(set_character
    ///   머리말) 클라가 한 번 더 접는다 — "기본"을 표현하는 모양이 둘이면 비교가 갈린다.
    /// - localID: `CharacterSelection.selectedID`(이미 모르는 id 를 아잉으로 접은 값).
    /// - migrated: 옮겨 가기 도장.
    /// - isKnown: 이 빌드 카탈로그에 있는 id 인가. 모르는 id(폰이 먼저 받은 새 캐릭터 등)는 아잉으로 접는다 —
    ///   `CharacterSelection.select` 가 모르는 id 를 저장하지 않으니, 접지 않으면 되돌아올 선택도 없이 조용히 무시된다.
    /// - isUnlocked: 가진 캐릭터인가(`WorkTimerStore.isCharacterUnlocked` — 상점을 아직 못 읽었으면 언제나 true).
    ///   서버는 `set_character` 에서 소유를 확인하므로 정상 경로에선 늘 true 지만, 운영자가 소유 행을 지운 경우 등
    ///   **안 가진 값이 서버에 남아 있으면** 로컬은 아잉으로 접는다(내 화면에 산 적 없는 캐릭터가 서지 않게).
    static func decide(
        serverID: String?,
        localID: String,
        migrated: Bool,
        isKnown: (String) -> Bool,
        isUnlocked: (String) -> Bool
    ) -> CharacterSyncDecision {
        let server = normalized(serverID)
        if server == nil, !migrated, localID != CharacterCatalog.builtInAingID {
            return .migrate(localID)
        }
        var target = server ?? CharacterCatalog.builtInAingID
        if !isKnown(target) || !isUnlocked(target) {
            target = CharacterCatalog.builtInAingID
        }
        return target == localID ? .keep : .adopt(target)
    }

    /// 옮겨 가기 밀기의 응답이 **판정을 끝냈는가**. 서버가 대답한 어휘면 끝이다 — 다시 밀어도 같은 대답이 온다.
    /// nil(네트워크 실패·취소·계정 전환)이거나 `unauthorized` 면 끝나지 않았다: 도장을 안 찍어 다음 판정에서 다시 민다.
    /// 도장을 먼저 찍으면 실패한 밀기 뒤 다음 실행이 서버 null 을 "기본으로 되돌렸다"로 읽어 사용자의 선택을 지운다.
    static func migrationSettled(byStatus status: String?) -> Bool {
        switch status {
        case "ok", "not_owned", "unknown_character", "no_profile": return true
        default: return false
        }
    }

    static func normalized(_ id: String?) -> String? {
        guard let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// 서버 착용값을 읽는 **때**. 스로틀은 팝오버에만 건다 — 실행·로그인은 세션이 생기는 순간이라 늘 읽는다.
enum CharacterSyncReason: Equatable {
    /// 저장 세션 활성화(실행당 1회).
    case launch
    /// 로그인 마무리(`completeSignIn`).
    case signIn
    /// 팝오버 열기(60초 스로틀) — 폰에서 바꾼 캐릭터가 맥에 반영되는 길.
    case popover
}
