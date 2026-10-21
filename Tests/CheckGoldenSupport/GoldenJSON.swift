import Foundation

// 골든 바탕(W0-b · K1 · contract/README.md). Swift 가 쓰고 Swift·Kotlin 이 둘 다 읽는 골든 JSON 의 값과 정규 작성기.
//
// 정규 바이트 = 파이썬 `json.dumps(값, indent=2, sort_keys=True, ensure_ascii=False) + "\n"` 과 **바이트까지 같다**.
// 그래서 같은 골든을 Swift(내보내기)와 파이썬(`_manifest.json` 조립 · `golden-digest.py`)이 따로 써도 한 벌이다.
//   · 들여쓰기 2칸, 항목 구분 `,` + 줄바꿈, 키와 값 사이 `": "`, 빈 배열 `[]` · 빈 객체 `{}`
//   · 키 정렬 = 유니코드 스칼라 값 순서(파이썬 str 비교와 같다). 키는 ASCII 만 받는다(Swift 사전은 정준 동치 키를 합친다)
//   · 문자열: `"` `\` 와 제어 문자만 이스케이프(`\b \f \n \r \t`, 나머지 `\u00xx` 소문자). 나머지 글자는 그대로 — NFC 로 바꾸지 않는다
//   · 정수는 ±2^53 안에서만. 64비트 값(난수·해시)은 `GoldenBits.hex64` 글자로, 실수는 `GoldenBits.bits` 글자로 싣는다.
//     **실수 갈래는 일부러 없다**(십진 표기는 언어마다 짧은 표기 규칙이 달라 바이트가 갈린다).

/// 골든 JSON 값. 실수는 없다 — `…Bits` 16진 글자로 싣는다.
package indirect enum GoldenJSON: Equatable, Sendable {
    case object([String: GoldenJSON])
    case array([GoldenJSON])
    case string(String)
    case int(Int)
    case bool(Bool)
    case null
}

package struct GoldenJSONError: Error, CustomStringConvertible, Equatable {
    package var description: String
    package init(_ description: String) { self.description = description }
}

extension GoldenJSON: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    package init(stringLiteral value: String) { self = .string(value) }
    package init(integerLiteral value: Int) { self = .int(value) }
    package init(booleanLiteral value: Bool) { self = .bool(value) }
    package init(arrayLiteral elements: GoldenJSON...) { self = .array(elements) }
    package init(dictionaryLiteral elements: (String, GoldenJSON)...) {
        var object: [String: GoldenJSON] = [:]
        for (key, value) in elements {
            precondition(object[key] == nil, "골든 객체 키가 겹친다: \(key)")
            object[key] = value
        }
        self = .object(object)
    }
    package init(nilLiteral: ()) { self = .null }
}

extension GoldenJSON {
    /// JSON 숫자로 실어도 언어마다 같은 값으로 읽히는 정수의 경계(2^53). 넘는 값은 `GoldenBits.hex64` 로 싣는다.
    package static let maxSafeInteger = 9_007_199_254_740_992

    package static func hex64(_ value: UInt64) -> GoldenJSON { .string(GoldenBits.hex64(value)) }
    package static func bits(_ value: Double) -> GoldenJSON { .string(GoldenBits.bits(value)) }

    /// 정규 글자(끝 줄바꿈 하나 포함). 규칙을 어기는 값(±2^53 밖 정수 · ASCII 밖 키)은 던진다.
    package func canonicalText() throws -> String {
        var out = ""
        try Self.write(self, level: 0, into: &out, path: "$")
        out.append("\n")
        return out
    }

    package func canonicalData() throws -> Data { Data(try canonicalText().utf8) }

    /// 키 정렬: 유니코드 스칼라 값의 사전식 순서(파이썬 `sorted(dict)` 와 같다).
    package static func keyPrecedes(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) { $0.value < $1.value }
    }

    private static func indent(_ level: Int, into out: inout String) {
        out.append(String(repeating: " ", count: level * 2))
    }

    private static func write(_ value: GoldenJSON, level: Int, into out: inout String, path: String) throws {
        switch value {
        case .null:
            out.append("null")
        case .bool(let flag):
            out.append(flag ? "true" : "false")
        case .int(let number):
            guard number >= -maxSafeInteger, number <= maxSafeInteger else {
                throw GoldenJSONError("\(path): 정수 \(number) 가 ±2^53 밖이다 — GoldenBits.hex64 글자로 싣는다")
            }
            out.append(String(number))
        case .string(let text):
            writeString(text, into: &out)
        case .array(let items):
            if items.isEmpty { out.append("[]"); return }
            out.append("[\n")
            for (index, item) in items.enumerated() {
                indent(level + 1, into: &out)
                try write(item, level: level + 1, into: &out, path: "\(path)[\(index)]")
                out.append(index == items.count - 1 ? "\n" : ",\n")
            }
            indent(level, into: &out)
            out.append("]")
        case .object(let members):
            if members.isEmpty { out.append("{}"); return }
            let keys = members.keys.sorted(by: keyPrecedes)
            out.append("{\n")
            for (index, key) in keys.enumerated() {
                guard key.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) else {
                    throw GoldenJSONError("\(path): 키 \(key.debugDescription) 에 ASCII 밖 글자가 있다(정준 동치 키가 합쳐진다)")
                }
                indent(level + 1, into: &out)
                writeString(key, into: &out)
                out.append(": ")
                try write(members[key]!, level: level + 1, into: &out, path: "\(path).\(key)")
                out.append(index == keys.count - 1 ? "\n" : ",\n")
            }
            indent(level, into: &out)
            out.append("}")
        }
    }

    private static func writeString(_ text: String, into out: inout String) {
        out.append("\"")
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: out.append("\\\"")
            case 0x5C: out.append("\\\\")
            case 0x08: out.append("\\b")
            case 0x0C: out.append("\\f")
            case 0x0A: out.append("\\n")
            case 0x0D: out.append("\\r")
            case 0x09: out.append("\\t")
            case 0x00..<0x20:
                let hex = String(scalar.value, radix: 16)
                out.append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out.append("\"")
    }
}

// MARK: - 읽기(비교 모드의 첫 불일치 찾기 · 지원 타깃 자기 시험)

extension GoldenJSON {
    /// 정규 글자를 다시 값으로 읽는다. 실수 숫자가 있으면 던진다(정규 골든에는 없다).
    package static func parse(_ data: Data) throws -> GoldenJSON {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try from(any, path: "$")
    }

    private static func from(_ any: Any, path: String) throws -> GoldenJSON {
        switch any {
        case is NSNull:
            return .null
        case let text as String:
            return .string(text)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let double = number.doubleValue
            guard double.rounded(.towardZero) == double, let exact = Int(exactly: number.int64Value),
                  Double(exact) == double else {
                throw GoldenJSONError("\(path): 정수가 아닌 숫자 \(number) — 골든에는 실수 숫자가 없다")
            }
            return .int(exact)
        case let items as [Any]:
            return .array(try items.enumerated().map { try from($0.element, path: "\(path)[\($0.offset)]") })
        case let members as [String: Any]:
            var object: [String: GoldenJSON] = [:]
            for (key, value) in members { object[key] = try from(value, path: "\(path).\(key)") }
            return .object(object)
        default:
            throw GoldenJSONError("\(path): 모르는 JSON 값 \(type(of: any))")
        }
    }

    package subscript(key: String) -> GoldenJSON? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    /// 두 값이 처음 갈리는 경로(같으면 nil). 비교 모드 실패 문구에 쓴다.
    package static func firstDifference(_ a: GoldenJSON, _ b: GoldenJSON, path: String = "$") -> String? {
        switch (a, b) {
        case (.object(let x), .object(let y)):
            for key in Set(x.keys).union(y.keys).sorted(by: keyPrecedes) {
                guard let xv = x[key] else { return "\(path).\(key)(새 값에만 있다)" }
                guard let yv = y[key] else { return "\(path).\(key)(파일에만 있다)" }
                if let found = firstDifference(xv, yv, path: "\(path).\(key)") { return found }
            }
            return nil
        case (.array(let x), .array(let y)):
            for index in 0..<min(x.count, y.count) {
                if let found = firstDifference(x[index], y[index], path: "\(path)[\(index)]") { return found }
            }
            return x.count == y.count ? nil : "\(path)(길이 \(x.count) ≠ \(y.count))"
        default:
            return a == b ? nil : path
        }
    }
}
