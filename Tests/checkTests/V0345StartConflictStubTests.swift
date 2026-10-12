import Foundation
import Testing
@testable import check
@testable import CheckCore

// 23505 재현 인프라의 **자기 검사**.
//
// 무엇을 재는가: 제품 코드가 아니라 `URLProtocolStub` 의 상태 있는 호스트(`start-conflict…`)다.
// 이 스위트가 없으면 다음 조각들은 "스텁이 정말 아이맥이 남긴 열린 행을 들고 있나"를 모른 채
// 그 위에 단언을 쌓는다 — 스텁이 조용히 2xx 를 돌려주면 복구 경로 테스트들이 **전부 초록인 채로**
// 아무것도 재지 않는다(기준선이 같은 입력이면 그 테스트는 영원히 초록이다).
//
// 2026-10-09 운영 사고의 모양: 아이맥이 세션을 열어 둔 채 남고, 맥북의 [근무 시작] INSERT 가 부분
// 유니크 `work_sessions_one_open_per_user`(user_id **where ended_at is null**)에 걸려 23505 로 떨어졌다.
@Suite
struct V0345StartConflictStubTests {
    // MARK: - 스텁에 직접 말 걸기
    //
    // 서비스 함수를 거치지 않는다. 지금 재는 것은 **스텁의 응답**(상태코드·본문·표의 전이)이고,
    // 서비스를 끼우면 그 왕복 중 어디서 모양이 바뀌었는지 가를 수 없다. 서비스가 이 본문을 실제로
    // 23505 로 읽는지는 맨 아래 한 건이 따로 못 박는다.

    private struct Reply {
        let statusCode: Int
        let bodyText: String
    }

    private func send(
        host: String,
        method: String,
        query: String? = nil,
        json: String? = nil
    ) async throws -> Reply {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = "/rest/v1/work_sessions"
        components.query = query
        var request = URLRequest(url: try #require(components.url))
        request.httpMethod = method
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(json.utf8)
        }
        let (data, response) = try await URLSession(configuration: .stubbed).data(for: request)
        return Reply(
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
            bodyText: String(decoding: data, as: UTF8.self)
        )
    }

    /// 맥북이 보내는 **열기** INSERT 본문(`StartSessionRequest` 와 같은 키 — `ended_at` 이 **없다**).
    private func openInsertBody(id: String, startedAt: String = "2026-10-09T02:00:00Z") -> String {
        """
        {"id":"\(id)","team_id":"\(URLProtocolStub.stubTeamID)",\
        "user_id":"\(URLProtocolStub.startConflictUserID)","started_at":"\(startedAt)"}
        """
    }

    /// 마감 폴백이 보내는 **닫힌 행** INSERT 본문(`CompletedSessionRequest` 와 같은 키).
    private func closedInsertBody(id: String) -> String {
        """
        {"id":"\(id)","team_id":"\(URLProtocolStub.stubTeamID)",\
        "user_id":"\(URLProtocolStub.startConflictUserID)","started_at":"2026-10-09T03:00:00Z",\
        "ended_at":"2026-10-09T04:00:00Z","duration_seconds":3600}
        """
    }

    // MARK: - 1. 다른 열린 행이 있으면 열기 POST 는 409 + 23505 다

    @Test
    func openInsertHitsPartialUniqueWithRealPostgRESTBody() async throws {
        let host = "start-conflict-open-insert"
        URLProtocolStub.resetStartConflictFixture(forHost: host)

        let reply = try await send(host: host, method: "POST", json: openInsertBody(id: "A1"))

        #expect(reply.statusCode == 409)
        // 본문은 **실제 PostgREST 모양**이어야 한다. 셋 다 본다 — 서비스의 판정이 제약명·SQLSTATE·
        // "duplicate key" 중 어느 것에 걸려도 같은 결론이 나오는 게 이 재현의 값이다.
        #expect(reply.bodyText.contains("23505"))
        #expect(reply.bodyText.contains("work_sessions_one_open_per_user"))
        #expect(reply.bodyText.contains("duplicate key value violates unique constraint"))

        // 실패한 INSERT 는 표를 바꾸지 않는다(서버라면 그 문장이 롤백된다).
        let rows = URLProtocolStub.startConflictRows(forHost: host)
        #expect(rows.count == 2)
        #expect(rows.contains { $0.id == "A1" } == false)
        #expect(rows.filter { $0.isOpen }.map(\.id) == [URLProtocolStub.startConflictBlockerSessionID])
    }

    // MARK: - 2. 같은 상황에서 **닫힌 행** INSERT 는 성공한다

    @Test
    func closedInsertSucceedsEvenWhileAnotherSessionIsOpen() async throws {
        // 부분 유니크는 `where ended_at is null` 이라 닫힌 행을 보지 않는다. 이 갈래를 막아 두면
        // 마감 폴백 POST 까지 23505 가 되어, "시작만 갇혔다"가 아니라 "아무것도 못 쓴다"가 된다 —
        // 그 재현으로 고친 코드는 실서버에서 무슨 짓을 할지 모른다.
        let host = "start-conflict-closed-insert"
        URLProtocolStub.resetStartConflictFixture(forHost: host)

        let reply = try await send(host: host, method: "POST", json: closedInsertBody(id: "C1"))

        #expect(200..<300 ~= reply.statusCode)
        #expect(reply.bodyText.contains("23505") == false)

        let rows = URLProtocolStub.startConflictRows(forHost: host)
        #expect(rows.contains { $0.id == "C1" && $0.endedAt == "2026-10-09T04:00:00Z" })
        // 블로커는 **그대로 열려 있다** — 닫힌 행을 더한 것이 열린 행을 치우지 않는다.
        #expect(rows.filter { $0.isOpen }.map(\.id) == [URLProtocolStub.startConflictBlockerSessionID])

        // 그리고 그 뒤에도 열기는 여전히 막혀 있다(닫힌 행이 늘어난 것이 유니크를 풀지 않는다).
        let stillBlocked = try await send(host: host, method: "POST", json: openInsertBody(id: "A2"))
        #expect(stillBlocked.statusCode == 409)
    }

    // MARK: - 3. 블로커를 PATCH 로 닫으면 그 다음 열기 POST 가 성공한다

    @Test
    func closingTheBlockerUnblocksTheNextOpenInsert() async throws {
        let host = "start-conflict-unblock"
        URLProtocolStub.resetStartConflictFixture(forHost: host)

        let blocked = try await send(host: host, method: "POST", json: openInsertBody(id: "A3"))
        #expect(blocked.statusCode == 409)

        let patch = try await send(
            host: host,
            method: "PATCH",
            query: "id=eq.\(URLProtocolStub.startConflictBlockerSessionID)&ended_at=is.null",
            json: #"{"ended_at":"2026-10-09T05:00:00Z","duration_seconds":14400}"#
        )
        #expect(200..<300 ~= patch.statusCode)
        // `Prefer: return=representation` 의 모양 — 닫은 행이 실려 온다(0행이면 폴백 INSERT 가 돈다).
        #expect(patch.bodyText.contains(URLProtocolStub.startConflictBlockerSessionID))
        #expect(patch.bodyText.contains("2026-10-09T05:00:00Z"))

        let reopened = try await send(host: host, method: "POST", json: openInsertBody(id: "A3"))
        #expect(reopened.statusCode == 201)

        let rows = URLProtocolStub.startConflictRows(forHost: host)
        #expect(rows.filter { $0.isOpen }.map(\.id) == ["A3"])
        #expect(rows.first { $0.id == URLProtocolStub.startConflictBlockerSessionID }?.endedAt == "2026-10-09T05:00:00Z")
    }

    // MARK: - 4. GET 이 픽스처를 그대로 비춘다

    @Test
    func selectMirrorsTheFixtureAndDecodesAsWorkSessionRows() async throws {
        let host = "start-conflict-select"
        URLProtocolStub.resetStartConflictFixture(forHost: host)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let all = try await send(host: host, method: "GET", query: "select=*")
        #expect(all.statusCode == 200)
        // **실제 표 모양으로 디코드되어야 한다** — 문자열 포함만 보면 서비스가 못 읽는 모양도 초록이다.
        let allRows = try decoder.decode([WorkSessionRow].self, from: Data(all.bodyText.utf8))
        #expect(allRows.map(\.id) == [
            URLProtocolStub.startConflictBlockerSessionID,
            URLProtocolStub.startConflictClosedSessionID
        ])
        #expect(allRows.allSatisfy { $0.userId == URLProtocolStub.startConflictUserID })
        #expect(allRows.filter { $0.endedAt == nil }.count == 1)
        #expect(allRows.first?.startedAt == URLProtocolStub.startConflictBlockerStartedAt)
        #expect(allRows.last?.durationSeconds == 7_200)

        // 열린 행만 묻는 조회(`ended_at=is.null`)는 블로커 한 줄이다 — 이것이 "다른 맥이 열어 뒀다"를
        // 앱이 읽는 그 요청이다.
        let open = try await send(host: host, method: "GET", query: "select=*&ended_at=is.null")
        let openRows = try decoder.decode([WorkSessionRow].self, from: Data(open.bodyText.utf8))
        #expect(openRows.map(\.id) == [URLProtocolStub.startConflictBlockerSessionID])

        // 닫은 뒤에는 그 조회가 0행이다(= 전이가 조회에도 보인다).
        _ = try await send(
            host: host,
            method: "PATCH",
            query: "ended_at=is.null",
            json: #"{"ended_at":"2026-10-09T06:00:00Z","duration_seconds":18000}"#
        )
        let openAfter = try await send(host: host, method: "GET", query: "select=*&ended_at=is.null")
        let openAfterRows = try decoder.decode([WorkSessionRow].self, from: Data(openAfter.bodyText.utf8))
        #expect(openAfterRows.isEmpty)
        // 전체 조회는 두 줄 그대로다(닫혔을 뿐 사라지지 않는다).
        let allAfter = try await send(host: host, method: "GET", query: "select=*")
        let allAfterRows = try decoder.decode([WorkSessionRow].self, from: Data(allAfter.bodyText.utf8))
        #expect(allAfterRows.count == 2)
        #expect(allAfterRows.allSatisfy { $0.endedAt != nil })
    }

    // MARK: - 5. 호스트가 다르면 상태가 섞이지 않는다

    @Test
    func stateIsKeyedByHostSoParallelTestsCannotOverwriteEachOther() async throws {
        // 이 스위트의 존재 이유 중 절반이다. 프로세스 전역 단일 변수로 뒀다면 아래 A 의 PATCH 가
        // B 의 "막혀 있다" 전제를 지워, B 를 쓴 테스트가 **순서에 따라** 초록/빨강이 된다
        // (URLProtocolStub 의 delayedHosts 주석이 경고하는 그 사고 — 쓰기까지 섞이면 더 조용하다).
        let hostA = "start-conflict-isolation-a"
        let hostB = "start-conflict-isolation-b"
        URLProtocolStub.resetStartConflictFixture(forHost: hostA)
        URLProtocolStub.resetStartConflictFixture(forHost: hostB)

        // A: 블로커를 닫고 새 세션을 연다.
        _ = try await send(
            host: hostA,
            method: "PATCH",
            query: "ended_at=is.null",
            json: #"{"ended_at":"2026-10-09T05:00:00Z","duration_seconds":14400}"#
        )
        let openedOnA = try await send(host: hostA, method: "POST", json: openInsertBody(id: "ONLY-A"))
        #expect(openedOnA.statusCode == 201)

        // B: 아무것도 안 했으므로 아직 막혀 있어야 한다.
        let blockedOnB = try await send(host: hostB, method: "POST", json: openInsertBody(id: "ONLY-B"))
        #expect(blockedOnB.statusCode == 409)
        #expect(blockedOnB.bodyText.contains("23505"))

        #expect(URLProtocolStub.startConflictRows(forHost: hostA).filter { $0.isOpen }.map(\.id) == ["ONLY-A"])
        #expect(
            URLProtocolStub.startConflictRows(forHost: hostB).filter { $0.isOpen }.map(\.id)
                == [URLProtocolStub.startConflictBlockerSessionID]
        )
        #expect(URLProtocolStub.startConflictRows(forHost: hostB).contains { $0.id == "ONLY-A" } == false)

        // reset 은 되돌리는 문이기도 하다 — 테스트마다 같은 호스트로 다시 시작할 수 있다.
        URLProtocolStub.resetStartConflictFixture(forHost: hostA)
        #expect(URLProtocolStub.startConflictRows(forHost: hostA) == URLProtocolStub.startConflictDefaultRows())
    }

    // MARK: - 스텁 본문이 제품 코드의 23505 판정에 **실제로** 걸리는가
    //
    // 위 다섯 건은 전부 스텁만 본다. 본문 문구를 한 글자 줄여도(예: 제약명만 남기고 code 를 빼도)
    // 그대로 초록이다. 그 자리를 이 한 건이 메운다: 서비스를 불러
    // `SupabaseWorkHTTP.serviceError` 가 이 응답을 `.sessionAlreadyOpen` 으로 접는지 본다.
    // 이 단언이 없으면 다음 조각이 "23505 를 만났을 때"를 테스트하면서 실제로는
    // `.invalidResponse(409)` 를 받고 있을 수 있다.

    @Test
    func startConflictBodyIsClassifiedAsSessionAlreadyOpen() async throws {
        let host = "start-conflict-service-classification"
        URLProtocolStub.resetStartConflictFixture(forHost: host)

        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )

        do {
            try await service.startWork(
                accessToken: "access-token",
                teamID: URLProtocolStub.stubTeamID,
                userID: URLProtocolStub.startConflictUserID,
                sessionID: "90000000-0000-0000-0000-00000000000f"
            )
            Issue.record("다른 열린 세션이 있는 서버에서 startWork 가 성공해서는 안 된다")
        } catch let error as SupabaseWorkServiceError {
            #expect(error == .sessionAlreadyOpen)
        }

        // 그리고 실패한 시작은 서버 표에 아무 줄도 남기지 않는다(= 유령 열린 행이 생기지 않는다).
        #expect(
            URLProtocolStub.startConflictRows(forHost: host).contains {
                $0.id == "90000000-0000-0000-0000-00000000000f"
            } == false
        )
    }
}
