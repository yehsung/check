// 원본: 없음
@testable import CheckCore
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckMobileKit

// W1-d 함수 표 골든(G1): 오류 분류(23505 → 5xx → 429 → 본문 — G §2-3 W1-d ③ · §5-2) · 재설정 경로 재분류 · 인증 처분 · JWT 만료 ·
// 와이어 파일 안의 규칙(역대 순위 정렬·날짜 캡션 · 상점 판정 · 선물 선택지 · 마이크로초 · 결과 갈래).

enum WireRulesSamples {
    static func base64URL(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func jwt(_ payload: String) -> String { "eyJhbGciOiJIUzI1NiJ9." + base64URL(payload) + ".c2ln" }
}

@Suite("GoldenExport W1-d 와이어 — 오류·JWT·규칙 표")
struct GoldenExportWireRules {
    static let classifyBodies: [(Int, String)] = [
        // 23505 · work_sessions 가 상태코드보다 먼저(500 이어도 sessionAlreadyOpen)
        (409, #"{"code":"23505","message":"duplicate key value violates unique constraint \"work_sessions_one_open_per_user\""}"#),
        (500, #"{"message":"duplicate key value violates unique constraint","details":"Key (user_id) on work_sessions"}"#),
        (400, "23505"),
        (400, #"{"message":"duplicate key value","hint":"profiles"}"#),
        // 5xx 가 본문보다 먼저
        (500, #"{"msg":"Invalid Refresh Token: Already Used"}"#),
        (503, ""),
        (599, "not json"),
        // 429
        (429, #"{"msg":"For security purposes, you can only request this after 30 seconds."}"#),
        (429, #"{"msg":"Email rate limit exceeded"}"#),
        (429, #"{"msg":"try again in 2 minutes and 15 seconds"}"#),
        // 디코드 실패
        (401, "<html>unauthorized</html>"),
        (403, "<html>forbidden</html>"),
        (400, ""),
        (400, #"{"msg": 42}"#),
        // 본문
        (404, #"{"code":"PGRST202","message":"Could not find the function public.shop_state(p_protocol) in the schema cache"}"#),
        (404, #"{"code":"42P01","message":"Could not find the table 'public.ai_limits' in the schema cache"}"#),
        (401, #"{"message":"Invalid API key","hint":"Double check your Supabase anon API key."}"#),
        (401, #"{"code":"PGRST301","message":"JWT expired"}"#),
        (401, #"{"message":"bad jwt"}"#),
        (403, #"{"message":"token is expired"}"#),
        (400, #"{"error":"invalid_grant","error_description":"Invalid Refresh Token: Already Used"}"#),
        (400, #"{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token: Refresh Token Not Found"}"#),
        (400, #"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#),
        (400, #"{"code":400,"error_code":"email_not_confirmed","msg":"Email not confirmed"}"#),
        (422, #"{"code":422,"error_code":"user_already_exists","msg":"User already registered"}"#),
        (422, #"{"msg":"Signups not allowed for this instance","error_code":"signup_disabled"}"#),
        (422, #"{"code":422,"error_code":"same_password","msg":"New password should be different from the old password."}"#),
        (422, #"{"code":422,"error_code":"weak_password","msg":"Password should be at least 6 characters."}"#),
        (400, #"{"message":"  ","msg":"  알 수 없는 오류  "}"#),
        (400, #"{"message":"","error":"something else"}"#),
        (400, #"{"details":"no message here"}"#),
        (418, #"{"error_code":"teapot"}"#),
        (200, #"{"message":"ok but called"}"#),
    ]

    static let recoveryInputs: [SupabaseWorkServiceError] = [
        .invalidResponse(429), .invalidResponse(400), .sessionExpired,
        .authMessage("Email rate limit exceeded"),
        .authMessage("For security purposes, you can only request this after 45 seconds."),
        .authMessage("Token has expired or is invalid"), .authMessage("otp_expired"), .authMessage("Verify requires either a token"),
        .authMessage("invalid JWT: unable to parse"), .authMessage("bad_jwt"), .authMessage("missing sub claim"),
        .authMessage("Something else"), .rateLimited(retryAfterSeconds: 9),
    ]

    static let authErrors: [(String, Error)] = [
        ("cancellation", CancellationError()),
        ("urlError.cancelled", URLError(.cancelled)),
        ("urlError.notConnectedToInternet", URLError(.notConnectedToInternet)),
        ("urlError.timedOut", URLError(.timedOut)),
        ("service.invalidResponse(500)", SupabaseWorkServiceError.invalidResponse(500)),
        ("service.invalidResponse(599)", SupabaseWorkServiceError.invalidResponse(599)),
        ("service.invalidResponse(429)", SupabaseWorkServiceError.invalidResponse(429)),
        ("service.invalidResponse(401)", SupabaseWorkServiceError.invalidResponse(401)),
        ("service.invalidResponse(600)", SupabaseWorkServiceError.invalidResponse(600)),
        ("service.rateLimited(nil)", SupabaseWorkServiceError.rateLimited(retryAfterSeconds: nil)),
        ("service.sessionExpired", SupabaseWorkServiceError.sessionExpired),
        ("service.authMessage", SupabaseWorkServiceError.authMessage("x")),
        ("service.databaseSchemaMissing", SupabaseWorkServiceError.databaseSchemaMissing),
    ]

    static let allServiceErrors: [SupabaseWorkServiceError] = [
        .missingAnonKey, .invalidAPIKey, .sessionExpired, .invalidLoginCredentials, .emailNotConfirmed, .emailAlreadyRegistered,
        .signupDisabled, .weakPassword, .databaseSchemaMissing, .ultraWalletUnavailable, .sessionAlreadyOpen,
        .rateLimited(retryAfterSeconds: nil), .rateLimited(retryAfterSeconds: 5), .otpInvalidOrExpired, .samePasswordReuse,
        .authMessage("서버가 보낸 문장"), .invalidResponse(500),
    ]

    @Test func errorClassification() async throws {
        let service = SupabaseWorkService(projectURL: URL(string: "https://golden.invalid")!, anonKey: "k",
                                          session: MobileStubURLProtocol.makeSession())
        var cases: [GoldenJSON] = []
        for (i, (status, body)) in Self.classifyBodies.enumerated() {
            let error = await service.serviceError(statusCode: status, data: Data(body.utf8))
            cases.append(.object([
                "id": .string("classify-\(i)"), "status": .int(status), "body": .string(body), "error": try GoldenMirror.dump(error),
            ]))
        }
        for (i, input) in Self.recoveryInputs.enumerated() {
            cases.append(.object([
                "id": .string("recovery-\(i)"), "input": try GoldenMirror.dump(input),
                "recovered": try GoldenMirror.dump(SupabaseWorkService.passwordRecoveryError(input)),
            ]))
        }
        for text in ["after 30 seconds", "in 1 minute and 07 seconds", "no number seconds", "5 minutes", "a3b4 second", "", "12second"] {
            cases.append(.object([
                "id": .string("retry-after-\(text)"), "text": .string(text),
                "seconds": SupabaseWorkService.retryAfterSeconds(in: text).map { .int($0) } ?? .null,
            ]))
        }
        for (id, error) in Self.authErrors {
            cases.append(.object(["id": .string("auth-\(id)"), "disposition": .string("\(AuthErrorRules.classify(error))")]))
        }
        for (i, error) in Self.allServiceErrors.enumerated() {
            cases.append(.object([
                "id": .string("message-\(i)"), "input": try GoldenMirror.dump(error),
                "message": .string(AuthErrorRules.message(for: error, fallback: "<FALLBACK>")),
                "missingFunction": .bool(BlockReportRules.isMissingFunction(error)),
            ]))
        }
        goldenEmit(GoldenFile(
            golden: "errors/classify",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkHTTP.swift", "Sources/CheckCore/SupabaseWorkService.swift",
                           "Sources/CheckCore/AuthErrorRules.swift", "Sources/CheckCore/BlockReportRules.swift"],
            spec: [
                "order": .string("23505·work_sessions(원문 소문자 포함) → 5xx(invalidResponse) → 429(rateLimited, 본문 'second' 앞 숫자) → 본문 디코드 실패(401 → sessionExpired, 그 밖 invalidResponse) → 본문 문구(schema cache · invalid api key · jwt/pgrst301 · refresh token · login · email · already · signup disable · same_password · password · 그 밖 authMessage)"),
                "error": .string("SupabaseWorkServiceError 의 GoldenMirror 덤프(연관값 없음 = 이름, 있음 = {$case,$value})"),
                "auth": .string("AuthErrorRules.classify: cancelled · transient · fatal. Kotlin 은 id 의 Swift 오류를 같은 뜻의 Kotlin 예외로 바꿔 넣는다(urlError.* = 전송 예외, cancellation = CancellationException)"),
            ],
            cases: cases
        ))
    }

    @Test func jwtExpiry() throws {
        let payloads: [(String, String)] = [
            ("int", #"{"exp":1789621500,"sub":"u"}"#),
            ("float", #"{"exp":1789621500.75}"#),
            ("string", #"{"exp":"1789621500"}"#),
            ("bool", #"{"exp":true}"#),
            ("missing", #"{"sub":"u"}"#),
            ("null", #"{"exp":null}"#),
            ("array-root", #"[1,2]"#),
            ("pad1", #"{"exp":1}"#),
            ("pad2", #"{"exp":12}"#),
            ("pad0", #"{"exp":123}"#),
            ("url-chars", #"{"exp":1789621500,"n":"?>?>"}"#),
            ("unicode", #"{"exp":42,"name":"아잉"}"#),
            ("big", #"{"exp":9007199254740993}"#),
            ("negative", #"{"exp":-5}"#),
        ]
        var cases: [GoldenJSON] = []
        for (id, payload) in payloads {
            // 토큰 글자는 싣지 않는다(eyJ… 는 비밀 검사에 걸린다) — 같은 규칙으로 Kotlin 이 payload 에서 다시 만든다.
            let token = WireRulesSamples.jwt(payload)
            cases.append(.object([
                "id": .string(id), "payload": .string(payload),
                "expiry": JWTClaims.expiry(accessToken: token).map { .object(["$date": .bits($0.timeIntervalSince1970)]) } ?? .null,
            ]))
        }
        let raw: [(String, String)] = [
            ("one-part", "abc"), ("empty", ""), ("two-parts", "x." + WireRulesSamples.base64URL(#"{"exp":7}"#)),
            ("bad-base64", "x.@@@@.y"), ("not-json", "x." + WireRulesSamples.base64URL("not json") + ".y"),
            ("std-base64-padded", "x." + Data(#"{"exp":8}"#.utf8).base64EncodedString() + ".y"),
            ("empty-payload", "x..y"), ("len-mod-1", "x.abcde.y"),
        ]
        for (id, token) in raw {
            cases.append(.object([
                "id": .string(id), "token": .string(token),
                "expiry": JWTClaims.expiry(accessToken: token).map { .object(["$date": .bits($0.timeIntervalSince1970)]) } ?? .null,
            ]))
        }
        goldenEmit(GoldenFile(
            golden: "jwt/expiry",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/JWTClaims.swift"],
            spec: [
                "rule": .string("가운데 조각을 base64url(-_ → +/, = 채우기)로 풀어 JSON 객체의 exp(NSNumber — 불도 숫자)를 1970 기준 초로. 못 읽으면 null(= 모른다, 만료가 아니다)"),
                "token": .string("payload 칸이 있으면 토큰 = \"eyJhbGciOiJIUzI1NiJ9.\" + base64url(payload, = 없음) + \".c2ln\"(골든에 토큰 글자를 싣지 않는다 — 비밀 검사). token 칸은 그대로 쓴다"),
            ],
            cases: cases
        ))
    }

    @Test func wireFileRules() throws {
        var cases: [GoldenJSON] = []
        // 역대 순위 정렬(점수 내림 → bestAt 이른 순, nil 뒤 → userID)
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let entries = [
            MiniGameAllTimeEntry(userID: "d", name: "가", avatarURL: nil, bestScore: 10, bestAt: nil, day: "2026-10-01"),
            MiniGameAllTimeEntry(userID: "b", name: "나", avatarURL: nil, bestScore: 10, bestAt: t0, day: nil),
            MiniGameAllTimeEntry(userID: "a", name: "다", avatarURL: nil, bestScore: 10, bestAt: t0.addingTimeInterval(1), day: nil),
            MiniGameAllTimeEntry(userID: "c", name: "라", avatarURL: nil, bestScore: 10, bestAt: t0, day: nil),
            MiniGameAllTimeEntry(userID: "e", name: "마", avatarURL: nil, bestScore: 99, bestAt: nil, day: nil),
            MiniGameAllTimeEntry(userID: "f", name: "바", avatarURL: nil, bestScore: 10, bestAt: nil, day: nil),
            MiniGameAllTimeEntry(userID: "A", name: "사", avatarURL: nil, bestScore: -1, bestAt: t0, day: nil),
        ]
        func row(_ e: MiniGameAllTimeEntry) -> GoldenJSON {
            .object(["userID": .string(e.userID), "bestScore": .int(e.bestScore),
                     "bestAtBits": e.bestAt.map { .bits($0.timeIntervalSince1970) } ?? .null])
        }
        cases.append(.object([
            "id": .string("alltime-sort"), "rule": .string("sortedForMiniGameAllTimeBoard"),
            "input": .array(entries.map(row)),
            "sorted": .array(entries.sortedForMiniGameAllTimeBoard().map { .string($0.userID) }),
        ]))
        for day in ["2026-10-05", "2026-1-05", "2026-13-01", "2026-12-31", "2026-02-30", "2026-00-10", "2026-10-00", "26-10-05",
                    "2026-10-05T00:00:00Z", "２０２６-10-05", "2026/10/05", "", "2026--10", "2026-10-5x"] {
            cases.append(.object(["id": .string("day-caption-\(day)"), "day": .string(day),
                                  "caption": MiniGameAllTimeEntry.dayCaption(day).map(GoldenJSON.string) ?? .null]))
        }
        cases.append(.object(["id": .string("day-caption-nil"), "day": .null, "caption": MiniGameAllTimeEntry.dayCaption(nil).map(GoldenJSON.string) ?? .null]))
        // 상점 행 판정
        let rows: [ShopCharacterRow] = [
            .init(id: "robot", price: 50), .init(id: "robot"), .init(id: "aing_gold", price: 99), .init(id: "aing_rainbow"),
            .init(id: "aing_cake_choco", price: 100, gachaOnly: true), .init(id: "aing_cake_strawberry"),
            .init(id: "fox", price: 10, gachaOnly: true), .init(id: "fox", price: 10, giftOnly: true),
            .init(id: "fox", price: 10, gachaOnly: false, giftOnly: false),
        ]
        for (i, r) in rows.enumerated() {
            cases.append(.object([
                "id": .string("shop-row-\(i)"), "row": try GoldenMirror.dump(r),
                "isPurchasable": .bool(r.isPurchasable), "isGiftOnly": .bool(r.isGiftOnly), "isGachaOnly": .bool(r.isGachaOnly),
            ]))
        }
        // 선물 선택지(내장 순서로 거른다)
        for (i, raw) in [["aing_cake_choco", "aing_cake_strawberry"], ["robot"], [], ["aing_cake_choco", "aing_cake_choco"],
                         ["AING_CAKE_CHOCO", "aing_cake_strawberry "]].enumerated() {
            cases.append(.object(["id": .string("gift-choosable-\(i)"), "raw": .array(raw.map(GoldenJSON.string)),
                                  "choosable": .array(CharacterGiftOffer.choosable(raw).map(GoldenJSON.string))]))
        }
        // 마이크로초(소수부 직접 · 초는 주입 파서)
        let parser: (String) -> Date? = { ISO8601DateFormatter().date(from: $0) }
        for text in ["2026-10-23T01:02:03.123456+00:00", "2026-10-23T01:02:03Z", "2026-10-23T01:02:03.1Z", "2026-10-23T01:02:03.1234567Z",
                     "2026-10-23 01:02:03", "2026-10-23T01:02:03.+00:00", "2026-10-23T01:02:03.000999+09:00"] {
            cases.append(.object(["id": .string("micros-\(text)"), "text": .string(text),
                                  "micros": MessagePokeLogRules.microsecondsSinceEpoch(text, wholeSeconds: parser).map { .hex64(UInt64(bitPattern: $0)) } ?? .null]))
        }
        // 결과 갈래
        for (i, status) in ["ok", "cooldown", "not_working", "target_not_working", "ultra_used_today", "target_focused",
                            "target_on_phone", "blackout", "not_text", "too_long", "flood", "weird"].enumerated() {
            let r = PokeSendResponse(status: status, retryAfterSeconds: i % 2 == 0 ? nil : -4, resetAfterSeconds: i % 3 == 0 ? nil : 0)
            cases.append(.object([
                "id": .string("send-outcome-\(status)"), "response": try GoldenMirror.dump(r),
                "poke": try GoldenMirror.dump(PokeSendOutcome(response: r)), "message": try GoldenMirror.dump(MessageSendOutcome(response: r)),
            ]))
        }
        for (i, status) in ["ok", "unchanged", "taken", "cooldown", "invalid_long", "invalid_empty", "other"].enumerated() {
            let r = DisplayNameChangeResponse(status: status, displayName: i == 0 ? "새이름" : nil,
                                              retryAfterSeconds: i == 3 ? 0 : nil, maxLength: nil)
            cases.append(.object(["id": .string("display-name-\(status)"), "response": try GoldenMirror.dump(r),
                                  "outcome": try GoldenMirror.dump(DisplayNameChangeOutcome(response: r))]))
        }
        goldenEmit(GoldenFile(
            golden: "wire/rules",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/CharacterGift.swift",
                           "Sources/CheckCore/MessagePokeLog.swift", "Sources/CheckCore/CharacterKit/CharacterCatalog.swift"],
            spec: [
                "alltime": .string("sortedForMiniGameAllTimeBoard: 점수 내림 → bestAt 이른 순(nil 은 뒤) → userID. dayCaption: 'YYYY-MM-DD'(ASCII 숫자, 월 1~12, 일 1~31) → 'M/D'"),
                "shop": .string("isPurchasable = gacha_only·gift_only 표식도 내장 판정도 아니고 값이 있다 · isGiftOnly 가 isGachaOnly 보다 먼저"),
                "micros": .string("MessagePokeLogRules.microsecondsSinceEpoch(초 파서 = 기본 ISO8601). 값은 64비트 16진"),
            ],
            cases: cases
        ))
    }
    /// 숫자 글자 → 칸 타입별 결과(C-X3 표의 확장 — 2^53 너머 소수 글자는 정수부를 정확히, 그 아래는 Double 을 거친다).
    @Test func numbers() throws {
        struct I: Decodable { let v: Int }
        struct D: Decodable { let v: Double }
        struct B: Decodable { let v: Bool }
        struct S: Decodable { let v: String }
        struct O: Decodable { let v: Int? }
        let literals = [
            "0", "-0", "3", "-3", "3.0", "3.5", "-2.5", "0.5", "1e2", "1E2", "1e-2", "15e-1", "1.5e1", "123.0e1", "-0.0",
            "2147483647", "2147483648", "4294967296", "4294967296.0", "4294967296.5", "9007199254740992", "9007199254740993",
            "9007199254740993.0", "9007199254740993.5", "9007199254740993e0", "9.007199254740993e15", "12345678901234567.5",
            "1234567890123456.5", "99999999999999999.9", "9223372036854775807", "9223372036854775808", "9223372036854775807.0",
            "-9223372036854775808", "-9223372036854775809", "-9007199254740993.5", "1.0000000000000002", "2.0000000000000001",
            "7.99999999999999999", "1e15", "1e19", "1e400", "1.7976931348623157e308", "4.9e-324", "\"3\"", "true", "null", "[]", "{}",
        ]
        let decoder = JSONDecoder()
        func run<T: Decodable>(_ t: T.Type, _ lit: String, _ show: (T) -> GoldenJSON) -> GoldenJSON {
            guard let value = try? decoder.decode(T.self, from: Data("{\"v\":\(lit)}".utf8)) else { return .string("error") }
            return show(value)
        }
        var cases: [GoldenJSON] = []
        for lit in literals {
            cases.append(.object([
                "id": .string(lit),
                "Int": run(I.self, lit) { .object(["$int": .hex64(UInt64(bitPattern: Int64($0.v)))]) },
                "Double": run(D.self, lit) { .object(["$f64": .bits($0.v)]) },
                "Bool": run(B.self, lit) { .bool($0.v) },
                "String": run(S.self, lit) { .string($0.v) },
                "OptionalInt": run(O.self, lit) { $0.v.map { .object(["$int": .hex64(UInt64(bitPattern: Int64($0)))]) } ?? .null },
            ]))
        }
        goldenEmit(GoldenFile(
            golden: "wire/numbers",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkService.swift"],
            spec: ["rule": .string("JSONDecoder 로 {\"v\": 글자} 를 칸 타입별로 읽은 결과(error = 던짐). Int 는 64비트 16진")],
            cases: cases
        ))
    }
}

