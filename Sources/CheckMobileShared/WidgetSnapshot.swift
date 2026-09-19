import Foundation

/// 위젯이 읽는 **유일한 모양**(SPEC-ios §4). 앱이 데이터를 받을 때마다 App Group `widget-snapshot.json` 에 쓴다.
///
/// 규칙
/// - 위젯은 네트워크를 쓰지 않고 이 파일만 그린다(토큰 갱신 금지 — R5). 할 일 체크만 예외(`TodoSharedFile` + 인텐트).
/// - **더하기만 한다.** 새 필드는 옵셔널로 더하고 `version` 을 올리지 않는다. 뜻이 바뀌는 변경만 version 을 올린다.
///   디코드는 모든 필드를 관대하게 읽는다(없는 칸은 기본값, 모르는 칸은 무시) — 앱과 위젯은 같은 번들로 나가지만
///   업데이트 직후 옛 앱이 쓴 파일을 새 위젯이(또는 반대로) 읽는 창이 실재한다.
/// - 파일이 없으면 = 로그아웃 상태(위젯: "앱에서 로그인해 주세요"). 로그아웃은 파일을 지운다.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// 이 코드가 쓰는 판. 읽을 때는 1 이상이면 받는다(뜻이 바뀐 판이 생기면 그때 상한을 둔다).
    public static let currentVersion = 1

    public var version: Int
    /// 앱이 이 스냅샷을 만든 시각. 위젯 오른쪽 아래 "N분 전".
    public var generatedAt: Date
    /// 내 상태. 아직 못 받았으면 nil(지금 탭이 한 번이라도 불러오기 전).
    public var me: Me?
    /// 지금 근무 중인 사람(우리 팀 먼저 정렬해 쓴다).
    public var working: [WorkingPerson]
    /// 오늘 할 일 앞부분(위젯 medium 3개 · large 6개를 그릴 만큼).
    public var todosPreview: [TodoPreview]
    /// 착용 캐릭터 id(서버 `profiles.character` 를 이 빌드가 아는 id 로 접은 값 — 기본은 "aing"). nil = 아직 모른다(옛 스냅샷 포함).
    /// **읽을 때는 `resolvedCharacterID`** — 모르는 id·nil 은 아잉으로 선다. `me` 와 따로 둔다: 지금 탭이 `me` 를 통째로 갈아 끼워도
    /// 착용값이 지워지지 않게(착용값은 나 탭이 알아 오고, 쓰는 주체는 여전히 지금 탭 하나다).
    public var characterID: String?

    public init(
        version: Int = WidgetSnapshot.currentVersion,
        generatedAt: Date,
        me: Me? = nil,
        working: [WorkingPerson] = [],
        todosPreview: [TodoPreview] = [],
        characterID: String? = nil
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.me = me
        self.working = working
        self.todosPreview = todosPreview
        self.characterID = characterID
    }

    /// 위젯이 세울 캐릭터 id — 이 빌드에 초상이 없는 id·nil 은 아잉(맥 `CharacterSyncDecision` 과 같은 접기).
    public var resolvedCharacterID: String {
        AingCharacterArt.resolvedID(characterID)
    }

    /// 내 근무 상태(위젯 초상 표정·링). 옛 스냅샷은 `working` 깃발만 있다 — 그때는 근무 중/안 함 둘로 읽는다.
    public enum WorkState: String, Codable, Equatable, Sendable, CaseIterable {
        /// 맥에서 근무 중(신호 신선).
        case working
        /// 근무 중인데 맥 신호가 끊겼다(90초 넘게 — 코어 `MemberPresence.staleWorking`).
        case disconnected
        /// 근무 안 함.
        case off
    }

    public struct Me: Codable, Equatable, Sendable {
        /// 맥에서 근무 중인가(서버 세션 기준).
        public var working: Bool
        /// 근무 중이면 서버 세션 시작 시각 — 위젯이 `Text(timerInterval:)` 로 스스로 센다.
        public var sessionStartedAt: Date?
        /// 스냅샷 시각 기준 오늘 누적 초(진행 중 세션 포함).
        public var todaySeconds: Int
        /// 스냅샷 시각 기준 이번 주 누적 초.
        public var weekSeconds: Int
        /// 팀 1인당 주간 목표(시간).
        public var goalHours: Int
        /// 근무 상태 3갈래. nil = 옛 스냅샷(이 칸이 없다) · 이 빌드가 모르는 값 — **읽을 때는 `resolvedStatus`**.
        public var status: WorkState?

        public init(working: Bool, sessionStartedAt: Date?, todaySeconds: Int, weekSeconds: Int, goalHours: Int, status: WorkState? = nil) {
            self.working = working
            self.sessionStartedAt = sessionStartedAt
            self.todaySeconds = todaySeconds
            self.weekSeconds = weekSeconds
            self.goalHours = goalHours
            self.status = status
        }

        /// 상태 칸이 있으면 그 값, 없으면 `working` 깃발로(근무 중 / 안 함). 상태가 `working` 깃발과 어긋나면 깃발을 믿는다
        /// (깃발은 옛 판부터 늘 써 온 칸이다 — 근무 안 함인데 "연결 끊김"을 그리지 않는다).
        public var resolvedStatus: WorkState {
            guard working else { return .off }
            return status == .disconnected ? .disconnected : .working
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            working = (try? c.decodeIfPresent(Bool.self, forKey: .working)) ?? false
            sessionStartedAt = try? c.decodeIfPresent(Date.self, forKey: .sessionStartedAt)
            todaySeconds = max(0, (try? c.decodeIfPresent(Int.self, forKey: .todaySeconds)) ?? 0)
            weekSeconds = max(0, (try? c.decodeIfPresent(Int.self, forKey: .weekSeconds)) ?? 0)
            goalHours = (try? c.decodeIfPresent(Int.self, forKey: .goalHours)) ?? 0
            // 모르는 문자열(다음 판이 더한 상태)은 nil — 깃발로 읽는다.
            status = (try? c.decodeIfPresent(String.self, forKey: .status)).flatMap(WorkState.init(rawValue:))
        }
    }

    public struct WorkingPerson: Codable, Equatable, Sendable, Identifiable {
        public var id: String { "\(teammate ? "t" : "o"):\(name):\(startedAt?.timeIntervalSince1970 ?? 0)" }
        public var name: String
        /// 센터 서버값("seoul"/"busan"). 모르면 nil(배지 없음 — 코어 `CenterLabel` 규칙).
        public var center: String?
        /// 우리 팀인가. 다른 팀 사람은 경과 시간을 모른다(서버가 주지 않는다 — startedAt nil).
        public var teammate: Bool
        public var startedAt: Date?
        /// 얼굴에 그릴 착용 캐릭터 id(앱의 캐릭터 한 표가 접은 값 — 착용값 null 은 이미 "aing"). nil = 모른다 → 이니셜
        /// (옛 스냅샷 · 표를 아직 못 받음 · 앱이 모르는 캐릭터). 위젯은 사진을 그리지 않으므로(네트워크 없음) 사진을 올린 사람도
        /// 앱의 '사진을 못 불러왔을 때'와 같이 캐릭터로 선다. **읽을 때는 `knownCharacterID`** — 이 빌드에 초상이 없는 id 는 이니셜이다
        /// (내 초상 `resolvedCharacterID` 처럼 아잉으로 접지 않는다 — 남에게 틀린 캐릭터를 입히지 않는다).
        public var characterID: String?

        public init(name: String, center: String?, teammate: Bool, startedAt: Date?, characterID: String? = nil) {
            self.name = name
            self.center = center
            self.teammate = teammate
            self.startedAt = startedAt
            self.characterID = characterID
        }

        /// 위젯이 이 사람 얼굴에 세울 캐릭터. nil 이면 이니셜 원.
        public var knownCharacterID: String? {
            guard let trimmed = characterID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  AingCharacterArt.knownIDs.contains(trimmed) else { return nil }
            return trimmed
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "사용자"
            center = try? c.decodeIfPresent(String.self, forKey: .center)
            teammate = (try? c.decodeIfPresent(Bool.self, forKey: .teammate)) ?? false
            startedAt = try? c.decodeIfPresent(Date.self, forKey: .startedAt)
            // 칸이 없거나(옛 앱이 쓴 스냅샷) 타입이 어긋나면 nil — 이니셜로 선다(더하기만 하는 규칙).
            characterID = try? c.decodeIfPresent(String.self, forKey: .characterID)
        }
    }

    public struct TodoPreview: Codable, Equatable, Sendable, Identifiable {
        /// 할 일 id(UUID 문자열). 위젯 체크 인텐트가 이 id 로 할 일 파일을 고친다.
        public var id: String
        public var title: String
        public var isCompleted: Bool
        /// 이월 일수(0 = 오늘 만든 것). "어제"/"3일 전" 배지.
        public var carryOverDays: Int

        public init(id: String, title: String, isCompleted: Bool, carryOverDays: Int = 0) {
            self.id = id
            self.title = title
            self.isCompleted = isCompleted
            self.carryOverDays = carryOverDays
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            isCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
            carryOverDays = max(0, (try? c.decodeIfPresent(Int.self, forKey: .carryOverDays)) ?? 0)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        me = try? c.decodeIfPresent(Me.self, forKey: .me)
        // 칸 하나가 깨져도 스냅샷 전체를 버리지 않는다 — 원소 단위로 건너뛴다(위젯이 통째로 비는 것보다 낫다).
        working = (try? c.decodeIfPresent(LossyArray<WorkingPerson>.self, forKey: .working))?.elements ?? []
        todosPreview = (try? c.decodeIfPresent(LossyArray<TodoPreview>.self, forKey: .todosPreview))?.elements ?? []
        characterID = try? c.decodeIfPresent(String.self, forKey: .characterID)
    }
}

/// 원소 하나가 깨져도 나머지를 살리는 배열 디코드.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                out.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        elements = out
    }

    private struct Skip: Decodable {}
}

/// 스냅샷 파일 읽고 쓰기(순수 I/O). 날짜는 epoch ms 정수로 쓴다 — 기기 로캘·포맷과 무관하고 왕복이 정확하다.
public enum WidgetSnapshotCodec {
    public static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// 못 읽으면 nil(= 위젯은 로그아웃 화면). version 이 1 미만이거나 없으면 nil.
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data), snapshot.version >= 1 else {
            return nil
        }
        return snapshot
    }

    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// 원자적으로 쓴다(위젯이 반쯤 쓰인 파일을 읽지 않게).
    public static func write(_ snapshot: WidgetSnapshot, to url: URL) throws {
        let data = try encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
