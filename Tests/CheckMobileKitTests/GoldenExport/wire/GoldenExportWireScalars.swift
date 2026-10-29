// 원본: 없음
import CheckGoldenSupport
import Foundation
import Testing

// W1-d 글자 판정 범위 표(G §8-20 #3 · §8-16 ② — 8차 fold). 와이어·통신이 기대는 Swift 글자 판정을 U+0000~U+10FFFF 구간으로 낸다.
// Kotlin 은 이 표를 압축해 번들(core/wire `WireScalarTable`)하고 `Character.getType`·`isLetter`·`isWhitespace`·`isUpperCase`·
// `isLowerCase`·인자 없는 `trim` 을 쓰지 않는다(JDK 21 = 유니코드 15.0, ART 는 기기 API 마다 판이 다르다).
//
// 다섯 비트(그 스칼라 하나로 된 Character 의 답):
//   ① Character.isWhitespace            — SupabaseWorkService.normalizeInviteCode 의 filter
//   ② CharacterSet.whitespaces          — RealtimeFeature.isEnabled 의 trimmingCharacters(in: .whitespaces)
//   ③ Character.isLetter                — convertFromSnakeCase(capitalized) 의 '대소문자 있는 글자' 판정
//   ④ Character.isUppercase             — convertToSnakeCase 의 단어 경계 · capitalized
//   ⑤ Character.isLowercase             — convertToSnakeCase 의 단어 경계 · capitalized

@Suite("GoldenExport W1-d 와이어 — 글자 판정 범위 표")
struct GoldenExportWireScalars {
    static func hex4(_ value: Int) -> String {
        let s = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 4 - s.count)) + s
    }

    static func bits(_ value: Int) -> String {
        guard let scalar = Unicode.Scalar(UInt32(value)) else { return "00000" } // 서로게이트(스칼라가 아니다)
        let c = Character(scalar)
        return (c.isWhitespace ? "1" : "0")
            + (CharacterSet.whitespaces.contains(scalar) ? "1" : "0")
            + (c.isLetter ? "1" : "0")
            + (c.isUppercase ? "1" : "0")
            + (c.isLowercase ? "1" : "0")
    }

    @Test func scalarProperties() {
        var cases: [GoldenJSON] = []
        var totalRanges = 0
        var classes = Set<String>()
        for plane in 0...16 {
            var tokens: [String] = []
            var runStart = plane << 16
            var runClass = Self.bits(plane << 16)
            for value in ((plane << 16) + 1)...((plane << 16) | 0xFFFF) {
                let klass = Self.bits(value)
                if klass != runClass {
                    tokens.append(Self.hex4(runStart) + "-" + Self.hex4(value - 1) + ":" + runClass)
                    classes.insert(runClass)
                    runStart = value
                    runClass = klass
                }
            }
            tokens.append(Self.hex4(runStart) + "-" + Self.hex4((plane << 16) | 0xFFFF) + ":" + runClass)
            classes.insert(runClass)
            totalRanges += tokens.count
            let id = plane < 10 ? "plane-0\(plane)" : "plane-\(plane)"
            cases.append(["id": .string(id), "ranges": .string(tokens.joined(separator: ","))])
        }
        print("[W1-d] wire/scalar-props ranges=\(totalRanges) classes=\(classes.count)")
        goldenEmit(GoldenFile(
            golden: "wire/scalar-props",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkService.swift", "Sources/CheckCore/RealtimeTransport.swift"],
            platformSensitive: false,
            spec: [
                "decision": "G §8-20 #3 · §8-16 ② — W1-d 글자 판정은 Character.getType·isLetter·isWhitespace 를 쓰지 않는다. Kotlin 은 이 표를 압축해 번들(core/wire WireScalarTable)하고, 시험이 번들을 풀어 이 표와 구간 하나까지 같은지 본다(JVM·API 26·36 ART 같은 답)",
                "ranges": "'시작-끝:비트' 를 쉼표로 잇는다(16진 소문자, 끝 포함, 평면 안에서 빈틈없이). 비트 = 다섯 글자 0/1",
                "bits": "① Character.isWhitespace(normalizeInviteCode) ② CharacterSet.whitespaces(RealtimeFeature 환경 변수 trim) ③ Character.isLetter ④ Character.isUppercase ⑤ Character.isLowercase(③~⑤ 키 전략 convertFromSnakeCase·convertToSnakeCase) — 그 스칼라 하나로 된 Character 의 답",
                "surrogate": "D800-DFFF 는 스칼라가 아니라 00000 으로 적는다",
                "platformSensitive": "false — Kotlin 답은 번들 표에서만 나온다(기기 ICU 판과 무관). 계측 시험은 번들이 ART 에서도 같게 풀리는지 덤으로 본다",
            ],
            cases: cases
        ))
    }
}
