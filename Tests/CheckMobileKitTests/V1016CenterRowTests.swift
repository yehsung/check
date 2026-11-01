import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 소속 센터 행(읽기 전용) — 폰 1.0.16
//
// 미지정이면 배지가 안 그려져 그 사람이 해결 방법을 알 길이 없었다. 상태 판정은 코어 `CenterSettingsRowState`(맥과 한 벌)이고 바꾸는 길은 없다.
@MainActor
@Suite(.serialized) struct V1016CenterRowTests {
    private nonisolated static func isCenterGET(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/profiles" && request.method == "GET" && request.queryValue("select") == "center"
    }

    private static func harness(_ label: String, center: BaseLockedBox<MobileStubResponse>) async -> RankMeHarness {
        await RankMeHarness(label: label) { request in
            if isCenterGET(request) { return center.get() }
            if request.path == "/rest/v1/profiles", request.method == "GET", request.query.contains("avatar_url") {
                return .json(#"[{"display_name":"새벽","avatar_url":null}]"#)
            }
            return nil
        }
    }

    @Test("코어 판정: 모름 · 미지정 · 값 셋이 갈린다 · 모르는 서버값은 미지정으로 접는다")
    func coreState() {
        #expect(CenterSettingsRowState.of(loaded: false, center: "seoul") == .loading)
        #expect(CenterSettingsRowState.of(loaded: true, center: nil) == .unset)
        #expect(CenterSettingsRowState.of(loaded: true, center: "mars") == .unset)
        #expect(CenterSettingsRowState.of(loaded: true, center: "busan") == .chosen("부산"))
        #expect(CenterSettingsRowState.loading.value == "…")
        #expect(CenterSettingsRowState.unset.value == "미지정")
        #expect(CenterSettingsRowState.chosen("서울").value == "서울")
    }

    @Test("폰 문장: 미지정은 운영자에게 말하라고 · 값이 있으면 바꾸려면 운영자에게 · 폰에 없는 '아바타 모서리'를 말하지 않는다")
    func caption() {
        #expect(MeText.centerRowCaption(.loading) == "불러오는 중…")
        #expect(MeText.centerRowCaption(.unset) == "가입할 때 안 골랐어요. 운영자에게 말해 주세요.")
        let chosen = MeText.centerRowCaption(.chosen("서울"))
        #expect(chosen == "이름 줄에 배지로 보여요. 바꾸려면 운영자에게.")
        #expect(!chosen.contains("아바타"), "폰 배지는 아바타 모서리에 없다")
    }

    @Test("설정을 열면 읽는다: 미지정 · 값 · 머리가 이미 읽었으면 다시 묻지 않는다")
    func settingsLoads() async throws {
        let center = BaseLockedBox(MobileStubResponse.json(#"[{"center":null}]"#))
        let harness = await Self.harness("v1016-center-unset", center: center)
        defer { harness.tearDown() }
        let store = harness.me
        #expect(store.centerRowState == .loading, "읽기 전에 미지정이라고 단정했다")

        await store.loadSettings()
        #expect(store.centerRowState == .unset)
        #expect(!store.centerFailed)
        let asked = harness.requests.filter(Self.isCenterGET).count
        #expect(asked == 1)

        await store.loadSettings()
        #expect(harness.requests.filter(Self.isCenterGET).count == asked, "아는 값을 또 물었다")
        harness.expectNoForbiddenCalls()
        #expect(harness.requests(path: "/rest/v1/profiles", method: "PATCH").isEmpty, "읽기 전용 행이 프로필을 고쳤다")
    }

    @Test("머리가 읽은 값을 그대로 쓴다")
    func headerAnswerIsEnough() async {
        let center = BaseLockedBox(MobileStubResponse.json(#"[{"center":"seoul"}]"#))
        let harness = await Self.harness("v1016-center-header", center: center)
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadHeader()
        #expect(store.centerRowState == .chosen("서울"))
        let asked = harness.requests.filter(Self.isCenterGET).count
        await store.loadSettings()
        #expect(harness.requests.filter(Self.isCenterGET).count == asked)
    }

    @Test("못 읽으면 '미지정'이라 하지 않는다: 실패 줄 · 다시 시도로 회복 · 로그아웃이 비운다")
    func failureIsNotUnset() async {
        let center = BaseLockedBox(MobileStubResponse.networkFailure())
        let harness = await Self.harness("v1016-center-fail", center: center)
        defer { harness.tearDown() }
        let store = harness.me

        await store.loadHeader()
        #expect(store.headerState.hasLoaded, "머리는 센터 실패와 독립이다")
        #expect(store.centerRowState == .loading, "머리의 센터 조회가 실패했는데 미지정으로 접었다")

        await store.loadSettings()
        #expect(store.centerFailed)
        #expect(store.centerRowState == .loading)

        center.mutate { $0 = .json(#"[{"center":"busan"}]"#) }
        await store.loadSettings()
        #expect(!store.centerFailed)
        #expect(store.centerRowState == .chosen("부산"))

        store.reset()
        #expect(store.centerRowState == .loading, "앞 계정의 센터가 남았다")
        #expect(!store.centerFailed)
    }

    @Test("데모: 기본 계정은 값 · 기록 없는 계정 장면(`me/`)은 미지정 — 두 상태 다 찍을 수 있다")
    func demoFixtures() throws {
        let request = MobileStubRequest(method: "GET", host: MobileDemo.host, path: "/rest/v1/profiles",
                                        query: "select=center&id=eq.\(RankMeFixture.userID)", headers: [:], bodyText: "")
        let index = MobileDemoFixtures.load()
        struct Row: Decodable { let center: String? }
        func center(scene: String) throws -> CenterSettingsRowState {
            let entry = try #require(index.entry(for: request, scenario: scene))
            let row = try #require(try JSONDecoder().decode([Row].self, from: entry.data).first)
            return .of(loaded: true, center: row.center)
        }
        #expect(try center(scene: "me-settings") == .chosen("서울"))
        #expect(try center(scene: "me-") == .unset)
        #expect(index.duplicateKeys.isEmpty, "\(index.duplicateKeys)")
    }

    @Test("화면 계약: 팀 절의 팀 이름 다음 · 읽기 전용(쓰기·버튼 없음) · 실패 줄 갈래 · 나 탭 루트는 그대로")
    func viewContract() throws {
        let view = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeSettingsView.swift")
        let team = try #require(view.range(of: "private var teamSection: some View {"))
        let row = try #require(view.range(of: "centerRow", range: team.upperBound..<view.endIndex))
        let code = try #require(view.range(of: "MeText.inviteCodeTitle", range: team.upperBound..<view.endIndex))
        #expect(row.upperBound <= code.lowerBound, "센터 행이 팀 절의 자리에 없다")
        let start = try #require(view.range(of: "private var centerRow: some View {"))
        let end = try #require(view.range(of: "private var accountSection", range: start.upperBound..<view.endIndex))
        let body = view[start.upperBound..<end.lowerBound]
        #expect(body.contains("store.centerFailed"))
        #expect(body.contains("loadFailureRow(MeText.centerLoadFailed)"))
        #expect(body.contains("MeText.centerRowCaption(state)"))
        #expect(body.contains("Text(state.value)"))
        for banned in ["Button", "Picker", "Toggle", "Menu", "setMyCenter"] {
            #expect(!body.contains(banned), "읽기 전용 행에 \(banned) 가 있다")
        }
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeTab.swift")
        #expect(!tab.contains("centerRow"), "나 탭 루트를 늘였다")
    }
}
