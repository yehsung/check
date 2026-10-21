import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W0-b 실험 표(GoldenRoot.probe — multiplatform/testkit/src/desktopTest/resources/golden/w0b-probe/*.json).
// 계약 골든이 아니라 **런타임·기기 차이를 재는 탐침의 Swift 쪽 기준값**이다. 같은 K1 형식이라 비교/쓰기 모드·영수증이 같다.
//   · pow3 · gravity   C-X1: Darwin pow 비트. JVM 몫은 testkit `W0bProbeJvmTest`, ART 몫은 W0-f ③ 이 이 표로 잰다.
//   · decoder          C-X3: JSONDecoder(+convertFromSnakeCase) 가 정수 칸의 3.0 · "3" · 2^63 … 을 어떻게 다루는가, 키 변환 표.
//   · mirror-dump      C-X10: 연관값 열거 · 겹친 Optional · 사전 · Set … 의 정규 덤프(규칙: contract/README.md G6).
//   · text-scalars · graphemes · nfc   C-X4 · C-X13: 스칼라 분류(구간 압축) · 그래핌 경계 · NFC. W0-f ③(ART API 26·36)이 대조한다.
//   · kst              C-X12: Asia/Seoul 달력 성분 · dayKey · 월요일 0시. W0-f ③(API 26)이 대조한다.
// 글자는 언제나 **코드포인트 16진 목록**("1100 1161 11a8")으로 싣는다 — 파일을 여는 도구가 NFC 로 바꿔도 값이 안 변한다.

@Suite("GoldenExport _base — W0-b 실험 표(C-X1 · C-X3 · C-X4 · C-X10 · C-X12 · C-X13)")
struct GoldenExportProbeW0b {
    static func cps(_ scalars: some Sequence<Unicode.Scalar>) -> String {
        scalars.map { String($0.value, radix: 16) }.map { String(repeating: "0", count: max(0, 4 - $0.count)) + $0 }
            .joined(separator: " ")
    }

    static func string(fromCodePoints values: [UInt32]) -> String {
        var view = String.UnicodeScalarView()
        for value in values { view.append(Unicode.Scalar(value)!) }
        return String(view)
    }

    static func base36(_ value: Int) -> String { String(value, radix: 36) }
    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
    static func hex4(_ value: Int) -> String {
        let text = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 4 - text.count)) + text
    }

    // MARK: C-X1 pow

    static let powSeed: UInt64 = 0x5EED_0000_0000_0003
    static let powTotal = 1_000_000
    static let powChunk = 100_000

    @Test("w0b-probe/pow3 — x = unit() 100만 개의 Darwin pow(x, 3) 를 (x*x)*x 와의 ulp 차로 싣는다(+ 끝값)")
    func pow3() {
        var rng = MiniGameRandom(seed: Self.powSeed)
        var cases: [GoldenJSON] = []
        var totalPlus = 0, totalMinus = 0, totalOther = 0
        for chunk in 0..<(Self.powTotal / Self.powChunk) {
            var tokens = ""
            var gap = 0
            var plus = 0, minus = 0, other = 0
            var powHash = GoldenFNV1a64(), refHash = GoldenFNV1a64(), xHash = GoldenFNV1a64()
            for _ in 0..<Self.powChunk {
                let x = rng.unit()
                let p = pow(x, 3)
                let m = x * x * x
                xHash.add(x.bitPattern); powHash.add(p.bitPattern); refHash.add(m.bitPattern)
                let delta = Int64(bitPattern: p.bitPattern) - Int64(bitPattern: m.bitPattern)
                if delta == 0 { gap += 1; continue }
                tokens += Self.base36(gap)
                switch delta {
                case 1: tokens += "+"; plus += 1
                case -1: tokens += "-"; minus += 1
                default: tokens += "=\(delta);"; other += 1
                }
                gap = 0
            }
            totalPlus += plus; totalMinus += minus; totalOther += other
            cases.append([
                "id": .string("chunk-" + Self.pad(chunk, 2)),
                "start": .int(chunk * Self.powChunk),
                "count": .int(Self.powChunk),
                "deltas": .string(tokens),
                "plus": .int(plus), "minus": .int(minus), "other": .int(other),
                "xDigest": .hex64(xHash.value),
                "refDigest": .hex64(refHash.value),
                "powDigest": .hex64(powHash.value),
            ])
        }
        // 끝값: 0 · 가장 작은 비정규 · 가장 작은 정규 · 세제곱이 비정규로 떨어지는 값 · 1 바로 아래 · 1 · 플래피 진행률 꼴(1 - p).
        let edges: [Double] = [0, 5e-324, 2.2250738585072014e-308, 1e-200, 1e-103, 3e-104, 1e-5, 0.1, 0.25, 0.3, 1.0 / 3.0,
                               0.5, 0.7, 0.9, 0.99, 1.0 - 0x1p-53, 1.0, 1 - 0.125, 1 - 0.6, 1 - 0.875]
        cases.append([
            "id": "edges",
            "xBits": .array(edges.map(GoldenJSON.bits)),
            "powBits": .array(edges.map { .bits(pow($0, 3)) }),
            "refBits": .array(edges.map { .bits($0 * $0 * $0) }),
        ])
        print("[C-X1] Darwin pow(x,3) vs (x*x)*x over \(Self.powTotal): +1ulp=\(totalPlus) -1ulp=\(totalMinus) other=\(totalOther) "
              + "same=\(Self.powTotal - totalPlus - totalMinus - totalOther)")
        goldenEmit(GoldenFile(
            golden: "w0b-probe/pow3",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/MiniGameEngine.swift", "Sources/CheckCore/FlappyGame.swift"],
            platformSensitive: true,
            spec: [
                "experiment": "C-X1 — Darwin pow(x, 3) 비트를 JVM Math.pow · StrictMath.pow · (x*x)*x · ART 와 대조한다(플래피 1 - pow(1 - p, 3), FlappyGame.swift:64)",
                "x": "SplitMix64(seed) 의 unit() 을 차례로 \(Self.powTotal)개(rng/splitmix64 와 같은 생성기). chunk 는 그 열을 \(Self.powChunk)개씩 자른 것",
                "seed": .hex64(Self.powSeed),
                "reference": "ref = (x * x) * x — IEEE 곱셈 두 번(어느 플랫폼이든 같은 비트)",
                "deltas": "Darwin pow(x, 3) 비트 = ref 비트 + δ. δ ≠ 0 인 x 만 적는다: 앞 δ≠0 뒤로 건너뛴 개수(36진, 소문자) + 기호. '+' = +1ulp, '-' = −1ulp, '=<부호 있는 십진>;' = 그 밖. 마지막 δ≠0 뒤의 0 들은 적지 않는다",
                "digests": "FNV-1a 64(GoldenFNV1a64 — 64비트 값을 작은 끝부터 8바이트로 접는다) — xDigest = x 비트, refDigest = ref 비트, powDigest = Darwin pow 비트를 chunk 안 순서대로 접은 값. 읽는 쪽은 ref + δ 로 되살린 값을 접어 powDigest 와 같은지 먼저 본다",
                "darwin": "Foundation pow(Double, Double) — macOS libm",
            ],
            cases: cases,
            root: .probe
        ))
    }

    @Test("w0b-probe/gravity — 테트리스 중력 20단계: 밑 · 지수 · pow 비트(= TetrisGame.gravitySeconds)")
    func gravity() {
        var cases: [GoldenJSON] = []
        for stage in 1...20 {
            let e = Double(stage)
            let base = 0.8 - 0.007 * (e - 1)
            let exponent = e - 1
            let value = pow(base, exponent)
            #expect(value.bitPattern == TetrisGame.gravitySeconds(forStage: stage).bitPattern,
                    "단계 \(stage): 엔진 중력이 이 표의 식(pow(0.8 - 0.007(E-1), E-1))과 다르다 — 표를 다시 맞춰라")
            cases.append([
                "id": .string("stage-\(stage)"),
                "stage": .int(stage),
                "baseBits": .bits(base),
                "exponentBits": .bits(exponent),
                "powBits": .bits(value),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "w0b-probe/gravity",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/TetrisGame.swift"],
            platformSensitive: true,
            spec: [
                "experiment": "C-X1 — 테트리스 중력 pow 를 플랫폼마다 다시 계산해 Darwin 비트와 대조(W1-a 는 런타임 pow 대신 이 비트를 상수 표로 쓴다, C§5.3)",
                "formula": "base = 0.8 - 0.007 * (E - 1); exponent = E - 1; seconds = pow(base, exponent) — TetrisGame.gravitySeconds(forStage:)",
            ],
            cases: cases,
            root: .probe
        ))
    }

    // MARK: C-X3 디코더

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct Holder<T: Decodable>: Decodable { let value: T }
    private struct OptionalHolder<T: Decodable>: Decodable { let value: T? }
    private struct KeyEcho: Decodable {
        let keys: [String]
        init(from decoder: Decoder) throws {
            keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue).sorted()
        }
    }
    private struct DictionaryHolder: Decodable { let shardCosts: [String: Int] }
    private struct NestedDictionaryHolder: Decodable { let outerMap: [String: [String: Int]] }
    private struct KeyWriter: Encodable {
        let names: [String]
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AnyKey.self)
            for (index, name) in names.enumerated() { try container.encode(index, forKey: AnyKey(stringValue: name)) }
        }
    }

    private static func serviceDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase   // SupabaseWorkService.swift:89 와 같다
        return decoder
    }

    private static func errorKind(_ error: Error) -> String {
        switch error {
        case DecodingError.typeMismatch: return "error:typeMismatch"
        case DecodingError.valueNotFound: return "error:valueNotFound"
        case DecodingError.keyNotFound: return "error:keyNotFound"
        case DecodingError.dataCorrupted: return "error:dataCorrupted"
        default: return "error:other"
        }
    }

    private static func decodeResult<T: Decodable>(_ type: T.Type, json: String, render: (T) -> String) -> String {
        do {
            return "ok:" + render(try serviceDecoder().decode(Holder<T>.self, from: Data(json.utf8)).value)
        } catch {
            return errorKind(error)
        }
    }

    private static func decodeOptional(json: String) -> String {
        do {
            let value = try serviceDecoder().decode(OptionalHolder<Int>.self, from: Data(json.utf8)).value
            return value.map { "ok:\($0)" } ?? "ok:nil"
        } catch {
            return errorKind(error)
        }
    }

    static let decoderInputs: [(String, String?)] = [
        ("int", "3"), ("int-negative", "-3"), ("zero", "0"), ("float-integral", "3.0"), ("float-fraction", "3.5"),
        ("negative-zero", "-0.0"), ("exponent", "1e2"), ("exponent-upper", "1E2"), ("exponent-fraction", "1.0e2"),
        ("string-int", "\"3\""), ("string-float", "\"3.0\""), ("string-text", "\"abc\""), ("true", "true"), ("false", "false"),
        ("null", "null"), ("two53-plus-one", "9007199254740993"), ("int64-max", "9223372036854775807"),
        ("two63", "9223372036854775808"), ("int64-min", "-9223372036854775808"), ("int64-min-minus-one", "-9223372036854775809"),
        ("uint64-max", "18446744073709551615"), ("two64", "18446744073709551616"), ("float-1e19", "1e19"),
        ("double-max", "1.7976931348623157e308"), ("overflow-1e400", "1e400"), ("array", "[]"), ("object", "{}"),
        ("missing", nil),
    ]

    @Test("w0b-probe/decoder — 정수·실수·불·글자 칸 × 입력 28가지, 키 변환(디코드 · 인코드 · 사전 키)")
    func decoder() throws {
        var cases: [GoldenJSON] = []
        for (id, raw) in Self.decoderInputs {
            let json = raw.map { "{\"value\": \($0)}" } ?? "{}"
            let results: [String: GoldenJSON] = [
                "Int": .string(Self.decodeResult(Int.self, json: json) { String($0) }),
                "Int32": .string(Self.decodeResult(Int32.self, json: json) { String($0) }),
                "Int64": .string(Self.decodeResult(Int64.self, json: json) { String($0) }),
                "UInt64": .string(Self.decodeResult(UInt64.self, json: json) { String($0) }),
                "Double": .string(Self.decodeResult(Double.self, json: json) { GoldenBits.bits($0) }),
                "Bool": .string(Self.decodeResult(Bool.self, json: json) { String($0) }),
                "String": .string(Self.decodeResult(String.self, json: json) { $0 }),
                "OptionalInt": .string(Self.decodeOptional(json: json)),
            ]
            cases.append(["id": .string("value-\(id)"), "json": .string(json), "results": .object(results)])
        }
        // 키 디코드: convertFromSnakeCase 뒤 Swift 가 보는 키 이름.
        let wireKeys = ["user_id", "userID", "user_i_d", "_user_id", "user_id_", "__a__b__", "a__b", "p_protocol", "url_2x",
                        "x2_y", "id", "ID", "USER_ID", "user-id", "a_b_c", "shard_costs", "gold_aing", "character_id",
                        "claimed_at_ms", "p_since_ms", "café_name", "_", "__"]
        var decoded: [String: GoldenJSON] = [:]
        for key in wireKeys {
            let json = "{\"\(key)\": 1}"
            let echoed = try Self.serviceDecoder().decode(KeyEcho.self, from: Data(json.utf8)).keys
            decoded[Self.cps(key.unicodeScalars)] = .string(echoed.first.map { Self.cps($0.unicodeScalars) } ?? "")
        }
        cases.append(["id": "keys-decoded", "note": "키·값 모두 코드포인트 16진 목록(전선 키 → convertFromSnakeCase 뒤 키)",
                      "map": .object(decoded)])
        // 사전 키: [String: T] 의 키는 변환을 타는가(C§4 #37 · Gacha.swift:61-62).
        let dict = try Self.serviceDecoder().decode(DictionaryHolder.self,
                                                    from: Data(#"{"shard_costs": {"gold_aing": 20, "rainbow_aing": 40, "robot": 4}}"#.utf8))
        let nested = try Self.serviceDecoder().decode(NestedDictionaryHolder.self,
                                                      from: Data(#"{"outer_map": {"inner_key": {"deep_key": 1}}}"#.utf8))
        cases.append([
            "id": "keys-dictionary",
            "json": #"{"shard_costs": {"gold_aing": 20, "rainbow_aing": 40, "robot": 4}}"#,
            "dictionaryKeys": .array(dict.shardCosts.keys.sorted(by: GoldenJSON.keyPrecedes).map(GoldenJSON.string)),
            "nestedJson": #"{"outer_map": {"inner_key": {"deep_key": 1}}}"#,
            "nestedKeys": .array(nested.outerMap.flatMap { outer in outer.value.keys.map { "\(outer.key)/\($0)" } }
                .sorted(by: GoldenJSON.keyPrecedes).map(GoldenJSON.string)),
        ])
        // 키 인코드: convertToSnakeCase(SupabaseWorkService.swift:87) 가 프로퍼티 이름을 어떤 전선 키로 바꾸는가.
        let names = ["userID", "pProtocol", "characterID", "url2x", "sinceMs", "pSinceMs", "requestID", "a", "aB", "HTTPStatus",
                     "myURLValue", "x2Y", "isOK", "p_already", "_private", "trailing_", "pFCMToken", "appBuild", "iOSVersion"]
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        var encoded: [String: GoldenJSON] = [:]
        for name in names {
            let data = try encoder.encode(KeyWriter(names: [name]))
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            encoded[name] = .string(object.keys.first ?? "")
        }
        cases.append(["id": "keys-encoded", "note": "프로퍼티 이름 → convertToSnakeCase 뒤 전선 키", "map": .object(encoded)])
        goldenEmit(GoldenFile(
            golden: "w0b-probe/decoder",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkService.swift"],
            spec: [
                "experiment": "C-X3 — Swift JSONDecoder(keyDecodingStrategy = .convertFromSnakeCase, SupabaseWorkService.swift:89) 의 숫자·키 처리. Kotlin lossy 직렬화기(W1-d)가 이 표와 같게 맞춘다(C§2.6)",
                "results": "칸 타입별 'ok:<값>' 또는 'error:<DecodingError 갈래>'. Double 값은 비트 16진. OptionalInt 는 합성 decodeIfPresent(Int?) 결과(ok:nil = 키 없음·null)",
            ],
            cases: cases,
            root: .probe
        ))
    }

    // MARK: C-X10 Mirror 덤프

    struct DumpSample {
        var tags: Set<String>
        var byNumber: [Int: String]
        var big: UInt64
        var small: Int64
        var ratio: Float
        var blob: Data
        var token: UUID
        var link: URL
        var initial: Character
        var maybe: [Int?]
        var nested: Int??
    }

    class DumpBase { let baseValue = 1; init() {} }
    final class DumpDerived: DumpBase { let derivedValue = "d"; override init() { super.init() } }

    static func mirrorSamples() -> [(String, Any)] {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000.25)
        let t1 = Date(timeIntervalSince1970: 1_790_000_030.5)
        let backoff = Backoff(attempt: 2, retryAt: t1, failingSince: t0)
        return [
            ("tetris-rpc-status", TetrisRPCStatus.notSignedIn),
            ("tetris-rpc-status-unknown", TetrisRPCStatus.unknown),
            ("gacha-pull-status-ok", GachaPullStatus.ok),
            ("gacha-pull-status-unknown", GachaPullStatus.unknown("weird_status")),
            ("realtime-idle", RealtimeState.idle(.disabled)),
            ("realtime-connecting", RealtimeState.connecting(attempt: 3, since: t0)),
            ("realtime-subscribed", RealtimeState.subscribed(since: t0, lastHeardAt: t1)),
            ("realtime-failed", RealtimeState.failed(backoff, .topicDenied)),
            ("transport-closed-nil", RealtimeTransportEvent.closed(code: nil)),
            ("transport-closed-1006", RealtimeTransportEvent.closed(code: 1006)),
            ("transport-join-rejected", RealtimeTransportEvent.joinRejected(.unknown("x"))),
            ("tetris-phase-line-clear", TetrisGame.Phase.lineClear(remaining: 0.25)),
            ("gacha-info", GachaInfo(price: 50, shards: nil,
                                     odds: [GachaOddsEntry(characterID: "aing_gold", percent: 3.0),
                                            GachaOddsEntry(characterID: "robot", percent: 97.0)],
                                     shardCosts: ["aing_gold": 20, "robot": 4])),
            ("gacha-info-empty", GachaInfo()),
            ("optional-some-nil", Optional<Optional<Int>>.some(nil) as Any),
            ("optional-some-some", Optional<Optional<Int>>.some(.some(5)) as Any),
            ("optional-none", Optional<Optional<Int>>.none as Any),
            ("sample-struct", DumpSample(tags: ["b", "a", "가"], byNumber: [10: "ten", 2: "two"], big: .max, small: .min,
                                          ratio: 0.1, blob: Data([0, 1, 2, 250]),
                                          token: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
                                          link: URL(string: "https://aingcheck.invalid/a?b=1")!, initial: "한",
                                          maybe: [1, nil, 3], nested: .some(nil))),
            ("class-derived", DumpDerived()),
        ]
    }

    @Test("w0b-probe/mirror-dump — 실제 타입 열 개 남짓 + 합성 표본의 정규 덤프(규칙 G6)")
    func mirrorDump() throws {
        var cases: [GoldenJSON] = []
        for (id, value) in Self.mirrorSamples() {
            let typeName = String(describing: type(of: value))
            cases.append(["id": .string(id), "type": .string(typeName), "dump": try GoldenMirror.dump(value)])
        }
        // 규칙 확인(대조): 겹친 Optional 의 .some(nil) 과 nil 은 같은 null 로 접힌다 — Kotlin 에 겹친 널이 없어서다.
        #expect(try GoldenMirror.dump(Optional<Optional<Int>>.some(nil) as Any) == .null)
        #expect(try GoldenMirror.dump(Optional<Optional<Int>>.some(.some(5)) as Any) == .int(5))
        // 연관값 하나는 이름표를 버린다 / 둘 이상은 객체 / 이름표 없는 둘 이상은 배열.
        #expect(try GoldenMirror.dump(RealtimeTransportEvent.closed(code: 1006))
                == .object(["$case": "closed", "$value": .int(1006)]))
        goldenEmit(GoldenFile(
            golden: "w0b-probe/mirror-dump",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RealtimeLink.swift", "Sources/CheckCore/Gacha.swift",
                           "Sources/CheckCore/TetrisWire.swift", "Sources/CheckCore/TetrisGame.swift"],
            spec: [
                "experiment": "C-X10 — Swift Mirror 정규 덤프(GoldenMirror)가 연관값 열거 · 겹친 Optional · 사전 · Set · 상속 클래스를 Kotlin 리플렉션과 같은 모양으로 내는가. 규칙 정본: contract/README.md 「디코드 덤프 규칙(G6)」",
                "type": "String(describing: type(of:)) — 참고용(대조 키 아님)",
            ],
            cases: cases,
            root: .probe
        ))
    }

    // MARK: C-X4 · C-X13 글자

    static func generalCategoryCode(_ category: Unicode.GeneralCategory) -> String {
        switch category {
        case .uppercaseLetter: return "Lu"
        case .lowercaseLetter: return "Ll"
        case .titlecaseLetter: return "Lt"
        case .modifierLetter: return "Lm"
        case .otherLetter: return "Lo"
        case .nonspacingMark: return "Mn"
        case .spacingMark: return "Mc"
        case .enclosingMark: return "Me"
        case .decimalNumber: return "Nd"
        case .letterNumber: return "Nl"
        case .otherNumber: return "No"
        case .connectorPunctuation: return "Pc"
        case .dashPunctuation: return "Pd"
        case .openPunctuation: return "Ps"
        case .closePunctuation: return "Pe"
        case .initialPunctuation: return "Pi"
        case .finalPunctuation: return "Pf"
        case .otherPunctuation: return "Po"
        case .mathSymbol: return "Sm"
        case .currencySymbol: return "Sc"
        case .modifierSymbol: return "Sk"
        case .otherSymbol: return "So"
        case .spaceSeparator: return "Zs"
        case .lineSeparator: return "Zl"
        case .paragraphSeparator: return "Zp"
        case .control: return "Cc"
        case .format: return "Cf"
        case .surrogate: return "Cs"
        case .privateUse: return "Co"
        case .unassigned: return "Cn"
        @unknown default: return "??"
        }
    }

    @Test("w0b-probe/text-scalars — U+0000~U+10FFFF 구간 압축: 일반 범주 · White_Space · 보이는 글자 · NFC 안정")
    func textScalars() {
        var cases: [GoldenJSON] = []
        var totalRanges = 0
        for plane in 0...16 {
            var tokens: [String] = []
            var runStart = plane << 16
            var runClass = ""
            func flush(_ end: Int) {
                tokens.append(Self.hex4(runStart) + "-" + Self.hex4(end) + ":" + runClass)
            }
            for value in (plane << 16)...((plane << 16) | 0xFFFF) {
                let klass: String
                if let scalar = Unicode.Scalar(UInt32(value)) {
                    let single = String(scalar)
                    let ws = scalar.properties.isWhitespace ? "1" : "0"
                    let visible = MessageBody.hasVisibleContent(single) ? "1" : "0"
                    let nfcStable = Array(single.precomposedStringWithCanonicalMapping.unicodeScalars) == [scalar] ? "1" : "0"
                    klass = Self.generalCategoryCode(scalar.properties.generalCategory) + ws + visible + nfcStable
                } else {
                    klass = "Cs000"   // 서로게이트(스칼라가 아니다 — Swift 글자에 들어올 수 없다)
                }
                if value == plane << 16 {
                    runClass = klass
                } else if klass != runClass {
                    flush(value - 1)
                    runStart = value
                    runClass = klass
                }
            }
            flush((plane << 16) | 0xFFFF)
            totalRanges += tokens.count
            cases.append(["id": .string("plane-\(plane)"), "ranges": .string(tokens.joined(separator: ","))])
        }
        print("[C-X4] text-scalars ranges=\(totalRanges)")
        goldenEmit(GoldenFile(
            golden: "w0b-probe/text-scalars",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/StatusMessage.swift"],
            platformSensitive: true,
            spec: [
                "experiment": "C-X4 — 스칼라 하나짜리 글자의 분류를 Swift 표준 라이브러리·Foundation 판으로 박는다. JVM(JDK 21)·ART(API 26·36) 가 대조한다",
                "ranges": "'시작-끝:분류' 를 쉼표로 잇는다(16진 소문자, 끝 포함). 분류 = 일반 범주 두 글자 + White_Space(0/1) + 보이는 글자(0/1) + NFC 안정(0/1)",
                "generalCategory": "Unicode.Scalar.Properties.generalCategory 의 두 글자 약어(Lu Ll … Cn). 서로게이트 구간은 Cs000",
                "whiteSpace": "Unicode.Scalar.Properties.isWhitespace(유니코드 White_Space)",
                "visible": "MessageBody.hasVisibleContent(그 스칼라 하나) — SupabaseWorkModels.swift(메시지·상태 메시지가 쓰는 판정)",
                "nfcStable": "String(스칼라).precomposedStringWithCanonicalMapping 이 그 스칼라 하나 그대로인가(Foundation NFC — StatusMessage.sanitized 가 쓴다)",
            ],
            cases: cases,
            root: .probe
        ))
    }

    /// 그래핌·NFC 표의 재료(코드포인트). 한글 자모 · 결합 문자 · 이모지 ZWJ · 국기 · 피부색 · 인도계 결합(유니코드 15.1 InCB) ·
    /// 앞붙이(Prepend) · 간격 결합(SpacingMark) · CR LF · 태그 · 키캡 · 이체 선택자.
    static let scalarPool: [UInt32] = [
        0x61, 0x41, 0x31, 0x20, 0x0D, 0x0A, 0x07, 0x00A9, 0x00E9, 0x0065, 0x0301, 0x0308, 0x0327, 0x0323, 0x031B, 0x0345,
        0x1100, 0x1101, 0x1112, 0x1161, 0x1175, 0x11A8, 0x11C2, 0xAC00, 0xAC01, 0xD7A3, 0x3131, 0x314F, 0x3164, 0x115F, 0x1160,
        0x200D, 0x200C, 0xFE0F, 0xFE0E, 0x20E3, 0x1F600, 0x1F468, 0x1F469, 0x1F466, 0x2764, 0x1F3FB, 0x1F3FF, 0x1F1F0, 0x1F1F7,
        0x1F3F4, 0xE0067, 0xE0062, 0xE007F, 0x0600, 0x110BD, 0x0903, 0x0915, 0x094D, 0x0937, 0x093F, 0x0E01, 0x0E33, 0x0E40,
        0x212B, 0x00C5, 0x0041, 0x030A, 0x1E0B, 0x1E0D, 0x0307, 0x0F73, 0x0344, 0x2126, 0x00F4, 0x05D0, 0x05B4,
    ]

    static func randomSequences(count: Int, seed: UInt64, maxLength: Int) -> [[UInt32]] {
        var rng = MiniGameRandom(seed: seed)
        return (0..<count).map { _ in
            let length = 1 + Int(rng.next() % UInt64(maxLength))
            return (0..<length).map { _ in scalarPool[Int(rng.next() % UInt64(scalarPool.count))] }
        }
    }

    static let curatedGraphemes: [[UInt32]] = [
        [0x1100, 0x1161, 0x11A8], [0xAC00, 0x11A8], [0x1100, 0x1100, 0x1161], [0x1161, 0x11A8], [0x3131, 0x314F],
        [0x0065, 0x0301], [0x0065, 0x0301, 0x0323], [0x0061, 0x200D], [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467, 0x200D, 0x1F466],
        [0x1F1F0, 0x1F1F7], [0x1F1F0, 0x1F1F7, 0x1F1F0], [0x1F44D, 0x1F3FB], [0x2764, 0xFE0F], [0x0031, 0xFE0F, 0x20E3],
        [0x1F3F4, 0xE0067, 0xE0062, 0xE0065, 0xE006E, 0xE0067, 0xE007F], [0x0D, 0x0A], [0x0A, 0x0D], [0x0600, 0x0661],
        [0x0915, 0x094D, 0x0937], [0x0915, 0x094D, 0x200D, 0x0937], [0x0915, 0x093F], [0x0E01, 0x0E33], [0x0E40, 0x0E01],
        [0x00A9, 0x200D, 0x1F600], [0x1F600, 0x200D], [0x200D, 0x1F600], [0x3164], [0x115F, 0x1160], [0x0308], [0xFE0F],
        [0x110BD, 0x0061], [0x0903], [0x0061, 0x0903], [0x1F469, 0x1F3FF, 0x200D, 0x1F4BB], [0x0020, 0x0301], [0x07, 0x0301],
    ]

    @Test("w0b-probe/graphemes — 300줄: 코드포인트 → 그래핌 경계(스칼라 수 목록) · count")
    func graphemes() {
        let inputs = Self.curatedGraphemes + Self.randomSequences(count: 300 - Self.curatedGraphemes.count, seed: 0x6A12_0001, maxLength: 8)
        var cases: [GoldenJSON] = []
        for (index, values) in inputs.enumerated() {
            let text = Self.string(fromCodePoints: values)
            let clusters = text.map { $0.unicodeScalars.count }
            cases.append([
                "id": .string("g-" + Self.pad(index, 3)),
                "cps": .string(Self.cps(text.unicodeScalars)),
                "clusters": .array(clusters.map(GoldenJSON.int)),
                "count": .int(text.count),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "w0b-probe/graphemes",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CheckTodoModel.swift"],
            platformSensitive: true,
            spec: [
                "experiment": "C-X4 · C-X13 — Swift String.count(확장 그래핌, 할 일 제목 상한 CheckTodoModel.swift titleFitsLimits)의 경계. JVM·ART BreakIterator 가 대조한다",
                "clusters": "그래핌마다 스칼라 수(앞에서부터). 합 = cps 의 스칼라 수",
            ],
            cases: cases,
            root: .probe
        ))
    }

    static let curatedNFC: [[UInt32]] = [
        [0x1100, 0x1161], [0x1100, 0x1161, 0x11A8], [0xAC00, 0x11A8], [0x1100, 0x1161, 0x11C3], [0x1112, 0x1175, 0x11C2],
        [0x0041, 0x030A], [0x212B], [0x2126], [0x0065, 0x0301], [0x0065, 0x0323, 0x0301], [0x0065, 0x0301, 0x0323],
        [0x1E0B, 0x0323], [0x0064, 0x0307, 0x0323], [0x0F73], [0x0344], [0x0958], [0x2ADC], [0x1D15E], [0xFB2C],
        [0x3131], [0x314F], [0x3164], [0x05D0, 0x05B4], [0x0061, 0x0345, 0x0301], [0x03B1, 0x0345, 0x0301],
    ]

    @Test("w0b-probe/nfc — 300줄: 코드포인트 → NFC(precomposedStringWithCanonicalMapping) 코드포인트")
    func nfc() {
        let inputs = Self.curatedNFC + Self.randomSequences(count: 300 - Self.curatedNFC.count, seed: 0x4EFC_0001, maxLength: 6)
        var cases: [GoldenJSON] = []
        for (index, values) in inputs.enumerated() {
            let text = Self.string(fromCodePoints: values)
            let normalized = text.precomposedStringWithCanonicalMapping
            cases.append([
                "id": .string("n-" + Self.pad(index, 3)),
                "cps": .string(Self.cps(text.unicodeScalars)),
                "nfc": .string(Self.cps(normalized.unicodeScalars)),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "w0b-probe/nfc",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/StatusMessage.swift"],
            platformSensitive: true,
            spec: [
                "experiment": "C-X4 — Foundation NFC(StatusMessage.sanitized ① 이 쓴다)를 java.text.Normalizer(JVM·ART)가 대조한다",
            ],
            cases: cases,
            root: .probe
        ))
    }

    // MARK: C-X12 KST

    @Test("w0b-probe/kst — Asia/Seoul: 1950~2040 표본 · 서머타임 전환 ±1초 · 앱 경계(월 0시 · 9시) → 성분 · dayKey · 월요일 0시")
    func kst() {
        let zone = TimeZone(identifier: "Asia/Seoul")!
        let calendar = WeeklyWorkCalendar.kst
        var instants: [(String, Int)] = []
        // 1) 서머타임 전환(전환 시각 −1 · 0 · +1초). 1987·1988 은 한국 서머타임, 그 앞은 tzdb 이력.
        var cursor = Date(timeIntervalSince1970: -2_208_988_800)   // 1900-01-01
        var transitions = 0
        while let next = zone.nextDaylightSavingTimeTransition(after: cursor), next.timeIntervalSince1970 < 2_208_988_800 {
            let t = Int(next.timeIntervalSince1970)
            for d in [-1, 0, 1] { instants.append(("dst-\(t)\(d >= 0 ? "+" : "")\(d)", t + d)) }
            cursor = next
            transitions += 1
        }
        // 2) 표준시 오프셋 변경(1954 +8:30, 1961 +9:00)을 지나도록 1950~1965 는 7일 간격, 그 뒤 2040 까지 61일 간격.
        var t = -631_152_000   // 1950-01-01T00:00Z
        while t < 2_208_988_800 {
            instants.append(("sample-\(t)", t))
            t += t < -126_230_400 ? 7 * 86_400 : 61 * 86_400   // 1966-01-01 앞까지 촘촘히
        }
        // 3) 앱 경계: 2026-10-19(월) 0시 KST · 9시 KST · 2026-12-31 23:59:59 KST · 2028-02-29 정오 KST.
        for (label, day, hour, minute, second) in [("week-start", "2026-10-19", 0, 0, 0), ("nine", "2026-10-21", 9, 0, 0),
                                                   ("year-end", "2026-12-31", 23, 59, 59), ("leap-day", "2028-02-29", 12, 0, 0)] {
            guard let midnight = WeeklyWorkCalendar.kstMidnight(day) else { continue }
            let base = Int(midnight.timeIntervalSince1970) + hour * 3600 + minute * 60 + second
            for d in [-1, 0, 1] { instants.append(("app-\(label)\(d >= 0 ? "+" : "")\(d)", base + d)) }
        }
        var cases: [GoldenJSON] = []
        for (id, epoch) in instants {
            let date = Date(timeIntervalSince1970: TimeInterval(epoch))
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
            let dayKey = MilestoneTracker.dayKey(date)
            // 그 날이 든 주의 월요일 0시(KST): weekday 1=일 … 7=토 → 월요일까지 뺄 날 수.
            let back = ((c.weekday ?? 2) + 5) % 7
            var mondayEpoch: GoldenJSON = .null
            if let dayStart = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day)),
               let monday = calendar.date(byAdding: .day, value: -back, to: dayStart) {
                let key = Self.pad(calendar.component(.year, from: monday), 4) + "-" + Self.pad(calendar.component(.month, from: monday), 2)
                    + "-" + Self.pad(calendar.component(.day, from: monday), 2)
                if let midnight = WeeklyWorkCalendar.kstMidnight(key) { mondayEpoch = .int(Int(midnight.timeIntervalSince1970)) }
            }
            cases.append([
                "id": .string(id),
                "epoch": .int(epoch),
                "y": .int(c.year ?? 0), "mo": .int(c.month ?? 0), "d": .int(c.day ?? 0),
                "h": .int(c.hour ?? 0), "mi": .int(c.minute ?? 0), "s": .int(c.second ?? 0),
                "weekday": .int(c.weekday ?? 0),
                "offset": .int(zone.secondsFromGMT(for: date)),
                "dayKey": .string(dayKey),
                "mondayEpoch": mondayEpoch,
            ])
        }
        print("[C-X12] kst instants=\(instants.count) dstTransitions=\(transitions)")
        goldenEmit(GoldenFile(
            golden: "w0b-probe/kst",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/MilestoneTracker.swift", "Sources/CheckCore/WeeklyWorkReward.swift"],
            platformSensitive: true,
            spec: [
                "experiment": "C-X12 — Foundation Calendar(gregorian, Asia/Seoul) 와 tzdb 이력. kotlinx-datetime TimeZone.of(\"Asia/Seoul\") 가 JVM·ART(API 26) 에서 같은 성분을 내는가",
                "weekday": "1 = 일요일 … 7 = 토요일(Foundation Calendar)",
                "offset": "TimeZone.secondsFromGMT(for:) — 그 순간의 UTC 오프셋(초)",
                "dayKey": "MilestoneTracker.dayKey(date) — KST yyyyMMdd",
                "mondayEpoch": "그 날이 든 주의 월요일 0시(KST) — WeeklyWorkCalendar.kstMidnight(\"yyyy-MM-dd\")",
            ],
            cases: cases,
            root: .probe
        ))
    }
}
