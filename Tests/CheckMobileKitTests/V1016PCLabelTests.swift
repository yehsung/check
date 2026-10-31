import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

// MARK: - 1.0.16 '맥' / 'PC' — 기기를 종류대로 부른다 (2026-10-31 사용자 결정)
//
// ## 무엇이 거짓이었나
// Windows 앱이 붙으면 그 기기도 폰 화면에서 **'맥'으로** 읽혔다. 자리는 둘이다:
//  ① 이름을 한 번도 올린 적 없는 기기의 대체 이름(`이름 모를 맥 A1B2`) — 이름을 올린 기기는 사람이 적은
//     컴퓨터 이름이 그대로 머리글이라 종류 낱말이 아예 없다. 그래서 종류가 글자로 드러나는 자리가 여기뿐이다.
//  ② 근무 출처. 서버는 `20261101120000` 부터 origin `'windows'` 를 보내는데 폰이 그 값을 모르고
//     **`?? .unknown` → `.mac` 으로 접어** PC 에서 근무를 켠 사람에게 "맥에서 근무 중"이라고 말했다.
// 그리고 안내 문구 다섯 줄이 '맥 앱에서…'·'고른 맥은…' 이었다(PC 만 쓰는 사람에게 거짓).
//
// ## 이 스위트가 지키는 불변
// **맥만 쓰는 사람의 기기 이름은 글자가 1비트도 바뀌지 않는다.** 문구 다섯 줄은 사용자가 모두에게 바뀌는 쪽을
// 직접 골랐으므로(10-31) 불변에서 **빠진다** — 그 경계를 흐리면 "불변을 지켰다"는 말이 뜻을 잃는다.
//
// ## 왜 `device_id` 하나로 가르나
// 서버에 정본 함수가 이미 있다(`desktop_device_platform` — `like 'win:%'`). 거울로 쓰면 왕복이 늘지 않고
// 추측하는 칸이 없다. 그 글자가 두 저장소에서 같은지는 맥 타깃의 `V1016WindowsPrefixContractTests` 가 잰다.
@MainActor
@Suite(.serialized) struct V1016PCLabelTests {
    private static func device(_ id: String, _ label: String? = nil) -> AILimitDevice {
        AILimitDevice(deviceID: id, label: label, lastObservedAt: nil)
    }

    // MARK: ① 가르는 키

    @Test("소문자 `win:` 접두만 PC 다 — 대문자·다른 접두·빈 값은 맥(서버 프로브와 같은 입력)")
    func platformKeyMirrorsServer() {
        #expect(AILimitDevicePlatform.windowsPrefix == "win:")
        #expect(AILimitDevicePlatform.of(deviceID: "win:0b7e4b1c-1111-2222-3333-44445555a1b2") == .windows)
        // 서버 적용 프로브가 실제로 재는 값: 'WIN:abc' 는 windows 가 아니다.
        #expect(AILimitDevicePlatform.of(deviceID: "WIN:abc") == .mac, "대소문자를 느슨하게 받으면 서버와 판정이 갈린다")
        #expect(AILimitDevicePlatform.of(deviceID: "Win:abc") == .mac)
        #expect(AILimitDevicePlatform.of(deviceID: "A0A0A0A0-0000-0000-0000-000000000000") == .mac, "맥 식별자는 대문자 UUID 다")
        #expect(AILimitDevicePlatform.of(deviceID: "") == .mac)
        #expect(AILimitDevicePlatform.of(deviceID: "winner:1") == .mac, "콜론까지가 접두다(서버 like 'win:%' 도 이 값을 mac 으로 읽는다)")
    }

    // MARK: ② 대체 이름

    @Test("이름을 안 올린 기기: 맥은 `이름 모를 맥 ABCD` · PC 는 `이름 모를 PC ABCD`")
    func unnamedPrefixFollowsPlatform() {
        #expect(Self.device("DEVICE-9F8E").baseName == "이름 모를 맥 9F8E")
        #expect(Self.device("win:0b7e4b1c-1111-2222-3333-44445555a1b2").baseName == "이름 모를 PC A1B2")
        #expect(AILimitDevice.unnamedPrefix == "이름 모를 맥")
        #expect(AILimitDevice.unnamedPCPrefix == "이름 모를 PC")
    }

    @Test("이름을 올린 기기에는 종류 낱말이 없다 — 사람이 적은 컴퓨터 이름 그대로")
    func namedDeviceKeepsItsOwnName() {
        #expect(Self.device("win:0b7e-a1b2", "DESKTOP-4F2K").baseName == "DESKTOP-4F2K")
        #expect(Self.device("DEVICE-77AA", "거실 Mac mini").baseName == "거실 Mac mini")
    }

    @Test("맥만 있는 명부는 글자가 1비트도 안 바뀐다 — 이 판에서 지킬 불변")
    func macOnlyRosterIsUnchanged() {
        let names = AILimitDeviceRoster.displayNames([
            Self.device("DEVICE-9F8E"), Self.device("DEVICE-2B1C"),
            Self.device("AAAA-77AA", "Mac mini"), Self.device("BBBB-88BB", "Mac mini"),
            Self.device("CCCC-99CC", "사무실 iMac"),
        ])
        #expect(names["DEVICE-9F8E"] == "이름 모를 맥 9F8E")
        #expect(names["DEVICE-2B1C"] == "이름 모를 맥 2B1C")
        #expect(names["AAAA-77AA"] == "Mac mini (77AA)", "겹친 이름의 꼬리 규칙이 바뀌었다")
        #expect(names["BBBB-88BB"] == "Mac mini (88BB)")
        #expect(names["CCCC-99CC"] == "사무실 iMac", "안 겹치는 이름에는 아무것도 붙지 않는다")
    }

    @Test("맥 하나 + PC 하나가 둘 다 이름이 없어도 서로 갈린다 — 종류 낱말이 이미 다르므로 꼬리가 안 붙는다")
    func macAndPCUnnamedDoNotCollide() {
        let parts = AILimitDeviceRoster.displayNameParts([
            Self.device("DEVICE-A1B2"), Self.device("win:0000-0000-0000-a1b2"),
        ])
        #expect(parts["DEVICE-A1B2"]?.base == "이름 모를 맥 A1B2" && parts["DEVICE-A1B2"]?.tail == nil)
        #expect(parts["win:0000-0000-0000-a1b2"]?.base == "이름 모를 PC A1B2")
        #expect(parts["win:0000-0000-0000-a1b2"]?.tail == nil, "꼬리까지 붙으면 같은 꼬리 둘이 나란히 서서 가르는 뜻을 잃는다")
    }

    // MARK: ③ 문구 다섯 줄 (사용자가 글자를 직접 골랐다 — 10-31)

    @Test("문구 다섯 줄이 '맥·PC' 다 — 앱과 위젯이 같은 행동을 같은 말로 가리킨다")
    func fiveCopyLines() {
        #expect(AILimitSurfaceText.noVisibleProviders == "맥·PC 앱에서 AI 도구에 로그인하고 리밋 보기를 켜면 보여요")
        #expect(AILimitSurfaceText.substitutedMainDevice == "고른 기기는 지금 보여 줄 숫자가 없어서 다른 기기를 보여 주고 있어요")
        #expect(MeText.inviteShareMessage(teamName: "우리팀", code: "ABCD1234")
            .hasSuffix("\n맥·PC 앱에서 가입할 때 이 코드를 입력하면 같은 팀이 돼요."))
        #expect(AingWidgetText.noTeam == "맥·PC 앱에서 팀에 참여하면 보여요")
        #expect(NowText.workingFooter == "근무는 맥·PC나 이 탭 맨 위 버튼으로 시작하고 끝내요")
        // 폰과 위젯이 **같은 상수**에서 가져온다(한쪽만 바뀌는 날을 막는다).
        #expect(MeText.aiLimitsNoProviders == AILimitSurfaceText.noVisibleProviders)
        #expect(MeText.aiLimitsSubstitutedDevice == AILimitSurfaceText.substitutedMainDevice)
        // 죽은 대체 문장은 **그대로 둔다**(서버에 폰 근무 함수가 없을 때만 쓰는 옛 문장).
        #expect(NowText.workingFooterMacOnly == "근무 시작과 종료는 맥 앱에서 해요")
    }

    // MARK: ④ 근무 출처 — 동작으로 잰다

    static let touchWindows = #"""
    {"status":"ok","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","ended_at":null,"origin":"windows"},
     "server_now":"2026-09-17T05:05:00+00:00"}
    """#
    /// 우리가 **모르는** 값(넷째 기기가 생기는 날). 특정 기기 이름으로 접으면 안 된다.
    static let touchUnknownOrigin = #"""
    {"status":"ok","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","ended_at":null,"origin":"linux"},
     "server_now":"2026-09-17T05:05:00+00:00"}
    """#

    private func activateAndTouch(_ h: NowHarness) async {
        await h.activate()
        await h.store.phoneTouchTask?.value
        await h.settle()
    }

    @Test("서버 origin 'windows' → 'PC에서 근무 중' · 버튼 아래 PC 안내 · 종료 확인도 PC")
    func windowsOriginSpeaksPC() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(Self.touchWindows))
        await h.launch()
        await activateAndTouch(h)
        let card = try #require(h.store.myCard(now: h.clock.now))
        #expect(card.origin == .windows, "서버가 보낸 'windows' 를 폰이 못 읽었다")
        #expect(card.stateText == NowText.workingOnPC && card.stateText == "PC에서 근무 중")
        #expect(h.store.myWorkOrigin == .windows)
        #expect(NowText.workStopConfirmMessage(origin: .windows).contains("PC에서 연 근무도"))
        #expect(!NowText.workStopConfirmMessage(origin: .windows).contains("맥"), "PC 사용자에게 남의 기기 이름을 적었다")
        #expect(NowText.pcWorkCaption == "PC에서 연 근무예요 · 여기서 끝낼 수도 있어요")
        #expect(NowText.alreadyWorkingOnPC == "이미 PC에서 근무 중이에요")
    }

    @Test("이미 PC 에서 근무 중인데 폰에서 시작을 누르면 '이미 PC에서 근무 중이에요' — 맥으로 말하지 않는다")
    func alreadyWorkingOnWindowsSpeaksPC() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(#"{"status":"not_working","last":null,"server_now":"2026-09-17T05:05:00+00:00"}"#))
        h.server.override("rpc.work_phone_start", .json(#"""
        {"status":"already_working","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","ended_at":null,"origin":"windows"},
         "server_now":"2026-09-17T05:05:00+00:00"}
        """#))
        await h.launch()
        await activateAndTouch(h)
        await h.store.clockIn()
        #expect(h.store.workNotice == NowText.alreadyWorkingOnPC)
        #expect(h.store.phoneSession?.origin == .windows)
    }

    @Test("모르는 origin 은 `.mac` 으로 접지 않는다 — '근무 중'으로만 말한다(넷째 값이 와도 남의 이름을 안 적는다)")
    func unknownOriginIsNotFoldedToMac() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(Self.touchUnknownOrigin))
        await h.launch()
        await activateAndTouch(h)
        let card = try #require(h.store.myCard(now: h.clock.now))
        #expect(h.store.phoneSession?.origin == .unknown, "모르는 값을 특정 기기로 접었다")
        #expect(card.stateText != NowText.workingOnMac, "이 접기가 바로 PC 사용자에게 '맥에서 근무 중'을 말하던 자리다")
        #expect(card.stateText == NowText.working)
    }

    @Test("`.mac` 으로 접는 줄이 소스에 되살아나지 않았다 · 뷰가 PC 문구를 실제로 그린다")
    func foldIsGoneAndViewsUsePCText() throws {
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowStorePhoneWork.swift")
        #expect(!store.contains("origin == .unknown ? .mac"), "모르는 값을 맥으로 접는 줄이 되살아났다")
        #expect(store.contains("NowText.alreadyWorkingOnPC"), "'이미 PC에서 근무 중' 을 아무도 쓰지 않는다")
        let models = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowModels.swift")
        #expect(models.contains("case .windows: return NowText.workingOnPC"), "상태 줄이 windows 를 안 가른다")
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        #expect(tab.contains("NowText.pcWorkCaption"), "버튼 아래 안내가 PC 문구를 안 그린다")
    }
}
