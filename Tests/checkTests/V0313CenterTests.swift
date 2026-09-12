import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.13 소속 센터(서울/부산)
//
// 이 스위트가 지키는 것은 여섯 가지다. 전부 **조용히 틀릴 수 있는** 자리라서 여기 모았다:
//  ① 서버값 → 화면 글자 변환이 한 곳이고, 모르는 값이 서울로 접히지 않는다.
//  ② 배지는 overlay 라 **폭 예산을 1pt 도 안 쓴다**(렌더 픽셀로 증명한다 — 계산으로는 못 증명한다).
//  ③ center 키가 **없는** 구버전 RPC 응답으로도 네 모델이 전부 디코딩된다(브루 배포가 db push 보다 먼저 나간다).
//  ④ 가입 화면에서 센터를 안 고르면 가입이 막힌다(기본 서울이면 부산 연수생이 조용히 서울이 된다).
//  ⑤ 로딩 플래그 없이 nil 을 '미지정'으로 읽지 않는다(로그인 직후 깜빡임 + 유령 PATCH).
//  ⑥ 설정 창 콘텐츠가 여전히 창 높이 안에 있다(행 하나가 통째로 사라지는 실패 모드).

// MARK: - ① 변환은 한 곳에서만 · 모르는 값은 nil

@Test
func 센터_서버값을_화면글자로_바꾸고_모르는_값은_nil_이다() {
    #expect(CenterLabel.display("seoul") == "서울")
    #expect(CenterLabel.display("busan") == "부산")

    // ★ 여기가 이 기능의 급소다. 모르는 값을 서울로 접으면 화면은 멀쩡해 보이고 아무 테스트도 안 빨개지는데
    //   **틀린 사실을 단정한다**(세 번째 센터가 생기는 날, 구버전 앱이 그 사람을 서울이라고 말한다).
    #expect(CenterLabel.display(nil) == nil)
    #expect(CenterLabel.display("") == nil)
    #expect(CenterLabel.display("daejeon") == nil)
    #expect(CenterLabel.display("gwangju") == nil)
    // 대문자·공백도 받아 주지 않는다 — 관대하게 접기 시작하면 서버가 실수로 보낸 값을 클라가 덮어 감춘다.
    #expect(CenterLabel.display("Seoul") == nil)
    #expect(CenterLabel.display("SEOUL") == nil)
    #expect(CenterLabel.display(" seoul") == nil)
    #expect(CenterLabel.display("서울") == nil, "화면 글자를 서버값 자리에 넣는 실수도 걸러야 한다")

    // 역방향(선택 UI 라벨 → 서버값)도 같은 엄격함이다.
    #expect(CenterLabel.serverValue(forDisplay: "서울") == "seoul")
    #expect(CenterLabel.serverValue(forDisplay: "부산") == "busan")
    #expect(CenterLabel.serverValue(forDisplay: "대전") == nil)
    #expect(CenterLabel.serverValue(forDisplay: nil) == nil)

    #expect(CenterLabel.isKnown("seoul"))
    #expect(CenterLabel.isKnown("busan"))
    #expect(!CenterLabel.isKnown(nil))
    #expect(!CenterLabel.isKnown("daejeon"))

    // 값은 **둘뿐**이다(사장님 확정 3 — 대전·광주 없음, 기수 축 없음).
    #expect(CenterLabel.allServerValues == ["seoul", "busan"])
}

@Test
func 화면_글자는_CenterLabel_밖에_적혀_있지_않다() throws {
    // "변환은 한 곳에서만"을 **사실로** 잰다. 네 화면과 두 입력 경로가 각자 "서울"/"부산" 을 적기 시작하면
    // 언젠가 한 곳만 모르는 값을 서울로 접거나 한 곳만 라벨이 어긋나고, 그 결함은 화면이 멀쩡해 보인다.
    // 주석은 걷어낸다 — 안 그러면 설명을 지워야만 초록이 된다(하우스 규칙).
    let sources = try v0313SourceFiles()
    #expect(sources.count > 30, "소스 목록이 비면 이 검사는 헛돈다 (실측 \(sources.count)개)")

    var offenders: [String] = []
    for url in sources where url.lastPathComponent != "CenterLabel.swift" {
        let code = v0313StrippingComments(try String(contentsOf: url, encoding: .utf8))
        if code.contains("\"서울\"") || code.contains("\"부산\"") {
            offenders.append(url.lastPathComponent)
        }
    }
    #expect(offenders.isEmpty, "센터 라벨 리터럴이 CenterLabel 밖에 있다: \(offenders)")

    // 반대쪽도 못 박는다: 서버 어휘를 화면 코드가 직접 비교하면 그 자리가 두 번째 변환점이 된다.
    for url in sources where url.lastPathComponent != "CenterLabel.swift" {
        let code = v0313StrippingComments(try String(contentsOf: url, encoding: .utf8))
        #expect(
            !code.contains("\"seoul\"") && !code.contains("\"busan\""),
            "\(url.lastPathComponent) 가 서버 어휘를 직접 적고 있다 — CenterLabel 을 통해라"
        )
    }
}

// MARK: - ② 배지는 폭 예산을 바꾸지 않는다 (overlay 계약 — 렌더로 증명한다)

@MainActor
@Test
func 배지는_아바타의_레이아웃_크기를_1pt_도_바꾸지_않는다() throws {
    // 가장 작은 증명부터: 아바타 **자체**의 자연 크기가 같아야 한다. overlay 는 자식의 크기를 제안받을 뿐
    // 부모의 크기에 기여하지 않는다 — 이 성질이 깨지면(예: overlay 를 HStack 으로 바꾸면) 여기서 먼저 빨개진다.
    for size in [CGFloat(22), 26, 30] {
        let bare = try v0313Bitmap(CheckAvatarView(name: "조현준", size: size).fixedSize(), scale: 2)
        let badged = try v0313Bitmap(
            CheckAvatarView(name: "조현준", size: size, center: "부산").fixedSize(), scale: 2)
        // 배지는 아바타 **밖으로** 넘쳐 그려지므로(offset x:4 y:2) 그림의 픽셀 크기는 커질 수 있다.
        // 레이아웃이 안 바뀌었다는 증거는 그림 크기가 아니라 아래 행 렌더의 '이름 띠 동일'이다.
        // 여기서 잡는 것은 **폭발적 변화**다: 배지가 아바타 자리를 밀면 폭이 배지 폭(≈24pt)만큼 늘어난다.
        let grewBy = CGFloat(badged.pixelsWide - bare.pixelsWide) / 2
        #expect(grewBy <= 8, "아바타 \(size)pt: 배지가 폭을 \(grewBy)pt 나 늘렸다 — overlay 가 아니라 자리를 먹고 있다")
    }
}

@MainActor
@Test
func 네_화면_모두_배지가_이름_자리를_건드리지_않는다() throws {
    // **이것이 이 기능의 계약이다.** 배지가 있는 행과 없는 행을 **한 번의 렌더 안에** 위아래로 겹쳐 그리고,
    // 두 행의 픽셀 차이가 **아바타 모서리 안에서 끝나는지**를 본다.
    //
    // 왜 한 번의 렌더인가: ImageRenderer 를 두 번 부르면 같은 뷰가 매번 같은 픽셀을 내지 않는다
    // (실측: 같은 행을 네 번 그렸더니 1·2번과 3·4번이 443열 달랐다 — 폰트/그림자 캐시 예열로 보인다).
    // 그 흔들림 위에서 "다르다"를 세면 이 테스트는 결함이 아니라 렌더러를 재게 된다.
    //
    // 왜 픽셀인가: 이름 줄은 lineLimit(1) + minimumScaleFactor 라 **넘쳐도 높이가 안 변한다** =
    // 레이아웃 테스트로는 절대 안 잡히고, 넘친 순간의 증상은 말줄임(글자 통째 오독)이다.
    // 이름 몫이 1pt 라도 줄면 긴 이름의 축소율이 바뀌어 이름 띠 전체의 픽셀이 달라진다 — 그걸 잰다.
    //
    // 경계값은 행 조립에서 그대로 따온다(배지는 아바타 오른쪽으로 offset x:4 만큼 넘친다):
    //  · 콕찌르기  : leading 8 + 바 3 + 간격 10 → 아바타 [21,47] · 배지 우단 51 · 이름 시작 57
    //  · 토큰 순위판: leading 8 + 바 3 + 간격 10 → 아바타 [21,51] · 배지 우단 55 · 이름 시작 61
    //  · 팀 리그   : leading 10                → 아바타 [10,40] · 배지 우단 44 · 이름 시작 51
    //  · 미니게임  : leading 5 + 배지칸 22 + 간격 7 → 아바타 [34,56] · 배지 우단 60 · 이름 시작 63
    for screen in v0313Screens {
        let scale = CGFloat(2)
        let rowHeightPx = Int(screen.height * scale)
        let paired = try v0313Bitmap(
            VStack(spacing: 0) {
                screen.make(nil).frame(width: screen.width, height: screen.height)
                screen.make("부산").frame(width: screen.width, height: screen.height)
            },
            scale: scale
        )
        #expect(paired.pixelsHigh == rowHeightPx * 2,
                "\(screen.name): 두 행을 겹쳐 그린 그림의 높이가 어긋난다 (실측 \(paired.pixelsHigh)px)")

        let differing = v0313DifferingColumnsBetweenHalves(paired, rowHeightPx: rowHeightPx)
        // (1) 배지가 실제로 그려졌다. 이게 비면 아래 (2)(3)은 공짜로 통과하는 거짓 초록이다.
        #expect(!differing.isEmpty, "\(screen.name): 배지를 줬는데 픽셀이 하나도 안 바뀌었다 — 배선이 끊겼다")
        // (2) 달라진 픽셀이 전부 배지가 그려지는 띠 안에서 끝난다(경계 1pt 는 안티에일리어싱 몫).
        let rightmost = CGFloat(differing.max() ?? 0) / scale
        #expect(rightmost <= screen.badgeRight + 1,
                "\(screen.name): 배지 때문에 x=\(rightmost)pt 까지 그림이 바뀌었다 (배지 우단 \(screen.badgeRight)pt)")
        // (3) **이름 띠는 픽셀까지 같다.** 폭 예산이 바뀌었다면 여기가 먼저 달라진다.
        let nameStartPx = Int(screen.nameStart * scale)
        #expect(differing.allSatisfy { $0 < nameStartPx },
                "\(screen.name): 이름 띠(x ≥ \(screen.nameStart)pt)의 픽셀이 달라졌다 — 배지가 이름 몫을 먹었다")
    }
}

@MainActor
@Test
func center_가_nil_이면_네_화면_어디에도_배지가_안_그려진다() throws {
    // "모르는 값이 오면 배지를 안 그린다"를 화면에서 확인한다. 모르는 서버값은 경계에서 이미 nil 로 접히므로
    // (아래 디코딩 테스트) 화면이 봐야 할 것은 nil 하나뿐이고, 그때 두 행은 **픽셀 하나까지** 같아야 한다.
    // 위 테스트와 같은 한 번-렌더 비교라, 이 초록은 "차이가 0"을 실제로 증명한다.
    let unknownFolded = CenterLabel.display("daejeon")
    #expect(unknownFolded == nil, "모르는 값이 화면 글자로 접혔다")

    for screen in v0313Screens {
        let scale = CGFloat(2)
        let rowHeightPx = Int(screen.height * scale)
        let paired = try v0313Bitmap(
            VStack(spacing: 0) {
                screen.make(nil).frame(width: screen.width, height: screen.height)
                screen.make(unknownFolded).frame(width: screen.width, height: screen.height)
            },
            scale: scale
        )
        let differing = v0313DifferingColumnsBetweenHalves(paired, rowHeightPx: rowHeightPx)
        #expect(differing.isEmpty,
                "\(screen.name): 모르는 센터가 그림을 바꿨다 — 서울로 접었거나 원문을 그대로 그렸다 (실측 \(differing.count)열)")
    }
}

// MARK: - ③ Optional 디코딩 — center 키가 없는 구버전 RPC 응답

@Test
func 구버전_RPC_응답에_center_키가_없어도_네_모델이_전부_디코딩된다() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    // 콕찌르기 디렉토리 — 이 디코드가 throw 되면 목록이 전원 사라지고 찔림까지 같이 죽는다.
    let pokeOld = #"[{"user_id":"u1","display_name":"조현준","avatar_url":null,"is_working":true}]"#
    let pokeRows = try decoder.decode([PokeDirectoryRow].self, from: Data(pokeOld.utf8))
    #expect(pokeRows.first?.center == nil)
    #expect(pokeRows.toPokeDirectoryEntries().first?.center == nil, "키가 없으면 배지도 없다")

    // 토큰 순위판.
    let tokenOld = """
    [{"user_id":"u1","display_name":"조현준","avatar_url":null,"claude_input":1,"claude_output":2,
      "claude_cache_read":3,"claude_cache_creation":4,"codex_input":5,"codex_output":6,"total":21}]
    """
    let tokenRows = try decoder.decode([TokenBoardRow].self, from: Data(tokenOld.utf8))
    #expect(tokenRows.first?.center == nil)
    #expect(tokenRows.toTokenBoardEntries().first?.center == nil)

    // 팀 리그.
    let leagueOld = """
    [{"team_id":"t1","team_name":"AIng","weekly_goal_hours":40,"total_seconds":100,"working_count":1,"member_count":3}]
    """
    let leagueRows = try decoder.decode([TeamLeaderboardRow].self, from: Data(leagueOld.utf8))
    #expect(leagueRows.first?.center == nil)

    // 미니게임 순위 · 어제 1등.
    let boardOld = #"[{"user_id":"u1","display_name":"윤","avatar_url":null,"best_score":980,"best_at":null,"plays":3}]"#
    #expect(try decoder.decode([MiniGameBoardRow].self, from: Data(boardOld.utf8)).first?.center == nil)
    let winnerOld = #"[{"day":"2026-09-11","user_id":"u1","display_name":"윤","avatar_url":null,"score":980,"awarded":true}]"#
    #expect(try decoder.decode([MiniGameWinnerRow].self, from: Data(winnerOld.utf8)).first?.center == nil)

    // 내 센터 1컬럼 응답도 빈 배열·null 을 견딘다(컬럼은 있는데 아직 안 고른 사람).
    #expect(try decoder.decode([ProfileCenterRow].self, from: Data("[]".utf8)).first == nil)
    #expect(try decoder.decode([ProfileCenterRow].self, from: Data(#"[{"center":null}]"#.utf8)).first?.center == nil)
}

@Test
func 새_RPC_응답의_center_는_화면_글자로_접혀_들어온다() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let poke = #"""
    [{"user_id":"u1","display_name":"조현준","avatar_url":null,"is_working":true,"center":"busan"},
     {"user_id":"u2","display_name":"윤","avatar_url":null,"is_working":false,"center":"seoul"},
     {"user_id":"u3","display_name":"킹예성","avatar_url":null,"is_working":false,"center":null},
     {"user_id":"u4","display_name":"영식","avatar_url":null,"is_working":false,"center":"daejeon"}]
    """#
    let entries = try decoder.decode([PokeDirectoryRow].self, from: Data(poke.utf8))
        .toPokeDirectoryEntries()
        .sorted { $0.userID < $1.userID }
    #expect(entries.map(\.center) == ["부산", "서울", nil, nil],
            "모르는 값(daejeon)은 nil 이어야 한다 — 서울로 접으면 틀린 사실을 단정한다")

    let token = """
    [{"user_id":"u1","display_name":"조현준","avatar_url":null,"claude_input":1,"claude_output":0,
      "claude_cache_read":0,"claude_cache_creation":0,"codex_input":0,"codex_output":0,"total":1,"center":"seoul"}]
    """
    #expect(try decoder.decode([TokenBoardRow].self, from: Data(token.utf8)).toTokenBoardEntries().first?.center == "서울")
}

// MARK: - ④ 가입: 안 고르면 막힌다

@MainActor
@Test
func 가입은_소속_센터를_고르기_전까지_막힌다() {
    let store = v0313Store()

    // 기본은 **미선택**이다. 서울을 미리 넣어 두면 부산 연수생이 아무것도 안 하고 서울로 잡힌다.
    #expect(store.signupCenter == nil, "가입 화면의 센터 기본값은 미선택이어야 한다")
    #expect(store.canSync, "키는 있다 — 막히는 이유가 센터 하나임을 분명히 한다")
    #expect(!store.canSubmitSignUp, "센터 미선택인데 가입 버튼이 살아 있다")

    // 로그인은 막지 않는다(이미 있는 계정의 센터는 서버가 안다).
    #expect(store.canSync)

    store.signupCenter = CenterLabel.seoul
    #expect(store.canSubmitSignUp)
    store.signupCenter = CenterLabel.busan
    #expect(store.canSubmitSignUp)

    // 키가 없으면 센터를 골라도 막힌다(종전 canSync 게이트가 살아 있어야 한다).
    let keyless = WorkTimerStore(
        environment: [:], defaults: UserDefaults(suiteName: "v0313-keyless-\(UUID().uuidString)")!)
    keyless.signupCenter = CenterLabel.seoul
    #expect(!keyless.canSubmitSignUp)
}

@MainActor
@Test
func Enter_제출_경로도_센터_없이는_가입을_시작하지_않는다() {
    // 버튼은 비활성이어도 **Enter 제출 경로가 따로 있다.** 그 길로 새면 서버가 center 없이 계정을 만들어
    // 영영 미지정인 사람이 생긴다(설정에서 고칠 수는 있지만, 본인은 자기가 미지정인 줄 모른다).
    let store = v0313Store()
    store.displayName = "조현준"
    store.email = "member@example.com"
    store.password = "team-password"
    store.isCreateTeamMode = true
    store.createTeamName = "새벽 러너스"

    #expect(store.signUp() == nil, "센터 미선택인데 가입 Task 가 떴다")
    #expect(store.syncMessage == "소속 센터를 골라 주세요")

    store.signupCenter = CenterLabel.busan
    let task = store.signUp()
    #expect(task != nil, "센터를 고른 뒤엔 가입이 시작돼야 한다")
    task?.cancel()
}

@MainActor
@Test
func 가입_요청의_메타데이터에_센터가_실린다() async throws {
    // display_name 과 **같은 자리**(raw_user_meta_data)에 얹는다 — 서버 트리거가 거기서 읽으므로 왕복이 안 는다.
    let host = "v0313-signup"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    _ = try await service.signUp(
        email: "member@example.com", password: "team-password", displayName: "조현준", center: "busan")
    let body = URLProtocolStub.bodyText(forHost: host)
    #expect(body.contains("\"display_name\":\"조현준\""))
    #expect(body.contains("\"center\":\"busan\""))

    // nil 이면 **키를 아예 싣지 않는다** — 이 변경 전과 바이트가 같아야 가입 경로에 회귀가 없다.
    let bareHost = "v0313-signup-bare"
    let bareService = SupabaseWorkService(
        projectURL: URL(string: "http://\(bareHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    _ = try await bareService.signUp(
        email: "member@example.com", password: "team-password", displayName: "조현준")
    #expect(!URLProtocolStub.bodyText(forHost: bareHost).contains("center"))
}

// MARK: - ⑤ 로딩 플래그 — nil 을 '미지정'으로 읽지 않는다

@MainActor
@Test
func 로딩_플래그가_없으면_미지정으로_읽지_않는다() {
    // ★ 깜빡임 회귀의 본체. `myCenter == nil` 은 두 가지 뜻이고 그 둘은 정반대다:
    //   "서버가 아직 말 안 했다"(loading) vs "서버가 없다고 말했다"(unset).
    //   플래그 없이 읽으면 로그인 직후 창이 '미지정'으로 한 번 그려졌다가 GET 이 도착하며 값으로 바뀐다.
    #expect(CenterSettingsRowState.of(loaded: false, center: nil) == .loading)
    #expect(CenterSettingsRowState.of(loaded: false, center: nil) != .unset)
    // 로딩 중에 우연히 값이 들어 있어도(옛 계정 미러 잔재 등) 아직은 '받았다'가 아니다.
    #expect(CenterSettingsRowState.of(loaded: false, center: "seoul") == .loading)
    #expect(CenterSettingsRowState.of(loaded: true, center: nil) == .unset)
    #expect(CenterSettingsRowState.of(loaded: true, center: "seoul") == .chosen("서울"))
    #expect(CenterSettingsRowState.of(loaded: true, center: "busan") == .chosen("부산"))
    // 모르는 서버값은 '미지정'으로 접는다 — 억지로 서울을 칠하지 않는다.
    #expect(CenterSettingsRowState.of(loaded: true, center: "daejeon") == .unset)

    // 로딩 중에는 어느 칸도 채우지 않고 누를 수도 없다(그 찰나의 누름은 유령 PATCH 가 된다).
    #expect(CenterSettingsRowState.loading.selection(center: "seoul") == nil)
    #expect(!CenterSettingsRowState.loading.isEnabled)
    #expect(CenterSettingsRowState.unset.selection(center: nil) == nil)
    #expect(CenterSettingsRowState.unset.isEnabled)
    #expect(CenterSettingsRowState.chosen("서울").selection(center: "seoul") == "seoul")

    // 세 상태의 문장이 서로 달라야 이 행이 무언가를 말한다.
    let captions = Set([
        CenterSettingsRowState.loading.caption,
        CenterSettingsRowState.unset.caption,
        CenterSettingsRowState.chosen("부산").caption
    ])
    #expect(captions.count == 3)

    // 스토어의 출발점도 '아직 모름'이어야 한다.
    let store = v0313Store()
    #expect(store.myCenter == nil)
    #expect(!store.myCenterLoaded)
    #expect(CenterSettingsRowState.of(loaded: store.myCenterLoaded, center: store.myCenter) == .loading)
}

@MainActor
@Test
func 설정_행은_로딩_플래그를_실제로_읽는다() throws {
    // 위 순수 판정이 아무리 옳아도 화면이 안 부르면 소용없다. 플래그를 빠뜨린 뮤턴트를 잡는다.
    let code = v0313Normalized(try v0313Source("CheckSettingsView.swift"))
    #expect(code.contains("CenterSettingsRowState.of(loaded: store.myCenterLoaded, center: store.myCenter)"))
    #expect(code.contains("CenterSettingsRow(store: store)"), "내 정보 섹션에 센터 행이 붙어 있어야 한다")
}

@MainActor
@Test
func 모르는_값은_서버로_나가지_않고_미러도_안_바뀐다() {
    // check 제약(23514)에 걸릴 값을 보내면 화면만 바뀌고 서버는 안 바뀐다 — 그런 요청은 나갈 이유가 없다.
    let store = v0313Store()
    store.myCenter = "seoul"
    store.myCenterLoaded = true
    store.setMyCenter("daejeon")
    #expect(store.myCenter == "seoul", "모르는 값이 미러를 덮었다")
    store.setMyCenter("busan")
    #expect(store.myCenter == "busan")
    #expect(store.myCenterLoaded, "사용자가 직접 고른 값은 로드 완료로 간주한다(폴링이 덮지 않게)")
}

@MainActor
@Test
func 센터_로드는_실패와_미지정을_가르고_실패하면_다시_묻는다() async {
    // ★ 로그인 후 설정 로드는 **한 번만** 돈다(tokenUsageCollectLoaded 래치). 거기서 blip 으로 실패했는데
    //   플래그가 서 버리면 그 세션 내내 설정 창이 '불러오는 중'에 멈춰 **자기 센터를 못 고친다.**
    //   그래서 실패는 플래그를 안 세우고, 설정 창이 뜰 때 다시 묻는다.
    func store(host: String) -> WorkTimerStore {
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: UserDefaults(suiteName: "v0313-load-\(UUID().uuidString)")!
        )
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        return store
    }

    // (1) 비로그인이면 아무 일도 안 한다.
    let signedOut = store(host: "v0313-signed-out")
    await signedOut.loadMyCenterIfNeeded()
    #expect(!signedOut.myCenterLoaded)
    #expect(URLProtocolStub.requests(forHost: "v0313-signed-out").isEmpty)

    // (2) 실패는 플래그를 안 세운다 — 다음 기회에 다시 묻는다.
    let failing = store(host: "schema-missing")
    failing.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: "me")
    await failing.loadMyCenterIfNeeded()
    #expect(!failing.myCenterLoaded, "실패했는데 '받았다'로 래치됐다 — 그 세션 내내 '불러오는 중'에 멈춘다")
    #expect(failing.myCenter == nil)

    // (3) 성공이면 값이 nil(= 아직 안 고른 사람)이어도 플래그가 선다 — '미지정'을 정직하게 그린다.
    let okHost = "v0313-center-load"
    let ok = store(host: okHost)
    ok.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: "me")
    await ok.loadMyCenterIfNeeded()
    #expect(ok.myCenterLoaded)
    #expect(ok.myCenter == nil)
    let afterFirst = URLProtocolStub.requests(forHost: okHost).count
    #expect(afterFirst > 0)

    // (4) 이미 알고 있으면 왕복이 안 는다(설정 창을 여닫아도 요청이 쌓이지 않는다).
    await ok.loadMyCenterIfNeeded()
    #expect(URLProtocolStub.requests(forHost: okHost).count == afterFirst)

    // (5) 설정 창이 실제로 그 복구 경로를 부른다 — 안 부르면 위 규약이 코드에만 있고 화면엔 없다.
    let settings = v0313Normalized((try? v0313Source("CheckSettingsView.swift")) ?? "")
    #expect(settings.contains(".task { await store.loadMyCenterIfNeeded() }"))
}

@Test
func 내_센터는_별도_GET_이다() async throws {
    // ★ 기존 설정 GET 의 select 에 끼우면 마이그레이션 전 맥에서 42703 으로 그 요청이 통째로 400 이 되어
    //   **토큰 공개·수집·집중 모드까지** 같이 죽는다(SupabaseWorkService 1543~1552 가 그 사고를 기록한다).
    let host = "v0313-center-get"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    _ = try? await service.fetchMyCenter(accessToken: "token", userID: "u1")
    let queries = URLProtocolStub.requests(forHost: host).compactMap { $0.url?.query }
    #expect(queries.contains { $0.contains("select=center") },
            "center 만 고르는 GET 이 따로 나가야 한다 (실측 \(queries))")
    // 그 요청이 다른 컬럼을 끌고 가면 별도 GET 의 의미가 없다.
    #expect(!queries.contains { $0.contains("select=center") && $0.contains("token_usage") })

    let settingsSource = v0313StrippingComments(try v0313Source("SupabaseWorkService.swift"))
    #expect(!settingsSource.contains("token_usage_public,token_usage_collect,focus_mode,center"),
            "센터를 기존 설정 GET 의 select 에 끼워 넣지 마라")
}

@MainActor
@Test
func 로그아웃은_센터_미러와_가입_선택을_함께_비운다() {
    // 계정에 묶인 값이다. 남기면 (1) 새 계정의 설정 창에 **앞 사람의 센터**가 이미 골라진 채로 뜨고,
    // (2) 가입 폼에서는 앞 사람이 고른 칸이 눌린 채라 아무것도 안 고르고도 가입 버튼이 살아 있다
    // (= 미선택 게이트가 무력화된다).
    let store = v0313Store()
    store.myCenter = CenterLabel.busan
    store.myCenterLoaded = true
    store.signupCenter = CenterLabel.busan

    store.signOut()

    #expect(store.myCenter == nil)
    #expect(!store.myCenterLoaded, "로딩 플래그가 남으면 앞 사람의 값이 '서버가 확인해 준 값'으로 읽힌다")
    #expect(store.signupCenter == nil)
    #expect(!store.canSubmitSignUp)
}

// MARK: - ⑥ 설정 창 높이 계약 · 네 화면 배선

@MainActor
@Test
func 설정창_콘텐츠는_센터_행이_붙어도_창_안에_있다() throws {
    // 470pt 계약(RealtimeLinkTests 의 그것과 같은 종류). 넘치면 **설정 항목 하나가 통째로 사라진다** —
    // 각주 한 줄이 잘리는 것과는 다른 결과라, 여유가 있어도 이 계약은 지킨다.
    // **가장 높은 상태로 잰다**: 센터 행의 안내 한 줄이 제일 긴 것이 '미지정'(아직 안 고른 계정)이라
    //   좁은 창에서 두 줄로 접힐 수 있는 유일한 상태다. 고른 상태로만 재면 그 줄바꿈을 영영 못 본다.
    // 이 렌더는 이 파일에 **하나뿐**이다(설정 창 렌더를 늘리면 옆 스위트의 팝오버 비교가 흔들린다는 실측 기록).
    let store = v0313Store()
    store.myCenterLoaded = true
    let image = try v0313Bitmap(
        CheckSettingsView(store: store, launchAtLoginSeed: false)
            .frame(width: CheckSettingsView.preferredWidth), scale: 2)
    let height = CGFloat(image.pixelsHigh) / 2
    #expect(height <= CheckSettingsWindowController.defaultContentSize.height,
            "설정 콘텐츠 \(height)pt 가 창 \(CheckSettingsWindowController.defaultContentSize.height)pt 를 넘었다")
    // 하한은 **센터 행이 실제로 자리를 차지한다**는 증거다. 실측(2026-09-12, preferredWidth 380):
    //   센터 행 있음 465pt · 행을 빼면 410pt. 그래서 440 은 "행 하나가 통째로 사라졌다"를 정확히 가른다
    //   (300 같은 헐거운 하한은 섹션 카드가 날아가야 겨우 걸린다 — 그건 이 변경이 답할 질문이 아니다).
    #expect(height >= 440, "설정 콘텐츠가 \(height)pt 뿐이다 — 소속 센터 행이 사라졌는지 보라")
    v0313Save(image, name: "v0313-settings.png")
}

@MainActor
@Test
func 네_화면과_어제_1등이_모두_행의_center_를_그대로_넘긴다() throws {
    // 배지 컴포넌트가 아무리 옳아도 값이 안 내려오면 화면은 그대로다("패치는 지금 center 를 아무도 안 넘긴다").
    // 내 행·우리 팀 행을 빼는 조건문이 끼어드는 회귀도 함께 막는다 — 그런 분기가 있으면 이 리터럴이 안 걸린다.
    // 주석을 걷어낸 뒤 **공백을 한 칸으로 접어** 비교한다: 주석 자리에 남는 빈 줄과 들여쓰기가
    // 여러 줄 인자 목록의 모양을 바꾸기 때문이다(그걸 그대로 매칭하면 주석을 지워야만 초록이 된다).
    let menu = v0313Normalized(try v0313Source("CheckMenuView.swift"))
    #expect(menu.contains("LeaderboardRow(entry: entry, center: entry.center, isMyTeam: entry.id == myTeamID)"))
    #expect(menu.contains("TokenBoardRowView( entry: entry, center: entry.center, isMe: isMe,"))
    #expect(menu.contains("ultraUnlimited: ultraUnlimited, center: entry.center,"))

    let game = v0313Normalized(try v0313Source("MiniGamePanel.swift"))
    #expect(game.contains("MiniGameRankRow( rank: index + 1, entry: entry, center: entry.center,"))
    #expect(game.contains("center: winner.center"), "어제 1등 카드도 같은 화면의 아바타다")

    // 배지 자체의 확정값(사장님 실렌더 확정)이 남아 있는지도 함께 못 박는다 — 지우거나 바꾸면 안 된다.
    let avatar = v0313Normalized(try v0313Source("CheckAvatarView.swift"))
    #expect(avatar.contains("max(6, (avatarSize * 0.24).rounded())"))
    #expect(avatar.contains(".offset(x: 4, y: 2)"))
    #expect(avatar.contains(".overlay(alignment: .bottomTrailing)"), "overlay 여야 폭 비용이 0이다")
}

@MainActor
@Test
func 센터는_순위를_가르지_않는다() {
    // 사장님 확정 2. 센터가 정렬·필터에 끼어들면 그 순간 이 기능은 '표시'가 아니게 된다.
    // 같은 입력에서 center 만 다른 두 목록이 **같은 순서**를 내야 한다.
    func team(_ id: String, _ name: String, seconds: Int, center: String?) -> TeamLeaderboardEntry {
        TeamLeaderboardEntry(
            id: id, name: name, weeklyGoalHours: 40, totalSeconds: seconds,
            workingCount: 1, memberCount: 2, center: center)
    }
    let mixed = [
        team("t1", "AIng", seconds: 7200, center: "부산"),
        team("t2", "낭만러너 김유정", seconds: 36000, center: "서울"),
        team("t3", "일단 돌아는 감", seconds: 18000, center: nil)
    ]
    let flat = mixed.map { team($0.id, $0.name, seconds: $0.totalSeconds, center: nil) }
    #expect(mixed.sortedByAverageDescending().map(\.id) == flat.sortedByAverageDescending().map(\.id))
    #expect(mixed.filteredForDisplay(myTeamID: "t1").map(\.id) == flat.filteredForDisplay(myTeamID: "t1").map(\.id),
            "센터로 거르는 분기가 끼어들었다")

    func person(_ id: String, _ name: String, working: Bool, center: String?) -> PokeDirectoryEntry {
        PokeDirectoryEntry(userID: id, name: name, avatarURL: nil, isWorking: working, center: center)
    }
    let people = [
        person("u1", "조현준", working: false, center: "부산"),
        person("u2", "윤", working: true, center: nil),
        person("u3", "킹예성", working: true, center: "서울")
    ]
    let plain = people.map { person($0.userID, $0.name, working: $0.isWorking, center: nil) }
    #expect(people.sortedForPokeDisplay().map(\.userID) == plain.sortedForPokeDisplay().map(\.userID))
}

// MARK: - 두 입력 경로의 그림 (사람이 눈으로 볼 자리 + 픽셀 단언)

@MainActor
@Test
func 가입_화면과_설정_창의_센터_칸이_실제로_그려진다() throws {
    // 픽셀로 확인하는 것은 둘이다: (1) 칸이 **그려진다**, (2) 고른 칸이 **눈에 띄게 달라진다**.
    // (2)가 없으면 두 칸이 똑같이 보이는 채로 초록이고, 사용자는 자기가 뭘 골랐는지 알 수 없다.
    let store = v0313Store()
    store.displayName = "조현준"
    store.email = "member@example.com"
    store.isCreateTeamMode = true
    store.createTeamName = "새벽 러너스"

    func cells(_ selection: String?, enabled: Bool = true) throws -> NSBitmapImageRep {
        try v0313Bitmap(
            CenterChoiceCells(selection: selection, isEnabled: enabled, fillsWidth: true) { _ in }
                .frame(width: 240),
            scale: 2)
    }
    let none = try cells(nil)
    let seoul = try cells(CenterLabel.seoul)
    let busan = try cells(CenterLabel.busan)
    #expect(v0313InkRatio(none) > 0.02, "칸이 아예 안 그려졌다")
    #expect(v0313ChangedPixelRatio(none, seoul) > 0.05, "서울을 골라도 그림이 그대로다")
    #expect(v0313ChangedPixelRatio(none, busan) > 0.05, "부산을 골라도 그림이 그대로다")
    // 두 칸이 **서로 다른 쪽**을 채운다(같은 칸을 칠하면 어느 쪽을 골랐는지 알 수 없다).
    #expect(v0313ChangedPixelRatio(seoul, busan) > 0.05)

    // 못 누르는 상태(서버값 대기)는 **눌리는 상태와 달라 보여야** 한다 — 같아 보이면 사용자는 눌러 보고
    // 아무 일도 안 일어나는 것을 겪는다.
    #expect(v0313ChangedPixelRatio(none, try cells(nil, enabled: false)) > 0.01)

    // ★ 설정 창을 여기서 그리지 **않는다.** 이 저장소에는 "설정 창 렌더가 둘 이상 동시에 돌면 옆에서 도는
    //   팝오버 렌더 비교가 흔들린다"는 실측 기록이 있다(RealtimeLinkTests 의 높이 계약 주석).
    //   그래서 이 파일의 설정 창 렌더는 **높이 계약 테스트 하나뿐**이고, 그 그림을 사람이 볼 자리로도 쓴다.
    //   여기서 보는 것은 칸 자체이고, 그 칸이 설정 창에 붙어 있다는 사실은 소스 계약이 따로 지킨다.
    v0313Save(seoul, name: "v0313-cells-seoul.png")
    v0313Save(try v0313Bitmap(
        CheckMenuView(store: store, initialAuthMode: .signUp), scale: 2), name: "v0313-signup.png")
}

// MARK: - 헬퍼

/// 배경과 다른 픽셀의 비율(그림이 비지 않았음을 증명한다 — 빈 PNG·전부 투명이면 0이다).
private func v0313InkRatio(_ bitmap: NSBitmapImageRep) -> Double {
    let ground = v0313Quantized(NSColor(CheckTheme.panel))
    var ink = 0
    for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh {
            guard let c = bitmap.colorAt(x: x, y: y) else { continue }
            if zip(v0313Quantized(c), ground).contains(where: { abs($0 - $1) > 12 }) { ink += 1 }
        }
    }
    return Double(ink) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
}

/// 두 그림에서 눈에 띄게 다른 픽셀의 비율.
private func v0313ChangedPixelRatio(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 1 }
    var changed = 0
    for x in 0..<a.pixelsWide {
        for y in 0..<a.pixelsHigh {
            guard let pa = a.colorAt(x: x, y: y), let pb = b.colorAt(x: x, y: y) else { continue }
            if v0313NoticeablyDifferent(pa, pb) { changed += 1 }
        }
    }
    return Double(changed) / Double(a.pixelsWide * a.pixelsHigh)
}

/// 세션 전용 절대 경로를 소스에 박지 않는다 — 퍼블릭 저장소에 개인 머신 경로가 남는다.
private func v0313Save(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0313", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}

/// 네 화면의 한 행씩 + 그 행의 경계값(배지 우단 / 이름 시작 x, pt). 두 렌더 테스트가 같은 목록을 쓴다 —
/// 갈리면 한쪽만 화면 하나를 빠뜨린 채 초록이 된다.
@MainActor
private var v0313Screens: [(name: String, width: CGFloat, height: CGFloat,
                            badgeRight: CGFloat, nameStart: CGFloat, make: (String?) -> AnyView)] {
    [
        ("콕찌르기", 292, 52, 51, 57, { center in AnyView(v0313PokeRow(center: center)) }),
        ("토큰순위판", 292, 62, 55, 61, { center in AnyView(v0313TokenRow(center: center)) }),
        ("팀리그", 292, 58, 44, 51, { center in AnyView(v0313LeagueRow(center: center)) }),
        ("미니게임", 314, MiniGameWindowLayout.rowHeight, 60, 63,
         { center in AnyView(v0313MiniGameRow(center: center)) })
    ]
}

@MainActor
private func v0313Store() -> WorkTimerStore {
    WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: UserDefaults(suiteName: "v0313-\(UUID().uuidString)")!
    )
}

private func v0313SourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)          // Tests/checkTests/V0313CenterTests.swift
        .deletingLastPathComponent()          // Tests/checkTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // repo root
        .appendingPathComponent("Sources/check", isDirectory: true)
}

private func v0313Source(_ name: String) throws -> String {
    try String(contentsOf: v0313SourcesDirectory().appendingPathComponent(name), encoding: .utf8)
}

private func v0313SourceFiles() throws -> [URL] {
    try FileManager.default
        .contentsOfDirectory(at: v0313SourcesDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// 주석(//, /* */)을 걷어낸 코드. 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다(하우스 규칙).
/// 문자열 리터럴 안의 `//` 는 보존해야 하므로 따옴표 상태를 추적한다.
private func v0313StrippingComments(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let next = source.index(after: index) < source.endIndex ? source[source.index(after: index)] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = source.index(after: index) }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = source.index(after: index)
        } else if c == "/", next == "*" {
            inBlock = true; index = source.index(after: index)
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}

/// 주석을 걷어내고 공백을 한 칸으로 접은 코드. 여러 줄 인자 목록을 한 줄로 보고 매칭하기 위한 것이다.
private func v0313Normalized(_ source: String) -> String {
    v0313StrippingComments(source).split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private enum V0313Error: Error { case renderFailed }

@MainActor
private func v0313Bitmap(_ view: some View, scale: CGFloat) throws -> NSBitmapImageRep {
    // 배경은 **단색**이다. CheckTheme.background 는 대각 그라디언트라, 같은 행을 위아래로 겹쳐 그리면
    // 두 행의 배경색이 서로 다르다 — 그러면 "행이 같은가"를 묻는 비교가 배경 때문에 전부 다르다고 답한다.
    let renderer = ImageRenderer(content: view.background(CheckTheme.panel))
    // 배율은 **언제나 명시한다** — 기본값은 주 디스플레이 backingScaleFactor 라 기계마다 갈린다.
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V0313Error.renderFailed }
    return bitmap
}

/// 한 번의 렌더 안에서 위/아래 절반이 **눈에 띄게** 다른 열의 집합.
///
/// ★ 왜 완전 일치가 아니라 허용 오차(12/255)인가 — 실측으로 밝혀진 사실 하나 때문이다:
///   **같은 뷰를 y 만 다르게 두 번 그리면 픽셀이 정확히 같지 않다.** 진행 게이지·강조 바 같은
///   그라디언트에 디더 노이즈가 얹히는데 그 무늬가 절대 좌표에 묶여 있어 두 행이 ±1~2 만큼 어긋난다
///   (덤프해서 육안으로 확인했다 — 두 행은 같은 그림이다).
///   그 노이즈를 '차이'로 세면 이 비교는 배지가 아니라 렌더러의 디더를 재게 되고, 무엇을 고쳐도 영영 빨갛다.
///   반대로 우리가 잡으려는 결함(이름이 1pt 밀림 = 글자 재배치·축소율 변화)은 글자 가장자리에서
///   100 단위로 벌어진다. 12 는 그 둘 사이의 넓은 골짜기다.
private func v0313DifferingColumnsBetweenHalves(_ bitmap: NSBitmapImageRep, rowHeightPx: Int) -> Set<Int> {
    // 위/아래 각 절반의 **맨 위·맨 아래 2픽셀 줄은 제외한다.** 두 행은 가운데서 맞닿아 있고 바깥쪽은
    // 그림의 테두리라, 그 경계에서 카드의 둥근 모서리·1px 테두리가 **서로 다른 이웃**과 안티에일리어싱된다
    // (실측: 이 2줄만 빼면 같은 행끼리의 차이가 584열 → 0열이 된다. 세로로 1px 만 밀어 비교하면 383열이
    //  달라지므로, 0열은 "비교가 헐거워서"가 아니라 정말 같은 그림이라는 뜻이다).
    // 배지는 아바타 모서리(행 가운데쯤)에 있어 이 2줄과 아무 상관이 없다.
    let edgeMargin = 2
    var columns: Set<Int> = []
    for x in 0..<bitmap.pixelsWide {
        for y in edgeMargin..<(rowHeightPx - edgeMargin) {
            guard let top = bitmap.colorAt(x: x, y: y),
                  let bottom = bitmap.colorAt(x: x, y: y + rowHeightPx) else { continue }
            if v0313NoticeablyDifferent(top, bottom) { columns.insert(x); break }
        }
    }
    return columns
}

/// 디더 노이즈(±1~2)는 무시하고 그림의 변화만 센다.
private func v0313NoticeablyDifferent(_ a: NSColor, _ b: NSColor) -> Bool {
    let lhs = v0313Quantized(a), rhs = v0313Quantized(b)
    guard lhs.count == rhs.count else { return true }
    return zip(lhs, rhs).contains { abs($0 - $1) > 12 }
}

private func v0313Quantized(_ color: NSColor) -> [Int] {
    guard let rgb = color.usingColorSpace(.sRGB) else { return [-1] }
    return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
        .map { Int(($0 * 255).rounded()) }
}

// MARK: - 렌더 픽스처 (네 화면의 한 행씩 — 이름은 프로덕션 최장 별명으로 최악을 담는다)

@MainActor
private func v0313PokeRow(center: String?) -> some View {
    PokeDirectoryRowView(
        entry: PokeDirectoryEntry(
            userID: "v0313-u0", name: "천만번더들어도기분좋은말사랑해", avatarURL: nil, isWorking: false),
        cooldownRemaining: { 0 },
        canPoke: true,
        ultraBalance: 3,
        center: center,
        onPoke: {},
        onUltra: {},
        onOpenMessages: {},
        hasUnreadMessages: false
    )
}

@MainActor
private func v0313TokenRow(center: String?) -> some View {
    TokenBoardRowView(
        entry: TokenBoardEntry(
            userID: "v0313-u0",
            name: "천만번더들어도기분좋은말사랑해",
            avatarURL: nil,
            total: 19_662_540_000,
            claudeInput: 19_660_000_000,
            claudeOutput: 0,
            claudeCacheRead: 0,
            claudeCacheCreation: 0,
            codexInput: 2_540_000,
            codexOutput: 0,
            todayTotal: 184_300_000,
            todayDate: "2026-09-12"
        ),
        center: center,
        isMe: true,
        showsPrivateChip: true,
        showsToday: true,
        todayKey: "2026-09-12"
    )
}

@MainActor
private func v0313LeagueRow(center: String?) -> some View {
    LeaderboardRow(
        entry: TeamLeaderboardEntry(
            id: "v0313-t0", name: "Alpha Everyday", weeklyGoalHours: 45,
            totalSeconds: 26 * 3600 * 7, workingCount: 4, memberCount: 7),
        center: center,
        isMyTeam: true
    )
}

@MainActor
private func v0313MiniGameRow(center: String?) -> some View {
    MiniGameRankRow(
        rank: 1,
        entry: MiniGameBoardEntry(
            userID: "v0313-u0", name: "천만번더들어도기분좋은말사랑해", avatarURL: nil,
            bestScore: 980, bestAt: Date(timeIntervalSince1970: 1_789_000_000), plays: 12),
        center: center,
        isMe: true
    )
}
