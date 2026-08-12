import Foundation
import Observation

// MARK: - 항목 / 파일 모델

/// 할 일 한 줄. **로컬 전용**이라 서버 스키마와 무관하고, 동기화·병합 개념이 없다(한 대에서만 산다).
///
/// 필드가 여섯 개나 되는 이유는 "지우지 않는 것"이 이 기능의 뼈대이기 때문이다:
/// - completedAt: 완료를 Bool 이 아니라 **시각**으로 남긴다. "그날 안에는 보이고 자정에 사라진다"는 규칙이
///   날짜 비교로만 성립하기 때문이다(Bool 이면 언제 끝냈는지 몰라 자정 판정을 못 한다).
/// - deletedAt: 삭제도 시각이다. 5초 되돌리기 창을 물리 삭제로 만들 수 없어 톰스톤으로 둔다.
/// - originDayKey: **처음 만든 날**의 KST yyyyMMdd. 이월 배지('어제'/'3일 전')의 기준이라
///   완료/취소/수정으로 절대 흔들리면 안 된다(updatedAt 을 기준으로 삼으면 고쳐 쓴 순간 배지가 리셋된다).
struct TodoItem: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date? = nil
    var deletedAt: Date? = nil
    var originDayKey: String          // 처음 만든 날의 KST yyyyMMdd
    var isDone: Bool { completedAt != nil }
}

/// 디스크에 실리는 파일 전체. 항목 배열을 그냥 쓰지 않고 봉투를 씌우는 이유는 version 한 칸 때문이다 —
/// 나중에 스키마가 바뀌어도 "이 파일이 몇 세대인지"를 알아야 마이그레이션할지 그냥 읽을지 판단할 수 있다.
struct TodoFile: Codable, Equatable {
    /// 현재 세대. 앞으로 형식이 바뀌면 이 값을 올리고 로드 측에서 분기한다.
    static let currentVersion = 1

    var version: Int
    var items: [TodoItem]

    init(version: Int = TodoFile.currentVersion, items: [TodoItem]) {
        self.version = version
        self.items = items
    }
}

// TodoFile 의 디코드 관용은 **비대칭**이다. 이게 의도다:
// - version 없음 → 1 세대로 본다(사람이 손으로 만든 파일도 읽어 준다).
// - items 없음/깨짐 → **던진다**. 여기서 관대하면 손상 파일이 조용히 빈 목록으로 둔갑해
//   그대로 덮어써진다. 사용자 데이터는 캐시와 달라서 "못 읽겠으면 버린다"가 답이 아니다(호출부가 백업한다).
extension TodoFile {
    enum CodingKeys: String, CodingKey {
        case version, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try c.decode([TodoItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(items, forKey: .items)
    }
}

// MARK: - 규칙 (순수 함수 · 값으로 검증 가능)

/// 투두의 모든 판정을 값으로만 내리는 순수 규칙 모음. 뷰도 스토어도 여기 답을 따르므로,
/// "화면을 띄워야 알 수 있는 규칙"이 하나도 남지 않는다(자정 경계 같은 건 실행 시각에 기대면 검증이 불가능하다).
enum TodoRules {
    /// 제목 상한. 넘으면 **거부**한다(잘라 저장하지 않는다) — 사용자가 쓴 문장을 앱이 몰래 훼손하면 안 된다.
    static let maxTitleLength = 100
    /// 글자수 카운터를 노출하기 시작하는 길이. 평소엔 숨겨 두고 한계에 다가갈 때만 보여준다.
    static let counterVisibleFrom = 90
    /// 이 일수 이상 이월된 미완료는 '오래된 항목' 접힌 영역으로 조용히 내린다(지우지는 않는다).
    static let oldItemDays = 7
    /// 완료/삭제 후 이 일수가 지나면 파일에서 제거한다. 화면 규칙이 아니라 **파일 비대 방지**용이다.
    static let purgeDays = 90
    /// 삭제 되돌리기 창(초). 삭제는 그 자리에서 이 시간 동안 `삭제됨 [되돌리기]` 로 남는다.
    static let undoSeconds: Double = 5

    // MARK: 정규화

    /// 제목 정규화: 유니코드 정준 결합 → 제어/포맷 문자 제거 → 공백 1칸으로 접기 → 앞뒤 공백 제거.
    /// WorkTimerStore.normalizedDisplayName 의 관용구를 따르되 **한 군데가 다르다**: 줄바꿈·탭을
    /// 지우지 않고 **공백으로 바꾼다**. 별명과 달리 투두는 여러 줄 텍스트를 붙여 넣는 일이 흔한데,
    /// 제어문자를 통째로 지우면 "회의\n준비" 가 "회의준비" 로 들러붙어 단어가 깨진다.
    static func normalizedTitle(_ raw: String) -> String {
        let composed = raw.precomposedStringWithCanonicalMapping
        var cleaned = String.UnicodeScalarView()
        for scalar in composed.unicodeScalars {
            if scalar == "\u{200D}" {           // ZWJ 는 이모지 결합용이라 지우면 그림이 쪼개진다
                cleaned.append(scalar)
                continue
            }
            let category = scalar.properties.generalCategory
            if category == .control || category == .format {
                // 줄바꿈·탭 같은 '공백성' 제어문자만 공백으로 살려 두고, 나머지 제어문자는 버린다.
                if scalar.properties.isWhitespace { cleaned.append(" ") }
                continue
            }
            cleaned.append(scalar)
        }
        return String(cleaned)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    // MARK: 날짜

    /// KST yyyyMMdd. 하루 경계 계산은 새로 만들지 않고 MilestoneTracker 의 것을 그대로 쓴다 —
    /// 앱 안에 '하루'의 정의가 둘이 되는 순간 자정 근처에서 기능마다 다른 날을 가리킨다.
    static func dayKey(_ date: Date) -> String {
        MilestoneTracker.dayKey(date)
    }

    /// dayKey 를 그 날 KST 0시로 되돌린다. 형식이 아니면 nil — 손상 파일의 쓰레기 문자열이
    /// 이월 일수 계산에 들어와 엉뚱한 배지를 만드는 걸 막는다.
    private static func dayStart(fromDayKey key: String) -> Date? {
        guard key.count == 8, key.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let digits = Array(key)
        guard let year = Int(String(digits[0..<4])),
              let month = Int(String(digits[4..<6])),
              let day = Int(String(digits[6..<8]))
        else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return MilestoneTracker.kstCalendar.date(from: comps)
    }

    /// 만든 날부터 오늘까지 넘어온 '날 수'. 시간 차(86400초)가 아니라 **KST 달력 날짜 차**다 —
    /// 밤 11시에 적고 새벽 1시에 보면 2시간밖에 안 지났어도 사용자에겐 '어제 적은 것'이다.
    /// 키가 깨졌거나 미래(시계 되돌림)면 0 — 배지는 '지나간 날'만 말한다.
    static func carriedDays(originDayKey: String, todayKey: String) -> Int {
        guard let origin = dayStart(fromDayKey: originDayKey),
              let today = dayStart(fromDayKey: todayKey)
        else { return 0 }
        let days = MilestoneTracker.kstCalendar.dateComponents([.day], from: origin, to: today).day ?? 0
        return max(0, days)
    }

    /// 이월 배지 문구. 오늘 만든 항목엔 배지가 없다(nil) — 대부분의 항목이 오늘 것이라
    /// 여기에 '오늘' 배지를 달면 목록 전체가 배지로 뒤덮여 이월이라는 신호가 죽는다.
    static func carryBadge(days: Int) -> String? {
        switch days {
        case ..<1: return nil
        case 1: return "어제"
        default: return "\(days)일 전"
        }
    }

    // MARK: 노출 판정

    /// 이 항목이 오늘 목록에 뜨는가. **제품 규칙의 전부가 이 한 줄이다**:
    /// 미완료는 끝날 때까지 계속 보이고(자동 삭제·자동 이동 없음), 완료는 그날 안에는 취소선으로 남아
    /// '오늘 한 일'을 이루다가 자정을 넘기면 조용히 사라진다. 톰스톤(삭제됨)은 어느 쪽이든 안 보인다.
    static func isVisible(_ item: TodoItem, todayKey: String) -> Bool {
        guard item.deletedAt == nil else { return false }
        guard let completedAt = item.completedAt else { return true }
        return dayKey(completedAt) == todayKey
    }

    /// 하단 '오래된 항목 (N)' 으로 내릴 대상. 완료한 항목은 아무리 오래돼도 여기 오지 않는다 —
    /// 완료는 어차피 자정에 사라지므로 '오래된 완료'라는 상태 자체가 존재하지 않는다.
    static func isOld(_ item: TodoItem, todayKey: String) -> Bool {
        guard item.completedAt == nil else { return false }
        return carriedDays(originDayKey: item.originDayKey, todayKey: todayKey) >= oldItemDays
    }

    /// 오늘 화면에 그릴 목록(완료 포함)을 걸러 정렬한다.
    static func visible(_ items: [TodoItem], todayKey: String) -> [TodoItem] {
        visible(items, todayKey: todayKey, keepingDeleted: nil)
    }

    /// 되돌리기 창(5초) 동안 방금 지운 항목을 **그 자리에** 남기기 위한 변형.
    /// 삭제가 즉시 사라지는 대신 `삭제됨 [되돌리기]` 로 바뀌어야 한다는 규칙 때문에, 톰스톤 하나를
    /// 예외로 통과시킬 길이 필요하다. createdAt 기준 정렬이라 통과된 항목은 원래 위치를 그대로 지킨다.
    static func visible(_ items: [TodoItem], todayKey: String, keepingDeleted id: UUID?) -> [TodoItem] {
        items
            .filter { isVisible($0, todayKey: todayKey) || ($0.deletedAt != nil && $0.id == id) }
            .sorted(by: ordersBefore)
    }

    /// 목록 순서. 미완료가 항상 위이고, 완료는 그 아래에 '오늘 한 일' 더미로 쌓인다.
    /// 완전 동률(같은 고정 clock 으로 만든 픽스처)에서도 순서가 흔들리지 않게 id 로 못을 박는다 —
    /// 렌더 테스트가 정렬 때문에 깜빡이면 안 된다.
    private static func ordersBefore(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.isDone {
            // 완료끼리는 방금 끝낸 것이 완료 구역 맨 위 — 체크한 항목이 눈앞에서 사라지지 않고 바로 아래로 내려간다.
            let ac = a.completedAt ?? a.updatedAt
            let bc = b.completedAt ?? b.updatedAt
            if ac != bc { return ac > bc }
        }
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    // MARK: 파일 비대 방지

    /// purgeDays 보다 오래된 **완료/삭제** 항목을 배열에서 뺀다. 미완료는 아무리 오래돼도 남는다 —
    /// 이 기능엔 자동 삭제가 없고(사용자 확정), 오래된 미완료는 '오래된 항목' 영역이 맡는다.
    /// 화면에서 이미 안 보이는(완료는 자정에, 삭제는 즉시) 것들만 정리하므로 사용자가 알아챌 변화가 없다.
    static func pruned(_ items: [TodoItem], now: Date) -> [TodoItem] {
        let cutoff = MilestoneTracker.kstCalendar.date(byAdding: .day, value: -purgeDays, to: now)
            ?? now.addingTimeInterval(-Double(purgeDays) * 86_400)
        return items.filter { item in
            if let deletedAt = item.deletedAt, deletedAt < cutoff { return false }
            if let completedAt = item.completedAt, completedAt < cutoff { return false }
            return true
        }
    }
}

// MARK: - 파일 저장소 (원자적 쓰기 · 손상 시 보존)

/// todos.json 의 로드/세이브. 토큰 캐시 저장소와 모양은 닮았지만 **한 가지가 다르다**:
/// 캐시는 못 읽으면 버리고 다시 만들면 그만이지만, 이건 사용자가 손으로 쓴 문장이라 다시 만들 길이 없다.
/// 그래서 load 는 실패를 삼키지 않고 던지고(호출부가 원본을 백업하게), save 는 원자적 쓰기로 쓰다 만 파일을 남기지 않는다.
enum TodoFileStore {
    static let currentVersion = TodoFile.currentVersion

    /// 로그인 사용자별로 파일을 가른다. 로그인 전(userID nil)은 `todos.local.json` 이다 —
    /// 계정 없이 적어 둔 것이 나중에 로그인한 사람 목록에 섞여 들어가지 않게 처음부터 분리해 둔다.
    static func defaultURL(userID: String?) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // userID 는 외부에서 온 문자열이라 그대로 경로에 붙이면 '..' 하나로 폴더를 벗어난다.
        // 파일명에 안전한 글자만 남긴다(UUID 형태면 원형 그대로 통과한다).
        let safe = (userID ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let suffix = safe.isEmpty ? "local" : safe
        return base.appendingPathComponent("aing-check/todos.\(suffix).json", isDirectory: false)
    }

    /// 파일이 없거나 비어 있으면 **빈 파일**로 시작한다(첫 실행 = 정상 경로, 예외 아님).
    /// 내용이 있는데 디코드가 안 되면 던진다 — 그래야 호출부가 원본을 백업하고 나서 새로 출발할 수 있다.
    static func load(from url: URL) throws -> TodoFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TodoFile(items: [])
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return TodoFile(items: []) }
        return try JSONDecoder().decode(TodoFile.self, from: data)
    }

    /// 상위 폴더를 만들고 원자적으로 쓴다. 쓰는 도중 앱이 죽어도 반쯤 쓰인 JSON 이 남지 않는다
    /// (남으면 다음 실행이 그걸 손상으로 보고 목록 전체를 백업으로 치워 버린다).
    static func save(_ file: TodoFile, to url: URL) throws {
        // Date 는 기본 전략(참조일 기준 실수)으로 둔다. ISO8601 은 보기 좋지만 초 단위로 잘려
        // 저장→로드 왕복에서 completedAt 이 미세하게 달라진다 — 자정 판정을 값으로 검증할 수 없게 된다.
        let data = try JSONEncoder().encode(file)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// 손상 파일을 옮겨 둘 경로. 같은 폴더에 `todos.local.json.corrupt-20260812-134500` 로 남긴다.
    /// 확장자를 .json 으로 유지하지 않는 이유는 다음 실행이 그걸 다시 목록으로 착각해 집어삼키지 않게 하기 위함이고,
    /// 시각을 붙이는 이유는 손상이 반복돼도 이전 백업을 덮어쓰지 않게 하기 위함이다(사용자 문장은 한 번도 못 버린다).
    static func corruptedBackupURL(for url: URL, now: Date) -> URL {
        let c = MilestoneTracker.kstCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: now
        )
        let stamp = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)", isDirectory: false)
    }
}

// MARK: - 스토어 (@MainActor · 메모리가 진실 · 변경마다 저장)

/// 투두 목록의 유일한 소유자. 서버가 없으므로 여기 메모리가 곧 진실이고, 디스크는 그 사본일 뿐이다.
/// 이 방향(메모리 → 디스크)을 고정했기 때문에 저장 실패를 조용히 삼켜도 안전하다 —
/// 사용자는 계속 쓰던 목록을 보고, 다음 변경에서 파일 전체가 다시 쓰인다(부분 저장이 없다).
@MainActor @Observable final class TodoListStore {
    private(set) var items: [TodoItem] = []

    private let fileURL: URL
    private let clock: () -> Date

    init(fileURL: URL, clock: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.clock = clock
        // 복원은 init 에서 끝낸다. 보드가 열릴 때 로드하면 첫 프레임이 빈 목록으로 한 번 깜빡인다.
        reload()
    }

    /// 오늘의 KST dayKey. 뷰는 이 값 하나로 이월 배지·완료 노출을 모두 판정한다(뷰가 Date 를 직접 다루지 않게).
    var todayKey: String { TodoRules.dayKey(clock()) }

    /// 디스크에서 다시 읽어 온다. 손상 파일은 **백업으로 옮기고** 빈 목록으로 출발한다 —
    /// 그냥 덮어쓰면 사용자가 적어 둔 문장이 영원히 사라진다(캐시라면 그래도 됐겠지만 이건 원본이다).
    func reload() {
        let now = clock()
        let loaded: [TodoItem]
        do {
            loaded = try TodoFileStore.load(from: fileURL).items
        } catch {
            try? FileManager.default.moveItem(
                at: fileURL, to: TodoFileStore.corruptedBackupURL(for: fileURL, now: now)
            )
            loaded = []
        }
        let kept = TodoRules.pruned(loaded, now: now)
        if items != kept { items = kept }      // @Observable 은 같은 값 재대입도 관찰자를 깨운다
        // 정리로 줄었으면 그 결과를 디스크에도 반영해, 다음 실행이 같은 낡은 항목을 또 읽고 또 버리지 않게 한다.
        if kept.count != loaded.count { persist() }
    }

    /// 새 항목을 목록 맨 앞에 넣는다. 빈 제목과 상한 초과는 **아무 일도 하지 않고 nil** 이다 —
    /// 특히 초과는 잘라서 저장하지 않는다(입력 단계에서 이미 막지만, 붙여넣기 경로를 위해 여기서도 거절한다).
    @discardableResult
    func add(_ rawTitle: String) -> TodoItem? {
        let title = TodoRules.normalizedTitle(rawTitle)
        guard !title.isEmpty, title.count <= TodoRules.maxTitleLength else { return nil }
        let now = clock()
        let item = TodoItem(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            deletedAt: nil,
            originDayKey: TodoRules.dayKey(now)
        )
        items.insert(item, at: 0)
        persist()
        return item
    }

    /// 완료/완료취소를 뒤집는다. **originDayKey 는 절대 건드리지 않는다** —
    /// 이월 배지의 기준이라, 어제 적은 걸 오늘 체크했다 풀면 배지가 사라지는 버그가 된다.
    func toggleDone(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let now = clock()
        var item = items[idx]
        item.completedAt = item.completedAt == nil ? now : nil
        item.updatedAt = now
        if items[idx] != item { items[idx] = item }
        persist()
    }

    /// 인라인 수정 커밋. 정규화 후 빈 제목/상한 초과는 무시한다(취소와 같은 결과 — 원래 문장이 남는다).
    /// 내용이 그대로면 updatedAt 도 건드리지 않는다: 의미 없는 저장과 관찰자 발화를 함께 막는다.
    func rename(_ id: UUID, to rawTitle: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let title = TodoRules.normalizedTitle(rawTitle)
        guard !title.isEmpty, title.count <= TodoRules.maxTitleLength else { return }
        guard items[idx].title != title else { return }
        items[idx].title = title
        items[idx].updatedAt = clock()
        persist()
    }

    /// 삭제는 톰스톤이다(배열에서 빼지 않는다). 5초 되돌리기 창 동안 그 자리에 남아 있어야 하는데,
    /// 물리 삭제 후 되살리면 원래 위치·id 를 복원할 수 없다. 실제 제거는 pruned 가 90일 뒤에 조용히 한다.
    func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].deletedAt == nil else { return }
        let now = clock()
        items[idx].deletedAt = now
        items[idx].updatedAt = now
        persist()
    }

    /// 되돌리기. 톰스톤만 벗기므로 제목·완료 상태·만든 날이 삭제 직전 그대로 돌아온다.
    func undoDelete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].deletedAt != nil else { return }
        items[idx].deletedAt = nil
        items[idx].updatedAt = clock()
        persist()
    }

    /// 변경마다 전체를 다시 쓴다. 실패는 삼킨다 — 디스크가 잠깐 말썽이라고 해서 사용자의 타이핑을
    /// 막거나 경고창을 띄우는 건 과하고, 메모리가 진실이므로 다음 변경에서 통째로 재시도된다.
    private func persist() {
        try? TodoFileStore.save(TodoFile(items: items), to: fileURL)
    }
}
