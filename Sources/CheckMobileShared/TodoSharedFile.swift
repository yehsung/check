import Foundation

/// App Group 안 할 일 파일의 위치와 **프로세스 사이 조정 읽기·쓰기**(SPEC-ios §3.2 · §4).
///
/// 앱(코어 `TodoListStore`)과 위젯 인텐트(`ToggleTodoIntent`)가 같은 파일을 고친다. 한 프로세스 안의 원자적 쓰기
/// (`.atomic`)만으로는 **읽고-고치고-쓰기** 사이에 다른 프로세스의 쓰기가 끼어 한쪽 변경이 사라진다. 그래서 두 프로세스 모두
/// 이 도우미의 `coordinatedUpdate` 로 한 조정 구간 안에서 읽고 쓴다(NSFileCoordinator 는 같은 URL 의 조정자끼리 직렬화한다).
///
/// 파일 모양은 코어 `TodoFile`(JSON) 그대로다 — 이 모듈은 코어를 모르므로 바이트만 나른다.
public enum TodoSharedFile {
    /// `<폴더>/todos.<uid>.json`. uid 는 파일명에 안전한 글자만 남긴다(맥 `TodoFileStore.defaultURL` 과 같은 규칙 — `..` 로 폴더를 못 벗어난다).
    /// 로그인 전(nil·빈 값)은 `todos.local.json`.
    public static func url(in directory: URL, userID: String?) -> URL {
        let safe = (userID ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let suffix = safe.isEmpty ? "local" : safe
        return directory.appendingPathComponent("todos.\(suffix).json", isDirectory: false)
    }

    public enum CoordinationError: Error, Equatable {
        case coordinationFailed(String)
    }

    /// 조정 읽기. 파일이 없으면 nil.
    public static func coordinatedRead(at url: URL) throws -> Data? {
        var result: Result<Data?, Error> = .success(nil)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            guard FileManager.default.fileExists(atPath: readURL.path) else {
                result = .success(nil)
                return
            }
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError {
            throw CoordinationError.coordinationFailed(coordinationError.localizedDescription)
        }
        return try result.get()
    }

    /// 조정 쓰기(원자적). 폴더가 없으면 만든다.
    public static func coordinatedWrite(_ data: Data, to url: URL) throws {
        try coordinatedUpdate(at: url) { _ in data }
    }

    /// 한 조정 구간 안에서 읽고(없으면 nil) 고친 값을 쓴다. `transform` 이 nil 을 돌려주면 쓰지 않는다.
    /// 돌려준 값은 transform 이 만든 새 바이트(쓰지 않았으면 nil).
    @discardableResult
    public static func coordinatedUpdate(at url: URL, _ transform: (Data?) throws -> Data?) throws -> Data? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var result: Result<Data?, Error> = .success(nil)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [.forMerging], error: &coordinationError) { writeURL in
            result = Result {
                let current = FileManager.default.fileExists(atPath: writeURL.path) ? try Data(contentsOf: writeURL) : nil
                guard let next = try transform(current) else { return nil }
                try next.write(to: writeURL, options: .atomic)
                return next
            }
        }
        if let coordinationError {
            throw CoordinationError.coordinationFailed(coordinationError.localizedDescription)
        }
        return try result.get()
    }

    /// 조정 삭제(로그아웃). 없으면 조용히 끝난다.
    public static func coordinatedRemove(at url: URL) {
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [.forDeleting], error: &coordinationError) { deleteURL in
            try? FileManager.default.removeItem(at: deleteURL)
        }
    }
}
