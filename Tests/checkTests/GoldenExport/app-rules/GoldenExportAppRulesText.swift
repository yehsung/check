// 원본: 없음(W1-c 골든 생성기 · 글자 · 정렬 · 이모티콘 — Sources/CheckCore/{StatusMessage,AingSticker}.swift · SupabaseWorkModels.swift(MessageBody) · Foundation 정렬 를 잰다)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-c 앱 규칙 — 글자 골든(C§5.1 "글자 규칙" · C§4 #29 · G §8-16 글자 결정 ①~③). Kotlin 은 core/rules/…/text 가 대조한다.
//
//   · text/scalar-classes  U+0000~U+10FFFF 구간 압축: 일반 범주 · White_Space · Foundation 공백 집합 둘 · 보이는 글자(MessageBody).
//                          G §8-16 ②: Kotlin 은 `Character.getType` 을 쓰지 않고 **이 표를 번들**한다(JVM·ART 같은 답).
//   · text/nfc             Foundation NFC(precomposedStringWithCanonicalMapping). G §8-16 ①: Kotlin 은 표준(java.text.Normalizer)을
//                          따르고, Foundation 이 표준과 어긋나는 **6줄**을 `knownDivergence` 로 잠근다(늘거나 줄면 빨강).
//   · text/graphemes       Swift String(확장 그래핌) 경계. G §8-16 ③: Kotlin 은 플랫폼 BreakIterator, InCB **2줄**을 `knownDivergence` 로 잠근다.
//   · text/sanitize        MessageBody(sanitized · length · hasVisibleContent · validate) · StatusMessage(sanitized · length · validate ·
//                          display · counterText) — 사용자 입력 → 서버와 같은 눈금.
//   · text/status-message  StatusMessageSaveOutcome(response:) · StatusMessageText(notice · 고정 문구) — 디코드한 응답 세 칸 → 결과 → 문구.
//   · stickers/tokens      아잉이 이모티콘(AingSticker): 토큰 여섯 · 통째 일치 판정(parse) · 글자 자리 미리보기(preview).
//   · sort/natural-ko      이름 정렬(localizedStandardCompare = ko_KR 로캘의 compare(.caseInsensitive·.numeric·.widthInsensitive·
//                          .forcedOrdering)) — C-X5 합성 이름 500개.
// 글자는 언제나 코드포인트 16진 목록("1100 1161 11a8")으로 싣는다 — 파일을 여는 도구가 NFC 로 바꿔도 값이 안 변한다.

@Suite("GoldenExport app-rules — 글자(text · stickers · sort)")
struct GoldenExportAppRulesText {
    // MARK: 공용 도우미

    static func cps(_ scalars: some Sequence<Unicode.Scalar>) -> String {
        scalars.map { hex4(Int($0.value)) }.joined(separator: " ")
    }

    static func cps(_ text: String) -> String { cps(text.unicodeScalars) }

    static func string(_ values: [UInt32]) -> String {
        var view = String.UnicodeScalarView()
        for value in values { view.append(Unicode.Scalar(value)!) }
        return String(view)
    }

    static func hex4(_ value: Int) -> String {
        let text = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 4 - text.count)) + text
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    /// 코퍼스 무작위 열(rng/splitmix64 와 같은 생성기 — Kotlin 이 다시 만들지 않는다. 입력은 골든에 그대로 실린다).
    static func randomSequences(pool: [UInt32], count: Int, seed: UInt64, maxLength: Int) -> [[UInt32]] {
        var rng = MiniGameRandom(seed: seed)
        return (0..<count).map { _ in
            let length = 1 + Int(rng.next() % UInt64(maxLength))
            return (0..<length).map { _ in pool[Int(rng.next() % UInt64(pool.count))] }
        }
    }

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

    // MARK: text/scalar-classes

    @Test("text/scalar-classes — U+0000~U+10FFFF: 일반 범주 · White_Space · whitespacesAndNewlines · whitespaces · 보이는 글자")
    func scalarClasses() {
        var cases: [GoldenJSON] = []
        var totalRanges = 0
        var classes = Set<String>()
        for plane in 0...16 {
            var tokens: [String] = []
            var runStart = plane << 16
            var runClass = ""
            for value in (plane << 16)...((plane << 16) | 0xFFFF) {
                let klass: String
                if let scalar = Unicode.Scalar(UInt32(value)) {
                    let gc = Self.generalCategoryCode(scalar.properties.generalCategory)
                    let ws = scalar.properties.isWhitespace ? "1" : "0"
                    let wsnl = CharacterSet.whitespacesAndNewlines.contains(scalar) ? "1" : "0"
                    let wsOnly = CharacterSet.whitespaces.contains(scalar) ? "1" : "0"
                    let visible = MessageBody.hasVisibleContent(String(scalar)) ? "1" : "0"
                    klass = gc + ws + wsnl + wsOnly + visible
                } else {
                    klass = "Cs0000"   // 서로게이트(스칼라가 아니다 — Swift 글자에 들어올 수 없다)
                }
                if value == plane << 16 {
                    runClass = klass
                } else if klass != runClass {
                    tokens.append(Self.hex4(runStart) + "-" + Self.hex4(value - 1) + ":" + runClass)
                    classes.insert(runClass)
                    runStart = value
                    runClass = klass
                }
            }
            tokens.append(Self.hex4(runStart) + "-" + Self.hex4((plane << 16) | 0xFFFF) + ":" + runClass)
            classes.insert(runClass)
            totalRanges += tokens.count
            cases.append(["id": .string("plane-\(Self.pad(plane, 2))"), "ranges": .string(tokens.joined(separator: ","))])
        }
        print("[W1-c] text/scalar-classes ranges=\(totalRanges) classes=\(classes.count)")
        goldenEmit(GoldenFile(
            golden: "text/scalar-classes",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/StatusMessage.swift",
                           "Sources/CheckCore/CheckTodoModel.swift", "Sources/CheckCore/AingSticker.swift"],
            platformSensitive: false,
            spec: [
                "decision": "G §8-16 ② — 글자 범주·보이는 글자 판정은 Character.getType 을 쓰지 않는다. Kotlin 은 이 표를 압축해 번들(UnicodeScalarTable)하고, 시험이 번들을 풀어 이 표와 구간 하나까지 같은지 본다(JVM·ART 같은 답)",
                "ranges": "'시작-끝:분류' 를 쉼표로 잇는다(16진 소문자, 끝 포함, 평면 안에서 빈틈없이). 분류 = 일반 범주 두 글자 + 네 비트",
                "bits": "① White_Space(Unicode.Scalar.Properties.isWhitespace — 할 일 제목 정규화·보이는 글자) ② CharacterSet.whitespacesAndNewlines(MessageBody.sanitized · 이모티콘 머리 검사 · 여러 trim) ③ CharacterSet.whitespaces(kst_day 같은 짧은 칸 trim) ④ MessageBody.hasVisibleContent(그 스칼라 하나)",
                "surrogate": "D800-DFFF 는 스칼라가 아니라 Cs0000 으로 적는다",
                "platformSensitive": "false — Kotlin 답은 번들 표에서만 나온다(기기 ICU 판과 무관). 계측 시험은 번들이 ART 에서도 같게 풀리는지 덤으로 본다",
            ],
            cases: cases
        ))
    }

    // MARK: text/nfc

    /// W0-b `w0b-probe/nfc` 와 같은 코퍼스(같은 시드·같은 풀) + 앱 실사용 줄(자모 분해 한글 이름 · 이모지 · 이모티콘 토큰).
    static let nfcPool: [UInt32] = [
        0x61, 0x41, 0x31, 0x20, 0x0D, 0x0A, 0x07, 0x00A9, 0x00E9, 0x0065, 0x0301, 0x0308, 0x0327, 0x0323, 0x031B, 0x0345,
        0x1100, 0x1101, 0x1112, 0x1161, 0x1175, 0x11A8, 0x11C2, 0xAC00, 0xAC01, 0xD7A3, 0x3131, 0x314F, 0x3164, 0x115F, 0x1160,
        0x200D, 0x200C, 0xFE0F, 0xFE0E, 0x20E3, 0x1F600, 0x1F468, 0x1F469, 0x1F466, 0x2764, 0x1F3FB, 0x1F3FF, 0x1F1F0, 0x1F1F7,
        0x1F3F4, 0xE0067, 0xE0062, 0xE007F, 0x0600, 0x110BD, 0x0903, 0x0915, 0x094D, 0x0937, 0x093F, 0x0E01, 0x0E33, 0x0E40,
        0x212B, 0x00C5, 0x0041, 0x030A, 0x1E0B, 0x1E0D, 0x0307, 0x0F73, 0x0344, 0x2126, 0x00F4, 0x05D0, 0x05B4,
    ]

    static let nfcCurated: [[UInt32]] = [
        [0x1100, 0x1161], [0x1100, 0x1161, 0x11A8], [0xAC00, 0x11A8], [0x1100, 0x1161, 0x11C3], [0x1112, 0x1175, 0x11C2],
        [0x0041, 0x030A], [0x212B], [0x2126], [0x0065, 0x0301], [0x0065, 0x0323, 0x0301], [0x0065, 0x0301, 0x0323],
        [0x1E0B, 0x0323], [0x0064, 0x0307, 0x0323], [0x0F73], [0x0344], [0x0958], [0x2ADC], [0x1D15E], [0xFB2C],
        [0x3131], [0x314F], [0x3164], [0x05D0, 0x05B4], [0x0061, 0x0345, 0x0301], [0x03B1, 0x0345, 0x0301],
    ]

    /// 앱 실사용 줄: 맥 입력기·파인더가 주는 자모 분해(NFD) 한글 이름·문장 · 이모티콘 토큰(NFD) · 이모지 · 섞인 글.
    static let nfcAppLines: [String] = [
        "아잉이", "한글", "예성의 MacBook", "[아잉:기쁨]", "[아잉:놀람]", "회의 준비 👨‍👩‍👧‍👦", "café", "Ａｂｃ１２３",
        "가나다 abc 123", "😀👍🏻", "🇰🇷", "ㄱㅏ", "뷁", "똠양꿍", "Ǆ", "ﬁ",
    ]

    /// Foundation 이 유니코드 표준(서버 Postgres normalize · java.text.Normalizer)과 어긋나는 줄과 **표준 NFC**.
    /// 값은 표준(UAX #15)대로 손으로 적었다 — 파이썬 unicodedata(15.0) · JDK 21 Normalizer 와 같다(W0-b 실측).
    ///   · 완성형 LV + 종성 자모: 표준은 LVT 로 합친다(ac00 11a8 → ac01) — Foundation 은 그대로 둔다.
    ///   · 옛 종성(11c3, 현대 종성 범위 밖): 표준은 앞 LV 만 합치고 11c3 은 남긴다 — Foundation 은 엉뚱한 음절(ac1c)을 만든다.
    ///   · 결합 등급 재배열: 0f73 의 분해(0f71 0f72, ccc 129·130)가 0345(ccc 240)·030a(ccc 230)보다 앞서야 한다 — Foundation 은 안 바꾼다.
    ///   · 태그 글자 + 결합 점: e0067 은 g 가 아니다 — Foundation 은 0121(ġ)로 합친다.
    static let nfcStandardForDivergent: [String: String] = [
        "ac00 11a8": "ac01",
        "1100 1161 11c3": "ac00 11c3",
        "0007 0007 0345 0f73 1f3fb": "0007 0007 0f71 0f72 0345 1f3fb",
        "030a 0f73 e0062": "0f71 0f72 030a e0062",
        "1f3fb 030a 0f73 1f466 e007f 05d0": "1f3fb 0f71 0f72 030a 1f466 e007f 05d0",
        "00e9 e0067 0307 0020 000a 1f3f4": "00e9 e0067 0307 0020 000a 1f3f4",
    ]

    @Test("text/nfc — W0-b 코퍼스 300줄 + 앱 줄: Foundation NFC 와 표준이 어긋나는 6줄을 knownDivergence 로 잠근다")
    func nfc() {
        let inputs = Self.nfcCurated.map(Self.string)
            + Self.randomSequences(pool: Self.nfcPool, count: 300 - Self.nfcCurated.count, seed: 0x4EFC_0001, maxLength: 6).map(Self.string)
        var cases: [GoldenJSON] = []
        var divergent = 0
        func add(_ id: String, _ text: String) {
            let normalized = text.precomposedStringWithCanonicalMapping
            var item: GoldenJSON = ["id": .string(id), "cps": .string(Self.cps(text)), "nfc": .string(Self.cps(normalized))]
            if let standard = Self.nfcStandardForDivergent[Self.cps(text)] {
                #expect(standard != Self.cps(normalized),
                        "\(id): Foundation 이 이 줄에서 표준과 같아졌다 — knownDivergence 목록을 다시 정한다(G §8-16 ①)")
                if case .object(var members) = item {
                    members["knownDivergence"] = ["standard": .string(standard),
                                                  "note": "Foundation NFC 가 유니코드 표준과 어긋난다 — Kotlin(표준)은 standard 를 낸다"]
                    item = .object(members)
                }
                divergent += 1
            }
            cases.append(item)
        }
        for (index, text) in inputs.enumerated() { add("n-" + Self.pad(index, 3), text) }
        for (index, line) in Self.nfcAppLines.enumerated() {
            add("app-" + Self.pad(index, 2) + "-nfc", line.precomposedStringWithCanonicalMapping)
            add("app-" + Self.pad(index, 2) + "-nfd", line.decomposedStringWithCanonicalMapping)
        }
        #expect(divergent == Self.nfcStandardForDivergent.count,
                "knownDivergence 입력 \(Self.nfcStandardForDivergent.count) 개 중 코퍼스에 든 것이 \(divergent) 개다")
        goldenEmit(GoldenFile(
            golden: "text/nfc",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/StatusMessage.swift", "Sources/CheckCore/SupabaseWorkModels.swift"],
            platformSensitive: true,
            spec: [
                "decision": "G §8-16 ① — NFC 는 유니코드 표준을 따른다(java.text.Normalizer, 서버 Postgres normalize 와 같은 쪽). Foundation 이 표준과 어긋나는 줄은 knownDivergence 로 정확히 잠근다 — 표준 답(standard)이 아닌 값이 나오거나, 목록 밖 줄이 Foundation 과 다르거나, 목록 줄이 Foundation 과 같아지면 빨강",
                "nfc": "Foundation precomposedStringWithCanonicalMapping(MessageBody.sanitized · StatusMessage.sanitized ①)",
                "knownDivergence": "Foundation ≠ 표준인 줄에만 있다: standard = 표준 NFC(UAX #15). 지금 6줄(완성형 LV + 종성 · 옛 종성 · 결합 등급 재배열 3 · 태그 글자 + 결합 점)",
                "corpus": "n-000~n-299 = W0-b w0b-probe/nfc 와 같은 줄(손으로 고른 25 + SplitMix64(0x4efc0001) 무작위 275) · app-* = 앱 실사용 글을 NFC·NFD 두 꼴로",
            ],
            cases: cases
        ))
    }

    // MARK: text/graphemes

    static let graphemeCurated: [[UInt32]] = [
        [0x1100, 0x1161, 0x11A8], [0xAC00, 0x11A8], [0x1100, 0x1100, 0x1161], [0x1161, 0x11A8], [0x3131, 0x314F],
        [0x0065, 0x0301], [0x0065, 0x0301, 0x0323], [0x0061, 0x200D], [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467, 0x200D, 0x1F466],
        [0x1F1F0, 0x1F1F7], [0x1F1F0, 0x1F1F7, 0x1F1F0], [0x1F44D, 0x1F3FB], [0x2764, 0xFE0F], [0x0031, 0xFE0F, 0x20E3],
        [0x1F3F4, 0xE0067, 0xE0062, 0xE0065, 0xE006E, 0xE0067, 0xE007F], [0x0D, 0x0A], [0x0A, 0x0D], [0x0600, 0x0661],
        [0x0915, 0x094D, 0x0937], [0x0915, 0x094D, 0x200D, 0x0937], [0x0915, 0x093F], [0x0E01, 0x0E33], [0x0E40, 0x0E01],
        [0x00A9, 0x200D, 0x1F600], [0x1F600, 0x200D], [0x200D, 0x1F600], [0x3164], [0x115F, 0x1160], [0x0308], [0xFE0F],
        [0x110BD, 0x0061], [0x0903], [0x0061, 0x0903], [0x1F469, 0x1F3FF, 0x200D, 0x1F4BB], [0x0020, 0x0301], [0x07, 0x0301],
    ]

    /// 할 일 제목 · 기기 이름처럼 그래핌으로 세는 앱 글(TodoRules.titleFitsLimits · AILimitDeviceLabelContract).
    static let graphemeAppLines: [String] = [
        "회의 준비", "👨🏽‍👩🏽‍👧🏽‍👦🏽 가족", "예성의 MacBook Pro", "🇰🇷🇯🇵", "1️⃣2️⃣", "é́", "아잉이 [아잉:기쁨]", "\r\n두 줄",
    ]

    /// Swift(유니코드 15.1+ 규칙 GB9c — Indic_Conjunct_Break)와 JDK 21 BreakIterator(15.1 전 규칙)가 갈리는 줄과 **옛 규칙의 경계**.
    /// G §8-16 ③: 플랫폼 BreakIterator 를 쓰고 이 2줄만 knownDivergence 로 잠근다(W0-b 실측: g-018 · g-019).
    static let graphemeLegacyForDivergent: [String: [Int]] = [
        "0915 094d 0937": [2, 1],
        "0915 094d 200d 0937": [3, 1],
    ]

    @Test("text/graphemes — W0-b 코퍼스 300줄 + 앱 줄: 그래핌 경계(스칼라 수) · count, InCB 2줄 knownDivergence")
    func graphemes() {
        let graphemePool: [UInt32] = Self.nfcPool   // W0-b 의 scalarPool 과 같은 풀
        let inputs = Self.graphemeCurated.map(Self.string)
            + Self.randomSequences(pool: graphemePool, count: 300 - Self.graphemeCurated.count, seed: 0x6A12_0001, maxLength: 8).map(Self.string)
        var cases: [GoldenJSON] = []
        var divergent = 0
        func add(_ id: String, _ text: String) {
            let clusters = text.map { $0.unicodeScalars.count }
            var members: [String: GoldenJSON] = [
                "id": .string(id),
                "cps": .string(Self.cps(text)),
                "clusters": .array(clusters.map(GoldenJSON.int)),
                "count": .int(text.count),
            ]
            if let legacy = Self.graphemeLegacyForDivergent[Self.cps(text)] {
                #expect(legacy != clusters, "\(id): Swift 가 옛 규칙과 같아졌다 — knownDivergence 를 다시 정한다(G §8-16 ③)")
                members["knownDivergence"] = ["legacyClusters": .array(legacy.map(GoldenJSON.int)),
                                              "note": "유니코드 15.1 GB9c(InCB) 전 규칙의 경계 — JDK 21 BreakIterator 는 이것을 낸다"]
                divergent += 1
            }
            cases.append(.object(members))
        }
        for (index, text) in inputs.enumerated() { add("g-" + Self.pad(index, 3), text) }
        for (index, line) in Self.graphemeAppLines.enumerated() { add("app-" + Self.pad(index, 2), line) }
        #expect(divergent == Self.graphemeLegacyForDivergent.count)
        goldenEmit(GoldenFile(
            golden: "text/graphemes",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CheckTodoModel.swift", "Sources/CheckCore/AILimits.swift"],
            platformSensitive: true,
            spec: [
                "decision": "G §8-16 ③ — 그래핌은 플랫폼 BreakIterator(ART = ICU, 데스크톱 = JDK). Swift 와 갈리는 줄은 knownDivergence(InCB 2줄)만 허용: 그 줄은 Swift 값 또는 legacyClusters, 나머지 줄은 Swift 값과 같아야 한다. 데스크톱(JDK 21)은 두 줄 모두 legacyClusters 를 내야 한다(JDK 가 고쳐지면 빨강 → 목록을 다시 정한다)",
                "clusters": "그래핌마다 스칼라 수(앞에서부터). 합 = cps 의 스칼라 수 · count = Swift String.count",
                "corpus": "g-000~g-299 = W0-b w0b-probe/graphemes 와 같은 줄(손으로 고른 37 + SplitMix64(0x6a120001) 무작위 263) · app-* = 할 일 제목 · 기기 이름 꼴",
            ],
            cases: cases
        ))
    }

    // MARK: text/sanitize

    /// 입력 풀: 공백·줄바꿈류(서버 ② 집합 전부) · trim 집합(서버 ③ 전부) · 폭 0 채움 · ZWSP · BOM · 제어 · 서식 · 한글(완성형·자모) ·
    /// 라틴(결합 문자) · 이모지 · 숫자. NFC 가 Foundation 과 표준이 갈리는 조합(완성형 + 종성 자모 · 0f73 · 태그 + 결합)은 넣지 않는다 —
    /// 그 갈림은 text/nfc 가 따로 잠근다.
    static let sanitizePool: [UInt32] = [
        0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029, 0xA0, 0x200B, 0xFEFF, 0x3000, 0x2002, 0x1680, 0x180E,
        0x3164, 0x115F, 0x1160, 0xFFA0, 0x2800, 0x200D, 0x200E, 0x202E, 0x00AD, 0x07, 0x1B, 0x7F,
        0x61, 0x5A, 0x31, 0x2E, 0x5B, 0x5D, 0xAC00, 0xD55C, 0xAE00, 0x1112, 0x1161, 0x11AB, 0x0065, 0x0301,
        0x1F600, 0x1F44D, 0x1F3FB, 0xFE0F, 0x1F4E2,
    ]

    static let sanitizeCurated: [String] = [
        "", " ", "\n", "\u{3164}", "\u{115F}\u{1160}", "\u{200B}", "\u{FEFF}", "\u{2800}", "\u{FFA0}",
        "  안녕  ", "\n\n안녕\n\n", "안\n\n녕", "안  녕", "안 \t 녕", "안\r\n녕", "안\u{2028}녕", "안\u{85}녕",
        "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}", "\u{200B}가\u{200B}", "\u{3000}가\u{3000}", "\u{A0}가\u{A0}",
        "\u{2002}가\u{2002}", "\u{1680}가", "가\u{180E}", "\u{202E}가", "\u{00AD}", "\u{200D}", "\u{0301}", " \u{0301}",
        "👨‍👩‍👧‍👦", "📢 확성기", "[아잉:기쁨]", String(repeating: "가", count: 40), String(repeating: "가", count: 41),
        String(repeating: "가", count: 200), String(repeating: "가", count: 201), String(repeating: "👨‍👩‍👧‍👦", count: 29),
        String(repeating: " ", count: 41), String(repeating: "\u{3164}", count: 5) + "가", "e\u{0301}" + String(repeating: "a", count: 199),
        "a\u{0007}b", "\u{0007}", "\u{7F}", "탭\t탭", "줄\u{0B}줄", "줄\u{0C}줄",
        // 상한보다 긴데 보이는 글자가 없는 줄(다듬기로 안 지워지는 채움 · 폭 0) — 빈 판정이 먼저라 tooLong 이 아니라 empty 여야 한다.
        String(repeating: "\u{3164}", count: 201), String(repeating: "\u{200B}", count: 41),
    ]

    static func messageValidation(_ value: MessageBodyValidation) -> GoldenJSON {
        switch value {
        case .ok(let text): return ["kind": "ok", "cps": .string(Self.cps(text))]
        case .empty: return ["kind": "empty"]
        case .tooLong(let maxLength): return ["kind": "tooLong", "maxLength": .int(maxLength)]
        }
    }

    static func statusValidation(_ value: StatusMessageValidation) -> GoldenJSON {
        switch value {
        case .ok(let text): return ["kind": "ok", "cps": .string(Self.cps(text))]
        case .empty: return ["kind": "empty"]
        case .tooLong(let maxLength): return ["kind": "tooLong", "maxLength": .int(maxLength)]
        }
    }

    @Test("text/sanitize — MessageBody · StatusMessage: 정규화 · 코드포인트 길이 · 보이는 글자 · 판정 · 화면 관문")
    func sanitize() {
        let inputs = Self.sanitizeCurated
            + Self.randomSequences(pool: Self.sanitizePool, count: 240, seed: 0x5A71_0001, maxLength: 9).map(Self.string)
        var cases: [GoldenJSON] = []
        for (index, raw) in inputs.enumerated() {
            let display = StatusMessage.display(raw)
            cases.append([
                "id": .string("s-" + Self.pad(index, 3)),
                "cps": .string(Self.cps(raw)),
                "message": [
                    "sanitized": .string(Self.cps(MessageBody.sanitized(raw))),
                    "length": .int(MessageBody.length(raw)),
                    "visible": .bool(MessageBody.hasVisibleContent(raw)),
                    "validate": Self.messageValidation(MessageBody.validate(raw)),
                ],
                "status": [
                    "sanitized": .string(Self.cps(StatusMessage.sanitized(raw))),
                    "length": .int(StatusMessage.length(raw)),
                    "validate": Self.statusValidation(StatusMessage.validate(raw)),
                    "display": display.map { .string(Self.cps($0)) } ?? .null,
                    "counter": .string(StatusMessage.counterText(raw)),
                ],
            ])
        }
        goldenEmit(GoldenFile(
            golden: "text/sanitize",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/StatusMessage.swift",
                           "Sources/CheckCore/CheckCoreShared.swift"],
            platformSensitive: true,
            spec: [
                "message": "MessageBody(SupabaseWorkModels.swift): sanitized = NFC 뒤 앞뒤 whitespacesAndNewlines trim(가운데 줄바꿈은 둔다) · length = 정규화 뒤 코드포인트 수 · visible = hasVisibleContent(원문) · validate = 빈 판정 먼저, 그다음 200 상한",
                "status": "StatusMessage: sanitized = NFC → 줄바꿈류(09 0a 0b 0c 0d 85 2028 2029)가 든 공백·줄바꿈 묶음을 공백 하나로 → 앞뒤 trim(20 09 0a 0b 0c 0d a0 200b feff 3000) · validate = 빈·안 보임 먼저, 그다음 40 상한 · display = 안 보이면 null · counter = \"n/40\"",
                "platformSensitive": "true — NFC 가 플랫폼 Normalizer 다(G §8-16 ①). 코퍼스는 NFC 갈림 조합(완성형 + 종성 자모 · 0f73 · 태그 + 결합)을 넣지 않는다 — 그 갈림은 text/nfc 가 잠근다",
                "corpus": "손으로 고른 줄 + SplitMix64(0x5a710001) 무작위 240줄(입력 풀은 이 생성기의 sanitizePool)",
            ],
            cases: cases
        ))
    }

    // MARK: text/status-message

    static func statusOutcome(_ outcome: StatusMessageSaveOutcome) -> GoldenJSON {
        switch outcome {
        case .saved(let value): return ["kind": "saved", "cps": .string(Self.cps(value))]
        case .cleared: return ["kind": "cleared"]
        case .tooLong(let maxLength): return ["kind": "tooLong", "maxLength": .int(maxLength)]
        case .notText: return ["kind": "notText"]
        case .serverNotReady: return ["kind": "serverNotReady"]
        case .invalid: return ["kind": "invalid"]
        }
    }

    static func statusNotice(_ outcome: StatusMessageSaveOutcome) -> GoldenJSON {
        let notice = StatusMessageText.notice(for: outcome)
        return ["text": .string(notice.text), "isError": .bool(notice.isError)]
    }

    /// set_status_message 응답(이미 디코드한 세 칸 — 전선 디코드는 W1-d wire 몫) → 저장 결과 → 문구. status 는 대소문자 · 공백까지 정확히 본다.
    static let statusResponses: [(status: String, statusMessage: String?, maxLength: Int?)] = [
        ("ok", "오늘은 집중 모드", nil), ("ok", "  안녕\n하세요  ", nil), ("ok", "\u{1100}\u{1161}\u{11A8}", 40), ("ok", nil, nil),
        ("ok", "", nil), ("ok", " \t\n", nil), ("ok", "\u{3164}\u{3164}", nil), ("ok", "\u{200B}", nil), ("ok", "😀", nil),
        ("cleared", nil, nil), ("cleared", "남은 값", 40), ("too_long", nil, 40), ("too_long", nil, 25), ("too_long", nil, nil),
        ("too_long", "x", 0), ("too_long", nil, -3), ("not_text", nil, nil), ("not_text", "abc", 40), ("unauthorized", nil, nil),
        ("", nil, nil), ("OK", "대문자", nil), ("ok ", "공백 붙은 상태", nil), ("Cleared", nil, nil), ("TOO_LONG", nil, 40),
        ("server_not_ready", nil, nil), ("invalid", nil, nil), ("saved", "x", nil),
    ]

    @Test("text/status-message — set_status_message 응답 → 저장 결과 → 문구(오류 여부) · 결과 여섯의 문구 · 고정 문구")
    func statusMessageOutcome() {
        var cases: [GoldenJSON] = []
        for (index, response) in Self.statusResponses.enumerated() {
            let outcome = StatusMessageSaveOutcome(response: SetStatusMessageResponse(
                status: response.status, statusMessage: response.statusMessage, maxLength: response.maxLength))
            cases.append([
                "id": .string("r-" + Self.pad(index, 2)),
                "status": .string(response.status),
                "statusMessage": response.statusMessage.map { .string(Self.cps($0)) } ?? .null,
                "maxLength": response.maxLength.map { .int($0) } ?? .null,
                "outcome": Self.statusOutcome(outcome),
                "notice": Self.statusNotice(outcome),
            ])
        }
        // 응답에서 나오지 않는 결과(serverNotReady — 서비스가 PGRST202 · 404 에서 만든다)까지 결과 여섯의 문구.
        let outcomes: [StatusMessageSaveOutcome] = [.saved("상태"), .cleared, .tooLong(maxLength: 40), .tooLong(maxLength: 7),
                                                    .notText, .serverNotReady, .invalid]
        cases.append(["id": "notices", "rows": .array(outcomes.map { ["outcome": Self.statusOutcome($0), "notice": Self.statusNotice($0)] })])
        cases.append([
            "id": "texts",
            "title": .string(StatusMessageText.title), "placeholder": .string(StatusMessageText.placeholder),
            "save": .string(StatusMessageText.save), "clear": .string(StatusMessageText.clear),
            "saved": .string(StatusMessageText.saved), "cleared": .string(StatusMessageText.cleared),
            "notText": .string(StatusMessageText.notText), "invalid": .string(StatusMessageText.invalid),
            "serverNotReady": .string(StatusMessageText.serverNotReady), "network": .string(StatusMessageText.network),
            "hint": .string(StatusMessageText.hint), "tooLong40": .string(StatusMessageText.tooLong(40)),
            "maxLength": .int(StatusMessage.maxLength),
        ])
        goldenEmit(GoldenFile(
            golden: "text/status-message",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/StatusMessage.swift", "Sources/CheckCore/CheckCoreShared.swift"],
            platformSensitive: true,
            spec: [
                "outcome": "StatusMessageSaveOutcome(response:): ok → display(statusMessage)(NFC · 줄바꿈류 접기 · trim · 보이는 글자) 가 있으면 saved(그 값) 없으면 cleared · cleared → cleared · too_long → tooLong(max_length ?? 40) · not_text → notText · 그 밖(대소문자 · 공백 다른 것 포함) → invalid",
                "notice": "StatusMessageText.notice: saved · cleared 는 오류 아님, 나머지 넷(tooLong · notText · serverNotReady · invalid)은 오류",
                "wire": "요청 본문(p_text 키를 언제나 싣는다) · 응답 디코드 · 내 상태 GET 행은 W1-d wire 몫(G5 · G6) — 이 골든은 디코드한 세 칸에서 시작한다",
                "platformSensitive": "true — saved 값이 display(NFC)를 거친다",
            ],
            cases: cases
        ))
    }

    // MARK: stickers/tokens

    static let stickerParseInputs: [String] = [
        "[아잉:기쁨]", "[아잉:하트]", "[아잉:슬픔]", "[아잉:화남]", "[아잉:졸림]", "[아잉:놀람]",
        " [아잉:기쁨] ", "\n[아잉:하트]\n", "\u{200B}[아잉:기쁨]", "\u{FEFF}[아잉:기쁨]", "\u{3000}[아잉:슬픔]", "\u{A0}[아잉:화남]",
        "[아잉:기쁨]!", "![아잉:기쁨]", "[아잉:기쁨][아잉:기쁨]", "[아잉:없는것]", "[아잉:]", "[아잉:굿]", "[아잉:박수]",
        "📢 [아잉:기쁨]", "[아잉: 기쁨]", "[ 아잉:기쁨]", "[아잉:기쁨 ]", "［아잉:기쁨］", "[아잉：기쁨]", "아잉:기쁨",
        "[AING:joy]", "[아잉:기쁨", "아잉:기쁨]", "", " ", "[", "기쁨", "안녕하세요",
        "\u{2002}[아잉:기쁨]", "\u{1680}[아잉:기쁨]", "\u{180E}[아잉:기쁨]", "\u{3164}[아잉:기쁨]", "\u{85}[아잉:놀람]",
    ]

    static func stickerParseCase(_ id: String, _ raw: String) -> GoldenJSON {
        let parsed = AingSticker.parse(raw)
        return [
            "id": .string(id),
            "cps": .string(Self.cps(raw)),
            "parsed": parsed.map { .string($0.rawValue) } ?? .null,
            "preview": .string(Self.cps(AingStickerText.preview(for: raw))),
        ]
    }

    @Test("stickers/tokens — 이모티콘 여섯(토큰 · 이름 · 그림 이름) · 통째 일치 판정 · 글자 자리 미리보기")
    func stickerTokens() {
        var cases: [GoldenJSON] = AingSticker.allCases.enumerated().map { index, sticker in
            [
                "id": .string("sticker-\(index)-\(sticker.rawValue)"),
                "order": .int(index),
                "rawValue": .string(sticker.rawValue),
                "token": .string(Self.cps(sticker.token)),
                "label": .string(Self.cps(sticker.label)),
                "resourceName": .string(sticker.resourceName),
                "accessibilityLabel": .string(Self.cps(AingStickerText.accessibilityLabel(sticker))),
            ]
        }
        cases.append([
            "id": "constants",
            "tokenPrefix": .string(Self.cps(AingSticker.tokenPrefix)),
            "count": .int(AingSticker.allCases.count),
            "gridTitle": .string(Self.cps(AingStickerText.gridTitle)),
            "buttonLabel": .string(Self.cps(AingStickerText.buttonLabel)),
            "closeGridLabel": .string(Self.cps(AingStickerText.closeGridLabel)),
            "sendingNowNotice": .string(Self.cps(AingStickerText.sendingNowNotice)),
            "folderName": .string(AingStickerArt.folderName),
        ])
        for (index, raw) in Self.stickerParseInputs.enumerated() {
            cases.append(Self.stickerParseCase("parse-" + Self.pad(index, 2), raw))
        }
        // 자모 분해(NFD)로 들어온 토큰도 같은 그림이어야 한다(AingSticker 머리말 "NFC 정규화를 거치는 이유").
        for (index, sticker) in AingSticker.allCases.enumerated() {
            cases.append(Self.stickerParseCase("parse-nfd-\(index)", sticker.token.decomposedStringWithCanonicalMapping))
            cases.append(Self.stickerParseCase("parse-nfd-padded-\(index)", "\u{200B} " + sticker.token.decomposedStringWithCanonicalMapping + "\n"))
        }
        goldenEmit(GoldenFile(
            golden: "stickers/tokens",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/AingSticker.swift", "Sources/CheckCore/SupabaseWorkModels.swift"],
            platformSensitive: true,
            spec: [
                "contract": "전선은 평문 토큰(\"[아잉:<이름>]\", 7 코드포인트) — 받는 쪽은 MessageBody.sanitized 뒤 **통째 일치**일 때만 그림. 토큰 글자와 화면 글자(label)는 따로 둔다(G §8-2)",
                "order": "case 순서 = 고르는 그리드의 순서",
                "parse": "첫 글자(whitespacesAndNewlines 를 건너뛴)가 '[' 가 아니면 null · 아니면 sanitized 가 토큰과 같은 것 · preview = 이모티콘이면 \"아잉이 <label>\", 아니면 원문 그대로",
                "platformSensitive": "true — sanitized 가 NFC(플랫폼 Normalizer)를 거친다",
            ],
            cases: cases
        ))
    }

    // MARK: sort/natural-ko

    /// 합성 이름의 재료(C-X5 — 실제 별명 꼴: 한글 · 영문 대소문자 · 숫자 덩어리 · 이모지 · 전각 · 공백 · 기호).
    static let nameSyllables: [String] = ["가", "나", "다", "라", "마", "바", "사", "아", "자", "차", "카", "타", "파", "하",
                                          "각", "간", "강", "김", "이", "박", "최", "정", "윤", "예", "성", "잉", "똑", "뷁", "힣"]
    static let nameLatin: [String] = ["a", "A", "b", "B", "c", "z", "Z", "e", "é", "E", "o", "x", "user", "User", "USER", "Kim", "kim", "lee"]
    static let nameDigits: [String] = ["0", "1", "2", "9", "10", "11", "20", "02", "007", "100", "1000"]
    static let nameOther: [String] = [" ", "_", "-", ".", "😀", "👍", "🐱", "Ａ", "１", "ａ", "ㄱ", "ㅏ", "★", "(", "#", "~", "ア", "漢"]

    static func syntheticNames(count: Int, seed: UInt64) -> [String] {
        var rng = MiniGameRandom(seed: seed)
        func pick(_ list: [String]) -> String { list[Int(rng.next() % UInt64(list.count))] }
        var names: [String] = []
        var seen = Set<String>()
        while names.count < count {
            let parts = 1 + Int(rng.next() % 4)
            var name = ""
            for _ in 0..<parts {
                switch rng.next() % 10 {
                case 0, 1, 2, 3: name += pick(nameSyllables)
                case 4, 5: name += pick(nameLatin)
                case 6, 7: name += pick(nameDigits)
                default: name += pick(nameOther)
                }
            }
            // 같은 글(스칼라 열)은 한 번만 — 정렬 결과가 입력 순서에 기대지 않게.
            if seen.insert(Self.cps(name)).inserted { names.append(name) }
        }
        return names
    }

    /// 정렬표 레퍼토리(단일 스칼라 순위표 — Kotlin 이 번들한다). 별명에 실제로 나올 만한 블록: ASCII · 라틴-1 · 라틴 확장-A ·
    /// 그리스·키릴 기본 · 일반 구두점 · 통화 · 화살표 · 도형 · 기타 기호 · 딩뱃 · CJK 구두점 · 가나 · 한글 자모(현대·옛·호환·확장) ·
    /// 반각·전각 · 이모지 블록. 한글 음절은 자모로 풀고(정준 분해), 한자는 표에 없다(아래 spec — 읽기순 정렬은 번들하지 않는다).
    static let collationRepertoire: [ClosedRange<UInt32>] = [
        0x20...0x7E, 0xA0...0x17F, 0x300...0x36F, 0x391...0x3A9, 0x3B1...0x3C9, 0x401...0x451,
        0x1100...0x11FF, 0x200B...0x200F, 0x2010...0x2027, 0x2030...0x205E, 0x20A0...0x20C0, 0x2190...0x21FF, 0x25A0...0x25FF,
        0x2600...0x27BF, 0x3000...0x303F, 0x3041...0x30FF, 0x3131...0x318E, 0xA960...0xA97C, 0xD7B0...0xD7FB,
        0xFE00...0xFE0F, 0xFF01...0xFFEE, 0x1F1E6...0x1F1FF, 0x1F300...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF,
    ]

    static let sortLocale = Locale(identifier: "ko_KR")

    /// `localizedStandardCompare` 와 같은 비교(Foundation 정의) — 로캘만 ko_KR 로 고정했다(시험 기계 로캘에 기대지 않게).
    static func naturalCompare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering],
                  range: a.startIndex..<a.endIndex, locale: sortLocale)
    }

    static func compareCode(_ a: String, _ b: String, _ options: String.CompareOptions) -> Int {
        switch a.compare(b, options: options, range: a.startIndex..<a.endIndex, locale: sortLocale) {
        case .orderedAscending: return -1
        case .orderedSame: return 0
        case .orderedDescending: return 1
        }
    }

    static func natural(_ a: String, _ b: String) -> Int {
        compareCode(a, b, [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering])
    }

    /// 단계별 같음(ICU 세기): 1차(대소문자·악센트·너비 무시) · 2차(대소문자·너비 무시) · 3차(아무것도 무시 안 함). 모두 숫자 모드.
    static func sameAt(_ level: Int, _ a: String, _ b: String) -> Bool {
        switch level {
        case 1: return compareCode(a, b, [.caseInsensitive, .diacriticInsensitive, .widthInsensitive, .numeric]) == 0
        case 2: return compareCode(a, b, [.caseInsensitive, .widthInsensitive, .numeric]) == 0
        default: return compareCode(a, b, [.numeric]) == 0
        }
    }

    @Test("sort/collation-table — 레퍼토리 단일 스칼라를 localizedStandardCompare(ko_KR) 로 줄 세우고 단계(1차·2차·3차·같음) 경계를 적는다")
    func collationTable() {
        var scalars: [Unicode.Scalar] = []
        for range in Self.collationRepertoire {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.generalCategory != .unassigned else { continue }
                scalars.append(scalar)
            }
        }
        let strings = scalars.map { String($0) }
        var ignorable: [String] = []        // 3차까지 빈 글과 같다(ZWJ · 이체 선택자 …)
        var primaryIgnorable: [String] = [] // 1차만 빈 글과 같다(결합 부호 …)
        var ranked: [String] = []
        // 무시되는 글자는 빈 글과 견주지 않고 'a<글자>b' 와 'ab' 로 잰다 — 빈 글과의 비교는 길이로 먼저 갈려 무시 여부를 말하지 않는다(실측).
        for text in strings {
            if Self.sameAt(3, "a" + text + "b", "ab") { ignorable.append(text) }
            else if Self.sameAt(1, "a" + text + "b", "ab") { primaryIgnorable.append(text) }
            else { ranked.append(text) }
        }
        let sorted = ranked.sorted { Self.natural($0, $1) < 0 }
        var tokens: [String] = []
        var asymmetric = 0
        for (index, text) in sorted.enumerated() {
            let marker: String
            if index == 0 {
                marker = "P"
            } else {
                let previous = sorted[index - 1]
                if Self.natural(previous, text) != -1 || Self.natural(text, previous) != 1 { asymmetric += 1 }
                if !Self.sameAt(1, previous, text) { marker = "P" }
                else if !Self.sameAt(2, previous, text) { marker = "S" }
                else if !Self.sameAt(3, previous, text) { marker = "T" }
                else { marker = "I" }
            }
            tokens.append(marker + String(text.unicodeScalars.first!.value, radix: 16))
        }
        #expect(asymmetric == 0, "단일 스칼라 이웃 \(asymmetric) 쌍이 반대칭이 아니다 — 표를 단일 스칼라로 만들 수 없다")
        let chunk = 400
        var cases: [GoldenJSON] = []
        for start in stride(from: 0, to: tokens.count, by: chunk) {
            cases.append([
                "id": .string("order-" + Self.pad(start / chunk, 2)),
                "start": .int(start),
                "tokens": .string(tokens[start..<min(start + chunk, tokens.count)].joined(separator: " ")),
            ])
        }
        cases.append(["id": "ignorable", "cps": .string(ignorable.map { Self.cps($0) }.joined(separator: " "))])
        cases.append(["id": "primary-ignorable", "cps": .string(primaryIgnorable.map { Self.cps($0) }.joined(separator: " "))])
        cases.append([
            "id": "repertoire",
            "ranges": .string(Self.collationRepertoire.map { Self.hex4(Int($0.lowerBound)) + "-" + Self.hex4(Int($0.upperBound)) }
                .joined(separator: ",")),
            "ranked": .int(sorted.count),
        ])
        print("[W1-c] sort/collation-table ranked=\(sorted.count) ignorable=\(ignorable.count) primaryIgnorable=\(primaryIgnorable.count)")
        goldenEmit(GoldenFile(
            golden: "sort/collation-table",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkModels.swift"],
            platformSensitive: false,
            spec: [
                "order": "레퍼토리의 할당된 스칼라(빈 글과 같은 것 제외)를 localizedStandardCompare(ko_KR) 로 오름차순. 토큰 = 표식 + 16진. 표식은 앞 글자와의 경계 단계: P 1차가 다르다(대소문자·악센트·너비 무시해도 다르다) · S 2차(악센트)만 · T 3차(대소문자·너비·호환 꼴)만 · I ICU 로는 같고 마지막 문자 비교로만 갈린다",
                "ignorable": "'a<글자>b' 가 3차까지 'ab' 와 같은 스칼라(비교에서 통째로 빠진다 — 마지막 원문 비교만 센다)",
                "primaryIgnorable": "'a<글자>b' 가 1차만 'ab' 와 같은 스칼라(결합 부호 · 피부색 — 2차 이하에서만 센다)",
                "bundle": "Kotlin NaturalKoCollation 이 이 표를 번들하고 시험이 토큰 하나까지 같은지 본다. 한글 음절은 정준 분해한 자모로, 숫자(Nd)는 숫자 모드 값으로 센다. 레퍼토리 밖은 코드포인트 순 꼬리(한자는 한글 뒤 · 라틴 앞 — ko 의 읽기순은 번들하지 않는다)",
            ],
            cases: cases
        ))
    }

    static let sortCuratedPairs: [(String, String)] = [
        ("가", "나"), ("가", "a"), ("A", "a"), ("a", "B"), ("user2", "user10"), ("user02", "user2"), ("user2", "User2"),
        ("1", "가"), ("가1", "가01"), ("10", "9"), ("가 나", "가나"), ("😀", "가"), ("😀", "a"), ("😀", "1"), ("Ａ", "a"),
        ("１", "1"), ("é", "e"), ("e\u{301}", "é"), ("e", "f"), ("ㄱ", "가"), ("ㄱ", "나"), ("ㄱㅏ", "가"), ("아잉이", "아잉"),
        ("Kim", "kim"), ("_a", "a"), ("-a", "a"), ("ア", "가"), ("ア", "あ"), ("漢", "가"), ("漢", "한"), ("漢", "a"), ("★", "가"),
        ("김2", "김10"), ("김 2", "김10"), ("", "a"), ("a1b2", "a1b10"), ("x9", "x09"), ("A2", "a02"), ("00", "0"),
        ("ﬁ", "fi"), ("ß", "ss"), ("가", "\u{1100}\u{1161}"), ("간", "가나"), ("각", "가가"), ("각", "가바"), ("갂", "각각"),
        ("가ㅏ", "각"), ("Ａb", "ab"), ("ａB", "Ab"), ("٣", "3"), ("²", "2"), ("😀\u{FE0F}", "😀"), ("a\u{200D}b", "ab"),
    ]

    @Test("sort/natural-ko — 이름 500개의 localizedStandardCompare(ko_KR): 이웃 쌍 · 무작위 쌍 · 손으로 고른 쌍의 양방향 비교값")
    func naturalSort() {
        let names = Self.syntheticNames(count: 500, seed: 0x5047_0005)
        let sorted = names.sorted { Self.natural($0, $1) < 0 }
        var pairs: [(String, String)] = []
        for index in 1..<sorted.count { pairs.append((sorted[index - 1], sorted[index])) }
        var rng = MiniGameRandom(seed: 0x5047_0006)
        for _ in 0..<2_000 {
            let a = names[Int(rng.next() % UInt64(names.count))]
            let b = names[Int(rng.next() % UInt64(names.count))]
            pairs.append((a, b))
        }
        pairs += Self.sortCuratedPairs
        var cases: [GoldenJSON] = []
        var inconsistent = 0
        let chunk = 250
        for start in stride(from: 0, to: pairs.count, by: chunk) {
            var rows: [GoldenJSON] = []
            for (a, b) in pairs[start..<min(start + chunk, pairs.count)] {
                let ab = Self.natural(a, b)
                let ba = Self.natural(b, a)
                if ab != -ba { inconsistent += 1 }
                rows.append([.string(Self.cps(a)), .string(Self.cps(b)), .int(ab), .int(ba)])
            }
            cases.append(["id": .string("pairs-" + Self.pad(start / chunk, 2)), "start": .int(start), "pairs": .array(rows)])
        }
        cases.append(["id": "names", "names": .array(names.map { .string(Self.cps($0)) })])
        cases.append(["id": "summary", "pairs": .int(pairs.count), "inconsistent": .int(inconsistent)])
        print("[W1-c] sort/natural-ko pairs=\(pairs.count) inconsistent(ab ≠ -ba)=\(inconsistent)")
        if Locale.current.identifier.hasPrefix("ko") {
            // 이 기계의 로캘이 한국어면 localizedStandardCompare 와 같은 값인지 덤으로 본다(골든 값에는 영향 없음).
            for (a, b) in pairs.prefix(600) {
                let standard = a.localizedStandardCompare(b)
                #expect(standard == Self.naturalCompare(a, b), "ko 로캘의 localizedStandardCompare 가 고정 옵션 비교와 다르다: \(a) / \(b)")
            }
        }
        goldenEmit(GoldenFile(
            golden: "sort/natural-ko",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/GomokuStore.swift",
                           "Sources/CheckCore/ChessStore.swift", "Sources/CheckCore/TetrisDuelStore.swift"],
            platformSensitive: false,
            spec: [
                "compare": "String.localizedStandardCompare = compare(_:options: [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering], range: 전체, locale: Locale.current). 골든은 locale 을 ko_KR 로 고정해 낸다(사용자 기기 로캘 — 시험 기계 로캘에 기대지 않는다)",
                "pairs": "[a 코드포인트, b 코드포인트, compare(a,b), compare(b,a)] (-1 앞 · 0 같음 · 1 뒤). 이웃 쌍(Swift sorted 결과의 이웃 499) + SplitMix64(0x50470006) 무작위 2000 + 손으로 고른 쌍",
                "inconsistent": "C-X5 실측: Foundation 의 ko 비교는 한글에서 반대칭이 아니다 — 종성으로 끝나는 음절과 같은 초·중성 뒤에 음절이 더 오는 글(예: '간' / '가나')을 양쪽으로 비교하면 둘 다 1 이다. 그런 쌍(ab ≠ -ba)은 Swift 에 일관된 답이 없으므로 Kotlin 은 반대칭(사전순 — 자모 L < V < T)만 지킨다. 나머지 쌍은 Swift 값과 같아야 한다",
                "names": "C-X5 합성 이름 500개(SplitMix64(0x50470005) — 한글 음절 · 영문 대소문자 · 숫자 덩어리 · 이모지 · 전각 · 공백 · 기호 · 가나 · 한자)",
                "platformSensitive": "false — Kotlin 은 기기 Collator 를 쓰지 않는 순수 비교기(NaturalKoCollation + sort/collation-table 번들)",
            ],
            cases: cases
        ))
    }
}
