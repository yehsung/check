import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 기본 아바타 = 착용 캐릭터(SPEC 작업 M · 2026-09-20 사용자 요청) — 맥.
//
// "유저들 프로필 기본값으로 장착중인 캐릭터로 뜨게 해줘. 지금은 별명의 첫글자가 들어가 있잖아. 그거 말고.
//  프로필 사진 직접 업로드한 사람은 업로드한 사진으로 뜨는거 유지하고."
//
// 규칙(정본은 코어 `AppUserCharacterDirectory` — 폰과 한 벌): 사진 → 착용 캐릭터(null = 아잉) → **모를 때만** 이니셜.
// 모르는 캐릭터 id 는 이니셜 · 서버에 함수가 없으면(404) 조용히 빈 표 = 이니셜 · 로그아웃하면 표를 비운다 · 내 칸은 이 맥의 착용 선택.
// 여기서는 맥의 배선을 잰다: 스토어(언제 묻고 언제 비우는가) · 창 루트 환경값 · 호출부 id(소스 계약) · 그림(픽셀).
//
// 네트워크는 `MessageReadStubProtocol`(호스트별 스크립트 · 요청 기록)을 쓴다. 스크립트하지 않은 RPC 는 200 `[]` 다.
// ★ 사용자 id·이름은 전부 합성이다(퍼블릭 저장소).

private let avMe = MessageReadFixture.me
private let avFox = "00000000-0000-4000-8000-00000335f001"
private let avPlain = "00000000-0000-4000-8000-00000335f002"
private let avPhoto = "00000000-0000-4000-8000-00000335f003"
private let avFuture = "00000000-0000-4000-8000-00000335f004"
private let avStranger = "00000000-0000-4000-8000-00000335f005"
private let avNextUser = "00000000-0000-4000-8000-00000335f006"
private let avRPC = "app_user_characters"

/// 나(null) · 여우 · 안 고른 사람(null) · 사진을 올린 유령 · 이 빌드가 모르는 새 캐릭터.
private let avRowsJSON = """
[{"user_id":"\(avMe)","character":null},
 {"user_id":"\(avFox)","character":"fox"},
 {"user_id":"\(avPlain)","character":null},
 {"user_id":"\(avPhoto)","character":"ghost"},
 {"user_id":"\(avFuture)","character":"dragon"}]
"""

/// 스토어 하나(고유 호스트 · 고유 착용 선택 도메인 · 전용 방송 · 손으로 돌리는 시계).
@MainActor
private func avStore(
    _ label: String,
    handler: @escaping MessageReadStubProtocol.Handler
) -> (store: WorkTimerStore, host: String, clock: AvatarTestClock) {
    let (store, host) = makeMessageReadStore("avatar-\(label)", handler: handler)
    // 착용 선택은 테스트마다 따로 — 전역(.standard)을 흔들면 같은 순간 아잉 픽셀을 재는 병렬 스위트가 빨개진다.
    store.characterDefaults = GomokuTestDefaults.make("v0335-avatar-local")
    store.characterSync.broadcast = CharacterSelectionBroadcast()
    let clock = AvatarTestClock()
    store.clock = { clock.now }
    return (store, host, clock)
}

@MainActor
private final class AvatarTestClock {
    var now = MessageReadFixture.now
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private func avSelect(_ id: String, in store: WorkTimerStore) {
    let selection = CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog)
    #expect(CheckCharacterPicker.choose(id, selection: selection, broadcast: store.characterSync.broadcast))
}

@MainActor
private func avFetches(_ host: String) -> Int {
    MessageReadStubProtocol.count(host: host, rpc: avRPC)
}

// MARK: - 스토어

@MainActor
@Suite(.serialized) struct V0335AvatarCharacterStoreTests {
    @Test(.gomokuDefaultsCleanup)
    func 로그인_직후_한_번_받는다_사진_캐릭터_이니셜_순_null은_아잉_모르는_id는_이니셜_사진_실패는_캐릭터() async throws {
        let (store, host, _) = avStore("prio") { call, _ in
            call.rpc == avRPC ? MessageReadStubProtocol.Reply(body: avRowsJSON) : nil
        }
        await store.refreshAppUserCharacters()?.value
        let call = try #require(MessageReadStubProtocol.calls(host: host, rpc: avRPC).first)
        #expect(call.method == "POST" && call.body == "{}", "인자 없는 RPC 본문은 {} 다")

        let directory = store.appUserCharacters
        let photoURL = try #require(URL(string: "https://x.invalid/ghost.jpg"))
        // ① 사진이 있으면 사진 — 실패하면 그 사람의 캐릭터로 떨어진다(이니셜이 아니다).
        let withPhoto = directory.avatar(for: avPhoto, photoURL: photoURL, characterHint: nil)
        #expect(withPhoto == .photo(photoURL, fallbackCharacterID: "ghost"))
        #expect(withPhoto.afterPhotoFailure == .character("ghost"))
        // ② 사진이 없으면 착용 캐릭터. 안 고른 사람(null)은 아잉이다.
        #expect(directory.avatar(for: avFox, photoURL: nil, characterHint: nil) == .character("fox"))
        #expect(directory.avatar(for: avPlain, photoURL: nil, characterHint: nil) == .character("aing"))
        // ③ 모를 때만 이니셜: 이 빌드가 모르는 새 캐릭터(아잉으로 단정하지 않는다) · 표에 없는 사람 · id 없음.
        #expect(directory.avatar(for: avFuture, photoURL: nil, characterHint: nil) == .initials)
        #expect(directory.avatar(for: avStranger, photoURL: nil, characterHint: nil) == .initials)
        #expect(directory.avatar(for: nil, photoURL: nil, characterHint: nil) == .initials)
        #expect(directory.avatar(for: avFuture, photoURL: photoURL, characterHint: nil).afterPhotoFailure == .initials)
        // 대문자로 넘긴 id 도 같은 사람이다.
        #expect(directory.characterID(for: avFox.uppercased()) == "fox")
        // 맥이 '안다'고 하는 캐릭터 = 번들에 neutral 초상이 **실제로 있는** id — 빈 원이 서지 않는다.
        #expect(Set(AppUserAvatarArt.knownIDs) == Set(CheckMascotAssets.catalog.allIDs), "번들 카탈로그에 초상 없는 캐릭터가 섞였다")
        #expect(directory.knownIDs == Set(AppUserAvatarArt.knownIDs))
        #expect(AppUserAvatarArt.knownIDs.count == 6 && AppUserAvatarArt.knownIDs.contains("aing"))
        for id in AppUserAvatarArt.knownIDs {
            #expect(AppUserAvatarArt.portrait(characterID: id) != nil, "\(id) neutral 초상을 못 그린다")
        }
        // 모르는 id 의 초상은 nil — 아잉으로 폴백하지 않는다(그 폴백은 내 캐릭터용 규칙이다).
        #expect(AppUserAvatarArt.portrait(characterID: "dragon") == nil)
        #expect(avFetches(host) == 1)
    }

    @Test(.gomokuDefaultsCleanup)
    func 서버에_함수가_없으면_조용히_빈_표_남은_이니셜_세션_그대로_다음_열기에_캐릭터로() async throws {
        let (store, host, clock) = avStore("404") { call, index in
            guard call.rpc == avRPC else { return nil }
            return index == 0 ? MessageReadFixture.missingFunction(avRPC) : MessageReadStubProtocol.Reply(body: avRowsJSON)
        }
        let before = store.syncMessage
        await store.refreshAppUserCharacters()?.value
        #expect(store.appUserCharacters.characterID(for: avFox) == nil, "404 에 남의 캐릭터가 섰다")
        #expect(store.appUserCharacters.avatar(for: avFox, photoURL: nil, characterHint: nil) == .initials)
        #expect(store.appUserCharacters.count <= 1, "404 인데 표에 남이 들어 있다(내 칸만 허용)")
        #expect(store.session != nil, "404 가 세션을 건드렸다")
        #expect(store.syncMessage == before, "404 가 오류 문구를 올렸다")

        // 서버가 함수를 얻은 뒤: 60초가 지나 팝오버를 열면 다시 묻고 캐릭터가 선다(앱 재시작 없이).
        clock.advance(WorkTimerStore.appUserCharactersRefreshSeconds)
        store.setMenuPresented(true)
        await messageReadWait { avFetches(host) == 2 && store.appUserCharactersInflightSerial == nil }
        #expect(store.appUserCharacters.avatar(for: avFox, photoURL: nil, characterHint: nil) == .character("fox"))
        store.setMenuPresented(false)
    }

    @Test(.gomokuDefaultsCleanup)
    func 갱신은_로그인_직후_한_번과_팝오버_열기의_60초_스로틀뿐_실패도_시도로_센다_실패는_가진_표를_둔다() async throws {
        let (store, host, clock) = avStore("throttle") { call, index in
            guard call.rpc == avRPC else { return nil }
            if index == 1 { return MessageReadStubProtocol.Reply(status: 503, body: #"{"message":"unavailable"}"#) }
            return MessageReadStubProtocol.Reply(body: avRowsJSON)
        }
        await store.refreshAppUserCharacters()?.value
        let loaded = store.appUserCharacters
        #expect(loaded.count == 5)

        // 60초 안의 여닫기 — 다시 묻지 않는다(무료 플랜 — 폴링 금지).
        #expect(store.refreshAppUserCharactersIfStale() == nil)
        clock.advance(WorkTimerStore.appUserCharactersRefreshSeconds - 1)
        #expect(store.refreshAppUserCharactersIfStale() == nil)
        #expect(avFetches(host) == 1)

        // 60초: 다시 묻는다 — 이번엔 5xx. 가진 표를 그대로 둔다(모든 아바타가 이니셜로 깜빡이지 않게).
        clock.advance(1)
        await store.refreshAppUserCharactersIfStale()?.value
        #expect(avFetches(host) == 2)
        #expect(store.appUserCharacters == loaded, "일시 장애가 표를 비웠다")
        #expect(store.session != nil)

        // 실패도 시도다: 곧바로 다시 열어도 묻지 않는다. 60초 뒤에만.
        #expect(store.refreshAppUserCharactersIfStale() == nil)
        clock.advance(WorkTimerStore.appUserCharactersRefreshSeconds)
        await store.refreshAppUserCharactersIfStale()?.value
        #expect(avFetches(host) == 3)
        #expect(store.appUserCharacters == loaded)
    }

    @Test(.gomokuDefaultsCleanup)
    func 떠_있는_조회_위에는_또_쏘지_않는다_로그인_직후_경로도() async throws {
        let gate = MessageReadStubGate()
        defer { gate.open() }
        let (store, host, clock) = avStore("overlap") { call, _ in
            call.rpc == avRPC ? MessageReadStubProtocol.Reply(body: avRowsJSON, gate: gate) : nil
        }
        let first = store.refreshAppUserCharacters()
        #expect(first != nil)
        await messageReadWait { avFetches(host) == 1 }
        clock.advance(WorkTimerStore.appUserCharactersRefreshSeconds * 2)
        #expect(store.refreshAppUserCharacters() == nil, "떠 있는 조회 위에 또 쐈다")
        #expect(store.refreshAppUserCharactersIfStale() == nil, "떠 있는 조회 위에 또 쐈다")
        gate.open()
        await first?.value
        #expect(avFetches(host) == 1)
        #expect(store.appUserCharacters.characterID(for: avFox) == "fox")
    }

    @Test(.gomokuDefaultsCleanup)
    func 표는_통째로_갈아_끼운다_다음_조회에서_빠진_사람은_이니셜로() async throws {
        let (store, _, clock) = avStore("replace") { call, index in
            guard call.rpc == avRPC else { return nil }
            return index == 0
                ? MessageReadStubProtocol.Reply(body: avRowsJSON)
                : MessageReadStubProtocol.Reply(body: #"[{"user_id":"\#(avFox)","character":"shiba"}]"#)
        }
        await store.refreshAppUserCharacters()?.value
        #expect(store.appUserCharacters.characterID(for: avPhoto) == "ghost")
        clock.advance(WorkTimerStore.appUserCharactersRefreshSeconds)
        await store.refreshAppUserCharactersIfStale()?.value
        #expect(store.appUserCharacters.characterID(for: avFox) == "shiba", "바꿔 입은 캐릭터가 반영되지 않았다")
        #expect(store.appUserCharacters.characterID(for: avPhoto) == nil, "숨김 격리 밖으로 옮겨진 사람의 옛 캐릭터가 남았다")
    }

    // MARK: 로그아웃

    @Test(.gomokuDefaultsCleanup)
    func 로그아웃하면_표를_비운다_떠_있던_조회가_늦게_와도_다시_채우지_않고_다음_계정은_자기_표만_본다() async throws {
        let gate = MessageReadStubGate()
        defer { gate.open() }
        let (store, host, clock) = avStore("signout") { call, index in
            guard call.rpc == avRPC else { return nil }
            switch index {
            case 0: return MessageReadStubProtocol.Reply(body: avRowsJSON)
            case 1: return MessageReadStubProtocol.Reply(body: avRowsJSON, gate: gate)
            default:
                return MessageReadStubProtocol.Reply(
                    body: #"[{"user_id":"\#(avNextUser)","character":"squirrel"},{"user_id":"\#(avPlain)","character":"jellyfish"}]"#)
            }
        }
        avSelect("fox", in: store)
        await store.refreshAppUserCharacters()?.value
        #expect(store.appUserCharacters.count == 5)
        #expect(store.appUserCharacters.characterID(for: avMe) == "fox", "내 칸이 이 맥의 착용 선택이 아니다")

        // 60초 뒤 갱신이 떠 있는 채(붙잡음) 로그아웃.
        clock.advance(WorkTimerStore.appUserCharactersRefreshSeconds)
        let late = store.refreshAppUserCharactersIfStale()
        await messageReadWait { avFetches(host) == 2 }
        store.clearPersistedSession()
        #expect(store.session == nil)
        #expect(store.appUserCharacters.isEmpty, "로그아웃했는데 앞 계정의 표가 남았다")
        #expect(store.appUserCharactersLastAttemptAt == nil)
        #expect(store.appUserCharactersInflightSerial == nil)

        // 앞 계정의 늦은 응답: 버린다.
        gate.open()
        await late?.value
        #expect(store.appUserCharacters.isEmpty, "로그아웃 뒤 도착한 앞 계정의 표가 다시 채워졌다")

        // 다음 계정: 로그인 직후 자기 표를 받고, 앞 계정의 칸(나 · 여우)은 따라오지 않는다.
        store.session = SupabaseSession(accessToken: "next-token", refreshToken: nil, userID: avNextUser)
        avSelect("ghost", in: store)
        await store.refreshAppUserCharacters()?.value
        let directory = store.appUserCharacters
        #expect(directory.count == 2)
        // 이 맥의 착용 선택이 내 칸이다(서버 squirrel 보다 이긴다 — 메뉴바·헤더와 같은 캐릭터).
        #expect(directory.characterID(for: avNextUser) == "ghost")
        #expect(directory.characterID(for: avPlain) == "jellyfish")
        #expect(directory.characterID(for: avMe) == nil, "앞 계정의 내 칸이 다음 계정 표에 남았다")
        #expect(directory.characterID(for: avFox) == nil)
    }

    @Test(.gomokuDefaultsCleanup)
    func 취소가_닿지_않은_늦은_응답_창_앞_계정의_표를_쓰지_않고_다음_계정_조회의_진행_표시도_건드리지_않는다() async throws {
        let gate = MessageReadStubGate()
        defer { gate.open() }
        let (store, host, clock) = avStore("late-window") { call, index in
            guard call.rpc == avRPC else { return nil }
            if index >= 2 {
                return MessageReadStubProtocol.Reply(body: #"[{"user_id":"\#(avNextUser)","character":"squirrel"}]"#, gate: gate)
            }
            return MessageReadStubProtocol.Reply(body: avRowsJSON)
        }
        await store.refreshAppUserCharacters()?.value
        // 앞 계정의 조회가 떠난 순간의 순번·세대를 찍는다(응답은 정상으로 끝난다).
        clock.advance(WorkTimerStore.appUserCharactersRefreshSeconds)
        let departed = store.refreshAppUserCharactersIfStale()
        let departedSerial = store.appUserCharactersSerial
        let departedGeneration = store.sessionGeneration
        await departed?.value
        let lateRows = [AppUserCharacterRow(userId: avFox, character: "fox"), AppUserCharacterRow(userId: avNextUser, character: "ghost")]

        // 로그아웃이 먼저 돌았다 — 그 뒤 메인 액터에 도착한 앞 계정의 응답은 버린다.
        store.clearPersistedSession()
        store.finishAppUserCharacters(lateRows, serial: departedSerial, generation: departedGeneration)
        #expect(store.appUserCharacters.isEmpty, "로그아웃 뒤 앞 계정의 표가 들어왔다")

        // 다음 계정의 조회가 떠 있는 동안 앞 조회의 끝이 와도 진행 표시를 풀지 않는다.
        store.session = SupabaseSession(accessToken: "next-token", refreshToken: nil, userID: avNextUser)
        let next = store.refreshAppUserCharacters()
        await messageReadWait { avFetches(host) == 3 }
        #expect(store.appUserCharactersInflightSerial != nil)
        store.finishAppUserCharacters(nil, serial: departedSerial, generation: departedGeneration)
        store.finishAppUserCharacters(lateRows, serial: departedSerial, generation: departedGeneration)
        #expect(store.appUserCharactersInflightSerial != nil, "앞 계정 조회의 끝이 다음 계정 조회의 진행 표시를 풀었다")
        #expect(store.appUserCharacters.characterID(for: avFox) == nil, "앞 계정의 표가 다음 계정 화면에 들어왔다")

        gate.open()
        await next?.value
        #expect(store.appUserCharactersInflightSerial == nil)
        #expect(store.appUserCharacters.characterID(for: avFox) == nil)
        // 서버는 squirrel 이라지만 내 칸은 이 맥의 착용 선택(여기선 기본 = 아잉)이다.
        #expect(store.appUserCharacters.characterID(for: avNextUser) == "aing")
    }

    // MARK: 내 착용

    @Test(.gomokuDefaultsCleanup)
    func 내가_캐릭터를_바꾸면_내_칸은_즉시_저장_전에_떠난_조회가_옛_값으로_늦게_와도_되돌리지_않는다() async throws {
        let gate = MessageReadStubGate()
        defer { gate.open() }
        let (store, host, clock) = avStore("equip") { call, index in
            if call.rpc == avRPC {
                // 서버는 아직 나를 null(아잉)이라고 답한다.
                return index == 0
                    ? MessageReadStubProtocol.Reply(body: avRowsJSON)
                    : MessageReadStubProtocol.Reply(body: avRowsJSON, gate: gate)
            }
            if call.rpc == "set_character" { return MessageReadStubProtocol.Reply(body: #"{"status":"ok"}"#) }
            return nil
        }
        await store.refreshAppUserCharacters()?.value
        #expect(store.appUserCharacters.characterID(for: avMe) == "aing")

        // 표 조회가 떠 있는 채 시바를 입는다(선택기 = choose → onChosen(pushSelectedCharacter) 한 동기 구간).
        clock.advance(WorkTimerStore.appUserCharactersRefreshSeconds)
        let inflight = store.refreshAppUserCharactersIfStale()
        await messageReadWait { avFetches(host) == 2 }
        avSelect("shiba", in: store)
        store.pushSelectedCharacter(announcesFailure: true)
        #expect(store.appUserCharacters.characterID(for: avMe) == "shiba", "착용 직후 내 칸이 그대로다")
        #expect(avFetches(host) == 2, "내 칸을 고치려고 표 전체를 다시 물었다")

        gate.open()
        await inflight?.value
        #expect(store.appUserCharacters.characterID(for: avMe) == "shiba", "저장 전에 떠난 조회가 방금 입은 캐릭터를 아잉으로 되돌렸다")
        #expect(store.appUserCharacters.characterID(for: avFox) == "fox", "남의 칸은 새 표 그대로")

        // 서버가 not_owned 로 거절해 아잉으로 되돌리면 내 칸도 즉시 아잉.
        store.revertCharacterToDefault()
        #expect(store.appUserCharacters.characterID(for: avMe) == "aing")
    }

    @Test(.gomokuDefaultsCleanup)
    func 폰에서_바꾼_캐릭터를_따르면_내_칸도_같은_캐릭터로() async throws {
        let (store, _, _) = avStore("adopt") { call, _ in
            if call.rpc == avRPC { return MessageReadStubProtocol.Reply(body: avRowsJSON) }
            if call.path == "/rest/v1/profiles", call.url.query?.contains("character") == true {
                return MessageReadStubProtocol.Reply(body: #"[{"character":"jellyfish"}]"#)
            }
            return nil
        }
        store.defaults.set(true, forKey: CharacterSyncDecision.migrationDefaultsKey)
        await store.refreshAppUserCharacters()?.value
        #expect(store.appUserCharacters.characterID(for: avMe) == "aing")
        await store.syncEquippedCharacterFromServer(reason: .signIn)?.value
        #expect(CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog).selectedID == "jellyfish")
        #expect(store.appUserCharacters.characterID(for: avMe) == "jellyfish", "메뉴바는 해파리인데 내 아바타는 아잉이다")
    }
}

// MARK: - 판정(맥의 힌트 규칙)

@Suite struct V0335AvatarCharacterRuleTests {
    @Test func 오목_행의_착용값은_표가_그_사람을_모를_때만_아는_캐릭터일_때만_쓴다() throws {
        let directory = AppUserCharacterDirectory(
            knownIDs: ["aing", "fox", "ghost", "jellyfish", "shiba", "squirrel"],
            rows: [AppUserCharacterRow(userId: avFox, character: "fox"),
                   AppUserCharacterRow(userId: avPlain, character: nil)]
        )
        let photo = try #require(URL(string: "https://x.invalid/p.jpg"))
        // 표가 아는 사람은 표가 이긴다(팝오버와 오목 창이 같은 사람을 다른 캐릭터로 그리지 않게).
        #expect(directory.avatar(for: avFox, photoURL: nil, characterHint: "ghost") == .character("fox"))
        #expect(directory.avatar(for: avPlain, photoURL: nil, characterHint: "ghost") == .character("aing"))
        // 표가 모르는 사람: 아는 캐릭터 힌트면 그 캐릭터(공백은 걷는다).
        #expect(directory.avatar(for: avStranger, photoURL: nil, characterHint: "jellyfish") == .character("jellyfish"))
        #expect(directory.avatar(for: avStranger, photoURL: nil, characterHint: " shiba ") == .character("shiba"))
        #expect(directory.avatar(for: avStranger, photoURL: photo, characterHint: "jellyfish")
                == .photo(photo, fallbackCharacterID: "jellyfish"))
        // nil 은 아잉으로 접지 않는다('안 골랐다'와 '칸을 안 실었다'를 못 가른다) · 모르는 id 도 이니셜.
        #expect(directory.avatar(for: avStranger, photoURL: nil, characterHint: nil) == .initials)
        #expect(directory.avatar(for: avStranger, photoURL: nil, characterHint: "   ") == .initials)
        #expect(directory.avatar(for: avStranger, photoURL: nil, characterHint: "dragon") == .initials)
        #expect(directory.avatar(for: avStranger, photoURL: photo, characterHint: "dragon")
                == .photo(photo, fallbackCharacterID: nil))
    }
}

// MARK: - 화면 배선(소스 계약 — 주석을 걷어내고 본다)

@Suite struct V0335AvatarCharacterSourceTests {
    /// `Sources/check` 에서 `name(` 호출 전부(선언·다른 이름의 일부 제외) — (파일, 호출 본문). 공백은 한 칸으로 접혀 있다.
    static func calls(of name: String) throws -> [(file: String, text: String)] {
        var out: [(file: String, text: String)] = []
        for (file, code) in try V0325TooltipTests.strippedSources() {
            let chars = Array(code)
            let needle = Array(name + "(")
            var i = 0
            while i + needle.count <= chars.count {
                guard Array(chars[i..<(i + needle.count)]) == needle else { i += 1; continue }
                let before = i > 0 ? chars[i - 1] : " "
                if before.isLetter || before.isNumber || before == "_" || before == "." { i += 1; continue }
                var depth = 0
                var j = i + needle.count - 1
                while j < chars.count {
                    if chars[j] == "(" { depth += 1 }
                    if chars[j] == ")" { depth -= 1; if depth == 0 { break } }
                    j += 1
                }
                out.append((file: file, text: String(chars[i...min(j, chars.count - 1)])))
                i = j
            }
        }
        return out.sorted { $0.file < $1.file }
    }

    @Test func 모든_사람_아바타_호출부가_사용자_id를_넘긴다_nil은_팀_리그_줄뿐() throws {
        let avatars = try Self.calls(of: "CheckAvatarView")
        // 18 호출부 + EditableAvatarView 안의 1. 줄면 호출부가 사라졌거나 검사가 헛돈다.
        #expect(avatars.count == 19, "CheckAvatarView( 호출 \(avatars.count)곳: \(avatars.map(\.file))")
        for call in avatars {
            #expect(call.text.contains("userID:"), "\(call.file): \(call.text) — 사용자 id 없이 그리면 그 자리만 이니셜로 남는다")
        }
        let nils = avatars.filter { $0.text.contains("userID: nil") }
        #expect(nils.map(\.file) == ["CheckComponents.swift"], "사람 자리에 userID: nil 이 있다: \(nils.map(\.text))")
        #expect(nils.first?.text == "CheckAvatarView(name: entry.name, userID: nil, size: 30, center: center)",
                "nil 은 팀 리그 줄(사진도 캐릭터도 없는 팀)만")

        // 자리마다 **그 사람의** id 다(엉뚱한 칸을 넘기면 남의 캐릭터가 선다).
        let expected: [(String, String)] = [
            ("CheckMessageView.swift", "userID: store.selectedMessagePeerID"),
            ("CheckMessageView.swift", "userID: entry.peerUserID"),
            ("CheckBlockReportViews.swift", "userID: person.userID"),
            ("MiniGamePanel.swift", "userID: winner.userID"),
            ("MiniGamePanel.swift", "userID: entry.userID"),
            ("CheckReportAdminView.swift", "userID: report.reporterID"),
            ("CheckReportAdminView.swift", "userID: report.targetID"),
            ("CheckFeedbackView.swift", "userID: report.userID"),
            ("CheckMenuView.swift", "userID: message.fromUserID, avatarURL: message.fromAvatarURL"),
            ("CheckComponents.swift", "userID: userID"),
            ("CheckAvatarView.swift", "userID: userID"),
        ]
        for (file, needle) in expected {
            #expect(avatars.contains { $0.file == file && $0.text.contains(needle) }, "\(file) 에 \(needle) 가 없다")
        }
        // 순위판(토큰)과 콕 찌르기 목록 — 같은 모양 둘.
        #expect(avatars.filter { $0.file == "CheckMenuView.swift" && $0.text.contains("userID: entry.userID") }.count == 2)
        // 오목 다섯 자리: 로비 · 보낸 신청 · 받은 신청 · 결과 머리 · 관전 카드. 행이 이미 받은 착용값도 함께 넘긴다.
        let gomoku = avatars.filter { $0.file == "GomokuPanel.swift" }
        #expect(gomoku.count == 5)
        for call in gomoku {
            #expect(call.text.contains("characterHint:"), "오목 \(call.text) 가 행의 착용값을 버린다")
        }
        #expect(gomoku.filter { $0.text.contains("userID: user.id") && $0.text.contains("characterHint: user.characterID") }.count == 2)
        #expect(gomoku.filter { $0.text.contains("userID: invite.peer.id") && $0.text.contains("characterHint: invite.peer.characterID") }.count == 2)
        #expect(gomoku.filter { $0.text.contains("userID: match.opponent.id") && $0.text.contains("characterHint: match.opponent.characterID") }.count == 1)

        // 내 프로필 편집(EditableAvatarView)도 같은 규칙 · 팀원 행은 그 팀원의 id 를 싣는다.
        let editable = try Self.calls(of: "EditableAvatarView")
        #expect(editable.count == 1 && editable.allSatisfy { $0.text.contains("userID: userID") }, "\(editable)")
        let memberRows = try Self.calls(of: "TeamMemberRow").filter { $0.file == "CheckMenuView.swift" }
        #expect(memberRows.contains { $0.text.contains("userID: member.id") }, "팀원 행이 id 를 안 넘긴다")
    }

    /// 사진 → 캐릭터 순서는 **사진을 넘겨야** 선다. 사진을 빠뜨린 사람 자리는 사진을 올린 사람도 그 자리에서만 캐릭터(대개 아잉)로
    /// 세운다 — 이니셜 시절엔 '정보 없음'으로 읽혔지만 이제는 **틀린 얼굴**이다(2026-09-20 검증: 콕 찌르기 '최근 받은 메시지' 줄).
    /// 사진 칸이 없는 자리는 사람이 아닌 팀 리그 줄뿐이다.
    @Test func 사람_아바타_호출부는_전부_사진도_넘긴다_빠진_곳은_팀_리그_줄뿐() throws {
        let avatars = try Self.calls(of: "CheckAvatarView")
        let withoutPhoto = avatars.filter { !$0.text.contains("avatarURL:") }
        #expect(withoutPhoto.map(\.text) == ["CheckAvatarView(name: entry.name, userID: nil, size: 30, center: center)"],
                "사진을 안 넘기는 사람 자리: \(withoutPhoto.map { "\($0.file): \($0.text)" })")
        // 받은 메시지 줄의 사진은 **그 메시지를 보낸 사람의** 사진이다(take_pokes 행의 from_avatar_url 을 나른 칸).
        let strip = avatars.filter { $0.file == "CheckMenuView.swift" && $0.text.contains("message.") }
        #expect(strip.map(\.text) == ["CheckAvatarView(name: message.fromName, userID: message.fromUserID, avatarURL: message.fromAvatarURL, size: 22)"],
                "\(strip.map(\.text))")
    }

    @Test func 이니셜_원은_얼굴_한_벌에서만_그리고_남의_초상은_아잉_폴백_경로를_타지_않는다() throws {
        let sources = try V0325TooltipTests.strippedSources()
        let initials = sources.filter { $0.value.contains("InitialAvatar(") }.map(\.key)
        #expect(initials == ["CheckAvatarView.swift"], "표를 건너뛰고 이니셜을 직접 그리는 자리: \(initials)")
        let avatar = try #require(sources["CheckAvatarView.swift"])
        #expect(V0325TooltipTests.count("InitialAvatar(name: name, size: size)", in: avatar) == 1, "이니셜 원은 AppUserAvatarStill 한 곳에서만")
        #expect(avatar.contains("AppUserAvatarStill(avatar: fallback, name: name, size: size)"), "사진 실패가 캐릭터로 떨어지지 않는다")
        #expect(avatar.contains("fallback: avatar.afterPhotoFailure"))
        #expect(avatar.contains("characters.avatar(for: userID, photoURL: avatarURL, characterHint: characterHint)"))
        // 2026-09-21 사용자 지시로 **그림 출처가 바뀌었다**: 남의 캐릭터 얼굴도 '캐릭터 고르기' 카드와 같은 그림
        // (`CharacterCardArt.image` — 아틀라스 전신)이다. 그래서 초상 PNG 를 따로 디코드하던 줄이 사라졌다.
        // 아잉으로 접지 않는 규칙은 그 앞의 `knownIDs` 가드가 지킨다(계약 전체는 `V0336AvatarArtTests`).
        #expect(avatar.contains("return CharacterCardArt.image(characterID: characterID)"), "남의 캐릭터 얼굴은 카드와 같은 그림")
        #expect(avatar.contains("guard knownIDs.contains(characterID) else { return nil }"), "모르는 캐릭터가 카드 그림의 아잉 폴백을 탄다")
        #expect(!avatar.contains("CheckMascotAssets.image("), "아잉으로 폴백하는 내 캐릭터 경로를 남의 아바타가 탄다")
        #expect(avatar.contains("Image(decorative: portrait, scale: 1)"), "Image(nsImage:) 는 보간 지정을 무시한다")
    }

    @Test func 창_루트_넷이_표를_걸고_스토어는_로그인_직후와_팝오버_열기에만_묻고_로그아웃에서_비운다() throws {
        let sources = try V0325TooltipTests.strippedSources()
        // 창 루트 넷 — 툴팁 레이어 바로 뒤(같은 자리 · 같은 수).
        let roots = sources.compactMap { name, code -> String? in
            let n = V0325TooltipTests.count(".appUserAvatarCharacters(from:", in: code)
            return n > 0 ? "\(name):\(n)" : nil
        }.sorted()
        #expect(roots == ["CheckMenuView.swift:1", "CheckSettingsView.swift:1", "GomokuPanel.swift:1", "MiniGamePanel.swift:1"], "\(roots)")
        #expect(sources["CheckMenuView.swift"]?.contains(".checkTooltipLayer() .appUserAvatarCharacters(from: store)") == true)
        #expect(sources["CheckSettingsView.swift"]?.contains(".checkTooltipLayer() .appUserAvatarCharacters(from: store)") == true)
        #expect(sources["MiniGamePanel.swift"]?.contains(".checkTooltipLayer() .appUserAvatarCharacters(from: store)") == true)
        #expect(sources["GomokuPanel.swift"]?.contains(".checkTooltipLayer() .appUserAvatarCharacters(from: safety)") == true)
        // 앱은 오목 창에 앱 스토어를 `safety` 로 넘긴다 — 그게 빠지면 오목 창의 표가 비어 전원 행 힌트·이니셜뿐이다.
        #expect(sources["CheckApp.swift"]?.contains("}, safety: store)") == true)
        #expect(sources["CheckGomokuWindow.swift"]?.contains("GomokuPanel(store: gomoku, me: me, safety: safety)") == true)

        let auth = try #require(sources["WorkTimerStoreAuth.swift"])
        // 로그인 직후 한 번 — 저장 세션 활성화 · 로그인 마무리 · 가입 마무리.
        #expect(V0325TooltipTests.count("refreshAppUserCharacters()", in: auth) == 3)
        #expect(auth.contains("syncEquippedCharacterFromServer(reason: .launch) refreshAppUserCharacters()"))
        #expect(auth.contains("syncEquippedCharacterFromServer(reason: .signIn) refreshAppUserCharacters()"))
        // 내 칸 — 로컬 선택이 바뀌는 문 셋(이 맥에서 고르기 · 서버값 따르기 · not_owned 되돌리기).
        #expect(V0325TooltipTests.count("noteMyEquippedCharacter()", in: auth) == 3)
        #expect(auth.contains("characterSync.noteLocalWrite() noteMyEquippedCharacter()"))

        let store = try #require(sources["WorkTimerStore.swift"])
        #expect(store.contains("refreshEquippedCharacterIfStale() refreshAppUserCharactersIfStale()"), "팝오버 열기의 60초 스로틀")
        #expect(V0325TooltipTests.count("refreshAppUserCharactersIfStale()", in: store) == 1, "갱신 시점이 팝오버 열기 말고 더 생겼다")
        #expect(store.contains("clearBlockReportState() clearAppUserCharacters()"), "로그아웃에서 비우기")
        // 새 폴링을 만들지 않는다: 이 기능의 파일에 타이머·잠이 없고, 다른 파일이 이 조회를 부르지 않는다.
        let avatars = try #require(sources["WorkTimerStoreAvatars.swift"])
        #expect(!avatars.contains("Timer.") && !avatars.contains("Timer(") && !avatars.contains("Task.sleep")
                && !avatars.contains("asyncAfter"))
        let callers = sources.filter { name, code in
            name != "WorkTimerStoreAvatars.swift" && code.contains("refreshAppUserCharacters")
        }.map(\.key).sorted()
        #expect(callers == ["WorkTimerStore.swift", "WorkTimerStoreAuth.swift"], "\(callers)")
    }
}

// MARK: - 그림(픽셀)

@MainActor
@Suite struct V0335AvatarCharacterRenderTests {
    /// 26pt 아바타 하나를 @2x(52px)로 굽는다. 배경은 단색(패널) — 그라디언트면 같은 그림끼리도 배경이 달라진다.
    static func bitmap(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.fixedSize().background(CheckTheme.panel))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { throw AvatarRenderError.failed }
        return rep
    }

    /// 두 그림의 평균 채널 차(0~255). 같은 뷰를 두 번 구우면 디더로 ±1~2 흔들린다 — 같음은 < 3, 다름은 > 20 으로 가른다.
    static func meanDifference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 255 }
        var total = 0.0
        var count = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let q = b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent)
                    + abs(p.blueComponent - q.blueComponent)
                count += 3
            }
        }
        return count == 0 ? 255 : total / Double(count) * 255
    }

    /// 원 안(가운데 지름 80%) 픽셀 중 조건을 만족하는 비율.
    static func share(_ rep: NSBitmapImageRep, where match: (Double, Double, Double) -> Bool) -> Double {
        let cx = Double(rep.pixelsWide) / 2, cy = Double(rep.pixelsHigh) / 2
        let radius = Double(min(rep.pixelsWide, rep.pixelsHigh)) / 2 * 0.8
        var hits = 0, total = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                guard dx * dx + dy * dy <= radius * radius,
                      let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += 1
                if match(c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255) { hits += 1 }
            }
        }
        return total == 0 ? 0 : Double(hits) / Double(total)
    }

    static let directory = AppUserCharacterDirectory(
        knownIDs: AppUserAvatarArt.knownIDs,
        rows: [AppUserCharacterRow(userId: avFox, character: "fox"),
               AppUserCharacterRow(userId: avPlain, character: nil),
               AppUserCharacterRow(userId: avFuture, character: "dragon")]
    )

    static func avatar(_ userID: String?, photo: URL? = nil, hint: String? = nil, size: CGFloat = 26,
                       directory: AppUserCharacterDirectory? = directory) -> some View {
        // 이름은 해시색이 파랑인 합성 이름이다(이니셜 원이 여우의 주황과 겹치지 않게).
        CheckAvatarView(name: "민수", userID: userID, avatarURL: photo, size: size, characterHint: hint)
            .environment(\.appUserCharacters, directory ?? AppUserCharacterDirectory(knownIDs: AppUserAvatarArt.knownIDs))
    }

    /// 원 안(지름 80%)에서 받침색과 확연히 다른 픽셀의 비율 = 캐릭터가 원을 덮는 정도. 받침색은 같은 크기의 받침 원만 구워 잰다.
    static func coverage(_ rep: NSBitmapImageRep, size: CGFloat) throws -> Double {
        let plate = try bitmap(Circle().fill(AppUserAvatarArt.backdrop).frame(width: size, height: size))
        guard let bg = plate.colorAt(x: plate.pixelsWide / 2, y: plate.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else {
            throw AvatarRenderError.failed
        }
        let (br, bgc, bb) = (bg.redComponent * 255, bg.greenComponent * 255, bg.blueComponent * 255)
        return share(rep) { r, g, b in abs(r - br) + abs(g - bgc) + abs(b - bb) > 60 }
    }

    /// 여우 기준 하한. 2026-09-20 실측(여우 16·22·26·34pt): 120% 초상 0.901~0.921 · 원 안에 통째로 넣는 84% 0.763~0.778.
    /// (다른 캐릭터는 여백이 달라 84% 에서도 0.9 에 닿는 것이 있어 여우로 잰다 — 알파 상자 대비 몸이 가장 작은 쪽이다.)
    static let minimumCoverage = 0.85

    static func isOrange(_ r: Double, _ g: Double, _ b: Double) -> Bool { r > 170 && g > 50 && g < 160 && b < 110 && r - g > 60 }
    static func isLavender(_ r: Double, _ g: Double, _ b: Double) -> Bool { b > 170 && r > 120 && b > g + 25 && r > g }

    @Test func 작은_아바타에_착용_캐릭터가_그려지고_사진이_실패하면_이니셜이_아니라_캐릭터다() throws {
        let initials = try Self.bitmap(Self.avatar(avFox, directory: nil))
        let fox = try Self.bitmap(Self.avatar(avFox))
        #expect(fox.pixelsWide == 52 && fox.pixelsHigh == 52, "26pt @2x 가 아니다: \(fox.pixelsWide)×\(fox.pixelsHigh)")
        // 여우의 주황이 원을 채운다(얼굴이 원 가운데) — 파란 이니셜 원에는 주황이 없다.
        let foxOrange = Self.share(fox, where: Self.isOrange)
        #expect(foxOrange > 0.2, "26pt 여우 아바타에 주황이 \(foxOrange) 뿐이다 — 캐릭터가 안 그려졌거나 너무 작다")
        #expect(Self.share(initials, where: Self.isOrange) < 0.02)
        // 26pt 에서 얼굴이 읽히려면 캐릭터가 원을 **채워야** 한다(초상 중심) — 전신을 원 안에 통째로 넣으면 받침만 보인다.
        let coverage = try Self.coverage(fox, size: 26)
        #expect(coverage > Self.minimumCoverage, "26pt 여우가 원의 \(coverage) 만 덮는다 — 초상이 작아 얼굴이 안 읽힌다")
        #expect(Self.meanDifference(fox, initials) > 20, "캐릭터를 아는데 이니셜이 섰다")

        // 사진 로딩 실패(없는 파일) → 이니셜이 아니라 그 사람의 캐릭터 — 사진 없는 여우와 같은 그림.
        let missing = URL(fileURLWithPath: NSTemporaryDirectory() + "v0335-no-such-avatar-\(UUID().uuidString).png")
        let photoFailed = try Self.bitmap(Self.avatar(avFox, photo: missing))
        #expect(Self.meanDifference(photoFailed, fox) < 3, "사진 실패가 캐릭터로 떨어지지 않는다")

        // 사진이 있으면 사진이다(캐릭터를 알아도) — 번들의 아잉 초상 파일을 '사진'으로 준다.
        let photoFile = try #require(CheckMascotAssets.url(for: .negative))
        let withPhoto = try Self.bitmap(Self.avatar(avFox, photo: photoFile))
        #expect(Self.meanDifference(withPhoto, fox) > 20, "올린 사진 대신 캐릭터가 섰다")
        #expect(Self.share(withPhoto, where: Self.isOrange) < 0.05)

        // 안 고른 사람(null) = 아잉 — 라벤더가 원을 채운다.
        let aing = try Self.bitmap(Self.avatar(avPlain))
        #expect(Self.share(aing, where: Self.isLavender) > 0.2, "null 인 사람이 아잉으로 안 섰다")
        #expect(Self.meanDifference(aing, fox) > 20)
    }

    /// 콕 찌르기 '최근 받은 메시지' 줄의 아바타(22pt)만 잘라 굽는다 — 서버 행(take_pokes) → 스토어의 옮김
    /// (`freshReceivedMessages`, drain 이 말풍선 큐에 넣는 그 함수) → 줄. 보낸 사람은 표에서 여우다.
    static func receiptAvatar(fromAvatarUrl: String?) throws -> NSBitmapImageRep {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let row = TakenPokeRow(id: "m-receipt", fromUser: avFox, fromDisplayName: "민수", fromAvatarUrl: fromAvatarUrl,
                               createdEpoch: Int(now.timeIntervalSince1970) - 10, kind: "message", body: "밥?")
        guard let message = WorkTimerStore.freshReceivedMessages(rows: [row], now: now).first else {
            throw AvatarRenderError.failed
        }
        let strip = try bitmap(
            PokeMessageReceiptStrip(message: message, now: now)
                .frame(width: 320)
                .environment(\.appUserCharacters, directory)
        )
        // 줄 높이 34pt · 가로 여백 10pt · 가운데 22pt 원 → @2x 로 (20, 12) 에서 44×44.
        guard strip.pixelsHigh == 68 else { throw AvatarRenderError.failed }
        let rect = CGRect(x: 20, y: (strip.pixelsHigh - 44) / 2, width: 44, height: 44)
        guard let crop = strip.cgImage?.cropping(to: rect) else { throw AvatarRenderError.failed }
        return NSBitmapImageRep(cgImage: crop)
    }

    /// 2026-09-20 검증(medium): 이 줄만 사진을 몰라 사진을 올린 사람도 여기서만 캐릭터(대개 아잉)로 섰다 — 바로 아래 목록 행에는
    /// 같은 사람이 사진으로 선다. 서버 행은 사진을 싣는데(from_avatar_url) 스토어가 받은 메시지로 옮길 때 버렸다.
    @Test func 받은_메시지_줄은_보낸_사람이_올린_사진을_그리고_사진이_없을_때만_캐릭터다() throws {
        // 기준선: 사진이 없으면 보낸 사람의 캐릭터(여우) — 자르는 자리가 맞고 표가 이 줄까지 닿는다는 증거이기도 하다.
        let fox = try Self.receiptAvatar(fromAvatarUrl: nil)
        #expect(Self.share(fox, where: Self.isOrange) > 0.2, "받은 메시지 줄에 보낸 사람(여우)의 캐릭터가 안 섰다")
        // 사진을 올린 사람 — 번들의 아잉 초상 파일을 '사진'으로 준다(라벤더 · 주황 없음).
        let photoFile = try #require(CheckMascotAssets.url(for: .negative))
        let photo = try Self.receiptAvatar(fromAvatarUrl: photoFile.absoluteString)
        #expect(Self.share(photo, where: Self.isOrange) < 0.05, "사진을 올린 사람이 받은 메시지 줄에서만 캐릭터로 선다")
        #expect(Self.meanDifference(photo, fox) > 20, "받은 메시지 줄이 보낸 사람의 사진을 버린다")

        // 옮김 자체(순수): 행의 사진 → 받은 메시지의 사진 · 없거나 URL 이 아니면 nil(캐릭터로 그린다).
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func carried(_ url: String?) -> URL?? {
            WorkTimerStore.freshReceivedMessages(rows: [
                TakenPokeRow(id: "m", fromUser: avFox, fromDisplayName: "민수", fromAvatarUrl: url,
                             createdEpoch: Int(now.timeIntervalSince1970) - 10, kind: "message", body: "밥?")
            ], now: now).first.map(\.fromAvatarURL)
        }
        #expect(carried(photoFile.absoluteString) == .some(photoFile))
        #expect(carried(nil) == .some(nil))
        #expect(carried("") == .some(nil))
    }

    @Test func 모르는_캐릭터와_표에_없는_사람은_이니셜_그대로다() throws {
        let initials = try Self.bitmap(Self.avatar(avStranger, directory: nil))
        let future = try Self.bitmap(Self.avatar(avFuture))
        let stranger = try Self.bitmap(Self.avatar(avStranger))
        #expect(Self.meanDifference(future, initials) < 3, "모르는 캐릭터를 아잉(또는 다른 그림)으로 그렸다")
        #expect(Self.meanDifference(stranger, initials) < 3)
        #expect(Self.share(future, where: Self.isLavender) < 0.05, "모르는 캐릭터를 아잉으로 단정했다")
        // 표가 모르는 사람이라도 행이 실은 착용값(오목)이 아는 캐릭터면 그 캐릭터.
        let hinted = try Self.bitmap(Self.avatar(avStranger, hint: "fox"))
        #expect(Self.share(hinted, where: Self.isOrange) > 0.2)
    }

    @Test(.gomokuDefaultsCleanup) func 창_루트의_감싸개가_스토어의_표를_아바타까지_흘리고_내_편집_아바타도_같은_규칙이다() throws {
        let (store, _) = makeMessageReadStore("avatar-scope")
        store.characterDefaults = GomokuTestDefaults.make("v0335-avatar-scope")
        var table = AppUserCharacterDirectory(knownIDs: AppUserAvatarArt.knownIDs)
        table.replace(with: [AppUserCharacterRow(userId: avFox, character: "fox"), AppUserCharacterRow(userId: avMe, character: "fox")])
        store.appUserCharacters = table
        let direct = try Self.bitmap(Self.avatar(avFox))
        let scoped = try Self.bitmap(
            CheckAvatarView(name: "민수", userID: avFox, size: 26).appUserAvatarCharacters(from: store))
        #expect(Self.meanDifference(scoped, direct) < 3, "감싸개가 스토어의 표를 흘리지 않는다")
        let noStore = try Self.bitmap(
            CheckAvatarView(name: "민수", userID: avFox, size: 26).appUserAvatarCharacters(from: nil))
        #expect(Self.share(noStore, where: Self.isOrange) < 0.02, "스토어 없는 루트가 표를 지어냈다")
        // 내 행(사진 없음) — 편집 아바타도 내 캐릭터로 선다.
        let mine = try Self.bitmap(
            EditableAvatarView(name: "민수", userID: avMe, size: 26, onPick: { _ in }).appUserAvatarCharacters(from: store))
        #expect(Self.meanDifference(mine, direct) < 3, "내 편집 아바타가 캐릭터를 건너뛴다")
    }

    @Test(arguments: [CGFloat(16), 22, 30, 34])
    func 여러_크기에서도_캐릭터가_원을_채운다(size: CGFloat) throws {
        let fox = try Self.bitmap(Self.avatar(avFox, size: size))
        #expect(fox.pixelsWide == Int(size * 2))
        #expect(Self.share(fox, where: Self.isOrange) > 0.2, "\(size)pt 여우가 작거나 안 그려졌다")
        let coverage = try Self.coverage(fox, size: size)
        #expect(coverage > Self.minimumCoverage, "\(size)pt 여우가 원의 \(coverage) 만 덮는다")
    }
}

private enum AvatarRenderError: Error {
    case failed
}
