import Foundation

// 골든 바탕(W0-b · K1): 64비트 값과 실수의 글자 표기, FNV-1a 64 접기.
//
// 표기(contract/README.md 「값 표기」):
//   · 64비트 정수(난수·해시·시드) → "0x" + 소문자 16진 16자리. 예: "0x00000000013529dc"
//   · Double → 키 이름 끝에 `Bits`, 값은 IEEE-754 비트의 소문자 16진 16자리("0x" 없음). 예: "dtBits": "3f90000000000000"
//   두 표기를 섞지 않는 이유: 키만 보고 "정수 비트"와 "실수 비트"를 가를 수 있어야 Kotlin 이 ULong·Double 로 바로 읽는다.

package enum GoldenBits {
    package static func hex64(_ value: UInt64) -> String {
        "0x" + padded16(value)
    }

    package static func bits(_ value: Double) -> String {
        padded16(value.bitPattern)
    }

    package static func parseHex64(_ text: String) -> UInt64? {
        guard text.hasPrefix("0x"), text.count == 18 else { return nil }
        return UInt64(text.dropFirst(2), radix: 16)
    }

    package static func parseBits(_ text: String) -> Double? {
        guard text.count == 16, let raw = UInt64(text, radix: 16) else { return nil }
        return Double(bitPattern: raw)
    }

    private static func padded16(_ value: UInt64) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// FNV-1a 64. `Tests/checkTests/V0360TetrisSoloGoldenTests.swift` 의 `GoldHasher` 와 **같은 정의**다
/// (64비트 값 하나를 작은 끝부터 8바이트로 접는다). 골든 머리말의 `spec.hash` 가 이 정의를 가리킨다.
package struct GoldenFNV1a64: Sendable, Equatable {
    package static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    package static let prime: UInt64 = 0x0000_0100_0000_01B3

    package private(set) var value: UInt64 = GoldenFNV1a64.offsetBasis

    package init() {}

    package mutating func add(_ x: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            value ^= (x >> UInt64(shift)) & 0xFF
            value &*= Self.prime
        }
    }

    package mutating func add(_ x: Int) { add(UInt64(bitPattern: Int64(x))) }
    package mutating func add(_ x: Double) { add(x.bitPattern) }
    package mutating func add(_ x: Bool) { add(x ? UInt64(1) : 0) }

    package var hex: String { GoldenBits.hex64(value) }
}
