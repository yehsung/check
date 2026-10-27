// 원본: 없음
@testable import CheckCore
import CheckGoldenSupport
import Foundation
@testable import CheckMobileKit

// W1-d 골든(와이어) 공용 도우미. 이 파일엔 시험이 없다(스위트는 GoldenExportWire*.swift).
//
// 숫자 글자를 **그대로** 쥐는 JSON 나무(`WireJSON`). JSONSerialization 은 `3.0` 을 3 으로 접어 G6 변형("정수 칸에 3.0")을
// 만들 수 없다. Kotlin 쪽은 kotlinx JsonElement 가 숫자 글자를 그대로 들고 있어 같은 변형을 같은 글자로 만든다.

enum WireJSON: Equatable {
    case object([(String, WireJSON)])
    case array([WireJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    static func == (lhs: WireJSON, rhs: WireJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)): return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.array(a), .array(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    // ---- 읽기(RFC 8259 — 원본 픽스처는 정상 JSON 이다) ----

    struct ParseError: Error, CustomStringConvertible { let description: String }

    static func parse(_ text: String) throws -> WireJSON {
        var p = Parser(Array(text.unicodeScalars))
        p.skipWS()
        let v = try p.value()
        p.skipWS()
        guard p.i == p.s.count else { throw ParseError(description: "뒤에 글자가 남았다") }
        return v
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        mutating func skipWS() {
            while i < s.count, [" ", "\n", "\r", "\t"].contains(s[i]) { i += 1 }
        }

        mutating func value() throws -> WireJSON {
            guard i < s.count else { throw ParseError(description: "끝") }
            switch s[i] {
            case "{":
                i += 1; skipWS()
                var members: [(String, WireJSON)] = []
                if i < s.count, s[i] == "}" { i += 1; return .object(members) }
                while true {
                    skipWS()
                    guard case .string(let key) = try value() else { throw ParseError(description: "키가 글자가 아니다") }
                    skipWS()
                    guard i < s.count, s[i] == ":" else { throw ParseError(description: ": 없음") }
                    i += 1; skipWS()
                    members.append((key, try value()))
                    skipWS()
                    guard i < s.count else { throw ParseError(description: "객체 끝 없음") }
                    if s[i] == "," { i += 1; continue }
                    if s[i] == "}" { i += 1; return .object(members) }
                    throw ParseError(description: "객체 구분 기호")
                }
            case "[":
                i += 1; skipWS()
                var items: [WireJSON] = []
                if i < s.count, s[i] == "]" { i += 1; return .array(items) }
                while true {
                    skipWS()
                    items.append(try value())
                    skipWS()
                    guard i < s.count else { throw ParseError(description: "배열 끝 없음") }
                    if s[i] == "," { i += 1; continue }
                    if s[i] == "]" { i += 1; return .array(items) }
                    throw ParseError(description: "배열 구분 기호")
                }
            case "\"":
                i += 1
                var out = String.UnicodeScalarView()
                while true {
                    guard i < s.count else { throw ParseError(description: "글자 끝 없음") }
                    let c = s[i]; i += 1
                    if c == "\"" { break }
                    if c == "\\" {
                        let e = s[i]; i += 1
                        switch e {
                        case "\"": out.append("\""); case "\\": out.append("\\"); case "/": out.append("/")
                        case "b": out.append("\u{08}"); case "f": out.append("\u{0C}"); case "n": out.append("\n")
                        case "r": out.append("\r"); case "t": out.append("\t")
                        case "u":
                            var code = try hex4()
                            if (0xD800..<0xDC00).contains(code), i + 1 < s.count, s[i] == "\\", s[i + 1] == "u" {
                                i += 2
                                let low = try hex4()
                                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            }
                            out.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                        default: throw ParseError(description: "모르는 이스케이프")
                        }
                    } else {
                        out.append(c)
                    }
                }
                return .string(String(out))
            case "t": i += 4; return .bool(true)
            case "f": i += 5; return .bool(false)
            case "n": i += 4; return .null
            default:
                let start = i
                while i < s.count, "+-0123456789.eE".unicodeScalars.contains(s[i]) { i += 1 }
                guard i > start else { throw ParseError(description: "모르는 값") }
                var t = String.UnicodeScalarView(); t.append(contentsOf: s[start..<i])
                return .number(String(t))
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= s.count else { throw ParseError(description: "\\u 짧음") }
            var t = String.UnicodeScalarView(); t.append(contentsOf: s[i..<(i + 4)]); i += 4
            guard let v = UInt32(String(t), radix: 16) else { throw ParseError(description: "\\u 16진") }
            return v
        }
    }

    // ---- 쓰기(키 순서 그대로, 숫자 글자 그대로) ----

    var text: String {
        switch self {
        case .object(let m): return "{" + m.map { WireJSON.quote($0.0) + ":" + $0.1.text }.joined(separator: ",") + "}"
        case .array(let a): return "[" + a.map(\.text).joined(separator: ",") + "]"
        case .string(let s): return WireJSON.quote(s)
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    /// 정규 골든 값으로(요청 본문 비교용): 정수 글자 → 숫자, 그 밖 숫자 → {"$num": 글자}.
    var golden: GoldenJSON {
        switch self {
        case .object(let m):
            var o: [String: GoldenJSON] = [:]
            for (k, v) in m { o[k] = v.golden }
            return .object(o)
        case .array(let a): return .array(a.map(\.golden))
        case .string(let s): return .string(s)
        case .number(let n):
            if n.range(of: #"^-?(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil, let v = Int(n),
               abs(v) <= GoldenJSON.maxSafeInteger {
                return .int(v)
            }
            return .object(["$num": .string(n)])
        case .bool(let b): return .bool(b)
        case .null: return .null
        }
    }
}

/// 두 덤프의 다른 점(`[[경로, 새 값], …]`) — Kotlin `GoldenDumpDiff` 와 같은 규칙.
enum GoldenWireDiff {
    static let absent: GoldenJSON = .string("$absent")

    static func diff(_ old: GoldenJSON, _ new: GoldenJSON) throws -> GoldenJSON {
        var out: [GoldenJSON] = []
        try walk(old, new, "$", &out)
        return .array(out)
    }

    private static func walk(_ old: GoldenJSON, _ new: GoldenJSON, _ path: String, _ out: inout [GoldenJSON]) throws {
        if case .object(let a) = old, case .object(let b) = new {
            let keys = Set(a.keys).union(b.keys).sorted { GoldenJSON.keyPrecedes($0, $1) }
            for k in keys {
                switch (a[k], b[k]) {
                case (nil, let v?): out.append(.array([.string("\(path).\(k)"), v]))
                case (_?, nil): out.append(.array([.string("\(path).\(k)"), absent]))
                case let (x?, y?): try walk(x, y, "\(path).\(k)", &out)
                default: break
                }
            }
            return
        }
        if case .array(let a) = old, case .array(let b) = new, a.count == b.count {
            for i in a.indices { try walk(a[i], b[i], "\(path)[\(i)]", &out) }
            return
        }
        if try old.canonicalText() != new.canonicalText() { out.append(.array([.string(path), new])) }
    }
}

/// G6 변형 하나를 나무에 가한다(경로는 `$.a[0].b` 꼴 — Kotlin `WireVariant` 와 같은 문법).
enum WireVariant {
    struct Step { let key: String?; let index: Int? }

    static func steps(_ path: String) -> [Step] {
        var out: [Step] = []
        var rest = Substring(path.dropFirst()) // "$"
        while !rest.isEmpty {
            if rest.first == "." {
                rest = rest.dropFirst()
                let end = rest.firstIndex { $0 == "." || $0 == "[" } ?? rest.endIndex
                out.append(Step(key: String(rest[..<end]), index: nil))
                rest = rest[end...]
            } else if rest.first == "[" {
                let close = rest.firstIndex(of: "]")!
                out.append(Step(key: nil, index: Int(rest[rest.index(after: rest.startIndex)..<close])!))
                rest = rest[rest.index(after: close)...]
            } else {
                fatalError("경로 문법: \(path)")
            }
        }
        return out
    }

    /// op: remove · null · str · num · enum · bool · float0 · float5 · big · int · empty
    static func apply(_ root: WireJSON, path: String, op: String) -> WireJSON {
        func go(_ v: WireJSON, _ steps: ArraySlice<Step>) -> WireJSON {
            guard let step = steps.first else { return replacement(v, op) }
            switch v {
            case .object(var m):
                guard let key = step.key, let idx = m.firstIndex(where: { $0.0 == key }) else { return v }
                if steps.count == 1, op == "remove" { m.remove(at: idx); return .object(m) }
                m[idx].1 = go(m[idx].1, steps.dropFirst())
                return .object(m)
            case .array(var a):
                guard let i = step.index, a.indices.contains(i) else { return v }
                if steps.count == 1, op == "remove" { a.remove(at: i); return .array(a) }
                a[i] = go(a[i], steps.dropFirst())
                return .array(a)
            default:
                return v
            }
        }
        return go(root, steps(path)[...])
    }

    static func replacement(_ v: WireJSON, _ op: String) -> WireJSON {
        switch op {
        case "null": return .null
        case "str": return .string("3")
        case "num": return .number("3")
        case "enum": return .string("zz_unknown_value")
        case "bool": return .bool(true)
        case "empty": return .array([])
        case "big": return .number("4294967296")
        case "int": return .number("3")
        case "float0", "float5":
            guard case .number(let n) = v else { return v }
            return .number(n + (op == "float0" ? ".0" : ".5"))
        default: return v
        }
    }

    /// 값 모양별 변형 목록. 배열은 첫 원소 안만 들어간다(같은 타입 원소의 변형은 같은 결과라 크기를 아낀다).
    static func plan(_ root: WireJSON) -> [(String, String)] {
        var out: [(String, String)] = []
        func ops(for v: WireJSON) -> [String] {
            switch v {
            case .number(let n):
                let isInt = n.range(of: #"^-?(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil
                return isInt ? ["null", "str", "float0", "float5", "big"] : ["null", "str", "int"]
            case .string: return ["null", "num", "enum"]
            case .bool: return ["null", "str", "num"]
            case .object: return ["null", "str"]
            case .array: return ["null", "str", "empty"]
            case .null: return ["str", "num"]
            }
        }
        func walk(_ v: WireJSON, _ path: String) {
            switch v {
            case .object(let m):
                for (k, child) in m {
                    let p = "\(path).\(k)"
                    out.append((p, "remove"))
                    for op in ops(for: child) { out.append((p, op)) }
                    walk(child, p)
                }
            case .array(let a):
                guard let first = a.first else { return }
                let p = "\(path)[0]"
                for op in ops(for: first) { out.append((p, op)) }
                walk(first, p)
            default:
                break
            }
        }
        walk(root, "$")
        return out
    }

    /// 같은 타입 · 같은 정규 경로(첨자 → [*]) · 같은 변형은 한 번만(먼저 나온 픽스처가 대표).
    static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: #"\[[0-9]+\]"#, with: "[*]", options: .regularExpression)
    }
}

/// 요청 녹음(골든 G5): 자리표시로 바꿀 값.
enum WireGoldenValues {
    static let anonKey = "golden-anon-key"
    static let accessToken = "golden-access-token"
    static let userID = "aa000000-0000-4000-8000-0000000000a1"
    static let peerID = "bb000000-0000-4000-8000-0000000000b2"
    static let matchID = "cc000000-0000-4000-8000-0000000000c3"
    static let requestID = UUID(uuidString: "DD000000-0000-4000-8000-0000000000D4")!
    /// 2026-09-17 14:05:00 KST(K2 FakeClock 기준과 같은 순간) = 05:05:00Z.
    static let now = Date(timeIntervalSince1970: 1_789_621_500)
}

/// 저장소 뿌리(이 파일 기준) — 맥 타깃의 `GoldenRepo` 와 같은 일(시험 타깃끼리는 파일을 나눌 수 없다).
enum WireRepo {
    static let root: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir.deleteLastPathComponent()
        }
        fatalError("Package.swift 를 못 찾았다")
    }()

    static func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
}

/// 골든 파일에 JWT 모양 글자(`eyJ` + 20자 이상)를 싣지 않는다 — 공개 저장소 비밀 검사(푸시 전 grep)가 막는다. 데모 픽스처의
/// 가짜 토큰(alg none)도 같다. 그런 글자는 `<jwt:길이>` 로 바꾼다(Kotlin `GoldenScrub` 과 같은 규칙 — 양쪽이 같은 값을 바꿔 견준다).
enum WireScrub {
    static let pattern = try! NSRegularExpression(pattern: "eyJ[A-Za-z0-9_-]{20,}")

    static func text(_ s: String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += "<jwt:\(m.range.length)>"
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    static func json(_ v: GoldenJSON) -> GoldenJSON {
        switch v {
        case .string(let t): return .string(text(t))
        case .array(let a): return .array(a.map(json))
        case .object(let o): return .object(o.mapValues(json))
        default: return v
        }
    }
}

/// 요청 골든(G5)의 바늘 시계 — 한 case 안에서 시각을 옮겨 상점 번호 깃발의 5분 만료(C§4 #9)를 잰다.
final class WireClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func set(secondsAfterStart seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = WireGoldenValues.now.addingTimeInterval(seconds)
    }
}

/// 동시에 떠나는 요청(팀 상태 네 GET)의 응답 고르기: 경로가 같고, `query` 가 있으면 디코드한 쿼리 쌍에 그 쌍이 있어야 한다.
/// 처음 맞는 길의 응답을 쓰고, 맞는 길이 없으면 200 `{}`.
struct WireRoute {
    let path: String
    var query: (String, String)? = nil
    let response: MobileStubResponse

    func matches(_ request: MobileStubRequest) -> Bool {
        guard request.path == path else { return false }
        guard let (name, value) = query else { return true }
        let items = URLComponents(string: "https://x/?\(request.query)")?.queryItems ?? []
        return items.contains { $0.name == name && $0.value == value }
    }

    var golden: GoldenJSON {
        .object([
            "path": .string(path),
            "query": query.map { .array([.string($0.0), .string($0.1)]) } ?? .null,
            "status": .int(response.status),
            "body": .string(String(decoding: response.body, as: UTF8.self)),
        ])
    }
}

/// 서비스 반환값(결과) 덤프 — G5 가 요청만 보고 버리던 서비스 후처리(행 → 표시 변환)를 Kotlin 이 대조한다.
///  · 성공: {"ok": GoldenMirror 덤프}(Void 는 "$void"). 글자 잎의 호스트 · 캐시 무력화 꼬리 · 토큰은 요청과 같은 자리표시로.
///  · 실패: {"throws": SupabaseWorkServiceError 덤프 | "$decoding"(DecodingError) | {"$type": 타입 이름, "$dump": 덤프}}.
enum WireResult {
    static func ok(_ value: Any?, host: String) throws -> GoldenJSON {
        guard let value else { return .object(["ok": .null]) }
        if value is Void { return .object(["ok": .string("$void")]) }
        return .object(["ok": scrub(try GoldenMirror.dump(value), host: host)])
    }

    static func thrown(_ error: Error) -> GoldenJSON {
        if let service = error as? SupabaseWorkServiceError, let dumped = try? GoldenMirror.dump(service) {
            return .object(["throws": dumped])
        }
        if error is DecodingError { return .object(["throws": .string("$decoding")]) }
        if let dumped = try? GoldenMirror.dump(error) {
            return .object(["throws": .object(["$type": .string(String(describing: type(of: error))), "$dump": dumped])])
        }
        return .object(["throws": .object(["$type": .string(String(describing: type(of: error)))])])
    }

    static func scrub(_ v: GoldenJSON, host: String) -> GoldenJSON {
        switch v {
        case .string(let t): return .string(WireScrub.text(WireRequestRecorder.scrub(t, host: host)))
        case .array(let a): return .array(a.map { scrub($0, host: host) })
        case .object(let o): return .object(o.mapValues { scrub($0, host: host) })
        default: return v
        }
    }
}
