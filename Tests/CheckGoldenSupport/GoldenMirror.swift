import Foundation

// 골든 바탕(W0-b · C§5.2 G6 · C-X10): Swift 값 → 정규 덤프(`GoldenJSON`). Kotlin 은 같은 규칙으로 리플렉션 덤프를 만들어
// 바이트 대조한다. 규칙은 contract/README.md 「디코드 덤프 규칙(G6)」이 정본이고, 이 파일은 그 Swift 구현이다.
//
//  · 구조체·클래스 → 객체. 키 = 저장 프로퍼티 이름(Swift 이름 그대로, C§2.3). 계산 프로퍼티는 없다(Mirror 가 안 보인다).
//    클래스는 상위 클래스 저장 프로퍼티까지. `$__lazy_storage_$_` 로 시작하는 lazy 저장 칸은 뺀다.
//  · Optional → 모든 겹을 벗긴다. nil(어느 겹이든) → null. **`Int??` 의 .some(nil) 과 nil 은 같은 null 이다**
//    — Kotlin 에는 겹친 널이 없다(`Int??` = `Int?`). 와이어 타입이 이 구분에 기대면 덤프로는 못 잡는다(그 자리는 따로 시험).
//  · 열거, 연관값 없음 → 갈래 이름 글자(원시값이 아니라 Swift case 이름 — `notSignedIn`, `"not_signed_in"` 아님).
//  · 열거, 연관값 있음 → {"$case": 이름, "$value": 값}. 값: 하나면 그 값 그대로(이름표가 있어도 버린다 — Swift 가 1-튜플을
//    만들지 않는다). 둘 이상이고 이름표가 다 있으면 객체, 이름표가 없으면 위치 순서 배열.
//  · 배열 → 배열. Set → 원소 덤프의 정규 글자 순서로 정렬한 배열. 사전 → 키가 String 이면 객체(키는 변환하지 않는다,
//    C§4 #37), 아니면 [키, 값] 쌍 배열을 키 덤프의 정규 글자 순서로.
//  · 정수(모든 폭) → ±2^53 안이면 숫자, 밖이면 {"$int": "0x…"}(64비트 2의 보수 16진). Bool → 불, String·Character → 글자.
//  · Double·Float·CGFloat → {"$f64": "<비트>"}(Float 은 Double 로 넓힌 비트). 글자 칸과 섞이지 않게 꼬리표를 단다.
//  · Date → {"$date": "<1970 기준 초의 Double 비트>"}. Data → {"$data": base64}. UUID → {"$uuid": 소문자}. URL → {"$url": 절대 주소}.
//  · 그 밖(클로저·메타타입·Any 상자 속 모르는 값) → 던진다. 조용히 description 으로 접지 않는다.

package enum GoldenMirror {
    package static let maxDepth = 48

    package static func dump(_ value: Any) throws -> GoldenJSON {
        try dump(value, depth: 0, path: "$")
    }

    private static func dump(_ value: Any, depth: Int, path: String) throws -> GoldenJSON {
        guard depth < maxDepth else { throw GoldenJSONError("\(path): 깊이 \(maxDepth) 를 넘는다(순환 참조?)") }
        // 1) 잎(leaf) 값
        switch value {
        case let flag as Bool: return .bool(flag)
        case let text as String: return .string(text)
        case let char as Character: return .string(String(char))
        case let x as Int: return integer(Int64(x))
        case let x as Int8: return integer(Int64(x))
        case let x as Int16: return integer(Int64(x))
        case let x as Int32: return integer(Int64(x))
        case let x as Int64: return integer(x)
        case let x as UInt: return unsigned(UInt64(x))
        case let x as UInt8: return integer(Int64(x))
        case let x as UInt16: return integer(Int64(x))
        case let x as UInt32: return integer(Int64(x))
        case let x as UInt64: return unsigned(x)
        case let x as Double: return .object(["$f64": .bits(x)])
        case let x as Float: return .object(["$f64": .bits(Double(x))])
        case let x as CGFloat: return .object(["$f64": .bits(Double(x))])
        case let date as Date: return .object(["$date": .bits(date.timeIntervalSince1970)])
        case let data as Data: return .object(["$data": .string(data.base64EncodedString())])
        case let uuid as UUID: return .object(["$uuid": .string(uuid.uuidString.lowercased())])
        case let url as URL: return .object(["$url": .string(url.absoluteString)])
        default: break
        }

        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional:
            guard let wrapped = mirror.children.first?.value else { return .null }
            return try dump(wrapped, depth: depth + 1, path: path)
        case .collection:
            return .array(try mirror.children.enumerated().map { try dump($0.element.value, depth: depth + 1, path: "\(path)[\($0.offset)]") })
        case .set:
            let items = try mirror.children.map { try dump($0.value, depth: depth + 1, path: "\(path){}") }
            return .array(try sortedByCanonicalText(items))
        case .dictionary:
            var pairs: [(GoldenJSON, GoldenJSON)] = []
            var allStringKeys = true
            for child in mirror.children {
                let pair = Mirror(reflecting: child.value).children.map(\.value)
                guard pair.count == 2 else { throw GoldenJSONError("\(path): 사전 항목 모양이 낯설다") }
                if !(pair[0] is String) { allStringKeys = false }
                pairs.append((try dump(pair[0], depth: depth + 1, path: "\(path){key}"),
                              try dump(pair[1], depth: depth + 1, path: "\(path){value}")))
            }
            if allStringKeys {
                var object: [String: GoldenJSON] = [:]
                for (key, item) in pairs {
                    guard case .string(let name) = key else { continue }
                    object[name] = item
                }
                return .object(object)
            }
            let entries = pairs.map { GoldenJSON.array([$0.0, $0.1]) }
            return .array(try sortedByCanonicalText(entries))
        case .enum:
            guard let child = mirror.children.first else {
                return .string(String(describing: value))
            }
            guard let name = child.label else { throw GoldenJSONError("\(path): 이름표 없는 열거 갈래") }
            return .object(["$case": .string(name), "$value": try payload(child.value, depth: depth + 1, path: "\(path).\(name)")])
        case .tuple:
            return try payload(value, depth: depth, path: path)
        case .struct, .class:
            var object: [String: GoldenJSON] = [:]
            var current: Mirror? = mirror
            while let level = current {
                for child in level.children {
                    guard let label = child.label else { throw GoldenJSONError("\(path): 이름 없는 저장 칸") }
                    if label.hasPrefix("$__lazy_storage_$_") { continue }
                    guard object[label] == nil else { throw GoldenJSONError("\(path).\(label): 상위 클래스와 이름이 겹친다") }
                    object[label] = try dump(child.value, depth: depth + 1, path: "\(path).\(label)")
                }
                current = mirror.displayStyle == .class ? level.superclassMirror : nil
            }
            return .object(object)
        default:
            throw GoldenJSONError("\(path): 덤프 규칙에 없는 값 \(type(of: value))")
        }
    }

    /// 열거 연관값: 하나면 그 값, 여럿이면 이름표가 다 있을 때 객체 · 하나도 없을 때 배열.
    private static func payload(_ value: Any, depth: Int, path: String) throws -> GoldenJSON {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .tuple else { return try dump(value, depth: depth, path: path) }
        let children = Array(mirror.children)
        if children.count == 1 { return try dump(children[0].value, depth: depth + 1, path: path) }
        let labels = children.map { $0.label ?? "" }
        let positional = labels.enumerated().allSatisfy { $0.element == ".\($0.offset)" }
        if positional {
            return .array(try children.enumerated().map { try dump($0.element.value, depth: depth + 1, path: "\(path).\($0.offset)") })
        }
        guard labels.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else {
            throw GoldenJSONError("\(path): 연관값 이름표가 일부만 있다(\(labels)) — 규칙 밖")
        }
        var object: [String: GoldenJSON] = [:]
        for child in children { object[child.label!] = try dump(child.value, depth: depth + 1, path: "\(path).\(child.label!)") }
        return .object(object)
    }

    private static func integer(_ x: Int64) -> GoldenJSON {
        if x >= -Int64(GoldenJSON.maxSafeInteger), x <= Int64(GoldenJSON.maxSafeInteger) { return .int(Int(x)) }
        return .object(["$int": .hex64(UInt64(bitPattern: x))])
    }

    private static func unsigned(_ x: UInt64) -> GoldenJSON {
        if x <= UInt64(GoldenJSON.maxSafeInteger) { return .int(Int(x)) }
        return .object(["$int": .hex64(x)])
    }

    private static func sortedByCanonicalText(_ items: [GoldenJSON]) throws -> [GoldenJSON] {
        try items.map { ($0, try $0.canonicalText()) }
            .sorted { GoldenJSON.keyPrecedes($0.1, $1.1) }
            .map(\.0)
    }
}
