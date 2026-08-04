import Foundation
import Testing
@testable import check

// 별명(표시명) 변경과 울트라 찌르기의 **와이어 계약** 테스트 — 모델(디코드/매핑)과 서비스(경로/본문)만 다룬다.
// 스토어·UI 계약은 별도 파일이 맡는다.
//
// 호스트 규약: TokenBoardURLProtocol 의 응답 표는 프로세스 전역이고 스위트는 병렬로 돈다. 같은 호스트를
// 두 테스트가 쓰면 서로의 응답을 덮어써 무음으로 잘못 통과한다 — 그래서 status 하나당 호스트 하나이고,
// 이 파일의 호스트에는 다른 파일과 겹치지 않도록 `-svc-` 를 박아 둔다.

// MARK: - 별명 변경(서비스 계층)

@Test
func setDisplayNameCallsRPCWithSnakeCaseBody() async throws {
    let testHost = "display-name-svc-ok-test"
    TokenBoardURLProtocol.setResponse(#"{"status":"ok","display_name":"영식"}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let response = try await service.setDisplayName(accessToken: "access-token", name: "영식")

    #expect(response.status == "ok")
    #expect(DisplayNameChangeOutcome(response: response) == .ok(name: "영식"))

    // 요청: POST /rest/v1/rpc/set_display_name + body {p_name:"영식"}.
    // pName 이 그대로 나가면 서버는 인자를 못 찾아 404(PGRST202)로 답한다 — 인코더 전략 회귀 방어.
    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/rpc/set_display_name")
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "POST")
    let body = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
    #expect(body.contains("\"p_name\":\"영식\""))
    #expect(!body.contains("\"pName\""))
}

@Test
func setDisplayNameDecodesTaken() async throws {
    let testHost = "display-name-svc-taken-test"
    TokenBoardURLProtocol.setResponse(#"{"status":"taken"}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let response = try await service.setDisplayName(accessToken: "access-token", name: "영식")

    #expect(response.status == "taken")
    #expect(response.displayName == nil)
    #expect(DisplayNameChangeOutcome(response: response) == .taken)
}

@Test
func setDisplayNameDecodesCooldown() async throws {
    let testHost = "display-name-svc-cooldown-test"
    TokenBoardURLProtocol.setResponse(#"{"status":"cooldown","retry_after_seconds":518400}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let response = try await service.setDisplayName(accessToken: "access-token", name: "영식")

    #expect(response.retryAfterSeconds == 518_400)
    #expect(DisplayNameChangeOutcome(response: response) == .cooldown(retryAfterSeconds: 518_400))
}

@Test
func setDisplayNameDecodesTooLong() async throws {
    let testHost = "display-name-svc-too-long-test"
    TokenBoardURLProtocol.setResponse(#"{"status":"invalid_long","max_length":12}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let response = try await service.setDisplayName(accessToken: "access-token", name: "열세글자를넘기는아주긴별명")

    #expect(response.maxLength == 12)
    #expect(DisplayNameChangeOutcome(response: response) == .tooLong(maxLength: 12))
}

@Test
func setDisplayNameMapsUnknownStatusToInvalid() async throws {
    let testHost = "display-name-svc-unknown-status-test"
    // 서버가 나중에 status 를 하나 더 늘려도(예: rate_limited) 옛 앱은 크래시하지 않고 안전한 문구로 수렴해야 한다.
    TokenBoardURLProtocol.setResponse(#"{"status":"future_status"}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let response = try await service.setDisplayName(accessToken: "access-token", name: "영식")

    #expect(DisplayNameChangeOutcome(response: response) == .invalid)
}

/// status 문자열 → 도메인 결과의 전 매핑을 한 곳에 못 박는다(서버 마이그레이션 주석의 status 목록과 1:1).
/// unauthorized·no_profile 은 사용자가 손쓸 수 없는 상태라 별도 케이스를 만들지 않고 .invalid 로 접는다.
@Test
func displayNameChangeOutcomeMapsEveryServerStatus() {
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "ok", displayName: "영식"))
        == .ok(name: "영식"))
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "unchanged", displayName: "영식"))
        == .unchanged)
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "taken")) == .taken)
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "invalid_empty")) == .empty)
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "unauthorized")) == .invalid)
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "no_profile")) == .invalid)
    // 선택 필드가 빠진 응답도 안내 문구를 만들 수 있어야 한다 — 폴백은 서버 상수와 같은 값(7일 / 12자).
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "cooldown"))
        == .cooldown(retryAfterSeconds: 604_800))
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "invalid_long"))
        == .tooLong(maxLength: 12))
    // ok 인데 서버가 이름을 안 보낸 경우까지 크래시하지 않는다(빈 이름으로 수렴 — 호출부가 로컬 미러를 안 덮는다).
    #expect(DisplayNameChangeOutcome(response: DisplayNameChangeResponse(status: "ok")) == .ok(name: ""))
}

@Test
func fetchDisplayNameChangedAtParsesFractionalSeconds() async throws {
    let testHost = "display-name-svc-changed-at-test"
    // 소수초가 붙은 timestamptz. 기본 ISO8601DateFormatter 는 이걸 nil 로 돌려주므로 parseDate 를 안 쓰면
    // 쿨타임이 영영 '한 번도 안 바꿈'으로 보이고, 잠긴 버튼이 열린 채로 남는다.
    TokenBoardURLProtocol.setResponse(
        #"[{"display_name_changed_at":"2026-08-01T09:00:00.123Z"}]"#,
        forHost: testHost
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let fetched = try await service.fetchDisplayNameChangedAt(accessToken: "access-token", userID: "u1")
    let changedAt = try #require(fetched)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let expected = try #require(formatter.date(from: "2026-08-01T09:00:00.123Z"))
    #expect(abs(changedAt.timeIntervalSince(expected)) < 0.5)

    // 요청: GET /rest/v1/profiles?id=eq.u1&select=display_name_changed_at.
    // **기존 설정 GET(token_usage_public,…)에 끼워 넣지 않는다** — 컬럼 없는 서버에서 400 이 나면
    // 토큰 공개/수집 설정까지 함께 못 읽게 되기 때문이다.
    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/profiles")
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "GET")
    let query = url.query ?? ""
    #expect(query.contains("select=display_name_changed_at"))
    #expect(query.contains("id=eq.u1"))
    #expect(!query.contains("token_usage"))
}

@Test
func fetchDisplayNameChangedAtReturnsNilWhenNeverChanged() async throws {
    let testHost = "display-name-svc-changed-at-null-test"
    // 한 번도 안 바꾼 사용자: 컬럼은 있으나 null 이다. 이 경우와 '조회 실패'가 같은 nil 로 수렴하는 것이 의도다
    // (둘 다 "잠글 근거가 없다" → 서버가 최종 판정한다).
    TokenBoardURLProtocol.setResponse(#"[{"display_name_changed_at":null}]"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let changedAt = try await service.fetchDisplayNameChangedAt(accessToken: "access-token", userID: "u1")
    #expect(changedAt == nil)
}

@Test
func fetchDisplayNameChangedAtParsesTimestampWithoutFractionalSeconds() async throws {
    let testHost = "display-name-svc-changed-at-plain-test"
    // Supabase timestamptz 는 소수초 유무가 섞여 내려온다. 소수초 전용 포매터만 쓰면 이쪽이 nil 이 된다.
    TokenBoardURLProtocol.setResponse(
        #"[{"display_name_changed_at":"2026-08-01T09:00:00Z"}]"#,
        forHost: testHost
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let changedAt = try await service.fetchDisplayNameChangedAt(accessToken: "access-token", userID: "u1")
    #expect(changedAt != nil)
}

// MARK: - 울트라 찌르기(모델/서비스 와이어 계약)

/// 스위트로 감싼 이유는 이름 충돌 방지다 — 울트라의 오버레이/스토어 테스트는 다른 파일에서 자라고,
/// 최상위 @Test 함수 이름이 겹치면 모듈이 통째로 컴파일되지 않는다. 여기 있는 것은 **와이어 계약만**이다.
@Suite struct UltraPokeWireContractTests {
    /// 서비스와 같은 설정의 디코더(스네이크 케이스 변환). 이게 어긋나면 테스트만 통과하고 앱은 못 읽는다.
    private func serviceDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// 마이그레이션 미적용 서버(kind 키 없음)에서도 행이 살아남아야 한다.
    /// 이게 깨지면 앱 배포가 db push 보다 앞선 창에서 **모든** 찔림이(일반 찌르기까지) 무증상 소멸한다.
    @Test func takenPokeRowDecodesWithoutKindKey() throws {
        let rows = try serviceDecoder().decode([TakenPokeRow].self, from: Data(#"""
        [{"id":"p1","from_user":"u1","from_display_name":"이유성","from_avatar_url":null,"created_epoch":1000}]
        """#.utf8))

        let row = try #require(rows.first)
        #expect(row.kind == nil)
        #expect(PokeKind(rawServerValue: row.kind) == .normal)
    }

    @Test func takenPokeRowDecodesUltraKindAndFoldsUnknownKind() throws {
        let rows = try serviceDecoder().decode([TakenPokeRow].self, from: Data(#"""
        [{"id":"p1","from_user":"u1","from_display_name":"이유성","from_avatar_url":null,"created_epoch":1000,"kind":"ultra"},
         {"id":"p2","from_user":"u2","from_display_name":"영식","from_avatar_url":null,"created_epoch":1001,"kind":"megaultra"},
         {"id":"p3","from_user":"u3","from_display_name":"민수","from_avatar_url":null,"created_epoch":1002,"kind":"normal"}]
        """#.utf8))

        #expect(rows.count == 3)
        #expect(PokeKind(rawServerValue: rows[0].kind) == .ultra)
        // 미래에 종류가 늘어도 옛 앱은 '평범한 찌르기'로 접어서 말풍선만은 띄운다(무음 소멸 금지).
        #expect(PokeKind(rawServerValue: rows[1].kind) == .normal)
        #expect(PokeKind(rawServerValue: rows[2].kind) == .normal)
    }

    /// ReceivedPoke 의 kind 기본값(.normal)이 살아 있는지 — 기존 호출부는 이 인자를 모른다.
    @Test func receivedPokeDefaultsToNormalKind() {
        let poke = ReceivedPoke(id: "1", fromName: "이유성", createdAt: Date(timeIntervalSince1970: 1000))
        #expect(poke.kind == .normal)
        #expect(ReceivedPoke(id: "1", fromName: "이유성", createdAt: Date(timeIntervalSince1970: 1000), kind: .ultra).kind == .ultra)
    }

    /// **디코드 경로를 실제로 지나는** 케이스. PokeSendResponse 는 커스텀 init(from:) 을 갖고 있어서
    /// CodingKey 만 더하고 디코드 한 줄을 빠뜨리면 값이 영원히 nil 인데, 직접 생성 테스트로는 절대 못 잡는다.
    @Test func pokeSendResponseDecodesResetAfterSecondsFromJSON() throws {
        let response = try serviceDecoder().decode(
            PokeSendResponse.self,
            from: Data(#"{"status":"ultra_used_today","reset_after_seconds":1234,"ultra_remaining":0}"#.utf8)
        )

        #expect(response.resetAfterSeconds == 1234)
        #expect(PokeSendOutcome(response: response) == .ultraUsedToday(resetAfterSeconds: 1234))
    }

    /// 남은 횟수(U2)도 같은 함정을 공유한다 — 디코드 줄이 빠지면 화면이 영영 남은 횟수를 말하지 못한다.
    @Test func pokeSendResponseDecodesUltraRemainingFromJSON() throws {
        let ok = try serviceDecoder().decode(
            PokeSendResponse.self,
            from: Data(#"{"status":"ok","ultra_remaining":1}"#.utf8)
        )
        #expect(ok.ultraRemaining == 1)
        #expect(ok.ultraRemainingForDisplay == 1)

        let spent = try serviceDecoder().decode(
            PokeSendResponse.self,
            from: Data(#"{"status":"ultra_used_today","ultra_remaining":0,"reset_after_seconds":60}"#.utf8)
        )
        #expect(spent.ultraRemainingForDisplay == 0)
    }

    /// nil 은 0 이 아니라 **모름**이다. 일반 poke_user 응답과 구버전 서버가 여기로 오는데, 0 으로 접으면
    /// 콕찌르기 한 번에 "오늘 0번 남음"이라는 거짓말이 화면에 남는다.
    @Test func pokeSendResponseUltraRemainingIsNilWhenServerOmitsIt() throws {
        let response = try serviceDecoder().decode(
            PokeSendResponse.self,
            from: Data(#"{"status":"ok"}"#.utf8)
        )
        #expect(response.ultraRemaining == nil)
        #expect(response.ultraRemainingForDisplay == nil)
    }

    /// 서버가 이상치(음수)를 보내도 "-1번 남음"이 화면에 뜨지 않는다.
    @Test func ultraRemainingForDisplayClampsNegativeToZero() {
        #expect(PokeSendResponse(status: "ok", ultraRemaining: -3).ultraRemainingForDisplay == 0)
    }

    @Test func pokeSendOutcomeMapsUltraUsedTodayAndKeepsExistingStatuses() {
        // reset_after_seconds 누락 시 1시간 폴백(안내 문구가 비지 않게).
        #expect(PokeSendOutcome(response: PokeSendResponse(status: "ultra_used_today"))
            == .ultraUsedToday(resetAfterSeconds: 3600))
        #expect(PokeSendOutcome(response: PokeSendResponse(status: "ultra_used_today", resetAfterSeconds: 0))
            == .ultraUsedToday(resetAfterSeconds: 1))   // 0 은 '지금 바로'가 아니라 최소 1초로 올린다
        // 기존 5개 매핑은 그대로여야 한다(구버전 서버·poke_user 경로 회귀).
        #expect(PokeSendOutcome(response: PokeSendResponse(status: "ok")) == .ok)
        #expect(PokeSendOutcome(response: PokeSendResponse(status: "cooldown", retryAfterSeconds: 25))
            == .cooldown(retryAfterSeconds: 25))
        #expect(PokeSendOutcome(response: PokeSendResponse(status: "not_working")) == .notWorking)
        #expect(PokeSendOutcome(response: PokeSendResponse(status: "target_not_working")) == .targetNotWorking)
        #expect(PokeSendOutcome(response: PokeSendResponse(status: "invalid")) == .invalid)
        // 서버가 나중에 상태를 추가해도(설계상 target_saturated 후보) 구클라는 .invalid 로 접는다.
        #expect(PokeSendOutcome(response: PokeSendResponse(status: "target_saturated")) == .invalid)
    }

    /// 경로가 정확히 ultra_poke_user 여야 한다. poke_user 오버로드(같은 이름·같은 인자)로 만들면
    /// PostgREST 가 어느 함수인지 못 가려 300/404 가 난다 — 그 회귀의 유일한 방어선.
    @Test func sendUltraPokeUsesDedicatedRPCPathAndSnakeCaseBody() async throws {
        let testHost = "ultra-poke-svc-ok-test"
        TokenBoardURLProtocol.setResponse(#"{"status":"ok","ultra_remaining":1}"#, forHost: testHost)
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(testHost)")!,
            anonKey: "anon-test-key",
            session: TokenBoardURLProtocol.session()
        )

        let response = try await service.sendUltraPoke(accessToken: "access-token", to: "target-user-id")

        #expect(PokeSendOutcome(response: response) == .ok)
        #expect(response.ultraRemainingForDisplay == 1)

        let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
        #expect(url.path == "/rest/v1/rpc/ultra_poke_user")
        #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "POST")
        let body = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
        #expect(body.contains("\"p_to\":\"target-user-id\""))
        #expect(!body.contains("\"pTo\""))
    }

    @Test func sendUltraPokeDecodesUsedTodayWithRemainingZero() async throws {
        let testHost = "ultra-poke-svc-used-today-test"
        TokenBoardURLProtocol.setResponse(
            #"{"status":"ultra_used_today","ultra_remaining":0,"reset_after_seconds":7200}"#,
            forHost: testHost
        )
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(testHost)")!,
            anonKey: "anon-test-key",
            session: TokenBoardURLProtocol.session()
        )

        let response = try await service.sendUltraPoke(accessToken: "access-token", to: "target-user-id")

        #expect(PokeSendOutcome(response: response) == .ultraUsedToday(resetAfterSeconds: 7200))
        #expect(response.ultraRemainingForDisplay == 0)
    }
}
