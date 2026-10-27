// 원본: 없음
@testable import CheckCore
import CheckGoldenSupport
import Foundation
import Testing

// W1-d 실시간 골든(G4 · C§5.2): ① 소켓 수명 상태기계 `RealtimeLink` 를 시드 고정 무작위 걷기 10,000걸음으로 몰아
// 걸음마다 (사건 · 효과 · 상태 · 보조 칸)의 정규 글자를 FNV-1a 64 로 접어 500걸음마다 체크포인트를 남긴다(앞 40걸음은 그대로).
// ② Phoenix 프레임 조립·해석 표(조인 private · 하트비트 · 토큰 밀기 · 들어온 글자 → 사건 · 거절 사유 분류 · 소켓 주소).
// 걷기 생성 규칙은 spec 에 적고 Kotlin 이 같은 SplitMix64 로 같은 사건열을 만든다.

enum RealtimeWalk {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func jwt(exp: Double) -> String {
        "eyJhbGciOiJIUzI1NiJ9." + WireRulesSamples.base64URL("{\"exp\":\(Int(exp))}") + ".c2ln"
    }

    static var tokOK: String { jwt(exp: start.timeIntervalSince1970 + 2_592_000) }
    static var tokSoon: String { jwt(exp: start.timeIntervalSince1970 + 100) }
    static let tokBad = "not-a-jwt"

    /// 사건 고르기(29 갈래, tick 은 6 칸). rng 를 쓰는 차례가 계약이다(Kotlin 도 같은 차례로 부른다).
    static func event(_ rng: inout MiniGameRandom) -> RealtimeEvent {
        let pick = rng.next() % 34
        switch pick {
        case 0: return .signedIn(accessToken: tokOK)
        case 1: return .signedIn(accessToken: tokSoon)
        case 2: return .signedIn(accessToken: tokBad)
        case 3: return .signedOut
        case 4: return .willSleep
        case 5: return .didWake
        case 6: return .transport(.opened)
        case 7, 8: return .transport(.joined)
        case 9: return .transport(.joinRejected(.expiredToken))
        case 10: return .transport(.joinRejected(.unauthorized))
        case 11: return .transport(.joinRejected(.unknown("boom")))
        case 12: return .transport(.broadcast(event: "gomoku"))
        case 13: return .transport(.broadcast(event: "chess"))
        case 14: return .transport(.broadcast(event: "tetris"))
        case 15: return .transport(.broadcast(event: "message_read"))
        case 16: return .transport(.broadcast(event: "poke"))
        case 17: return .transport(.heartbeatAck)
        case 18: return .transport(.heartbeatTimedOut)
        case 19: return .transport(.closed(code: rng.next() % 2 == 0 ? nil : 1006))
        case 20, 21: return .backoffElapsed
        case 22...27: return .tick
        case 28: return .tokenRefreshed(accessToken: tokOK)
        case 29: return .tokenRefreshed(accessToken: tokSoon)
        case 30: return .tokenRefreshFailed(fatal: rng.next() % 2 == 0)
        case 31: return .userRequestedRetry
        default: return .tick
        }
    }

    static func fnv(_ text: String, into h: inout UInt64) {
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
    }

    static func record(_ link: RealtimeLink, _ event: RealtimeEvent, _ effects: [RealtimeEffect], now: Date) throws -> GoldenJSON {
        .object([
            "now": .bits(now.timeIntervalSince1970),
            "e": try GoldenMirror.dump(event),
            "fx": try GoldenMirror.dump(effects),
            "s": try GoldenMirror.dump(link.state),
            "tok": link.accessToken.map(GoldenJSON.string) ?? .null,
            "fs": link.failingSince.map { .bits($0.timeIntervalSince1970) } ?? .null,
            "fr": .bool(link.forcedRefreshUsedThisAttempt),
            "hb": link.lastHeartbeatSentAt.map { .bits($0.timeIntervalSince1970) } ?? .null,
        ])
    }

    static func walk(seed: UInt64, steps: Int, transportAvailable: Bool) throws -> GoldenJSON {
        var rng = MiniGameRandom(seed: seed)
        var link = RealtimeLink(transportAvailable: transportAvailable)
        var now = start
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        var checkpoints: [GoldenJSON] = []
        var head: [GoldenJSON] = []
        var counts: [String: Int] = [:]
        for step in 1...steps {
            var dt = Double(rng.next() % 20_001) / 1000
            if rng.next() % 50 == 0 { dt += 60 }
            now = now.addingTimeInterval(dt)
            let event = event(&rng)
            let effects = link.apply(event, now: now) { ceiling in ceiling * (0.5 + 0.5 * rng.unit()) }
            let rec = try record(link, event, effects, now: now)
            fnv(try rec.canonicalText(), into: &h)
            if step <= 40 { head.append(WireScrub.json(rec)) }
            if step % 500 == 0 { checkpoints.append(.hex64(h)) }
            let stateName: String = {
                switch link.state {
                case .idle(let r): return "idle.\(r)"
                case .connecting: return "connecting"
                case .subscribed: return "subscribed"
                case .reconnecting: return "reconnecting"
                case .failed(_, let f): return "failed.\(f)"
                }
            }()
            counts[stateName, default: 0] += 1
        }
        return .object([
            "id": .string("seed-\(String(seed, radix: 16))-\(steps)-\(transportAvailable)"),
            "seed": .hex64(seed),
            "steps": .int(steps),
            "transportAvailable": .bool(transportAvailable),
            "head": .array(head),
            "checkpoints": .array(checkpoints),
            "final": .hex64(h),
            "stateCounts": .object(counts.mapValues { .int($0) }),
        ])
    }
}

@Suite("GoldenExport W1-d 와이어 — 실시간 G4·프레임")
struct GoldenExportWireRealtime {
    @Test func linkWalk() throws {
        let cases = [
            try RealtimeWalk.walk(seed: 0x5EED_0000_0000_0004, steps: 10_000, transportAvailable: true),
            try RealtimeWalk.walk(seed: 42, steps: 2_000, transportAvailable: true),
            try RealtimeWalk.walk(seed: 7, steps: 300, transportAvailable: false),
        ]
        goldenEmit(GoldenFile(
            golden: "realtime/link-walk",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RealtimeLink.swift", "Sources/CheckCore/JWTClaims.swift", "Sources/CheckCore/MiniGameEngine.swift"],
            spec: [
                "rng": .string("MiniGameRandom(SplitMix64)(seed). 걸음마다: dt = (next() % 20001)/1000 초, next() % 50 == 0 이면 dt += 60 → now += dt → 사건 = event(rng) → link.apply(사건, now, jitter: c → c * (0.5 + 0.5 * unit()))"),
                "events": .string("next() % 34: 0 signedIn(tokOK) · 1 signedIn(tokSoon) · 2 signedIn(\"not-a-jwt\") · 3 signedOut · 4 willSleep · 5 didWake · 6 opened · 7,8 joined · 9 joinRejected(expiredToken) · 10 joinRejected(unauthorized) · 11 joinRejected(unknown(\"boom\")) · 12 gomoku · 13 chess · 14 tetris · 15 message_read · 16 poke(방송) · 17 heartbeatAck · 18 heartbeatTimedOut · 19 closed(next()%2==0 ? nil : 1006) · 20,21 backoffElapsed · 22…27 tick · 28 tokenRefreshed(tokOK) · 29 tokenRefreshed(tokSoon) · 30 tokenRefreshFailed(fatal: next()%2==0) · 31 userRequestedRetry · 32,33 tick"),
                "tokens": .string("start = 1970+1790000000초. tokOK = JWT(exp = start+2592000), tokSoon = JWT(exp = start+100) — 머리 eyJhbGciOiJIUzI1NiJ9 · 꼬리 c2ln · 가운데 base64url({\"exp\":N})"),
                "record": .string("걸음 기록 = {now(비트) · e(사건 덤프) · fx(효과 덤프) · s(상태 덤프) · tok · fs(failingSince 비트) · fr(forcedRefreshUsedThisAttempt) · hb(lastHeartbeatSentAt 비트)} 의 정규 글자를 UTF-8 바이트로 FNV-1a 64 에 접는다. 500걸음마다 체크포인트, 앞 40걸음은 기록 그대로(JWT 모양 글자만 <jwt:길이> — 지문은 바꾸기 전 글자로 센다)"),
            ],
            cases: cases
        ))
    }

    @Test func frames() throws {
        var cases: [GoldenJSON] = []
        func parsed(_ text: String) throws -> GoldenJSON { try GoldenJSON.parse(Data(text.utf8)) }
        cases.append(.object(["id": .string("join-private"),
                              "frame": try parsed(RealtimeFrame.join(channel: "poke:u1", accessToken: "tok", isPrivate: true, ref: "1"))]))
        cases.append(.object(["id": .string("join-public"),
                              "frame": try parsed(RealtimeFrame.join(channel: "poke:u1", accessToken: "tok", isPrivate: false, ref: "7"))]))
        cases.append(.object(["id": .string("heartbeat"), "frame": try parsed(RealtimeFrame.heartbeat(ref: "12"))]))
        cases.append(.object(["id": .string("access-token"),
                              "frame": try parsed(RealtimeFrame.accessToken(channel: "poke:u1", token: "new", ref: "3", joinRef: "1"))]))
        for (i, url) in ["https://abc.invalid", "http://localhost:54321", "https://abc.invalid/", "https://abc.invalid/path?x=1"].enumerated() {
            cases.append(.object(["id": .string("socket-url-\(i)"), "projectURL": .string(url),
                                  "socketURL": RealtimeFrame.socketURL(projectURL: URL(string: url)!, apiKey: "k&y").map { .string($0.absoluteString) } ?? .null]))
        }
        let incoming: [(String, String?)] = [
            (#"{"topic":"phoenix","event":"phx_reply","payload":{"status":"ok"},"ref":"9"}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_reply","payload":{"status":"ok","response":{}},"ref":"1"}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_reply","payload":{"status":"ok"},"ref":"2"}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_reply","payload":{"status":"ok"},"ref":1}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_reply","payload":{"status":"ok"},"ref":"5"}"#, nil),
            (#"{"topic":"realtime:poke:u1","event":"phx_reply","payload":{"status":"error","response":{"reason":"Unauthorized: RLS policy"}},"ref":"1"}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_reply","payload":{"status":"error","response":{"error":"InvalidJWTToken: Token has expired 30 seconds ago"}},"ref":"1"}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_reply","payload":{"status":"error","response":{}},"ref":"1"}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_reply","payload":{},"ref":"1"}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"broadcast","payload":{"event":"gomoku","payload":{"m":"x"}}}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"broadcast","payload":{}}"#, "1"),
            (#"{"event":"broadcast","payload":{"event":"chess"}}"#, "1"),
            (#"{"topic":7,"event":"broadcast","payload":{"event":"tetris"}}"#, "1"),
            (#"{"topic":"realtime:poke:other","event":"broadcast","payload":{"event":"gomoku"}}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_error","payload":{}}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"phx_close","payload":{}}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"system","payload":{"status":"error","message":"permission denied for topic"}}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"system","payload":{"status":"ok","message":"subscribed"}}"#, "1"),
            (#"{"topic":"realtime:poke:u1","event":"presence_state","payload":{}}"#, "1"),
            (#"{"topic":"realtime:poke:u1","payload":{}}"#, "1"),
            (#"[1,2]"#, "1"),
            ("not json", "1"),
            (#"{"topic":"realtime:poke:u1","event":"broadcast","payload":"x"}"#, "1"),
        ]
        for (i, (text, joinRef)) in incoming.enumerated() {
            let event = RealtimeFrame.decode(text: text, channel: "poke:u1", joinRef: joinRef)
            cases.append(.object([
                "id": .string("decode-\(i)"), "text": .string(text), "joinRef": joinRef.map(GoldenJSON.string) ?? .null,
                "event": try event.map { try GoldenMirror.dump($0) } ?? .null,
            ]))
        }
        for reason in ["", "Token has expired", "InvalidJWTToken", "invalid JWT", "Unauthorized", "You do not have permission",
                       "not authorized", "Forbidden", "RLS", "expired and unauthorized", "something else", "EXPIRED"] {
            cases.append(.object(["id": .string("classify-\(reason)"), "reason": .string(reason),
                                  "rejection": try GoldenMirror.dump(RealtimeFrame.classifyJoinError(reason: reason))]))
        }
        goldenEmit(GoldenFile(
            golden: "realtime/frames",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RealtimeTransport.swift"],
            spec: [
                "frame": .string("조립한 글자를 파싱한 JSON 값(키 순서 무관). 조인은 private 칸·access_token·join_ref = ref"),
                "decode": .string("RealtimeFrame.decode(text, channel: \"poke:u1\", joinRef) → 사건 덤프 또는 null"),
            ],
            cases: cases
        ))
    }
}
