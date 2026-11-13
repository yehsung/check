import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 서버 왕복 하나(경로 + JSON 본문 → 상태 코드 + 본문). 시험은 가짜를 넣는다 — 운영 서버에 닿지 않는다.
protocol ScanTransport: Sendable {
    func post(path: String, body: Data) async throws -> (status: Int, body: Data)
}

struct URLSessionTransport: ScanTransport {
    let server: URL
    let anonKey: String

    func post(path: String, body: Data) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("aing-scan/\(AingScanBuild.version)", forHTTPHeaderField: "User-Agent")
        // 리눅스 Foundation 에는 async data(for:) 가 판마다 달라 완료 처리기로 감싼다.
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: (status, data ?? Data()))
            }.resume()
        }
    }
}

enum ScanServerError: Error, Equatable {
    /// 연결 코드가 틀렸거나 만료됐거나 이미 쓰였다.
    case codeRejected(String)
    /// 서버가 이 키를 모른다(끊긴 기계).
    case revoked
    case http(Int)
    case malformed
}

/// 서버 함수 세 개(scanner_link · scanner_upload · scanner_unlink)의 얇은 손잡이.
struct ScanServer: Sendable {
    let transport: ScanTransport

    struct LinkResult: Decodable, Equatable {
        let deviceId: String
        let deviceKey: String
    }

    struct UploadResult: Decodable, Equatable {
        let ok: Bool
        let reason: String?
    }

    func link(code: String, name: String, os: String, previousDeviceId: String?) async throws -> LinkResult {
        struct Body: Encodable {
            let pCode: String
            let pName: String
            let pOs: String
            let pVersion: String
            let pPrevDeviceId: String?
        }
        let data = try await call("rest/v1/rpc/scanner_link", Body(
            pCode: code, pName: name, pOs: os, pVersion: AingScanBuild.version, pPrevDeviceId: previousDeviceId
        ))
        struct Envelope: Decodable {
            let ok: Bool
            let reason: String?
            let deviceId: String?
            let deviceKey: String?
        }
        guard let env = try? ScanStorage.decoder().decode(Envelope.self, from: data) else { throw ScanServerError.malformed }
        guard env.ok, let id = env.deviceId, let key = env.deviceKey, !id.isEmpty, !key.isEmpty else {
            throw ScanServerError.codeRejected(env.reason ?? "rejected")
        }
        return LinkResult(deviceId: id, deviceKey: key)
    }

    func upload(key: String, payload: ScanUploadPayload) async throws -> UploadResult {
        struct Body: Encodable {
            let pKey: String
            let pPayload: ScanUploadPayload
        }
        let data = try await call("rest/v1/rpc/scanner_upload", Body(pKey: key, pPayload: payload))
        guard let result = try? ScanStorage.decoder().decode(UploadResult.self, from: data) else { throw ScanServerError.malformed }
        if !result.ok, result.reason == "revoked" { throw ScanServerError.revoked }
        return result
    }

    func unlink(key: String) async throws {
        struct Body: Encodable { let pKey: String }
        _ = try await call("rest/v1/rpc/scanner_unlink", Body(pKey: key))
    }

    private func call<B: Encodable>(_ path: String, _ body: B) async throws -> Data {
        let encoded = try ScanStorage.encoder().encode(body)
        let (status, data) = try await transport.post(path: path, body: encoded)
        guard (200..<300).contains(status) else { throw ScanServerError.http(status) }
        return data
    }
}
