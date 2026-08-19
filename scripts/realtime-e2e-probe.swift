#!/usr/bin/env swift
//
// 초인종 배달 e2e 프로브 — **폴링 제거의 하드 게이트**.
//
// ── 이 프로브가 증명하는 것 (그리고 증명하지 못하는 것) ──
// DB 레벨 확인(`poke_ring` 이 'sent' 를 돌려준다)은 **쓰기 확인이지 배달 확인이 아니다.** rid 되읽기는
// 같은 트랜잭션의 미커밋 행을 보는 것이고, Realtime 서비스가 그 커밋된 행을 구독자에게 미는지는
// 배포 시점에도 런타임에도 아무도 확인하지 않는다. 실제로 이 프로젝트의 `realtime.messages` 에는
// 파티션이 0개이고 `realtime.send` 는 모든 예외를 삼킨다(agent-server 실측) — 즉 지금 배포하면
// 모든 ring 이 'failed' 다. 그 사실을 **밖에서** 재는 것이 이 프로브의 존재 이유다.
//
// 증명하는 것: private 채널 `poke:<uid>` 를 구독한 클라이언트가 poke_ring 이 쓴 브로드캐스트를
//              **실제로 수신한다**(= realtime.messages RLS 정책 + 파티션 + 배달 파이프라인이 전부 산다).
// 증명하지 못하는 것: 앱의 LiveRealtimeTransport 자체(이 스크립트는 프레임을 직접 만든다. 앱의 프레임
//              조립·해석은 RealtimeLinkTests 의 순수 테스트가 지킨다). 그리고 poke_user 의 게이트들
//              (자리비움·집중모드·쿨타임) — 그건 서버 마이그레이션 사후 단언이 이미 지킨다.
//
// ── 실행법 ──
//   export CHECK_SUPABASE_ANON_KEY=...            # 필수
//   export CHECK_PROBE_EMAIL=...                  # 수신자(구독하는 쪽) 계정
//   export CHECK_PROBE_PASSWORD=...
//   export CHECK_SUPABASE_SERVICE_ROLE_KEY=...    # 발사자(poke_ring 을 부르는 쪽). service_role 전용 함수다.
//   swift scripts/realtime-e2e-probe.swift            # 두 프로세스(부모가 listen/fire 를 각각 띄운다)
//   swift scripts/realtime-e2e-probe.swift listen     # 한 쪽만 수동으로
//   swift scripts/realtime-e2e-probe.swift fire <uid>
//
// 종료 코드 0 = 배달 확인. 그 밖 = 실패(사유가 stderr 에 남는다).
//
// **서버 마이그레이션이 적용되기 전에는 이 프로브가 실패하는 것이 정상이다**(poke_ring 이 없다).
// 실패하면 v0.2.34 는 리얼타임만 빼고 나머지를 낸다 — 그것이 사장님 확정 ②다.

import Foundation

// MARK: - 공통

let projectURLString = ProcessInfo.processInfo.environment["CHECK_SUPABASE_URL"]
    ?? "https://xfnhfjvubetkdnfkfljg.supabase.co"
let anonKey = ProcessInfo.processInfo.environment["CHECK_SUPABASE_ANON_KEY"] ?? ""
let serviceRoleKey = ProcessInfo.processInfo.environment["CHECK_SUPABASE_SERVICE_ROLE_KEY"] ?? ""
let probeEmail = ProcessInfo.processInfo.environment["CHECK_PROBE_EMAIL"] ?? ""
let probePassword = ProcessInfo.processInfo.environment["CHECK_PROBE_PASSWORD"] ?? ""
let listenTimeout = Double(ProcessInfo.processInfo.environment["CHECK_PROBE_TIMEOUT"] ?? "") ?? 30

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("[probe] 실패: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func log(_ message: String) {
    FileHandle.standardError.write(("[probe] " + message + "\n").data(using: .utf8)!)
}

func post(path: String, apiKey: String, bearer: String?, body: [String: Any], query: String = "") -> [String: Any]? {
    guard let url = URL(string: projectURLString + path + query) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer " + (bearer ?? apiKey), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let semaphore = DispatchSemaphore(value: 0)
    var result: [String: Any]?
    var status = 0
    URLSession.shared.dataTask(with: request) { data, response, _ in
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let data {
            result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if result == nil, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                result = ["_raw": text]
            }
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + 20)
    if status >= 400 { log("HTTP \(status) \(path) → \(result ?? [:])") }
    return status < 400 ? result : nil
}

/// 이메일/비밀번호로 로그인해 (access token, user id) 를 얻는다.
func signIn() -> (token: String, userID: String) {
    guard !anonKey.isEmpty else { fail("CHECK_SUPABASE_ANON_KEY 가 비어 있다") }
    guard !probeEmail.isEmpty, !probePassword.isEmpty else { fail("CHECK_PROBE_EMAIL / CHECK_PROBE_PASSWORD 가 비어 있다") }
    guard let json = post(
        path: "/auth/v1/token",
        apiKey: anonKey,
        bearer: anonKey,
        body: ["email": probeEmail, "password": probePassword],
        query: "?grant_type=password"
    ),
        let token = json["access_token"] as? String,
        let user = json["user"] as? [String: Any],
        let uid = user["id"] as? String
    else { fail("로그인 실패") }
    return (token, uid)
}

// MARK: - listen (구독하는 쪽)

func runListen() -> Never {
    let (token, uid) = signIn()
    // 접두사 **없는** 채널명이 서버 public.poke_topic(uuid) 의 반환값이고,
    // Phoenix wire 의 topic 은 여기에 `realtime:` 을 붙인 것이다. 둘은 같은 것의 두 표현이다.
    let channel = "poke:\(uid)"
    let wireTopic = "realtime:\(channel)"

    guard var components = URLComponents(string: projectURLString) else { fail("URL 파싱 실패") }
    components.scheme = "wss"
    components.path = "/realtime/v1/websocket"
    components.queryItems = [
        URLQueryItem(name: "apikey", value: anonKey),
        URLQueryItem(name: "vsn", value: "1.0.0")
    ]
    guard let socketURL = components.url else { fail("소켓 URL 조립 실패") }

    let task = URLSession.shared.webSocketTask(with: socketURL)
    task.resume()

    // ★ config.private = true 가 이 페이로드의 존재 이유다. 빠뜨리면 조인이 그냥 성공하고
    //   realtime.messages RLS 가 **아예 상담되지 않는다** — 그러면 프로브가 통과해도
    //   "정책이 산다"를 증명하지 못한 채 초록이 된다(가장 나쁜 종류의 거짓 확신).
    let join: [String: Any] = [
        "topic": wireTopic,
        "event": "phx_join",
        "ref": "1",
        "join_ref": "1",
        "payload": [
            "config": [
                "broadcast": ["self": false, "ack": false],
                "presence": ["key": ""],
                "postgres_changes": [],
                "private": true
            ],
            "access_token": token
        ]
    ]
    let joinData = try! JSONSerialization.data(withJSONObject: join)
    task.send(.string(String(data: joinData, encoding: .utf8)!)) { error in
        if let error { fail("조인 전송 실패: \(error)") }
    }

    let done = DispatchSemaphore(value: 0)
    var received = false
    var joined = false
    var rejection: String?

    func receiveNext() {
        task.receive { result in
            switch result {
            case .failure(let error):
                rejection = rejection ?? "소켓 오류: \(error)"
                done.signal()
            case .success(let message):
                var text: String?
                if case .string(let value) = message { text = value }
                if case .data(let data) = message { text = String(data: data, encoding: .utf8) }
                if let text,
                   let object = (try? JSONSerialization.jsonObject(with: text.data(using: .utf8)!)) as? [String: Any] {
                    let event = object["event"] as? String
                    let payload = object["payload"] as? [String: Any] ?? [:]
                    if event == "phx_reply", (object["ref"] as? String) == "1" {
                        if (payload["status"] as? String) == "ok" {
                            joined = true
                            // 부모(또는 사람)가 이 줄을 보고 나서 발사한다. 순서가 뒤집히면
                            // 브로드캐스트는 재생이 없으므로 프로브가 확정적으로 실패한다.
                            print("READY \(uid)")
                            fflush(stdout)
                        } else {
                            rejection = "조인 거절: \(payload)"
                            done.signal()
                            return
                        }
                    }
                    if event == "broadcast" {
                        let name = (payload["event"] as? String) ?? ""
                        log("브로드캐스트 수신: \(name) payload=\(payload)")
                        if name == "ring" { received = true; done.signal(); return }
                    }
                    if event == "phx_error" || event == "phx_close" {
                        rejection = rejection ?? "채널 종료: \(object)"
                        done.signal()
                        return
                    }
                }
                receiveNext()
            }
        }
    }
    receiveNext()

    _ = done.wait(timeout: .now() + listenTimeout)
    task.cancel(with: .goingAway, reason: nil)

    if received {
        print("RESULT ok")
        exit(0)
    }
    if !joined {
        fail(rejection ?? "조인 응답이 \(Int(listenTimeout))초 안에 오지 않았다")
    }
    fail(rejection ?? "조인은 됐는데 \(Int(listenTimeout))초 안에 ring 이 오지 않았다 — 배달 파이프라인(파티션/정책/Broadcast-from-Database)을 의심하라")
}

// MARK: - fire (초인종을 울리는 쪽)

func runFire(targetUID: String) -> Never {
    guard !serviceRoleKey.isEmpty else { fail("CHECK_SUPABASE_SERVICE_ROLE_KEY 가 비어 있다 (poke_ring 은 service_role 전용이다)") }
    guard let json = post(
        path: "/rest/v1/rpc/poke_ring",
        apiKey: serviceRoleKey,
        bearer: serviceRoleKey,
        body: ["p_to": targetUID]
    ) else { fail("poke_ring 호출 실패 — 마이그레이션이 아직 적용되지 않았을 수 있다") }
    log("poke_ring → \(json)")
    // 'failed' 는 realtime.send 가 삼켰다는 뜻이다(파티션 0개가 대표 원인). 그래도 listen 쪽 판정이
    // 최종 답이므로 여기서 죽이지 않는다 — 두 답이 어긋나는 것 자체가 진단 정보다.
    exit(0)
}

// MARK: - 두 프로세스 조립

func runBoth() -> Never {
    let scriptPath = CommandLine.arguments[0]
    let swiftPath = "/usr/bin/swift"

    let listener = Process()
    listener.executableURL = URL(fileURLWithPath: swiftPath)
    listener.arguments = [scriptPath, "listen"]
    let out = Pipe()
    listener.standardOutput = out
    do { try listener.run() } catch { fail("listen 프로세스 실행 실패: \(error)") }

    // READY 를 기다린다. 브로드캐스트는 **재생이 없으므로** 구독보다 먼저 쏘면 확정적으로 못 받는다.
    var targetUID: String?
    let readyDeadline = Date().addingTimeInterval(listenTimeout)
    var buffer = Data()
    while Date() < readyDeadline, targetUID == nil {
        let chunk = out.fileHandleForReading.availableData
        if chunk.isEmpty { break }
        buffer.append(chunk)
        if let text = String(data: buffer, encoding: .utf8) {
            for line in text.split(separator: "\n") where line.hasPrefix("READY ") {
                targetUID = String(line.dropFirst("READY ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
    }
    guard let uid = targetUID else {
        listener.terminate()
        fail("구독자가 준비되지 않았다(READY 없음)")
    }
    log("구독 완료: \(uid) — 이제 초인종을 울린다")

    let firer = Process()
    firer.executableURL = URL(fileURLWithPath: swiftPath)
    firer.arguments = [scriptPath, "fire", uid]
    do { try firer.run() } catch { listener.terminate(); fail("fire 프로세스 실행 실패: \(error)") }
    firer.waitUntilExit()

    // 나머지 출력을 마저 읽어 RESULT 를 본다.
    let rest = out.fileHandleForReading.readDataToEndOfFile()
    buffer.append(rest)
    listener.waitUntilExit()
    let text = String(data: buffer, encoding: .utf8) ?? ""
    if text.contains("RESULT ok"), listener.terminationStatus == 0 {
        print("[probe] 통과 — 초인종이 실제로 배달됐다. poke_ring_strict() 를 true 로 올려도 된다.")
        exit(0)
    }
    fail("배달 확인 실패(listener 종료코드 \(listener.terminationStatus))")
}

// MARK: - 진입

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "both"
switch mode {
case "listen": runListen()
case "fire":
    guard CommandLine.arguments.count > 2 else { fail("사용법: fire <target-uid>") }
    runFire(targetUID: CommandLine.arguments[2])
default: runBoth()
}
