// 화면에 떠 있는 창을 센다(창을 만들지 않는다). vm.sh 가 "Fusion 창 증가 0" 을 재는 데 쓴다.
// 사용: swift cgwindows.swift [--owner-regex RE] [--pids 1,2,3]
// 출력: {"count":N,"byOwner":{"이름":n,…}} — 소유자 이름 정규식 또는 PID 목록(에이전트가 띄운 자손, H L-6)에 맞는 화면 위 창만.
import CoreGraphics
import Foundation

var ownerRegex: String?
var pids = Set<Int>()
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--owner-regex": ownerRegex = it.next()
    case "--pids": pids = Set((it.next() ?? "").split(separator: ",").compactMap { Int($0) })
    default:
        FileHandle.standardError.write("cgwindows: 모르는 인자 \(a)\n".data(using: .utf8)!)
        exit(64)
    }
}

let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var count = 0
var byOwner: [String: Int] = [:]
for w in info {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let pid = w[kCGWindowOwnerPID as String] as? Int ?? -1
    let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
    var match = pids.contains(pid)
    if let re = ownerRegex, owner.range(of: re, options: .regularExpression) != nil { match = true }
    if match && alpha > 0 {
        count += 1
        byOwner[owner, default: 0] += 1
    }
}
let owners = byOwner.keys.sorted().map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\":\(byOwner[$0]!)" }.joined(separator: ",")
print("{\"count\":\(count),\"byOwner\":{\(owners)}}")
