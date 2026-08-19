import Foundation

struct WorkStatusSnapshot: Equatable {
    var status: WorkStatus
    var elapsedSeconds: Int
    var pendingSync: Bool = false
    /// 자리 비움으로 자동 마감된 근무가 **아직 되살릴 수 있는 창 안에** 있는가(v0.2.35 / docs/away-close.md).
    ///
    /// 이 한 칸이 메뉴바를 "오프"에서 "자리비움"으로 바꾸는 유일한 스위치다. 왜 메뉴바까지 오는가:
    /// 임계가 2시간 30분이라 4시간일 때보다 자주 끊기는데, 복원 창(6시간)을 놓치면 그날 오전이 **영구 소실**된다.
    /// 캐릭터(말풍선)를 끈 사람에게 남는 채널은 메뉴바 하나뿐이라, 여기서 평소와 다른 글자가 보이지 않으면
    /// 그 사람은 잃은 줄도 모르고 창이 닫힌다.
    ///
    /// 새 필드는 **반드시 마지막**에 둔다 — 위치 인자로 이 타입을 만드는 호출부(스토어 3파일·테스트)가
    /// 그대로 컴파일되고, 기본값 false 는 "모르면 평소대로"라 아무 화면도 조용히 바뀌지 않는다.
    var isAwayRestorable: Bool = false

    var isWorking: Bool {
        status == .working
    }

    /// 자리 비움 표시를 켠 사본. 스냅샷은 스토어 여러 파일이 만들고 이 파생 상태는 폴링(away_sync)이
    /// 따로 들고 오므로, 라벨을 그리는 자리에서 한 번만 얹는다(원본 스냅샷 재대입 = 전체 무효화 회피).
    func markingAwayRestorable(_ restorable: Bool) -> WorkStatusSnapshot {
        var copy = self
        copy.isAwayRestorable = restorable
        return copy
    }

    var localizedStatus: String {
        if pendingSync {
            return "동기화 대기"
        }

        switch status {
        case .working:
            return "근무중"
        case .offWork:
            return "근무종료"
        }
    }
}

enum WorkStatus: Equatable {
    case working
    case offWork

    var localizedStatus: String {
        switch self {
        case .working:
            return "근무중"
        case .offWork:
            return "근무종료"
        }
    }
}

enum MenuBarStatusFormatter {
    /// 복원 창이 열려 있는 동안의 비근무 라벨. "오프"(2글자)보다 두 글자 길어 **메뉴바에서 가장 긴 라벨**이
    /// 된다 — 그래서 폭 예산(maxLabelWidth)을 렌더 테스트가 실측으로 못 박는다.
    static let awayTitle = "자리비움"

    /// 메뉴바 라벨 하나(아이콘 + 글자)가 차지해도 되는 최대 폭(pt).
    ///
    /// 메뉴바 오른쪽은 다른 앱과 나눠 쓰는 공간이고, 이 앱은 그중 한 칸을 상시 점유한다. 기존 최장 라벨은
    /// 근무 중 "00:00"(monospacedDigit 5칸)이었는데 자리비움(한글 4글자)이 그보다 넓어지므로, 늘어난 폭을
    /// 상수로 고정해 다음 사람이 문구를 더 길게 바꾸면 테스트가 먼저 막게 한다.
    /// (실측: 자리비움 77pt · 근무+복원표식 "23:59•" 76.5pt — 좌우 6pt 여백 포함 — 에 여유 5pt.
    ///  문구나 표식을 바꾸려면 이 숫자와 함께 바꿔라. **예산을 키워서 통과시키면 메뉴바에서 잘린다.**)
    static let maxLabelWidth: CGFloat = 82
    /// 복원 창 동안의 심볼. 마스코트 이미지가 없거나 자리 비움일 때만 그려진다(MenuBarStatusLabel).
    static let awaySymbol = "moon.zzz.fill"

    /// **근무 중에** 복원 창이 열려 있음을 알리는 심볼(v0.2.35).
    ///
    /// 왜 `awaySymbol`(달)이 아닌가: 사람은 이미 돌아와 일하는 중이라 "자고 있다"는 그림은 거짓말이 된다.
    /// 지금 알려야 할 사실은 상태가 아니라 **되돌릴 수 있는 마감이 남아 있다**는 것뿐이고, 되감기 화살표는
    /// 그 한 문장만 말한다. `.circle.fill` 가족을 유지해 기존 세 심볼과 굵기·크기가 어긋나지 않는다.
    ///
    /// `pendingSync`(exclamationmark.icloud.fill)와의 구분: 저쪽은 느낌표+구름이고 제목까지 "대기"로
    /// 갈아치워 시계가 사라진다. 이쪽은 시계를 그대로 두고 화살표+점만 더한다 — 두 고장이 겹쳐 보이면
    /// 둘 다 무의미해지므로 심볼과 제목이 **양쪽 다** 달라야 한다.
    static let awayRestorableWorkingSymbol = "arrow.uturn.backward.circle.fill"

    /// 근무 중 경과 시간 뒤에 붙는 표식 한 점.
    ///
    /// 근무 중 메뉴바에서 가장 많이 읽히는 정보는 MM:SS 다 — 제목을 "자리비움"으로 갈아치우면 시계가
    /// 사라져, 되살릴 시간을 알리려다 매일 보는 화면을 망가뜨린다. 그렇다고 심볼만 바꾸면 **글자는
    /// 평소와 한 픽셀도 같아서** 숫자만 흘깃 보는 사람(=대부분)은 그냥 지나간다. 그래서 시계는 살리고
    /// 뒤에 점 하나를 더한다 — 표식 목적은 예쁜 상태 표시가 아니라 "팝오버를 열어 보게 만드는 것"이다.
    /// (더해지는 폭 3pt. 최장 근무 라벨 "23:59•" 76.5pt 로 maxLabelWidth 안에 5.5pt 여유가 남는다.)
    static let awayRestorableMarker = "•"

    /// 복원 창이 열려 있는 동안 근무 라벨에 표식을 얹는다. 이미 붙어 있으면 두 번 붙이지 않는다 —
    /// `displayTitle` 은 스토어의 저장값(`refreshMenuBarTitle` 이 만든 값)을 받아 다시 얹기 때문에,
    /// 그 저장값이 언젠가 표식을 포함하게 되어도 "01:24••" 가 되지 않는다.
    static func markingRestorable(_ base: String, _ restorable: Bool) -> String {
        guard restorable, !base.hasSuffix(awayRestorableMarker) else { return base }
        return base + awayRestorableMarker
    }

    static func title(for snapshot: WorkStatusSnapshot) -> String {
        // 동기화 대기가 먼저다. 큐에 근무 조작이 남아 있다는 사실이 "자리 비웠다"보다 급하고,
        // 그 상태에서 자리비움을 그리면 아직 서버에 없는 마감을 이미 끝난 일처럼 보여 준다.
        if snapshot.pendingSync {
            return "대기"
        }

        switch snapshot.status {
        case .working:
            // 근무 중에도 복원 창은 열려 있을 수 있다 — 자동 시작이 방금 사람을 `.working` 으로 되돌린
            // 그 순간이 바로 그렇다. 여기서 표식을 접으면 돌아온 사람에게 능동 채널이 0이 된다.
            return markingRestorable(duration(snapshot.elapsedSeconds), snapshot.isAwayRestorable)
        case .offWork:
            return snapshot.isAwayRestorable ? awayTitle : "오프"
        }
    }

    static func symbolName(for snapshot: WorkStatusSnapshot) -> String {
        if snapshot.pendingSync {
            return "exclamationmark.icloud.fill"
        }

        switch snapshot.status {
        case .working:
            return snapshot.isAwayRestorable ? awayRestorableWorkingSymbol : "figure.run.circle.fill"
        case .offWork:
            return snapshot.isAwayRestorable ? awaySymbol : "pause.circle.fill"
        }
    }

    /// 메뉴바가 실제로 그리는 문자열.
    ///
    /// 왜 스토어의 파생 저장값(`menuBarTitle`)을 그대로 못 쓰는가: 그 값을 갱신하는 `refreshMenuBarTitle()` 은
    /// 근무 틱(`startedAt != nil`)에서만 불린다. 자리 비움은 **마감된 뒤**(= 비근무) 상태라 그 틱이 영영 돌지
    /// 않는다 — 저장값만 믿으면 라벨은 6시간 내내 "오프"로 남고 이 기능의 유일한 수동 채널이 죽는다.
    /// 그래서 자리 비움일 때만 스냅샷에서 다시 만든다(그 외에는 저장값을 한 글자도 건드리지 않는다).
    ///
    /// 근무 중(복원 창이 열린 채 자동 시작이 돌아간 상태)은 반대다: 저장값이 **유일하게 살아 있는 초**다.
    /// 스냅샷의 `elapsedSeconds` 는 틱이 재대입하지 않아 낡았으므로(전체 무효화 회피), 여기서 `title(for:)`
    /// 로 다시 만들면 메뉴바 시계가 옛 값에 얼어붙는다. 그래서 저장값은 그대로 두고 표식만 얹는다.
    static func displayTitle(stored: String, snapshot: WorkStatusSnapshot) -> String {
        guard !snapshot.pendingSync, snapshot.isAwayRestorable else { return stored }
        guard !snapshot.isWorking else { return markingRestorable(stored, true) }
        return title(for: snapshot)
    }

    static func duration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "%02d:%02d", hours, minutes)
        }

        let secs = safeSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func hoursMinutes(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        return "\(hours)시간 \(String(format: "%02d", minutes))분"
    }
}
