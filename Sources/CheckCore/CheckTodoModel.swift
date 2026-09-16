import Foundation
import Observation

// MARK: - 항목 / 파일 모델

/// 할 일 한 줄. v0.3.30 부터 **계정에 저장돼 기기끼리 맞춰진다**(서버 `todo_items` · `todo_sync`, 계약 1.2).
/// 기기마다 로컬 파일이 사본을 들고 서버와는 "보낼 것 + watermark" 만 주고받는다 — 오프라인에서도 쓰기가 막히지 않는다.
///
/// ★ **모든 Date 는 정수 밀리초에서 만든 값이다**(`TodoRules.milliseconds` / `date(milliseconds:)`). 서버 LWW 는 ms 로
///   비교하는데, 소수 ms 가 남은 Date 를 들고 있으면 "보낸 값 == 지금 값" 판정(보낸 뒤 또 고쳤나)이 반올림 한 번에 흔들린다.
///   Codable 모양(키 7개 · Date 는 참조일 기준 실수)은 0.3.29 와 **글자 그대로 같다** — 옛 앱이 새 파일을 읽어야 한다.
///
/// 필드가 여섯 개나 되는 이유는 "지우지 않는 것"이 이 기능의 뼈대이기 때문이다:
/// - completedAt: 완료를 Bool 이 아니라 **시각**으로 남긴다. "그날 안에는 보이고 자정에 사라진다"는 규칙이
///   날짜 비교로만 성립하기 때문이다(Bool 이면 언제 끝냈는지 몰라 자정 판정을 못 한다).
/// - deletedAt: 삭제도 시각이다. 5초 되돌리기 창을 물리 삭제로 만들 수 없어 톰스톤으로 둔다.
/// - originDayKey: **처음 만든 날**의 KST yyyyMMdd. 이월 배지('어제'/'3일 전')의 기준이라
///   완료/취소/수정으로 절대 흔들리면 안 된다(updatedAt 을 기준으로 삼으면 고쳐 쓴 순간 배지가 리셋된다).
package struct TodoItem: Codable, Equatable, Identifiable {
    package let id: UUID
    package var title: String
    package var createdAt: Date
    package var updatedAt: Date
    package var completedAt: Date? = nil
    package var deletedAt: Date? = nil
    package var originDayKey: String          // 처음 만든 날의 KST yyyyMMdd
    package var isDone: Bool { completedAt != nil }

    /// 서버 LWW 가 비교하는 값. 변환 규칙은 `TodoRules.milliseconds` 하나뿐이다(여기서 다시 계산하지 않는다).
    package var updatedAtMs: Int64 { TodoRules.milliseconds(updatedAt) }

    /// 네 시각을 전부 정수 ms 격자에 올린 사본. 1세대 파일(소수 ms 가 남은 Date)을 읽을 때 한 번 거친다.
    package func withMillisecondTimes() -> TodoItem {
        var copy = self
        copy.createdAt = TodoRules.normalizedTime(createdAt)
        copy.updatedAt = TodoRules.normalizedTime(updatedAt)
        copy.completedAt = completedAt.map(TodoRules.normalizedTime)
        copy.deletedAt = deletedAt.map(TodoRules.normalizedTime)
        return copy
    }
}

/// 파일에 실리는 동기화 상태(2세대부터). 항목과 한 파일에 두는 이유: 따로 두면 "항목은 저장됐는데 보낼 목록은 못 썼다"는
/// 반쪽 상태가 생기고, 그 id 는 영영 서버로 안 간다(원자적 쓰기가 한 파일 단위라서).
package struct TodoFileSyncState: Codable, Equatable, Sendable {
    /// 마지막으로 서버와 맞춘 시각(서버 트랜잭션 시각, epoch ms). nil = 한 번도 못 맞췄다 → 다음 요청은 전체를 받는다.
    package var watermarkMs: Int64?
    /// 아직 서버에 확정되지 않은 항목 id. 순서는 뜻이 없지만 파일 diff 가 흔들리지 않게 정렬해 쓴다.
    package var pendingIDs: [UUID]
    /// 서버가 거절해(`rejected`) **붙잡아 둔** 항목 id(부록 B-3). 이 id 의 로컬 사본은 서버 행이 와도 덮지 않고 full 동기화에서도
    /// 지우지 않는다 — 사용자가 다시 고칠 때까지. **선택 필드**다: 이 키가 없던 파일(붙잡기 이전 2세대)은 빈 목록으로 읽는다.
    package var heldRejectedIDs: [UUID]

    package enum CodingKeys: String, CodingKey {
        case watermarkMs, pendingIDs, heldRejectedIDs
    }

    package init(watermarkMs: Int64?, pendingIDs: [UUID], heldRejectedIDs: [UUID] = []) {
        self.watermarkMs = watermarkMs
        self.pendingIDs = pendingIDs
        self.heldRejectedIDs = heldRejectedIDs
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        watermarkMs = try c.decodeIfPresent(Int64.self, forKey: .watermarkMs)
        pendingIDs = try c.decode([UUID].self, forKey: .pendingIDs)
        // 키가 없으면 빈 목록. 키가 있는데 깨졌으면 **던진다** — 빈 목록으로 접으면 붙잡혀 있던 줄이 보낼 것도 붙잡기도 아닌 채
        // 남아 다음 응답의 서버 옛 행에 덮이거나 full 에서 지워진다. 던지면 파일 쪽 관용(sync 통째로 "전부 보낼 것")을 타고,
        // 다시 보낸 줄은 또 거절돼 다시 붙잡힌다.
        heldRejectedIDs = try c.decodeIfPresent([UUID].self, forKey: .heldRejectedIDs) ?? []
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // null 을 **싣는다**(키를 빼지 않는다) — 명세의 파일 모양 `watermarkMs: int|null` 을 글자 그대로 지킨다.
        try c.encode(watermarkMs, forKey: .watermarkMs)
        try c.encode(pendingIDs, forKey: .pendingIDs)
        try c.encode(heldRejectedIDs, forKey: .heldRejectedIDs)
    }
}

/// 디스크에 실리는 파일 전체. 항목 배열을 그냥 쓰지 않고 봉투를 씌우는 이유는 version 한 칸 때문이다 —
/// 나중에 스키마가 바뀌어도 "이 파일이 몇 세대인지"를 알아야 마이그레이션할지 그냥 읽을지 판단할 수 있다.
///
/// 2세대(v0.3.30): `{"version":2,"items":[…],"sync":{"watermarkMs":int|null,"pendingIDs":[uuid…],"heldRejectedIDs":[uuid…]}}`
/// (`heldRejectedIDs` 는 선택 — 없으면 빈 목록).
/// 0.3.29 의 디코더는 version·items 두 키만 읽고 **모르는 키(sync)를 무시한다** — 되돌려 설치해도 목록은 그대로 읽힌다
/// (V0330TodoFileMigrationTests 가 옛 디코더 사본으로 실제 바이트를 읽어 확인한다).
package struct TodoFile: Codable, Equatable {
    /// 현재 세대. 앞으로 형식이 바뀌면 이 값을 올리고 로드 측에서 분기한다.
    package static let currentVersion = 2

    package var version: Int
    package var items: [TodoItem]
    package var sync: TodoFileSyncState

    /// `sync` 를 안 주면 **모든 항목이 보낼 것**이다 — 동기화 상태를 모르는 파일은 1세대와 같은 규칙으로 읽는다.
    package init(version: Int = TodoFile.currentVersion, items: [TodoItem], sync: TodoFileSyncState? = nil) {
        self.version = version
        self.items = items
        self.sync = sync ?? TodoFileSyncState(watermarkMs: nil, pendingIDs: items.map(\.id))
    }
}

// TodoFile 의 디코드 관용은 **비대칭**이다. 이게 의도다:
// - version 없음 → 1 세대로 본다(사람이 손으로 만든 파일도 읽어 준다).
// - items 없음/깨짐 → **던진다**. 여기서 관대하면 손상 파일이 조용히 빈 목록으로 둔갑해
//   그대로 덮어써진다. 사용자 데이터는 캐시와 달라서 "못 읽겠으면 버린다"가 답이 아니다(호출부가 백업한다).
// - sync 없음/깨짐 → **던지지 않는다.** 사용자 문장이 아니라 파생 상태라, 모르면 "전부 보낼 것 + watermark 없음"으로
//   출발하면 된다(서버 LWW 가 같은 값을 다시 받아도 결과가 같다). 여기서 던지면 멀쩡한 목록이 백업으로 치워진다.
// - **1세대(version 없음·1)는 모든 id 가 보낼 것이다** — 업데이트 뒤 첫 동기화 때 전부 올라간다(= 전원 자동 전환).
extension TodoFile {
    package enum CodingKeys: String, CodingKey {
        case version, items, sync
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try c.decode([TodoItem].self, forKey: .items)
        if version >= 2, let state = try? c.decodeIfPresent(TodoFileSyncState.self, forKey: .sync) {
            sync = state
        } else {
            sync = TodoFileSyncState(watermarkMs: nil, pendingIDs: items.map(\.id))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(items, forKey: .items)
        try c.encode(sync, forKey: .sync)
    }
}

// MARK: - 규칙 (순수 함수 · 값으로 검증 가능)

/// 투두의 모든 판정을 값으로만 내리는 순수 규칙 모음. 뷰도 스토어도 여기 답을 따르므로,
/// "화면을 띄워야 알 수 있는 규칙"이 하나도 남지 않는다(자정 경계 같은 건 실행 시각에 기대면 검증이 불가능하다).
package enum TodoRules {
    /// 제목 상한. 넘으면 **거부**한다(잘라 저장하지 않는다) — 사용자가 쓴 문장을 앱이 몰래 훼손하면 안 된다.
    package static let maxTitleLength = 100
    /// 제목의 **코드 포인트** 상한(v0.3.30). 서버 `todo_items.title` 이 `char_length(title) between 1 and 1000` 이고, UTF-8 DB 의
    /// char_length 는 글자(그래핌)가 아니라 코드 포인트를 센다. 이모지 한 글자가 코드 포인트 11개일 수 있어(👨🏽‍👩🏽‍👧🏽‍👦🏽)
    /// 글자 100 만 보면 코드 포인트 1100 짜리 제목이 이 맥에 저장되고 서버에서 영구 거절된다 — 다른 기기에 끝내 안 가고
    /// 사용자는 모른다(a4-verify PROBE-P8). 화면에 보이는 한도(카운터 `/100`)는 그대로 두고, 이 값은 드문 극단만 막는다.
    package static let maxTitleCodePoints = 1000
    /// 글자수 카운터를 노출하기 시작하는 길이. 평소엔 숨겨 두고 한계에 다가갈 때만 보여준다.
    package static let counterVisibleFrom = 90
    /// 이 일수 이상 이월된 미완료는 '오래된 항목' 접힌 영역으로 조용히 내린다(지우지는 않는다).
    package static let oldItemDays = 7
    /// 완료/삭제 후 이 일수가 지나면 파일에서 제거한다. 화면 규칙이 아니라 **파일 비대 방지**용이다.
    package static let purgeDays = 90
    /// 삭제 되돌리기 창(초). 삭제는 그 자리에서 이 시간 동안 `삭제됨 [되돌리기]` 로 남는다.
    package static let undoSeconds: Double = 5

    // MARK: 정규화

    /// 제목 정규화: 유니코드 정준 결합 → 제어/포맷 문자 제거 → 공백 1칸으로 접기 → 앞뒤 공백 제거.
    /// WorkTimerStore.normalizedDisplayName 의 관용구를 따르되 **한 군데가 다르다**: 줄바꿈·탭을
    /// 지우지 않고 **공백으로 바꾼다**. 별명과 달리 투두는 여러 줄 텍스트를 붙여 넣는 일이 흔한데,
    /// 제어문자를 통째로 지우면 "회의\n준비" 가 "회의준비" 로 들러붙어 단어가 깨진다.
    package static func normalizedTitle(_ raw: String) -> String {
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

    /// 제목이 두 상한(글자 100 · 코드 포인트 1000) 안에 드는가. **입력칸(뷰)·초안(컨트롤러)·추가·수정 네 문이 이 판정 하나를
    /// 쓴다** — 한 문만 글자 수를 보면 그 경로로 서버가 못 받는 줄이 들어온다. 빈 제목 판정은 호출부 몫이다(입력 중엔 빈 값도 정상).
    package static func titleFitsLimits(_ title: String) -> Bool {
        title.count <= maxTitleLength && title.unicodeScalars.count <= maxTitleCodePoints
    }

    // MARK: 날짜

    /// KST yyyyMMdd. 하루 경계 계산은 새로 만들지 않고 MilestoneTracker 의 것을 그대로 쓴다 —
    /// 앱 안에 '하루'의 정의가 둘이 되는 순간 자정 근처에서 기능마다 다른 날을 가리킨다.
    package static func dayKey(_ date: Date) -> String {
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
    package static func carriedDays(originDayKey: String, todayKey: String) -> Int {
        guard let origin = dayStart(fromDayKey: originDayKey),
              let today = dayStart(fromDayKey: todayKey)
        else { return 0 }
        let days = MilestoneTracker.kstCalendar.dateComponents([.day], from: origin, to: today).day ?? 0
        return max(0, days)
    }

    /// 이월 배지 문구. 오늘 만든 항목엔 배지가 없다(nil) — 대부분의 항목이 오늘 것이라
    /// 여기에 '오늘' 배지를 달면 목록 전체가 배지로 뒤덮여 이월이라는 신호가 죽는다.
    package static func carryBadge(days: Int) -> String? {
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
    package static func isVisible(_ item: TodoItem, todayKey: String) -> Bool {
        guard item.deletedAt == nil else { return false }
        guard let completedAt = item.completedAt else { return true }
        return dayKey(completedAt) == todayKey
    }

    /// 하단 '오래된 항목 (N)' 으로 내릴 대상. 완료한 항목은 아무리 오래돼도 여기 오지 않는다 —
    /// 완료는 어차피 자정에 사라지므로 '오래된 완료'라는 상태 자체가 존재하지 않는다.
    package static func isOld(_ item: TodoItem, todayKey: String) -> Bool {
        guard item.completedAt == nil else { return false }
        return carriedDays(originDayKey: item.originDayKey, todayKey: todayKey) >= oldItemDays
    }

    /// 오늘 화면에 그릴 목록(완료 포함)을 걸러 정렬한다.
    package static func visible(_ items: [TodoItem], todayKey: String) -> [TodoItem] {
        visible(items, todayKey: todayKey, keepingDeleted: nil)
    }

    /// 되돌리기 창(5초) 동안 방금 지운 항목을 **그 자리에** 남기기 위한 변형.
    /// 삭제가 즉시 사라지는 대신 `삭제됨 [되돌리기]` 로 바뀌어야 한다는 규칙 때문에, 톰스톤 하나를
    /// 예외로 통과시킬 길이 필요하다. createdAt 기준 정렬이라 통과된 항목은 원래 위치를 그대로 지킨다.
    package static func visible(_ items: [TodoItem], todayKey: String, keepingDeleted id: UUID?) -> [TodoItem] {
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
    package static func pruned(_ items: [TodoItem], now: Date) -> [TodoItem] {
        let cutoff = MilestoneTracker.kstCalendar.date(byAdding: .day, value: -purgeDays, to: now)
            ?? now.addingTimeInterval(-Double(purgeDays) * 86_400)
        return items.filter { item in
            if let deletedAt = item.deletedAt, deletedAt < cutoff { return false }
            if let completedAt = item.completedAt, completedAt < cutoff { return false }
            return true
        }
    }

    // MARK: 시각 ↔ 정수 ms (서버 계약 1.2)

    /// Date → epoch ms. **변환은 이 함수 하나뿐이고 규칙은 '가장 가까운 정수로 반올림' 하나다.**
    ///
    /// 왜 내림이 아니라 반올림인가: 서버에서 온 ms 로 만든 Date 는 Double 오차 때문에 ...122.99999 처럼 **정수 바로 아래**로
    /// 되돌아올 수 있다(2100년 근처 epoch 초는 4e9 라 소수 자릿수가 모자란다). 내림이면 그 순간 ms 가 하나 틀어져
    /// "보낸 값 == 지금 값" 판정이 영원히 거짓이 되고, 그 항목은 매 동기화마다 다시 올라간다. 오차는 1e-3ms 수준이라
    /// 반올림은 언제나 원래 정수로 돌아온다(2020~2100 임의 값 왕복 속성 테스트가 지킨다).
    ///
    /// 비정상 값(손상 파일의 무한대·천문학적 수)에서 `Int64(_:)` 가 죽지 않게 ±8.64e15ms(±27만 년) 로 누른다.
    package static func milliseconds(_ date: Date) -> Int64 {
        let raw = (date.timeIntervalSince1970 * 1000).rounded()
        guard !raw.isNaN else { return 0 }
        return Int64(min(max(raw, -millisecondsLimit), millisecondsLimit))
    }

    /// epoch ms → Date. `milliseconds` 의 역함수(왕복이 항상 같은 정수로 돌아온다).
    package static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// 정수 ms 격자 위의 Date. 만들 때·고칠 때의 '지금'은 전부 이걸 거친다.
    package static func normalizedTime(_ date: Date) -> Date {
        self.date(milliseconds: milliseconds(date))
    }

    /// `milliseconds` 의 안전 상한. 2^53 보다 작아 Double 로 정확히 표현된다.
    private static let millisecondsLimit: Double = 8_640_000_000_000_000

    // MARK: 동기화 병합 (순수)

    /// 서버 응답을 로컬 사본에 합친다. **서버 `todo_sync` 의 LWW 와 같은 규칙**이라 두 기기와 서버가 같은 값으로 수렴한다.
    ///
    /// 규칙(명세 A4-3 · 부록 B-3):
    /// ⓪ pending·붙잡기 중 로컬에 없는 id 는 버린다 — 항목이 없는 id 는 뜻이 없고, 남기면 같은 응답을 두 번 합칠 때 결과가 갈린다.
    ///    pending 이면서 붙잡힌 id 는 pending 이 이긴다(사용자가 다시 고친 값이다 — 붙잡기는 "안 고친 채 거절됐다"는 뜻이라서).
    /// ① **보낸 스냅샷**: 응답을 받은 시점의 로컬 updatedAtMs 가 **보낸 값과 같을 때만** pending 에서 뺀다(보낸 뒤 또 고쳤으면
    ///    그 새 값은 서버가 아직 모른다). 합치기 **전** 값으로 본다 — 서버가 미래 시각을 눌러(clamp) 더 작은 값으로 돌려준
    ///    경우에도 "안 고쳤다"가 성립해야 서버 값으로 수렴한다.
    /// ② rejected: 보낸 뒤 안 고쳤으면(①과 같은 판정) pending 에서 빼고 **붙잡는다**. 보낸 뒤 또 고쳤으면 새 값은 통과할 수
    ///    있으니 pending 으로 둔다(붙잡지 않는다). 어느 쪽이든 로컬 사본은 남는다. 로컬에 없는 id, 서버가 로컬과 **똑같은**
    ///    행을 돌려준 id 는 붙잡지도 다시 보내지도 않는다(지킬 로컬 수정이 없다).
    /// ③ 같은 id: 붙잡힌 id 면 **로컬 유지**(서버 행이 와도 — X2 F1: 60초 겹침 창 안이면 서버가 거절된 수정의 옛 행을 돌려준다).
    ///    아니면 로컬이 (①② 뒤에도) pending 이고 로컬 updatedAtMs > 서버 updatedAtMs 면 로컬 유지. 아니면 서버 것으로
    ///    교체하고 pending 에서 뺀다(서버가 이긴 값은 보낼 것이 아니다 — 같은 ms 동률도 서버 유지, 서버 LWW 와 같다).
    /// ④ full 이면 서버에 없고 pending 도 붙잡기도 아닌 로컬 항목을 지운다(80일 넘게 못 맞춘 기기 — 그사이 서버가 정리한 것).
    ///    붙잡힌 줄은 올릴 때마다 거절돼 원래 이 기기에만 있는 줄이라 "서버에 없다"가 "서버가 정리했다"는 뜻이 아니다(X2 F2:
    ///    예전 응답에서 거절된 id 를 기억하지 않아 81일 뒤 full 에서 조용히 사라졌다 — 넘친 제목이든 quota 든).
    ///    이번 응답의 rejected 는 ②를 거쳐 전부 pending 이거나 붙잡기라 따로 예외를 두지 않는다(두 곳에 두면 한쪽을 지워도 초록이다).
    /// ⑤ 서버에만 있는 항목은 뒤에 붙인다. 로컬에만 있는 새 항목은 그대로.
    ///
    /// `protected`(편집 중 · 삭제 되돌리기 창)는 ③④를 **미룬다**: 로컬을 그대로 두고, 바뀌었어야 할 id 는 pending 에 다시
    /// 넣어 `deferredIDs` 로 알린다. 다음 요청이 그 id 를 보내면 서버는 LWW 로 판정하고 **자기 현재 행을 돌려주므로**
    /// (계약: 이번 p_changes 의 id 는 since 와 무관하게 온다) watermark 가 지나가도 놓치지 않는다. 붙잡힌 id 는 미루지 않는다 —
    /// 다시 보내 봐야 또 거절되고, 로컬은 어차피 그대로다.
    ///
    /// 멱등: 같은 응답을 결과에 한 번 더 합쳐도 결과(items·pending·붙잡기)가 같다(속성 테스트).
    package static func mergedSync(
        local: [TodoItem],
        pending: Set<UUID>,
        sent: [UUID: Int64],
        server: [TodoItem],
        rejected: Set<UUID>,
        full: Bool,
        held: Set<UUID> = [],
        protected: Set<UUID> = []
    ) -> TodoSyncMergeResult {
        var localByID: [UUID: TodoItem] = [:]
        for item in local where localByID[item.id] == nil { localByID[item.id] = item }
        var serverByID: [UUID: TodoItem] = [:]
        var serverOrder: [UUID] = []
        for item in server {
            if serverByID[item.id] == nil { serverOrder.append(item.id) }
            serverByID[item.id] = item
        }

        // ⓪
        var nextPending = pending.filter { localByID[$0] != nil }
        var nextHeld = held.filter { localByID[$0] != nil && !nextPending.contains($0) }
        // ①
        for (id, sentMs) in sent where localByID[id]?.updatedAtMs == sentMs {
            nextPending.remove(id)
        }
        // ②
        for id in rejected where localByID[id] != nil {
            let unchangedSinceSent = sent[id] == nil || localByID[id]?.updatedAtMs == sent[id]
            // 서버 행이 로컬과 똑같이 왔으면 지킬 것도 다시 보낼 것도 없다. 이 조건이 없으면 첫 병합에서 서버 값으로 바뀐(또는
            // 서버에서 새로 붙은) 줄이 같은 응답을 한 번 더 합칠 때만 붙잡기·pending 에 들어가 멱등이 깨진다.
            let serverRowDiffers = serverByID[id] != localByID[id]
            if unchangedSinceSent {
                nextPending.remove(id)
                if serverRowDiffers { nextHeld.insert(id) }
            } else {
                nextHeld.remove(id)
                if serverRowDiffers { nextPending.insert(id) }
            }
        }

        var deferred: Set<UUID> = []
        var merged: [TodoItem] = []
        var emitted: Set<UUID> = []
        for item in local where !emitted.contains(item.id) {
            emitted.insert(item.id)
            if let incoming = serverByID[item.id] {
                // ③
                if nextHeld.contains(item.id) {
                    merged.append(item)
                } else if nextPending.contains(item.id), item.updatedAtMs > incoming.updatedAtMs {
                    merged.append(item)
                } else if protected.contains(item.id) {
                    merged.append(item)
                    if incoming != item {
                        nextPending.insert(item.id)
                        deferred.insert(item.id)
                    }
                } else {
                    merged.append(incoming)
                    nextPending.remove(item.id)
                }
            } else if full, !nextPending.contains(item.id), !nextHeld.contains(item.id) {
                // ④
                if protected.contains(item.id) {
                    merged.append(item)
                    nextPending.insert(item.id)
                    deferred.insert(item.id)
                }
            } else {
                merged.append(item)
            }
        }
        // ⑤
        for id in serverOrder where !emitted.contains(id) {
            if let incoming = serverByID[id] { merged.append(incoming) }
        }
        return TodoSyncMergeResult(items: merged, pending: nextPending, heldRejectedIDs: nextHeld, deferredIDs: deferred)
    }
}

/// `TodoRules.mergedSync` 의 결과.
package struct TodoSyncMergeResult: Equatable, Sendable {
    package var items: [TodoItem]
    package var pending: Set<UUID>
    /// 서버가 거절해 붙잡아 둔 id(부록 B-3). 언제나 `items` 에 있고 `pending` 과 겹치지 않는다.
    package var heldRejectedIDs: Set<UUID>
    /// 편집 중이라 반영을 미룬 id(비면 미룬 것이 없다). 병합 결과의 동치 비교에는 참여하지만 멱등 판정은 items·pending·붙잡기로 한다.
    package var deferredIDs: Set<UUID>
}

// MARK: - 파일 저장소 (원자적 쓰기 · 손상 시 보존)

/// todos.json 의 로드/세이브. 토큰 캐시 저장소와 모양은 닮았지만 **한 가지가 다르다**:
/// 캐시는 못 읽으면 버리고 다시 만들면 그만이지만, 이건 사용자가 손으로 쓴 문장이라 다시 만들 길이 없다.
/// 그래서 load 는 실패를 삼키지 않고 던지고(호출부가 원본을 백업하게), save 는 원자적 쓰기로 쓰다 만 파일을 남기지 않는다.
package enum TodoFileStore {
    package static let currentVersion = TodoFile.currentVersion

    /// 로그인 사용자별로 파일을 가른다. 로그인 전(userID nil)은 `todos.local.json` 이다 —
    /// 계정 없이 적어 둔 것이 나중에 로그인한 사람 목록에 섞여 들어가지 않게 처음부터 분리해 둔다.
    package static func defaultURL(userID: String?) -> URL {
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
    package static func load(from url: URL) throws -> TodoFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TodoFile(items: [])
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return TodoFile(items: []) }
        return try JSONDecoder().decode(TodoFile.self, from: data)
    }

    /// 상위 폴더를 만들고 원자적으로 쓴다. 쓰는 도중 앱이 죽어도 반쯤 쓰인 JSON 이 남지 않는다
    /// (남으면 다음 실행이 그걸 손상으로 보고 목록 전체를 백업으로 치워 버린다).
    package static func save(_ file: TodoFile, to url: URL) throws {
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
    package static func corruptedBackupURL(for url: URL, now: Date) -> URL {
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

/// 투두 목록의 이 기기 사본의 유일한 소유자. 여기 메모리가 곧 진실이고, 디스크는 그 사본일 뿐이다.
/// 이 방향(메모리 → 디스크)을 고정했기 때문에 저장 실패를 조용히 삼켜도 안전하다 —
/// 사용자는 계속 쓰던 목록을 보고, 다음 변경에서 파일 전체가 다시 쓰인다(부분 저장이 없다).
///
/// 서버와 맞추는 일(v0.3.30)은 `TodoSync` 가 한다. 스토어는 **두 문만** 연다:
/// ① `makeSyncRequest(ids:)` — 보낼 항목의 스냅샷(보낸 updatedAtMs 와 파일 세대까지 같이 찍는다)
/// ② `applySync(_:for:)` — 응답 병합. 요청을 찍을 때의 파일 세대가 **지금과 다르면 아무것도 하지 않는다**
///    (계정을 바꾼 사이 도착한 앞 계정의 늦은 응답이 새 계정 파일에 섞이면 남의 할 일이 보인다 — 세대 가드는 여기 하나다).
@MainActor @Observable package final class TodoListStore {
    package private(set) var items: [TodoItem] = []
    /// 아직 서버에 확정되지 않은 항목 id(파일의 `sync.pendingIDs`).
    package private(set) var pendingIDs: Set<UUID> = []
    /// 서버가 거절해 붙잡아 둔 항목 id(파일의 `sync.heldRejectedIDs`, 부록 B-3). 서버 행에 덮이지 않고 full 에서도 안 지워진다.
    /// 사용자가 그 줄을 다시 고치면(`didChangeLocally`) 빠져 pending 으로 돌아가고, 줄이 목록에서 정리되면 함께 빠진다.
    /// 언제나 `items` 의 id 이고 `pendingIDs` 와 겹치지 않는다.
    package private(set) var heldRejectedIDs: Set<UUID> = []
    /// 마지막으로 맞춘 서버 시각(epoch ms). nil = 다음 요청은 전체를 받는다.
    package private(set) var watermarkMs: Int64?
    /// 지금 쓰는 파일. **계정이 바뀌면 바뀐다**(`switchFile`) — 예전에는 실행 때 고른 파일을 끝까지 써서, 실행 중에
    /// 로그아웃하고 다른 계정으로 들어오면 앞 사람 목록에 이어 적었다.
    package private(set) var fileURL: URL
    /// 파일을 바꿀 때마다 오른다. 동기화 응답이 "찍을 때의 세대"를 들고 와 이 값과 견준다.
    package private(set) var fileGeneration = 0

    /// 사용자가 목록을 고쳤다(추가·완료·수정·삭제·되돌리기). 동기화가 1.5초 디바운스를 건다. 병합·재로드는 부르지 않는다.
    @ObservationIgnored package var onLocalChange: (@MainActor () -> Void)?
    /// 지금 서버 반영을 미뤄야 하는 id(편집 중인 줄 · 삭제 되돌리기 창). 보드 컨트롤러가 채운다.
    @ObservationIgnored package var syncProtectedIDs: @MainActor () -> Set<UUID> = { [] }
    /// 보호 때문에 반영을 미룬 id. 보호가 풀리면 한 번 더 맞춘다(`syncProtectionDidEnd`).
    @ObservationIgnored private var deferredSyncIDs: Set<UUID> = []

    @ObservationIgnored private let clock: () -> Date

    package init(fileURL: URL, clock: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.clock = clock
        // 복원은 init 에서 끝낸다. 보드가 열릴 때 로드하면 첫 프레임이 빈 목록으로 한 번 깜빡인다.
        reload()
    }

    /// 오늘의 KST dayKey. 뷰는 이 값 하나로 이월 배지·완료 노출을 모두 판정한다(뷰가 Date 를 직접 다루지 않게).
    package var todayKey: String { TodoRules.dayKey(clock()) }

    /// 다른 계정의 파일로 갈아탄다. 세대를 **먼저** 올린다 — 진행 중이던 요청의 응답은 이 순간부터 전부 버려진다.
    package func switchFile(to url: URL) {
        fileGeneration += 1
        if fileURL != url { fileURL = url }
        reload()
    }

    /// 디스크에서 다시 읽어 온다. 손상 파일은 **백업으로 옮기고** 빈 목록으로 출발한다 —
    /// 그냥 덮어쓰면 사용자가 적어 둔 문장이 영원히 사라진다(캐시라면 그래도 됐겠지만 이건 원본이다).
    ///
    /// 읽으면서 세 가지를 정리한다: 시각을 ms 격자에 올리고(1세대 파일), 90일 지난 완료·삭제를 빼고,
    /// 빠진 항목의 id 를 보낼 목록에서도 뺀다. 그중 하나라도 바뀌었거나 옛 세대 파일이면 곧바로 2세대로 다시 쓴다.
    package func reload() {
        let now = clock()
        let loaded: TodoFile
        do {
            loaded = try TodoFileStore.load(from: fileURL)
        } catch {
            try? FileManager.default.moveItem(
                at: fileURL, to: TodoFileStore.corruptedBackupURL(for: fileURL, now: now)
            )
            loaded = TodoFile(items: [], sync: TodoFileSyncState(watermarkMs: nil, pendingIDs: []))
        }
        let normalized = loaded.items.map { $0.withMillisecondTimes() }
        let kept = TodoRules.pruned(normalized, now: now)
        let keptIDs = Set(kept.map(\.id))
        let pending = Set(loaded.sync.pendingIDs).intersection(keptIDs)
        // 붙잡기는 정리된 줄에서 빠지고, 보낼 것과 겹치면 보낼 것이 이긴다(다시 고친 값 — 병합 ⓪ 과 같은 규칙).
        let held = Set(loaded.sync.heldRejectedIDs).intersection(keptIDs).subtracting(pending)
        if items != kept { items = kept }      // @Observable 은 같은 값 재대입도 관찰자를 깨운다
        if pendingIDs != pending { pendingIDs = pending }
        if heldRejectedIDs != held { heldRejectedIDs = held }
        if watermarkMs != loaded.sync.watermarkMs { watermarkMs = loaded.sync.watermarkMs }
        deferredSyncIDs = []
        // 정리로 줄었으면 그 결과를 디스크에도 반영해, 다음 실행이 같은 낡은 항목을 또 읽고 또 버리지 않게 한다.
        let rewrite = kept.count != loaded.items.count
            || normalized != loaded.items
            || pending.count != loaded.sync.pendingIDs.count
            || held.count != loaded.sync.heldRejectedIDs.count
            || loaded.version < TodoFile.currentVersion
        if rewrite { persist() }
    }

    /// 새 항목을 목록 맨 앞에 넣는다. 빈 제목과 상한 초과(글자 100 · 코드 포인트 1000)는 **아무 일도 하지 않고 nil** 이다 —
    /// 특히 초과는 잘라서 저장하지 않는다(입력 단계에서 이미 막지만, 붙여넣기 경로를 위해 여기서도 거절한다).
    @discardableResult
    package func add(_ rawTitle: String) -> TodoItem? {
        let title = TodoRules.normalizedTitle(rawTitle)
        guard !title.isEmpty, TodoRules.titleFitsLimits(title) else { return nil }
        let now = TodoRules.normalizedTime(clock())
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
        didChangeLocally(item.id)
        return item
    }

    /// 완료/완료취소를 뒤집는다. **originDayKey 는 절대 건드리지 않는다** —
    /// 이월 배지의 기준이라, 어제 적은 걸 오늘 체크했다 풀면 배지가 사라지는 버그가 된다.
    package func toggleDone(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let now = TodoRules.normalizedTime(clock())
        var item = items[idx]
        item.completedAt = item.completedAt == nil ? now : nil
        item.updatedAt = Self.nextUpdatedAt(now: now, previous: item.updatedAt)
        if items[idx] != item { items[idx] = item }
        didChangeLocally(id)
    }

    /// 인라인 수정 커밋. 정규화 후 빈 제목/상한 초과는 무시한다(취소와 같은 결과 — 원래 문장이 남는다).
    /// 내용이 그대로면 updatedAt 도 건드리지 않는다: 의미 없는 저장과 관찰자 발화를 함께 막는다.
    package func rename(_ id: UUID, to rawTitle: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let title = TodoRules.normalizedTitle(rawTitle)
        guard !title.isEmpty, TodoRules.titleFitsLimits(title) else { return }
        guard items[idx].title != title else { return }
        items[idx].title = title
        items[idx].updatedAt = Self.nextUpdatedAt(now: TodoRules.normalizedTime(clock()), previous: items[idx].updatedAt)
        didChangeLocally(id)
    }

    /// 삭제는 톰스톤이다(배열에서 빼지 않는다). 5초 되돌리기 창 동안 그 자리에 남아 있어야 하는데,
    /// 물리 삭제 후 되살리면 원래 위치·id 를 복원할 수 없다. 실제 제거는 pruned 가 90일 뒤에 조용히 한다.
    /// 톰스톤이어야 할 이유가 하나 더 생겼다 — 다른 기기에 "지웠다"를 전하려면 지운 사실이 행으로 남아 있어야 한다.
    package func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].deletedAt == nil else { return }
        let now = TodoRules.normalizedTime(clock())
        items[idx].deletedAt = now
        items[idx].updatedAt = Self.nextUpdatedAt(now: now, previous: items[idx].updatedAt)
        didChangeLocally(id)
    }

    /// 되돌리기. 톰스톤만 벗기므로 제목·완료 상태·만든 날이 삭제 직전 그대로 돌아온다.
    package func undoDelete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].deletedAt != nil else { return }
        items[idx].deletedAt = nil
        items[idx].updatedAt = Self.nextUpdatedAt(now: TodoRules.normalizedTime(clock()), previous: items[idx].updatedAt)
        didChangeLocally(id)
    }

    /// 고친 시각. **이전 값보다 반드시 1ms 이상 크다.** 서버 LWW 는 "들어온 값 > 기존 값"일 때만 덮으므로, 같은 ms 안의
    /// 두 번째 수정이나 시계가 뒤로 간 뒤의 수정은 이미 올라간 옛 값에 져서 **조용히 사라진다**(완료 체크 → 곧바로 해제가
    /// 다른 기기에서 체크된 채로 남는 그림). 사람 손으로 1ms 를 밀어 올리는 건 화면에 아무 차이가 없다.
    private static func nextUpdatedAt(now: Date, previous: Date) -> Date {
        let floor = TodoRules.milliseconds(previous) + 1
        return TodoRules.milliseconds(now) >= floor ? now : TodoRules.date(milliseconds: floor)
    }

    /// 사용자 변경 공통 꼬리: 보낼 목록에 넣고 → 저장하고 → 동기화에 알린다(순서가 곧 계약이다 — 저장 전에 알리면
    /// 디바운스가 끝나기 전 앱이 죽었을 때 pending 이 파일에 없다).
    /// 거절돼 붙잡혀 있던 줄이면 여기서 **풀린다**(부록 B-3) — 사용자가 다시 고친 값은 서버가 받을 수도 있으니 다시 보낸다.
    /// 완료·수정·삭제·되돌리기가 전부 이 문을 지나므로 풀어 주는 자리는 여기 하나다.
    private func didChangeLocally(_ id: UUID) {
        pendingIDs.insert(id)
        heldRejectedIDs.remove(id)
        persist()
        onLocalChange?()
    }

    // MARK: 동기화 문

    /// 보낼 스냅샷을 찍는다. 넘긴 id 중 **아직 pending 이고 로컬에 있는 것만** 싣는다. `sent` 는 싣는 순간의 updatedAtMs —
    /// 응답이 왔을 때 "보낸 뒤 또 고쳤나"를 이 값으로 가린다.
    package func makeSyncRequest(ids: [UUID]) -> TodoSyncOutgoing {
        var byID: [UUID: TodoItem] = [:]
        for item in items where byID[item.id] == nil { byID[item.id] = item }
        var seen: Set<UUID> = []
        let changes = ids.compactMap { id -> TodoItem? in
            guard pendingIDs.contains(id), seen.insert(id).inserted else { return nil }
            return byID[id]
        }
        return TodoSyncOutgoing(
            fileGeneration: fileGeneration,
            request: TodoSyncRequest(changes: changes.map(TodoSyncWireItem.init(item:)), sinceMs: watermarkMs),
            sent: Dictionary(changes.map { ($0.id, $0.updatedAtMs) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// 서버 응답을 합치고 watermark 를 올린 뒤 파일에 쓴다. 찍을 때의 파일 세대가 지금과 다르면 **false 이고 아무것도
    /// 바꾸지 않는다** — 이 함수가 늦은 응답을 막는 유일한 문이다.
    @discardableResult
    package func applySync(_ result: TodoSyncResult, for outgoing: TodoSyncOutgoing) -> Bool {
        guard outgoing.fileGeneration == fileGeneration else { return false }
        let merged = TodoRules.mergedSync(
            local: items,
            pending: pendingIDs,
            sent: outgoing.sent,
            server: result.items,
            rejected: result.rejectedIDs,
            full: result.full,
            held: heldRejectedIDs,
            protected: syncProtectedIDs()
        )
        // 서버에서 온 오래된 톰스톤도 로컬 90일 정리를 똑같이 거친다. 정리된 id 는 보낼 목록·붙잡기에서도 뺀다(명세 A4-9 · B-3).
        let kept = TodoRules.pruned(merged.items, now: clock())
        let keptIDs = Set(kept.map(\.id))
        let pending = merged.pending.intersection(keptIDs)
        let held = merged.heldRejectedIDs.intersection(keptIDs)
        if items != kept { items = kept }
        if pendingIDs != pending { pendingIDs = pending }
        if heldRejectedIDs != held { heldRejectedIDs = held }
        if watermarkMs != result.watermarkMs { watermarkMs = result.watermarkMs }
        deferredSyncIDs.formUnion(merged.deferredIDs)
        persist()
        return true
    }

    /// 보호(편집·되돌리기 창)가 끝났다. 그동안 미룬 id 가 있으면 한 번 더 맞추게 알린다 — 그 id 는 이미 pending 이라
    /// 다음 요청에 실리고, 서버는 LWW 로 판정한 **현재 행**을 돌려준다.
    package func syncProtectionDidEnd() {
        let released = deferredSyncIDs.subtracting(syncProtectedIDs())
        guard !released.isEmpty else { return }
        deferredSyncIDs.subtract(released)
        onLocalChange?()
    }

    /// 변경마다 전체를 다시 쓴다. 실패는 삼킨다 — 디스크가 잠깐 말썽이라고 해서 사용자의 타이핑을
    /// 막거나 경고창을 띄우는 건 과하고, 메모리가 진실이므로 다음 변경에서 통째로 재시도된다.
    private func persist() {
        let sync = TodoFileSyncState(
            watermarkMs: watermarkMs,
            pendingIDs: pendingIDs.sorted { $0.uuidString < $1.uuidString },
            heldRejectedIDs: heldRejectedIDs.sorted { $0.uuidString < $1.uuidString }
        )
        try? TodoFileStore.save(TodoFile(items: items, sync: sync), to: fileURL)
    }
}
