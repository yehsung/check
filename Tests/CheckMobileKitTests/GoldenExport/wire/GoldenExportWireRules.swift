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

    static func jwt(_ payload: String) -> String { "e30." + base64URL(payload) + ".c2ln" }
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
        ("urlError.networkConnectionLost", URLError(.networkConnectionLost)),
        ("urlError.secureConnectionFailed", URLError(.secureConnectionFailed)),
        ("urlError.serverCertificateUntrusted", URLError(.serverCertificateUntrusted)),
        ("urlError.badServerResponse", URLError(.badServerResponse)),
        ("urlError.cannotConnectToHost", URLError(.cannotConnectToHost)),
        ("urlError.cannotFindHost", URLError(.cannotFindHost)),
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
        for text in ["after 30 seconds", "in 1 minute and 07 seconds", "no number seconds", "5 minutes", "a3b4 second", "", "12second",
                     "after ３０ seconds", "after ²30 seconds", "after ٣٠ seconds", "after Ⅻ30 seconds", "after 一30 seconds", "after ३0 seconds",
                     "after 3٠ seconds", "after ½ seconds", "after -30 seconds", "after +30 seconds", "99999999999999999999 seconds"] {
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
                "token": .string("payload 칸이 있으면 토큰 = \"e30.\" + base64url(payload, = 없음) + \".c2ln\"(골든에 토큰 글자를 싣지 않는다 — 비밀 검사). token 칸은 그대로 쓴다"),
            ],
            cases: cases
        ))
    }

    @Test func wireFileRules() async throws {
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
        // ---- URL(string:) — 서비스가 아바타 글자를 URL 로 거르는 규칙(빈 글자 nil · 잘못된 글자 퍼센트 인코딩 · 호스트·포트가 틀리면 nil) ----
        for (i, text) in Self.urlInputs.enumerated() {
            cases.append(.object(["id": .string("url-\(i)"), "text": .string(text),
                                  "url": URL(string: text).map { .string($0.absoluteString) } ?? .null]))
        }
        // ---- 날짜 파싱(parseDate: 소수초 포매터 → 기본 포매터). Kotlin 이 따르지 않는 관대함은 knownDivergence 로 잠근다 ----
        let service = SupabaseWorkService(projectURL: URL(string: "https://golden.invalid")!, anonKey: "k", session: MobileStubURLProtocol.makeSession())
        for (i, text) in Self.dateInputs.enumerated() {
            let parsed = await service.parseDate(text)
            cases.append(.object(["id": .string("date-\(i)"), "text": .string(text),
                                  "date": parsed.map { .object(["$date": .bits($0.timeIntervalSince1970)]) } ?? .null]))
        }
        // ---- todo_sync 응답(키 변환 없는 JSONDecoder — camel 키는 못 읽는다) ----
        for (i, json) in Self.todoResponses.enumerated() {
            let decoded = try? TodoSyncResponse.decode(Data(json.utf8))
            cases.append(.object(["id": .string("todo-response-\(i)"), "json": .string(json),
                                  "decoded": try decoded.map { try GoldenMirror.dump($0) } ?? .string("error")]))
        }
        // ---- 아바타 디렉터리(AppUserCharacters ★ 접기 규칙 · ⚠️ 경합 — 갈아 끼운 뒤 내 착용값 다시 얹기) ----
        cases.append(contentsOf: try Self.appUserCharacterCases())
        // ---- 제보 글자 규칙(FeedbackComposer · FeedbackText) ----
        cases.append(contentsOf: Self.feedbackCases())
        // ---- 폰 근무 응답 → 뜻(PhoneWorkOutcome.from) ----
        for (i, json) in Self.phoneWorkResponses.enumerated() {
            let response = try WireDecodeRegistry.decoder.decode(PhoneWorkResponse.self, from: Data(json.utf8))
            cases.append(.object(["id": .string("phone-work-outcome-\(i)"), "json": .string(json),
                                  "outcome": try Self.phoneWorkOutcome(PhoneWorkOutcome.from(response))]))
        }
        goldenEmit(GoldenFile(
            golden: "wire/rules",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/CharacterGift.swift",
                           "Sources/CheckCore/MessagePokeLog.swift", "Sources/CheckCore/CharacterKit/CharacterCatalog.swift",
                           "Sources/CheckCore/AppUserCharacters.swift", "Sources/CheckCore/TodoSync.swift", "Sources/CheckCore/SupabaseWorkService.swift",
                           "Sources/CheckMobileKit/Session/MobilePhoneWorkService.swift"],
            spec: [
                "alltime": .string("sortedForMiniGameAllTimeBoard: 점수 내림 → bestAt 이른 순(nil 은 뒤) → userID. dayCaption: 'YYYY-MM-DD'(ASCII 숫자, 월 1~12, 일 1~31) → 'M/D'"),
                "shop": .string("isPurchasable = gacha_only·gift_only 표식도 내장 판정도 아니고 값이 있다 · isGiftOnly 가 isGachaOnly 보다 먼저"),
                "micros": .string("MessagePokeLogRules.microsecondsSinceEpoch(초 파서 = 기본 ISO8601). 값은 64비트 16진"),
                "url": .string("URL(string:)?.absoluteString — 서비스가 아바타 글자를 거르는 규칙(null = 못 만든다)"),
                "urlKnownDivergence": .array(Self.urlInputs.enumerated().compactMap { i, text in
                    Self.urlKnownDivergence[text].map { .object(["id": .string("url-\(i)"), "text": .string(text), "reason": .string($0)]) }
                }),
                "date": .string("SupabaseWorkService.parseDate(소수초 포매터 → 기본 포매터) → $date 비트 또는 null"),
                "dateKnownDivergence": .array(Self.dateInputs.enumerated().compactMap { i, text in
                    Self.dateKnownDivergence[text].map { .object(["id": .string("date-\(i)"), "text": .string(text), "reason": .string($0)]) }
                }),
                "todoResponse": .string("TodoSyncResponse.decode(키 변환 없는 JSONDecoder) 덤프 또는 error"),
                "appUserCharacters": .string("AppUserCharacterDirectory(knownIDs: [robot, ' fox ', '', aing_cake_choco, ROBOT], rows) → setEquipped(unicorn, aa-1) · setEquipped(nil, ZZ-9) · setEquipped(robot, '  ') → replace([dd-4 fox, ff-6 nil]) → removeAll. 사진 = https://golden.invalid/p.jpg. avatar = {kind photo|character|initials …}. hinted = 힌트 [nil, robot, fox, unicorn, ' robot ', '', aing] 마다 [사진 없음, 사진]"),
                "feedback": .string("FeedbackComposer(자소 = Swift Character) · FeedbackText 상수·함수. age = now(values) - secondsAgo"),
                "phoneWorkOutcome": .string("PhoneWorkResponse(convertFromSnakeCase) → PhoneWorkOutcome.from → {case, session|last|alreadyWorking}"),
            ],
            cases: cases
        ))
    }
    // ---- 검증 지적 수리: 표 입력 ----

    static let urlInputs: [String] = [
        "", " ", "  https://x.invalid/a.jpg  ", "https://x.invalid/a b.jpg", "https://x.invalid/a.jpg", "not a url", "%", "%zz", "a%2",
        "https://x.invalid/%E1%84", "https://x.invalid/한글.jpg", "https://x.invalid/a.jpg?v=1-ABCDEF12", "https://x.invalid/a%20b.jpg",
        "https://x.invalid/a.jpg#frag", "https://x.invalid/a.jpg#fr ag", "http://[::1]/a", "https://x.invalid/a|b", "https://x.invalid/a\"b",
        "https://x.invalid/a<b>c", "https://x.invalid/a{b}", "https://x.invalid/a\\b", "https://x.invalid/a^b`c", "javascript:alert(1)",
        "https://user@x.invalid/", "https://us er@x.invalid/", "https://x.invalid:99999/", "https://x.invalid:abc/", "https://x .invalid/",
        "https://x.invalid/?q=a b&r=한", "https://x.invalid/?q=%", "mailto:a b@c", "//x.invalid/a b", "/rel/a b", "a:b:c", "https://",
        "https:", ":", "?", "#", "https://x.invalid/a\tb", "https://x.invalid/a\nb", "https://x.invalid/\u{7F}", "https://x.invalid/\u{00A0}",
        "https://x.invalid/😀", "HTTPS://X.INVALID/A", "https://x.invalid/a[b]", "https://[x]/", "https://x.invalid/a%2Fb", "file:///a b",
        "a b:c", "1a:b", ":a b", "+a:b", "a+.-:b", "https://한글.com/", "https://x.invalid/a#b#c", "https://x.invalid/a?b?c", "https://[a b]/",
        "https://x.invalid:/", "https://@x.invalid/", "https://a:b@x.invalid/", "https://a@b@x.invalid/", "https://x.invalid/a@b:c",
        "https://x_y.invalid/", "https://x~y.invalid/", "https://x%41.invalid/", "https://x%zz.invalid/", "https://x.invalid/%",
        "https://x.invalid/?%41", "https://x.invalid/#%", "https://x.invalid/a%2g", "http://x.invalid/a b?c d#e f", "https://x.invalid//a b",
        "x", "x y", "./a b", "../a", "a/b:c", "?a b", "#a b", "https://x.invalid?a", "https://x.invalid#a", "https://x.invalid:8%30/",
        "https://x.invalid/\u{0}", "HTTP://X/ a", "h:ttps", "https://x.invalid/!$&'()*+,;=:@", "https://x.invalid/?!$&'()*+,;=:@/?",
        "https://x.invalid/#!$&'()*+,;=:@/?", "https://x!.invalid/", "https://x$&'()*+,;=.invalid/", "https://[::1]:80/a", "https://[::1]x/",
        "https://x.invalid/a\u{FEFF}b", "\u{FEFF}https://x.invalid/", "https://x.invalid/a\u{200B}b", "https://user:p w@x.invalid/",
        "https://us%er@x.invalid/", "https://abcdefgh.supabase.invalid/storage/v1/object/public/avatars/aa000000-0000-4000-8000-0000000000a1.jpg?v=1789621500000-ABCDEF12",
    ]

    /// Kotlin `SwiftURL.parse` 가 따르지 않는 갈림(아바타 주소는 늘 Supabase Storage 의 ASCII 호스트다). 늘거나 줄면 Kotlin 이 빨갛다.
    static let urlKnownDivergence: [String: String] = [
        "https://한글.com/": "아스키 밖 호스트 — Apple 은 IDNA(punycode)로 바꾸고 Kotlin 은 null",
    ]

    static let dateInputs: [String] = [
        "2026-09-17T05:05:00Z", "2026-09-17T05:05:00.123456+00:00", "2026-09-17T05:05:00.5Z", "2026-09-17T05:05:00+09:00",
        "2026-09-17T05:05:00-03:30", "2026-09-17T05:05:00.1234567890Z", "2026-09-17T05:05:00.999999Z", "1970-01-01T00:00:00Z",
        "1969-12-31T23:59:59.999Z", "２０２６-09-17T05:05:00Z", "2026-09-17T05:05:00.５Z", "٢٠٢٦-09-17T05:05:00Z", "२०२६-09-17T05:05:00Z",
        "2026-09-17T05:05:00+0900", "2026-09-17T05:05:00+09", "2026-09-17 05:05:00Z", "2026-09-17t05:05:00z", "2026-09-17T05:05:60Z",
        "2026-02-30T00:00:00Z", "2026-09-17T24:00:00Z", "2026-09-17T05:05Z", "+2026-09-17T05:05:00Z", "2026-09-17T05:05:00,5Z",
        "2026-09-17T05:05:00.Z", "  2026-09-17T05:05:00Z", "2026-09-17T05:05:00Z ", "2026-9-17T05:05:00Z", "20260917T050500Z",
        "2026-09-17T05:05:00", "", "bad-date",
    ]

    /// Kotlin `SwiftISO8601.parse` 가 **일부러** 따르지 않는 Apple 포매터의 관대함(서버 timestamptz 는 늘 ASCII · 두 자리 · ±hh:mm 이다).
    /// 이 목록이 늘거나 줄면 Kotlin 시험이 빨갛다 — 갈림을 고치거나 새로 생기면 이 목록부터 바꾼다.
    static let dateKnownDivergence: [String: String] = [
        "２０２６-09-17T05:05:00Z": "전각 숫자", "2026-09-17T05:05:00.５Z": "전각 숫자(소수부)", "٢٠٢٦-09-17T05:05:00Z": "아랍-인도 숫자",
        "२०२६-09-17T05:05:00Z": "데바나가리 숫자", "2026-09-17T05:05:00+09": "분 없는 시간대", "2026-02-30T00:00:00Z": "없는 날짜를 넘김",
        "2026-09-17T24:00:00Z": "24시", "  2026-09-17T05:05:00Z": "앞 공백", "2026-09-17T05:05:00Z ": "뒤 공백",
        "2026-9-17T05:05:00Z": "한 자리 월",
    ]

    static let todoResponses: [String] = [
        #"{"status":"ok","items":[{"id":"a","title":"t","created_at_ms":1,"updated_at_ms":2,"completed_at_ms":null,"deleted_at_ms":null,"origin_day_key":"20260917"}],"watermark_ms":5,"rejected":[{"id":"b","reason":"stale"}],"full":true,"max":200}"#,
        #"{"status":"ok","watermarkMs":5,"items":[{"id":"a","createdAtMs":1,"updatedAtMs":2,"originDayKey":"x"}]}"#,
        #"{"status":"ok","WATERMARK_MS":5,"Watermark_Ms":6}"#,
        #"{"status":"ok","watermark_ms":"5","full":"yes","max":3.5}"#,
        #"{"status":3}"#,
        #"[]"#,
    ]

    static let phoneWorkResponses: [String] = [
        #"{"status":"ok","session":{"id":"S-1","started_at":"2026-09-17T05:00:00Z","origin":"phone"}}"#,
        #"{"status":"ok","session":{"id":"S-1","started_at":"2026-09-17T05:00:00Z","ended_at":"2026-09-17T06:00:00Z","reason":"manual"}}"#,
        #"{"status":"ok"}"#,
        #"{"status":"already_working","session":{"id":"S-2","origin":"mac"}}"#,
        #"{"status":"already_working"}"#,
        #"{"status":"not_working","last":{"id":"S-0","ended_at":"2026-09-17T04:00:00Z","reason":"idle"}}"#,
        #"{"status":"not_working"}"#,
        #"{"status":"mismatch"}"#, #"{"status":"no_team"}"#, #"{"status":"unauthorized"}"#, #"{"status":"weird"}"#, #"{}"#,
        #"{"status":3,"session":{"id":"S"}}"#,
    ]

    static func phoneWorkOutcome(_ outcome: PhoneWorkOutcome) throws -> GoldenJSON {
        switch outcome {
        case let .working(session, alreadyWorking):
            return .object(["case": .string("working"), "session": try GoldenMirror.dump(session), "alreadyWorking": .bool(alreadyWorking)])
        case .stopped(let session):
            return .object(["case": .string("stopped"), "session": try session.map { try GoldenMirror.dump($0) } ?? .null])
        case .notWorking(let last):
            return .object(["case": .string("notWorking"), "last": try last.map { try GoldenMirror.dump($0) } ?? .null])
        case .mismatch: return .object(["case": .string("mismatch")])
        case .noTeam: return .object(["case": .string("noTeam")])
        case .unauthorized: return .object(["case": .string("unauthorized")])
        case .failed: return .object(["case": .string("failed")])
        }
    }

    static func avatar(_ a: AppUserAvatar) -> GoldenJSON {
        switch a {
        case let .photo(url, fallback):
            return .object(["kind": .string("photo"), "url": .string(url.absoluteString), "fallback": fallback.map(GoldenJSON.string) ?? .null])
        case .character(let id): return .object(["kind": .string("character"), "id": .string(id)])
        case .initials: return .object(["kind": .string("initials")])
        }
    }

    /// 디렉터리 대본: 만들기(knownIDs · rows) → 물음들 → replace · setEquipped · removeAll 뒤 다시 물음.
    static func appUserCharacterCases() throws -> [GoldenJSON] {
        let known = ["robot", " fox ", "", "aing_cake_choco", "ROBOT"]
        let rows: [AppUserCharacterRow] = [
            .init(userId: "AA-1", character: "robot"), .init(userId: "bb-2", character: nil), .init(userId: "cc-3", character: "  "),
            .init(userId: "dd-4", character: "unicorn"), .init(userId: " ee-5 ", character: " fox "), .init(userId: nil, character: "fox"),
            .init(userId: "  ", character: "robot"), .init(userId: "aa-1", character: "aing_cake_choco"),
        ]
        let users: [String?] = ["aa-1", "AA-1", " aa-1 ", "bb-2", "cc-3", "dd-4", "ee-5", "zz-9", nil, ""]
        let photo = URL(string: "https://golden.invalid/p.jpg")!
        let hints: [String?] = [nil, "robot", "fox", "unicorn", " robot ", "", "aing"]
        func snapshot(_ d: AppUserCharacterDirectory) -> GoldenJSON {
            var perUser: [GoldenJSON] = []
            for user in users {
                var hinted: [GoldenJSON] = []
                for hint in hints {
                    hinted.append(.array([avatar(d.avatar(for: user, photoURL: nil, characterHint: hint)),
                                          avatar(d.avatar(for: user, photoURL: photo, characterHint: hint))]))
                }
                perUser.append(.object([
                    "user": user.map(GoldenJSON.string) ?? .null,
                    "characterID": d.characterID(for: user).map(GoldenJSON.string) ?? .null,
                    "equippedID": d.equippedID(for: user).map(GoldenJSON.string) ?? .null,
                    "avatarNoPhoto": avatar(d.avatar(for: user, photoURL: nil)),
                    "avatarPhoto": avatar(d.avatar(for: user, photoURL: photo)),
                    "afterPhotoFailure": avatar(d.avatar(for: user, photoURL: photo).afterPhotoFailure),
                    "hinted": .array(hinted),
                ]))
            }
            return .object(["count": .int(d.count), "isEmpty": .bool(d.isEmpty),
                            "knownIDs": .array(d.knownIDs.sorted().map(GoldenJSON.string)), "users": .array(perUser)])
        }
        var d = AppUserCharacterDirectory(knownIDs: known, rows: rows)
        var out: [GoldenJSON] = [.object(["id": .string("app-user-characters-built"), "snapshot": snapshot(d)])]
        d.setEquipped("unicorn", for: "aa-1")
        d.setEquipped(nil, for: "ZZ-9")
        d.setEquipped("robot", for: "  ")
        out.append(.object(["id": .string("app-user-characters-setEquipped"), "snapshot": snapshot(d)]))
        d.replace(with: [.init(userId: "dd-4", character: "fox"), .init(userId: "ff-6", character: nil)])
        out.append(.object(["id": .string("app-user-characters-replaced"), "snapshot": snapshot(d)]))
        d.removeAll()
        out.append(.object(["id": .string("app-user-characters-removed"), "snapshot": snapshot(d)]))
        for (i, raw) in [nil, "", "  ", " robot ", "\nfox\t"].enumerated() {
            out.append(.object(["id": .string("app-user-characters-fold-\(i)"), "raw": raw.map(GoldenJSON.string) ?? .null,
                                "folded": .string(AppUserCharacterDirectory.foldedEquippedID(raw)),
                                "userKey": AppUserCharacterDirectory.normalizedUserID(raw).map(GoldenJSON.string) ?? .null]))
        }
        return out
    }

    static let feedbackInputs: [String] = [
        "", "  ", " a ", "\n버그\n", String(repeating: "가", count: 1000), String(repeating: "가", count: 1001),
        " " + String(repeating: "가", count: 1000) + " ", String(repeating: "👨‍👩‍👧", count: 1000), String(repeating: "👨‍👩‍👧", count: 1001),
        String(repeating: "a", count: 900), String(repeating: "a", count: 901), String(repeating: "e\u{301}", count: 501),
        String(repeating: "나", count: 499) + "e\u{301}" + "다", "\u{3000}전각 공백\u{3000}",
    ]

    static func feedbackCases() -> [GoldenJSON] {
        var out: [GoldenJSON] = []
        for (i, text) in feedbackInputs.enumerated() {
            out.append(.object([
                "id": .string("feedback-compose-\(i)"), "text": .string(text),
                "normalized": .string(FeedbackComposer.normalized(text)),
                "isSendable": .bool(FeedbackComposer.isSendable(text)),
                "counterText": .string(FeedbackComposer.counterText(text)),
                "isCounterWarning": .bool(FeedbackComposer.isCounterWarning(text)),
                "normalizedNote": FeedbackComposer.normalizedNote(text).map(GoldenJSON.string) ?? .null,
                "isSendableReplyNil": .bool(FeedbackComposer.isSendableReply(draft: text, savedNote: nil)),
                "isSendableReplySame": .bool(FeedbackComposer.isSendableReply(draft: text, savedNote: FeedbackComposer.normalizedNote(text))),
            ]))
        }
        let constants: [(String, String)] = [
            ("windowTitle", FeedbackText.windowTitle), ("sendTab", FeedbackText.sendTab), ("inboxTab", FeedbackText.inboxTab),
            ("placeholder", FeedbackText.placeholder), ("sendAction", FeedbackText.sendAction), ("sending", FeedbackText.sending),
            ("sendSuccess", FeedbackText.sendSuccess), ("rateLimited", FeedbackText.rateLimited), ("sendFailed", FeedbackText.sendFailed),
            ("sendSchemaMissing", FeedbackText.sendSchemaMissing), ("forbidden", FeedbackText.forbidden), ("statusFailed", FeedbackText.statusFailed),
            ("mineTitle", FeedbackText.mineTitle), ("mineEmpty", FeedbackText.mineEmpty), ("inboxEmpty", FeedbackText.inboxEmpty),
            ("inboxEmptyHint", FeedbackText.inboxEmptyHint), ("inboxFilterEmptyHint", FeedbackText.inboxFilterEmptyHint),
            ("filterAll", FeedbackText.filterAll), ("loading", FeedbackText.loading), ("failed", FeedbackText.failed), ("retry", FeedbackText.retry),
            ("notePlaceholder", FeedbackText.notePlaceholder), ("noteSave", FeedbackText.noteSave), ("replyAction", FeedbackText.replyAction),
            ("replySending", FeedbackText.replySending), ("replyBlockTitle", FeedbackText.replyBlockTitle), ("replySent", FeedbackText.replySent),
            ("replyFailed", FeedbackText.replyFailed), ("replySchemaMissing", FeedbackText.replySchemaMissing), ("replyEmpty", FeedbackText.replyEmpty),
            ("replyTooLong", FeedbackText.replyTooLong), ("replyNotFound", FeedbackText.replyNotFound),
            ("maxBodyLength", String(FeedbackComposer.maxBodyLength)), ("warnBodyLength", String(FeedbackComposer.warnBodyLength)),
            ("maxNoteLength", String(FeedbackComposer.maxNoteLength)),
        ]
        for (name, value) in constants {
            out.append(.object(["id": .string("feedback-text-\(name)"), "name": .string(name), "value": .string(value),
                                "isSuccessNotice": .bool(FeedbackText.isSuccessNotice(value))]))
        }
        for status in FeedbackStatus.known + [.other("검토")] {
            out.append(.object(["id": .string("feedback-filter-empty-\(status.rawValue)"), "status": .string(status.rawValue),
                                "text": .string(FeedbackText.inboxFilterEmpty(status))]))
        }
        for (i, (version, build, os)) in [("0.3.67", 120, "15.6.1"), ("", nil, "14.0"), ("1.0", 0, "26"), ("", -3, "")].enumerated() {
            out.append(.object(["id": .string("feedback-auto-attach-\(i)"), "appVersion": .string(version), "build": build.map { .int($0) } ?? .null,
                                "osVersion": .string(os),
                                "text": .string(FeedbackText.autoAttachNotice(appVersion: version, build: build, osVersion: os))]))
        }
        let now = WireGoldenValues.now
        for offset in [nil, -5.0, 0, 59.9, 60, 3599, 3600, 86_399, 86_400, 172_800.5, 1e9] as [Double?] {
            let date = offset.map { now.addingTimeInterval(-$0) }
            out.append(.object(["id": .string("feedback-age-\(offset.map { String($0) } ?? "nil")"),
                                "secondsAgo": offset.map { .object(["$f64": .bits($0)]) } ?? .null,
                                "text": .string(FeedbackText.ageText(date, now: now))]))
        }
        return out
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

