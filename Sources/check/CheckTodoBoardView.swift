// AppKit 은 **창 가시성 관찰 하나** 때문에만 들어온다(맨 아래 TodoBoardWindowVisibility — 왜 필요한지는
// 그쪽 주석에 실측과 함께 적어 뒀다). 그 밖에는 여전히 금지다:
// · 색을 AppKit 에서 가져오지 마라. 패널이 .darkAqua 로 고정돼 있어서, 시스템 외관을 따라가는 색
//   (NSColor.labelColor 류)을 하나라도 들이면 그 고정이 깨져 밝은 테마에서 글자가 사라진다.
// · 블러용 NSViewRepresentable 을 되살리지 마라(아래 삭제 사유 주석 참고).
import AppKit
import SwiftUI

// MARK: - 문구

/// 보드에 쓰이는 모든 문구. 뷰 밖 순수 enum 으로 둔 이유는 CheckMenuView 의 *EmptyMessage 들과 같다 —
/// 문구는 제품 결정이라 뷰를 그리지 않고도 값 하나로 리뷰·회귀 검증이 되어야 한다.
enum TodoBoardStrings {
    static let title = "오늘 할 일"
    static let close = "닫기"
    static let placeholder = "할 일 추가"
    /// 빈 상태를 2줄로 쪼갠 이유: 첫 줄은 사실(비었다), 둘째 줄은 다음 행동(적고 Enter).
    /// 한 줄로 합치면 처음 여는 사용자가 위쪽 입력 행을 못 찾는다 — 이 보드에는 다른 안내가 없다.
    static let emptyTitle = "오늘 할 일이 비어 있어요"
    static let emptyHint = "위에 적고 Enter를 누르세요"
    static let deleted = "삭제됨"
    static let undo = "되돌리기"
    /// 하단 캡션은 항상 떠 있는다. 같은 앱 안에서 근무 기록은 팀으로 나가기 때문에, 이 목록만은
    /// 서버로 가지 않는다는 사실을 매번 보여 줘야 사용자가 사적인 메모를 마음 놓고 적는다.
    static let footer = "이 목록은 내 맥에만 저장돼요"
    static let markDone = "완료로 표시"
    static let markUndone = "완료 취소"
    static let deleteItem = "삭제"
    static let editTitle = "할 일 수정"
    /// 헤더의 조절 버튼(닫기 왼쪽). '투명도'가 아니라 '진하기'인 이유는 **방향이 정확히 반대**여서다 —
    /// 옆에 뜨는 숫자는 `percentLabel`(= opacity × 100)이고 `opacity` 는 '뒤를 얼마나 가리는가'라서,
    /// 가장 투명한 끝이 "20%", 가장 불투명한 끝이 "95%" 로 나온다. 한국어에서 "투명도 20%"는 관용적으로
    /// *거의 안 투명함*을 뜻하니 화면이 거짓말을 하는 셈이고, VoiceOver 사용자는 보드가 거의 사라진 상태에서
    /// "20%" 를 듣는다. 코드도 이미 '진하기'로 말하고 있다(⌥+스크롤 주석: "위로 밀면 진해진다").
    ///
    /// ⌥ 안내를 툴팁에 함께 넣는 이유: 전 소스에서 ⌥+스크롤은 **주석에만** 있고 사용자에게 닿는 문구가
    /// 하나도 없어 스스로 발견할 사람이 없다. 같은 관례가 이미 있다 —
    /// CheckMenuView 의 "클릭: 앱 종료 · 길게 누르기: 자동 실행 설정". 툴팁은 폭 제한이 없다.
    static let opacityToggle = "배경 진하기 · ⌥ + 스크롤로도 조절"
    /// 슬라이더 자체의 접근성 이름. 버튼과 달리 이건 값을 가진 컨트롤이라 조작 안내를 뺀다
    /// (VoiceOver 는 "보드 배경 진하기, 55%, 슬라이더" 로 읽는다 — 안내가 붙으면 문장이 두 번 꺾인다).
    static let opacityLabel = "보드 배경 진하기"

    static func oldSection(count: Int) -> String {
        "오래된 항목 (\(count))"
    }

    /// 입력 카운터. 분모를 TodoRules.maxTitleLength 에서 읽어 문구와 실제 제한이 갈라지지 않게 한다.
    static func counter(current: Int) -> String {
        "\(current)/\(TodoRules.maxTitleLength)"
    }
}

// MARK: - 입력 길이 판정(순수)

/// 제목 입력 길이 제한 판정. 뷰에서 떼어 낸 이유는 '막는다 vs 자른다'가 사용자가 직접 확정한 제품 결정이라
/// 렌더 없이 값으로 지켜져야 하기 때문이다.
enum TodoDraftInput {
    /// 새 입력(proposed)을 실제로 반영할지 고른다. 반영하지 않을 땐 이전 값(current)을 그대로 돌려준다.
    static func accepted(current: String, proposed: String) -> String {
        // 지우는 방향(길이가 줄어듦)은 무조건 통과시킨다. 어떤 경로로든 100자를 넘긴 값이 필드에 들어와도
        // 이 예외가 없으면 사용자가 한 글자도 못 지우고 갇힌다.
        if proposed.count <= current.count { return proposed }
        // 늘리는 방향은 100자까지. 초과분만 잘라 넣는 게 아니라 변경 자체를 되돌린다 —
        // 자동 절단은 붙여넣은 문장 끝이 소리 없이 사라져 '분명 적었는데 없어졌다'로 읽힌다.
        return proposed.count <= TodoRules.maxTitleLength ? proposed : current
    }

    /// 카운터 문구. 한계에서 멀 땐 nil 이라 숫자가 아예 안 뜬다 — 평소에 늘 떠 있으면 글자 수를 세는 도구처럼
    /// 보여서, 짧게 적어야 한다는 압박을 준다.
    static func counterText(_ text: String) -> String? {
        let count = text.count
        guard count >= TodoRules.counterVisibleFrom else { return nil }
        return TodoBoardStrings.counter(current: count)
    }
}

// MARK: - 틴트
//
// 여기 있던 `TodoBoardTint`(틴트 알파 0.55 · hudWindow 실측 밝기 0.713)는 지웠다. 두 값 다
// **CheckTodoBoardAppearance.swift 가 정본**이다 — 그쪽은 같은 물리량으로 대비비를 계산해 하한·무릎점을
// 정하므로, 여기 사본을 남겨 두면 같은 화면을 두 기준으로 재게 되고 한쪽만 고쳐진 순간 조용히 갈라진다.
// 틴트 알파는 `TodoBoardAppearance.tintAlpha`(기본값 `defaultOpacity`), 순백 바탕이 hudWindow 재질을
// 통과한 뒤의 밝기는 `TodoBoardAppearance.hudOverWhite` 에서 가져온다.

// MARK: - 글자 그림자(순수 계산)

/// 낮은 투명도에서 글자 뒤에 까는 어두운 헤일로의 세기. 뷰 밖 순수 계산으로 뺀 이유는 두 가지다 —
/// (1) "기본값에서는 그림자가 한 톨도 없다"가 렌더 없이 값으로 지켜져야 하고,
/// (2) 임계 근처에서 얼마나 부드럽게 들어오는지가 숫자로 리뷰돼야 한다.
///
/// **글자 알파는 절대 건드리지 않는다.** 이 값은 글자 뒤에 깔리는 그림자의 진하기일 뿐이다 —
/// 글자를 흐리게 만들면 "투명하게 했더니 글자까지 유령이 됐다"가 되고, 그건 이 기능이 피하려던 바로 그 결과다.
enum TodoBoardTextShadow {
    /// 세기가 0 에서 1 까지 오르는 데 걸리는 스텝 수. 슬라이더 한 칸이 `TodoBoardAppearance.step` 이므로
    /// **두 칸**에 걸쳐 들어온다는 뜻이다(0.55 → 0.50 → 0.45 에서 0 → 0.5 → 1.0).
    ///
    /// 한 칸에 0→1 로 켜면 글자 생김새가 툭 바뀌어 고장으로 읽힌다. 두 칸으로 나눌 근거가 있는가 —
    /// 있다. 켜지는 첫 칸(0.50)은 틴트가 AA 돌파선(실측 0.5047)에 거의 닿아 있어 배경이 아직 대부분을
    /// 떠받치는 자리라, 여기서 그림자를 최대로 깔면 필요하지도 않은데 글자만 두꺼워 보인다.
    /// 그 다음 칸(0.45)부터는 배경이 확실히 손을 놓으므로 최대로 간다.
    static let rampSteps: Double = 2

    /// 획에 바짝 붙는 진한 그림자. **두 겹**으로 건다(아래 body 참고).
    ///
    /// 왜 두 겹인가: 그림자의 진하기는 그림자를 만드는 도형의 두께에 달려 있다. 13pt 본문의 획은 1.5pt 남짓이라
    /// 반경 1pt 블러만 지나도 알파가 절반 아래로 주저앉는다 — 색을 1.0 으로 줘도 실제로 깔리는 건 옅은 회색이다.
    /// 실측(순백 바탕·하한 0.20, 국소 대비): 한 겹 1.66:1, 두 겹 2.51:1, 두 겹 + 넓은 그림자 **5.14:1**.
    static let tightRadius: CGFloat = 1.0
    static let tightAlpha: Double = 1.0
    /// 그 바깥으로 넓게 퍼지는 그림자. 밝은 **사진** 위에서 글자 둘레의 잔무늬(잔디·창틀)를 눌러 준다 —
    /// 진한 그림자만 있으면 획 바로 옆은 어두워도 획과 획 사이로 밝은 무늬가 그대로 올라온다.
    /// 이 한 겹이 국소 대비를 2.51 → 5.14 로 끌어올린다(위 실측과 같은 조건).
    static let softRadius: CGFloat = 4.0
    static let softAlpha: Double = 0.7

    /// 0…1.
    ///
    /// 그림자를 그릴지 말지는 **오직 `needsTextShadow`** 가 정한다(임계 숫자를 이 파일에 복사하지 않는다).
    /// 꺼져 있으면 한 톨도 안 그린다 — 그래야 출고 기본값에서 이 기능 도입 전과 픽셀이 같다.
    ///
    /// 세기의 모양은 출고 기본값(`defaultOpacity`)을 0 으로 잡은 램프다. 임계(`blurKnee`)가 아니라
    /// 기본값에 걸어 둔 이유: 스텝이 0.05 인데 임계는 기본값에서 0.03 밖에 안 떨어져 있어, 임계를 기준으로
    /// 램프를 걸면 **슬라이더로 밟을 수 있는 눈금 사이에 중간값이 하나도 없다**(0.55 다음이 곧바로 0.50).
    /// 그러면 이름만 램프고 실제로는 하드 스위치다.
    static func strength(for appearance: TodoBoardAppearance) -> Double {
        guard appearance.needsTextShadow else { return 0 }
        let span = TodoBoardAppearance.step * rampSteps
        let ramp = (TodoBoardAppearance.defaultOpacity - appearance.tintAlpha) / span
        // 하한 0.5 는 '임계가 기본값 위로 올라가는' 설정 변경에 대한 방어다 — 그때도 판정이 켜졌는데
        // 그림자가 0 인 구간(아무도 대비를 책임지지 않는 구간)은 생기면 안 된다.
        return min(max(ramp, 0.5), 1)
    }
}

extension View {
    /// 헤일로를 거는 **유일한** 자리. 보드도 여기를 쓰고, 대비를 재는 테스트도 여기를 쓴다.
    ///
    /// 함수로 뽑은 이유가 이것이다 — 테스트가 겹수·반경을 자기 쪽에 베껴 두면, 여기서 한 겹을 빼도
    /// 측정값은 그대로라 "숫자는 여전히 5.14:1 인데 화면은 2.58:1" 인 상태가 조용히 통과한다(실제로 그랬다).
    func todoBoardTextHalo(strength: Double) -> some View {
        self
            // 진한 그림자를 **두 번** 겹친다(두 번째는 첫 번째의 결과 위에 다시 깔린다). 얇은 획이 만드는
            // 그림자가 한 겹으로는 너무 옅어서다 — 근거 숫자는 TodoBoardTextShadow.tightRadius 주석에 있다.
            .shadow(
                color: .black.opacity(TodoBoardTextShadow.tightAlpha * strength),
                radius: TodoBoardTextShadow.tightRadius
            )
            .shadow(
                color: .black.opacity(TodoBoardTextShadow.tightAlpha * strength),
                radius: TodoBoardTextShadow.tightRadius
            )
            .shadow(
                color: .black.opacity(TodoBoardTextShadow.softAlpha * strength),
                radius: TodoBoardTextShadow.softRadius
            )
    }

    /// 헤일로를 **잉크에만** 거는 자리. 세기는 환경(`todoBoardAppearance`)에서 읽는다.
    ///
    /// ☠︎ 왜 잉크만인가 — 헤일로를 보드 콘텐츠 **통째로** 걸던 시절, 그림자는 잉크뿐 아니라 입력창·배지·
    /// 캡슐 같은 **면**의 알파에서도 만들어졌다. 면은 글리프와 달리 넓고 꽉 찬 마스크라, 세 겹으로 쌓인
    /// 그림자가 면 뒤에서 거의 불투명한 검정 판이 된다. 실측(순백 바탕, 알파 0.20 입력창):
    /// 무릎점 바로 위 0.52 에서 채움 픽셀 118 → 한 칸 내린 0.50 에서 **80**, 하한 0.20 에서 **51**.
    /// 같은 구간에서 보드 바탕은 147 → 149 → 213 으로 **밝아진다**. 즉 사용자가 투명도를 한 칸 올리는
    /// 순간 박스만 검게 가라앉는다 — 실사용 신고("박스 색상은 오히려 더 진해져")의 정체가 이것이다.
    ///
    /// 그래서 면은 헤일로 밖에 둔다(`.background`/`.overlay` 로 감싸기 **전에** 잉크에만 건다).
    /// 잉크 쪽 계약은 그대로다: 글자·글리프·1px 선은 전부 이걸 통과하므로 낮은 투명도에서 헤일로가
    /// 국소 대비를 만든다(그 숫자는 CheckTodoBoardViewTests 의 haloLifts… 가 지킨다).
    func todoBoardInkHalo() -> some View {
        modifier(TodoBoardInkHalo())
    }
}

/// `todoBoardInkHalo()` 의 알맹이. ViewModifier 로 감싼 이유는 환경 읽기가 필요해서다
/// (extension 메서드 안에서는 @Environment 를 못 쓴다).
private struct TodoBoardInkHalo: ViewModifier {
    @Environment(\.todoBoardAppearance) private var appearance

    func body(content: Content) -> some View {
        content.todoBoardTextHalo(strength: TodoBoardTextShadow.strength(for: appearance))
    }
}

// MARK: - 재질 값 전달(환경)

/// 보드가 자식들에게 흘려보내는 재질 값(표면 배율 + 헤일로 세기의 출처).
///
/// 왜 생성자 인자가 아니라 Environment 인가 — 이 값이 필요한 자리가 입력 행·행·배지·버튼·인라인 편집기까지
/// 다섯 뷰에 흩어져 있다. 전부 저장 프로퍼티로 받으면 그 뷰들의 **메모리와이즈 이니셜라이저가 곧 계약**인
/// 이 파일에서 계약 다섯 개가 한꺼번에 흔들리고, 스냅샷 테스트의 호출부가 전부 따라 바뀐다.
///
/// 기본값을 출고 기본값(`TodoBoardAppearance()`)으로 두는 이유: 보드 밖에서 행·입력 행만 따로 그리는
/// 자리(스냅샷 테스트)가 출고 화면과 같은 그림을 얻어야 한다.
/// ☠︎ 대신 보드가 주입을 빠뜨리면 **조용히** 출고 그림으로 되돌아간다(= 이 수정 이전 상태). 그 배선은
/// '실제 보드 경로에서 표면이 실제로 옅어지는가'를 픽셀로 재는 테스트가 지킨다.
private struct TodoBoardAppearanceKey: EnvironmentKey {
    static let defaultValue = TodoBoardAppearance()
}

extension EnvironmentValues {
    var todoBoardAppearance: TodoBoardAppearance {
        get { self[TodoBoardAppearanceKey.self] }
        set { self[TodoBoardAppearanceKey.self] = newValue }
    }
}

extension Color {
    /// 보드 **표면(면 채움)** 전용 알파 배율. 이름을 따로 둔 이유는 grep 한 번으로 "어디에 곱했는지"가
    /// 드러나야 하기 때문이다 — 글자·선·글리프에 이게 붙어 있으면 그 자체가 계약 위반의 증거다.
    func todoBoardSurface(_ appearance: TodoBoardAppearance) -> Color {
        opacity(appearance.surfaceAlpha)
    }
}

// MARK: - 슬라이더 행 펼침 상태(순수)

/// 헤더의 투명도 조절 행이 펼쳐져 있는가. 뷰의 `@State` 안에 Bool 로 두지 않고 값 타입으로 뺀 이유는
/// '보드를 닫으면 접힌다'가 제품 결정이라 렌더 없이 검증돼야 하기 때문이다(TodoDraftInput 과 같은 이유).
///
/// 투명도 **값**은 영속되지만 이 패널은 아니다 — 조절기는 맞출 때만 필요한 도구라, 다음에 보드를 열었을 때도
/// 펼쳐져 있으면 목록 자리를 계속 갉아먹는다.
struct TodoBoardTuningState: Equatable {
    private(set) var isExpanded: Bool

    init(isExpanded: Bool = false) {
        self.isExpanded = isExpanded
    }

    mutating func toggle() {
        isExpanded.toggle()
    }

    /// 보드가 화면에서 사라질 때(닫기 버튼·Esc·캐릭터 재클릭 — 경로와 무관하게) 접는다.
    mutating func boardDidClose() {
        isExpanded = false
    }
}

// 여기 있던 `VisualEffectBackground`(NSViewRepresentable 로 감싼 NSVisualEffectView)는 지웠다.
// 블러는 패널의 contentView 자체가 담당한다(CheckTodoBoardWindow). SwiftUI `.background()` 로 넣으면
// 호스팅 뷰가 자기 레이어에 **불투명하게** 합성해 behind-window 블렌딩이 죽는다 — 백킹스토어 픽셀 실측으로
// 옛 배치는 알파 1.000 의 평평한 회색, 현 배치는 0.549 였다. 쓰지 않는 껍데기를 남겨 두면 다음 사람이
// "블러는 여기 있네" 하고 되돌려 놓아 '뒤를 완전히 가린다'는 신고가 그대로 재발한다.

// MARK: - 보드

/// 근무 중 떠 있는 캐릭터를 클릭하면 열리는 할 일 보드(300×400). 서버를 모르고 store 도 모른다 —
/// 값 + 클로저만 받아, 렌더 테스트가 픽스처만으로 모든 상태(편집 중·삭제 대기·오래된 항목 펼침)를 재현한다.
struct CheckTodoBoardView: View {
    /// 이미 필터·정렬된 '활성' 목록(오늘 완료한 항목 포함). 뷰는 순서를 바꾸지 않는다.
    let items: [TodoItem]
    /// 7일 이상 이월된 미완료 항목. 비어 있지 않을 때만 하단 접힘 영역이 생긴다.
    let oldItems: [TodoItem]
    let todayKey: String
    let isOldSectionExpanded: Bool
    let editingID: UUID?
    let pendingDeleteID: UUID?
    @Binding var draft: String
    let onSubmitDraft: () -> Void
    let onToggleDone: (UUID) -> Void
    let onBeginEdit: (UUID) -> Void
    let onCommitEdit: (UUID, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onUndoDelete: (UUID) -> Void
    let onToggleOldSection: () -> Void
    let onClose: () -> Void
    /// 배경 두 겹의 세기를 정하는 값(사용자 조절). 기본값을 주지 않는 이유는 배선 누락을 **컴파일 에러로**
    /// 잡기 위해서다 — 기본값이 있으면 보드를 띄우는 쪽이 이 인자를 빼먹어도 조용히 출고 기본값으로 그려져
    /// "슬라이더는 움직이는데 화면은 안 바뀐다"가 된다(테스트도 뷰만 보면 통과한다).
    var appearance: TodoBoardAppearance
    /// 슬라이더가 만든 **절대값**을 그대로 올려보낸다(clamp·저장·통지는 전부 스토어 몫이다).
    /// 드래그 중 연속 호출되지만 스토어가 값이 실제로 바뀔 때만 통지하므로 창을 매 프레임 다시 그리지 않는다.
    var onOpacityChange: (Double) -> Void
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안쪽을 못 그린다).
    /// 빈 상태의 세로 위치처럼 '리스트 영역 높이 안에서 어디에 놓이는가'는 이 플래그 없이는 그림으로 확인이 안 된다.
    /// 앱에서는 항상 false — 기본값이라 보드를 띄우는 쪽(패널)은 이 인자를 몰라도 된다.
    /// CheckMenuView 의 clipsOverflowInsteadOfScroll 과 같은 관례이고, 같은 이유로 계약 맨 끝에 둔다
    /// (메모리와이즈 이니셜라이저의 기존 인자 순서를 흔들지 않는다).
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 테스트 전용: 첫 등장에서 조절 행을 펼친 **상태로 씨를 뿌린다**(previewHovering 과 같은 관례).
    ///
    /// 여기가 `||` 강제 표시가 아니라 **씨앗**인 게 중요하다. 강제였다면 '보드를 닫으면 접힌다'를
    /// 영영 검증할 수 없다(항상 펼쳐진 채로 그려지니까). 씨앗이면 그 뒤로는 진짜 `@State` 가 굴러가므로,
    /// 실제 패널에 얹어 놓고 창을 내렸다 올려서 접혔는지를 그림으로 확인할 수 있다.
    /// 앱에서는 항상 false.
    var previewExpandsOpacityRow: Bool = false

    // 저장 프로퍼티는 위 계약이 전부다(포커스 상태는 TodoBoardDraftField 가 들고 있다).
    // 예외는 아래 조절 행 펼침 하나 — 이건 밖으로 새면 안 되는 값이다(보드를 닫으면 사라져야 한다).
    // @State 는 메모리와이즈 이니셜라이저의 인자로 잡히지 않으므로 계약을 흔들지 않는다.
    /// 패널 쪽(NSVisualEffectView 레이어)도 같은 값으로 깎아야 모서리가 어긋나지 않아 internal 이다.
    static let cornerRadius: CGFloat = 14

    @State private var tuning = TodoBoardTuningState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // 펼친 행은 헤더 **아래·구분선 위**에 끼운다. 구분선 아래(입력 상자 옆)로 내리면 조절기가
            // 내용의 일부처럼 보이고, 오버레이로 띄우면 이미 반투명한 판 위에 반투명 판이 한 겹 더 얹혀
            // 하필 가장 안 읽히는 낮은 투명도에서 조절기 자신이 안 보인다.
            if tuning.isExpanded {
                opacityRow
            }
            PanelDivider().todoBoardInkHalo().padding(.vertical, 8)
            draftRow
            list.padding(.top, 6)
            footer
        }
        .padding(12)
        // 헤일로는 여기서 통째로 걸지 않는다. 예전에는 이 자리에 `.todoBoardTextHalo` 한 줄이 있었고,
        // 그게 제목·본문·체크 원·아이콘을 한꺼번에 지켜 주는 대신 **입력창·배지·캡슐 같은 면까지** 그림자
        // 원본으로 삼았다 — 면은 마스크가 넓고 꽉 차 있어 세 겹 그림자가 검은 판이 된다(숫자는
        // `todoBoardInkHalo` 주석). 지금은 잉크마다 `todoBoardInkHalo()` 를 걸고, 면은 그 바깥에 둔다.
        // 지켜야 할 것은 그대로다: 글자·보조 텍스트·배지 글자뿐 아니라 **체크 원 테두리와 아이콘**도
        // 전부 잉크로 분류해 헤일로를 받는다(미완료 체크 원 테두리는 흰색 알파 0.32 라 밝은 바탕에서
        // 글자보다 먼저 사라진다).
        //
        // 표면 배율·헤일로 세기는 여기서 한 번만 흘려보낸다(자식들이 각자 슬라이더 값을 다시 받지 않는다).
        .environment(\.todoBoardAppearance, appearance)
        // 크기는 보드를 띄우는 쪽(패널)이 정한다. 여기서 300×400을 박으면 크기 상수가 두 파일로 갈라진다.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(boardBackground)
        // style 은 **반드시 .continuous** 로 명시한다(생략 금지). 패널 쪽은 CALayer 로 같은 모서리를 자르는데
        // CALayer 의 기본 곡률은 원호(.circular)라 cornerCurve 를 .continuous 로 맞춰 놨다.
        // 두 클립의 곡선 종류가 갈리면 반지름이 같아도 곡선이 달라, 재질(레이어가 자름)과
        // 틴트·테두리(SwiftUI 가 자름)의 경계가 몇 px 어긋나 모서리에 지저분한 실선이 남는다.
        // 반지름도 Self.cornerRadius 하나에서만 나온다 — 패널이 이 값을 그대로 읽어 레이어에 쓴다.
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        // 보드가 화면에서 내려가면 조절 행을 접는다. 값은 남고 도구만 치운다.
        // `.onDisappear` 가 아닌 이유는 TodoBoardWindowVisibility 주석에 있다(그건 여기서 영영 안 불린다).
        .onBoardWindowHidden { tuning.boardDidClose() }
        .onAppear {
            // 테스트가 뿌린 씨앗만 반영한다(앱에서는 플래그가 false 라 아무 일도 없다).
            if previewExpandsOpacityRow { tuning = TodoBoardTuningState(isExpanded: true) }
        }
    }

    /// 여기서는 **틴트만** 얹는다. 블러를 여기 넣으면(= NSVisualEffectView 를 SwiftUI 배경으로 감싸면)
    /// 호스팅 뷰가 자기 레이어에 불투명하게 합성해 behind-window 블렌딩이 죽고 보드가 뒤를 완전히 가린다 —
    /// 백킹스토어 픽셀 실측으로 그 배치는 알파 1.000, 현재 배치는 0.549 였다. 블러는 패널의 contentView 몫이다.
    ///
    /// 틴트가 필요한 이유는 대비다. 블러만 두면 밝은 바탕화면 위에서 흰 글자가 그대로 사라진다.
    /// 알파가 나오는 자리는 여기 **하나**다(리터럴을 여기 다시 적지 말 것) — 사용자가 슬라이더로 정한 값이
    /// `appearance.tintAlpha` 로 들어온다. 나머지 한 겹(블러 뷰의 alphaValue)은 패널 쪽이 같은 값에서 파생한다.
    private var boardBackground: some View {
        CheckTheme.panel.opacity(appearance.tintAlpha)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(TodoBoardStrings.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .todoBoardInkHalo()
            Spacer(minLength: 6)
            // 닫기 **왼쪽**에 둔다. 오른쪽 끝은 어느 창에서나 닫기 자리라, 그 자리를 다른 버튼에 내주면
            // 보드를 닫으려던 손이 조절 행을 펼친다.
            TodoBoardOpacityButton(isExpanded: tuning.isExpanded) { tuning.toggle() }
            TodoBoardCloseButton(action: onClose)
        }
        .frame(height: 24)
    }

    /// 펼쳐졌을 때만 그려지는 얇은 조절 행. **평소엔 아예 없다** — 늘 떠 있으면 목록 자리를 상시로 갉아먹고,
    /// 하루에 한 번 만질까 말까 한 값이 보드를 열 때마다 눈에 들어온다.
    ///
    /// 목록 높이 처리: 오버레이가 아니라 **레이아웃에 끼워** 목록을 그만큼 줄인다(약 28pt, 400pt 보드에서 7%).
    /// 오버레이면 목록 위에 겹쳐 항목 한 줄을 가리는데, 하필 조절 중에는 그 가려진 줄이 "지금 이 설정에서
    /// 글자가 읽히는가"를 판단할 표본이다. 줄어드는 쪽은 목록 **아래끝**이라(위에서부터 쌓인다) 보고 있던
    /// 행이 밀려나지 않고, 빈 상태는 줄어든 영역의 한가운데로 다시 앉는다.
    private var opacityRow: some View {
        // 클로저를 지역 상수로 받아 바인딩에 넘긴다(입력 행의 draft 바인딩과 같은 관례) —
        // 저장 프로퍼티를 그대로 넘기면 뷰 전체가 클로저 안으로 끌려 들어간다.
        let notify = onOpacityChange
        return HStack(spacing: 8) {
            Slider(
                // get 은 clamp 를 거친 값(tintAlpha)이다 — 저장된 값이 범위 밖이어도 손잡이가 레일 밖으로 안 나간다.
                value: Binding(get: { appearance.tintAlpha }, set: { notify($0) }),
                in: TodoBoardAppearance.minOpacity...TodoBoardAppearance.maxOpacity,
                step: TodoBoardAppearance.step
            )
            .controlSize(.small)
            .tint(CheckTheme.accent)
            .accessibilityLabel(TodoBoardStrings.opacityLabel)
            .accessibilityValue(appearance.percentLabel)
            // 퍼센트는 문자열 만들기까지 appearance 몫이다(반올림 격자가 거기 한 곳에만 있어야 표시가 안 흔들린다).
            Text(appearance.percentLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.secondaryText)
                .monospacedDigit()
                // 폭을 고정한다. 안 그러면 20%↔100% 사이에서 라벨 폭이 바뀌며 슬라이더 트랙 길이가 같이
                // 늘었다 줄었다 해서, 끄는 중에 손잡이가 손끝 아래에서 미끄러진다.
                .frame(width: 34, alignment: .trailing)
        }
        // 이 행만은 슬라이더까지 통째로 헤일로 안에 둔다. 슬라이더는 AppKit 백킹 컨트롤이라 ImageRenderer 로는
        // 노란 막대로만 찍혀 **낮은 투명도에서 실제로 얼마나 보이는지를 잴 수단이 없다** — 잴 수 없는 것에서
        // 가독 보조를 걷어내지는 않는다. 면이 아니라 컨트롤이라 '검은 판때기' 문제와도 무관하다.
        .todoBoardInkHalo()
        .frame(height: 22)
        .padding(.top, 6)
    }

    private var draftRow: some View {
        TodoBoardDraftField(
            draft: $draft,
            // 편집 중인 행이 있는 채로 열렸다면(보드 재열기 등) 그쪽 포커스를 빼앗지 않는다.
            autoFocuses: editingID == nil,
            onSubmit: onSubmitDraft
        )
    }

    /// 목록은 스크롤 영역 안에 들어간다. 스크롤 밖으로 넘치는 만큼은 ImageRenderer 가 그리지 못하므로
    /// 그림으로 확인해야 할 알맹이는 TodoBoardRowStack 으로 빼 놨다(테스트는 그쪽을 직접 그린다).
    @ViewBuilder
    private var list: some View {
        let stack = TodoBoardRowStack(
            items: items,
            oldItems: oldItems,
            todayKey: todayKey,
            isOldSectionExpanded: isOldSectionExpanded,
            editingID: editingID,
            pendingDeleteID: pendingDeleteID,
            onToggleDone: onToggleDone,
            onBeginEdit: onBeginEdit,
            onCommitEdit: onCommitEdit,
            onCancelEdit: onCancelEdit,
            onDelete: onDelete,
            onUndoDelete: onUndoDelete,
            onToggleOldSection: onToggleOldSection
        )
        if stack.isEntirelyEmpty || clipsOverflowInsteadOfScroll {
            // 스크롤할 게 하나도 없으면 ScrollView 를 씌우지 않는다. 씌우면 세로로 무한 높이가 제안되어
            // 빈 상태의 frame(maxHeight:.infinity) 가 이상 높이(=두 줄 높이)로 접히고, 세로 가운데 정렬이
            // 조용히 상단 붙임으로 되돌아간다. 스냅샷 경로(clipsOverflow…)도 같은 이유로 여기로 온다.
            // .clipped() 는 ScrollView 가 하던 자르기를 그대로 흉내 낸다 — 두 경로의 잘림 규칙이 갈라지면
            // 한쪽에서만 재현되는 잘림 버그가 다시 생긴다.
            stack
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                stack
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var footer: some View {
        Text(TodoBoardStrings.footer)
            .font(.caption2)
            .foregroundStyle(CheckTheme.secondaryText.opacity(0.75))
            .lineLimit(1)
            .todoBoardInkHalo()
            .padding(.top, 6)
    }
}

// MARK: - 목록 본문

/// 스크롤 영역 안에 들어가는 목록 본문(활성 행 + 빈 상태 + 오래된 항목 접기). 보드에서 떼어 낸 이유는
/// ImageRenderer 가 ScrollView 안쪽을 그리지 못하기 때문이다 — 스크롤을 벗기고 이 뷰만 그리면
/// 행 배치·말줄임·배지를 그림으로 확인할 수 있다(CheckMenuView 의 clipsOverflowInsteadOfScroll 과 같은 목적).
struct TodoBoardRowStack: View {
    let items: [TodoItem]
    let oldItems: [TodoItem]
    let todayKey: String
    let isOldSectionExpanded: Bool
    let editingID: UUID?
    let pendingDeleteID: UUID?
    let onToggleDone: (UUID) -> Void
    let onBeginEdit: (UUID) -> Void
    let onCommitEdit: (UUID, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onUndoDelete: (UUID) -> Void
    let onToggleOldSection: () -> Void
    /// 스냅샷 전용: hover 로만 뜨는 ✕ 를 모든 행에 강제로 그린다. 앱에서는 항상 false.
    var previewHovering: Bool = false

    /// 목록에 그릴 게 하나도 없는 상태. 이때만 빈 상태가 리스트 영역을 통째로 먹는다.
    var isEntirelyEmpty: Bool { items.isEmpty && oldItems.isEmpty }

    var body: some View {
        if isEntirelyEmpty {
            // 리스트 영역(400pt 보드에서 약 278pt) 전체를 먹고 세로 가운데에 앉는다. 상단 28pt 만 띄우면
            // 두 줄이 입력 상자 바로 밑에 붙고 아래 240pt 가 통째로 비어, 목록이 없는 게 아니라
            // 뭔가 그리다 만 화면처럼 읽힌다.
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if items.isEmpty {
                    // oldItems 가 있어도 빈 상태를 보인다 — '오늘 할 일'이 비었다는 건 사실이고,
                    // 아래 접힌 영역은 오늘의 목록이 아니라 따로 모아 둔 것이다.
                    // 이 경우엔 세로 중앙으로 내리지 않는다. 아래에 접힘 머리가 이어지므로,
                    // 가운데로 내리면 두 줄이 그 머리를 밀어내며 순서가 뒤엉킨 것처럼 보인다.
                    emptyState.padding(.vertical, 24)
                } else {
                    ForEach(items) { item in
                        row(item)
                    }
                }
                if !oldItems.isEmpty {
                    oldSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ item: TodoItem) -> some View {
        TodoBoardRowView(
            item: item,
            todayKey: todayKey,
            isEditing: editingID == item.id,
            isPendingDelete: pendingDeleteID == item.id,
            onToggleDone: onToggleDone,
            onBeginEdit: onBeginEdit,
            onCommitEdit: onCommitEdit,
            onCancelEdit: onCancelEdit,
            onDelete: onDelete,
            onUndoDelete: onUndoDelete,
            previewHovering: previewHovering
        )
    }

    /// 빈 상태 두 줄. 가로는 언제나 가운데다 — 목록이 없을 때 좌상단에 두 줄만 붙어 있으면 '로딩 실패'처럼 읽힌다.
    /// 안쪽 VStack(alignment:.center) 는 두 줄끼리만 맞추므로, 판 폭 한가운데로 보내는 건 바깥
    /// frame(maxWidth:.infinity, alignment:.center) 쪽이다(둘 중 하나만 있으면 왼쪽에 붙는다).
    /// 세로 위치는 부르는 쪽이 정한다 — 목록이 통째로 비었을 때와 아래에 접힘 영역이 있을 때가 다르다.
    private var emptyState: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(TodoBoardStrings.emptyTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text(TodoBoardStrings.emptyHint)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText.opacity(0.8))
        }
        // 두 줄 다 잉크다(면이 없다) — 한 번에 걸어도 '검은 판' 문제가 생기지 않는다.
        .todoBoardInkHalo()
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 7일 넘게 끌고 온 미완료를 조용히 모아 두는 자리. 지우거나 옮기지 않고 접기만 하는 이유는
    /// 사용자가 자동 삭제·자동 이동을 명시적으로 뺐기 때문이다 — 목록에서 시야만 덜어 준다.
    private var oldSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            PanelDivider().todoBoardInkHalo().padding(.vertical, 4)
            Button(action: onToggleOldSection) {
                HStack(spacing: 6) {
                    Image(systemName: isOldSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(TodoBoardStrings.oldSection(count: oldItems.count))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(CheckTheme.secondaryText)
                // 글리프(chevron)와 글자뿐이라 통째로 잉크다.
                .todoBoardInkHalo()
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodoBoardStrings.oldSection(count: oldItems.count))
            if isOldSectionExpanded {
                ForEach(oldItems) { item in
                    row(item)
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - 입력 행

/// 새 할 일 입력 행(32pt). 보드 본체에서 떼어 낸 이유는 포커스 상태 때문이다 — @FocusState 같은 private
/// 저장 프로퍼티가 CheckTodoBoardView 안에 있으면 그쪽 메모리와이즈 이니셜라이저 접근 수준이 흔들린다.
struct TodoBoardDraftField: View {
    @Binding var draft: String
    /// 보드가 열리는 순간 커서를 여기에 둘지. 열자마자 바로 적을 수 있어야 캐릭터를 누른 흐름이 끊기지 않는다.
    let autoFocuses: Bool
    let onSubmit: () -> Void

    @FocusState private var focused: Bool
    /// 표면 배율만 쓴다(헤일로 세기는 `todoBoardInkHalo` 가 알아서 읽는다).
    @Environment(\.todoBoardAppearance) private var appearance

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                // 플레이스홀더를 직접 깐다(CredentialField 와 같은 방식) — 기본 TextField 플레이스홀더는
                // 이 팔레트에서 너무 밝게 나와 이미 입력된 글자처럼 보인다.
                if draft.isEmpty {
                    Text(TodoBoardStrings.placeholder)
                        .font(.subheadline)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(CheckTheme.primaryText)
                    .tint(CheckTheme.accent)
                    .lineLimit(1)
                    .focused($focused)
                    .accessibilityLabel(TodoBoardStrings.placeholder)
                    .onSubmit(onSubmit)
            }
            // 카운터는 90자부터만 나타난다. 늘 떠 있으면 글자 수를 세는 도구처럼 보여 짧게 쓰라는 압박이 된다.
            if let counter = TodoDraftInput.counterText(draft) {
                Text(counter)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        // 잉크(플레이스홀더·입력 글자·카운터)에만 헤일로. **아래 배경보다 앞**에 있어야 채움이 그림자
        // 원본에서 빠진다 — 이 순서가 뒤집히면 신고된 '검은 박스'가 그대로 돌아온다.
        .todoBoardInkHalo()
        .padding(.horizontal, 10)
        .frame(height: 32)
        // 채움은 사용자 투명도에 **연동**된다. `CheckTheme.fieldFill` 은 검정(0.20)이라, 고정으로 두면
        // 바탕이 걷힐수록 이 사각형만 남아 밝은 화면 위의 검은 판이 된다(실사용 신고).
        // 팔레트(CheckTheme) 는 앱 전체가 공유하므로 그쪽을 고치지 않고 여기서 파생값을 쓴다.
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckTheme.fieldFill.todoBoardSurface(appearance))
        )
        // 테두리는 배율을 **곱하지 않는다**. 1px 선은 면적이 없어 밝기에 거의 기여하지 않는 대신,
        // 채움이 옅어진 구간에서 "여기가 입력하는 곳"을 남기는 유일한 단서다. 선이므로 잉크로 분류해
        // 헤일로도 그대로 받는다(흰색 0.14 는 밝은 바탕에서 헤일로 없이는 사라진다).
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
                .todoBoardInkHalo()
        )
        .onChange(of: draft) { previous, next in
            let accepted = TodoDraftInput.accepted(current: previous, proposed: next)
            // != 가드 없이 매번 되쓰면 한글 IME 조합 중간 상태에서 대입 루프가 돈다(CredentialField 와 같은 이유).
            if accepted != next { draft = accepted }
        }
        .onAppear {
            if autoFocuses { focused = true }
        }
    }
}

// MARK: - 창 가시성 관찰

/// "보드가 화면에서 내려갔다"를 SwiftUI 쪽으로 끌어오는 최소 관찰자.
///
/// ☠︎ 왜 `.onDisappear` 로 안 되는가 — 보드 패널은 닫을 때 **파괴되지 않는다**. 컨트롤러는 `orderOut` 만 하고
/// 패널·호스팅 뷰를 붙들고 있다(입력 상태를 남기고 재생성 깜빡임을 피하려는 의도적 설계, CheckTodoBoardWindow
/// 의 panelStorage 주석). 뷰 계층이 그대로라 SwiftUI 는 사라졌다고 보지 않는다 —
/// **실측: orderOut 후 onDisappear 0회, 다시 띄워도 onAppear 0회(최초 1회로 끝).**
/// 그래서 창 자체를 봐야 한다.
///
/// 신호로 `isVisible` KVO 를 고른 근거도 실측이다: 같은 패널에서
/// `didChangeOcclusionState` 는 **한 번도 오지 않았고**(화면 밖/비활성 창은 occlusion 이 안 움직인다),
/// `willClose` 는 `close()` 전용이라 `orderOut` 에서는 오지 않는다. `isVisible` KVO 만 orderOut·재표시
/// 양쪽에서 정확히 한 번씩 왔다.
struct TodoBoardWindowVisibility: NSViewRepresentable {
    /// 창이 화면에서 내려갈 때마다 불린다(다시 띄우면 다음 내려감에 또 불린다).
    let onHidden: () -> Void

    func makeNSView(context: Context) -> NSView {
        WatcherView(onHidden: onHidden)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 클로저는 뷰가 다시 만들어질 때마다 새것이 온다. 갈아 끼우지 않으면 첫 렌더의 낡은 상태를 붙든다.
        (nsView as? WatcherView)?.onHidden = onHidden
    }

    /// 그림을 그리지 않는 0pt 뷰. 오직 자기 window 를 붙잡기 위해 계층에 존재한다.
    final class WatcherView: NSView {
        var onHidden: () -> Void
        private var token: NSKeyValueObservation?

        init(onHidden: @escaping () -> Void) {
            self.onHidden = onHidden
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // 창이 바뀌면 옛 관찰은 버린다 — 안 그러면 이미 남의 것이 된 창을 계속 듣는다.
            token = window?.observe(\.isVisible, options: [.new]) { [weak self] _, change in
                guard change.newValue == false else { return }
                // 창 순서 조작은 메인 스레드에서만 일어난다(AppKit 계약)이므로 홉 없이 그 자리에서 부른다.
                // `Task { @MainActor in … }` 로 한 턴 미루면 안 된다 — 메인 액터가 막혀 있는 동안에는 그 턴이
                // 아예 오지 않아 콜백이 통째로 사라진다(테스트 프로세스에서 실측: KVO 는 왔는데 Task 는 안 돎).
                MainActor.assumeIsolated { self?.onHidden() }
            }
        }
    }
}

extension View {
    /// 이 뷰가 얹힌 창이 화면에서 내려갈 때 알려 준다. 0pt 배경으로 끼우므로 레이아웃에 영향이 없다.
    func onBoardWindowHidden(perform action: @escaping () -> Void) -> some View {
        background(TodoBoardWindowVisibility(onHidden: action).frame(width: 0, height: 0))
    }
}

// MARK: - 헤더 투명도 버튼

/// 조절 행을 여닫는 버튼. 생김새·크기는 TodoBoardCloseButton 과 맞춘다(같은 24pt 헤더에 나란히 서므로
/// 한쪽만 크면 두 버튼의 중심선이 어긋난다).
///
/// 글리프가 `circle.lefthalf.filled` 인 이유: 반쯤 채운 원은 macOS·iOS 전반에서 불투명도/대비를 뜻하는
/// 관용 기호다(디스플레이 설정의 대비, 사진 앱의 노출 계열). 슬라이더 아이콘(`slider.horizontal.3`)은
/// '설정 전반'으로 읽혀 사용자가 여기서 다른 옵션까지 기대하게 된다.
struct TodoBoardOpacityButton: View {
    /// 펼쳐져 있으면 버튼이 계속 켜져 보인다 — 아래 행이 어디서 왔는지 알려 주는 유일한 단서다.
    let isExpanded: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.todoBoardAppearance) private var appearance

    var body: some View {
        Button(action: action) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isExpanded || hovering ? CheckTheme.primaryText : CheckTheme.secondaryText)
                // 글리프는 잉크(헤일로 받음), 원은 면(배율 받음). 순서가 곧 그 구분이다.
                .todoBoardInkHalo()
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        Color.white
                            .opacity(isExpanded || hovering ? 0.14 : 0.06)
                            .todoBoardSurface(appearance)
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(TodoBoardStrings.opacityToggle)
        .accessibilityLabel(TodoBoardStrings.opacityToggle)
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }
}

// MARK: - 헤더 닫기 버튼

/// 헤더 전용 닫기 버튼. IconButton 을 쓰지 않은 이유는 그쪽 히트영역이 27pt 라 24pt 헤더를 위아래로 밀어
/// 구분선까지 겹치기 때문이다. 생김새(원형 호버 배경 + secondaryText)는 IconButton 과 맞춘다.
struct TodoBoardCloseButton: View {
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.todoBoardAppearance) private var appearance

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? CheckTheme.primaryText : CheckTheme.secondaryText)
                .todoBoardInkHalo()
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.06).todoBoardSurface(appearance))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(TodoBoardStrings.close)
        .accessibilityLabel(TodoBoardStrings.close)
    }
}

// MARK: - 항목 행

/// 할 일 한 줄. 세 모습(평소 / 편집 중 / 삭제 대기)이 **같은 높이**를 쓰도록 숫자를 맞춰 놨다 —
/// 상태가 바뀔 때마다 행이 커졌다 작아지면 아래 행들이 밀려 다음 클릭 목표가 손끝에서 도망간다.
/// 내부 치수: 세로 패딩 6 + (체크 16 / 편집 필드 18 / 되돌리기 버튼 22) ≤ minHeight 34.
struct TodoBoardRowView: View {
    let item: TodoItem
    let todayKey: String
    let isEditing: Bool
    let isPendingDelete: Bool
    let onToggleDone: (UUID) -> Void
    let onBeginEdit: (UUID) -> Void
    let onCommitEdit: (UUID, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onUndoDelete: (UUID) -> Void
    /// 스냅샷 전용: 마우스 없이도 hover ✕ 를 그린다(ImageRenderer 엔 포인터가 없다). 앱에서는 항상 false.
    var previewHovering: Bool = false

    static let minHeight: CGFloat = 34

    /// 완료한 줄의 글자색. secondaryText(0.68)보다 더 흐리다 — 남아 있되 시선을 끌지 않는 게 목적이라
    /// 미완료(0.94)와 두 단계 벌려 놨다.
    private static let doneText = Color.white.opacity(0.42)

    @State private var hovering = false
    @Environment(\.todoBoardAppearance) private var appearance

    var body: some View {
        Group {
            if isPendingDelete {
                pendingDeleteBody
            } else {
                normalBody
            }
        }
        // 좌우 여백은 두지 않는다. 잘림은 여백으로 가릴 문제가 아니라 체크 원을 strokeBorder 로 그려
        // 근본을 없앴고(위 checkButton 주석), 여기서 2pt 를 들여쓰면 헤더 제목·구분선·입력 상자·하단 캡션이
        // 다 맞춰 서 있는 왼쪽 기준선에서 행만 혼자 밀려난다.
        .frame(maxWidth: .infinity, minHeight: Self.minHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var normalBody: some View {
        HStack(alignment: .top, spacing: 8) {
            checkButton
            if let badge = carryBadge {
                carryBadgeView(badge)
            }
            if isEditing {
                // 편집 필드는 남는 폭을 전부 먹는다. 여기에 Spacer 를 같이 두면 둘 다 '늘어나는 뷰'라
                // HStack 이 남은 폭을 반씩 나눠 주고, 필드가 행의 절반으로 쪼그라든다.
                TodoBoardTitleEditor(
                    initialTitle: item.title,
                    onCommit: { onCommitEdit(item.id, $0) },
                    onCancel: onCancelEdit
                )
            } else {
                titleText
                Spacer(minLength: 4)
            }
            deleteButton
        }
        .padding(.vertical, 6)
    }

    /// 삭제 직후 5초간 그 자리에 남는 모습. 행이 즉시 사라지면 실수로 지운 걸 되돌릴 자리 자체가 없어진다.
    private var pendingDeleteBody: some View {
        HStack(spacing: 8) {
            Text(TodoBoardStrings.deleted)
                .font(.subheadline)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                .todoBoardInkHalo()
            Spacer(minLength: 4)
            Button {
                onUndoDelete(item.id)
            } label: {
                Text(TodoBoardStrings.undo)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.accent)
                    .todoBoardInkHalo()
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    // 채움은 면 → 배율. 테두리는 선 → 그대로 + 헤일로.
                    // 5초 안에 눌러야 하는 버튼이라, 면이 옅어져도 윤곽은 남아 있어야 한다.
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(CheckTheme.accent.opacity(0.14).todoBoardSurface(appearance))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1)
                            .todoBoardInkHalo()
                    )
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodoBoardStrings.undo)
        }
        .padding(.vertical, 6)
    }

    private var checkButton: some View {
        Button {
            onToggleDone(item.id)
        } label: {
            ZStack {
                // stroke 가 아니라 **strokeBorder** 다. stroke 는 선 굵기의 절반(0.75pt)을 도형 바깥에 그려
                // 16pt 프레임을 넘어가고, 목록을 감싼 컨테이너가 그 삐져나온 만큼을 잘라 낸다 —
                // 사용자가 신고한 '원 왼쪽 끝이 살짝 잘림'의 정체다. strokeBorder 는 안쪽으로만 그린다.
                // 테두리에는 배율을 곱하지 않는다. 채움이 옅어질수록 이 선 하나가 '여기 항목이 있다'를
                // 지키는 유일한 단서가 되기 때문이다(미완료는 흰색 0.32 라 원래도 가장 먼저 사라진다).
                Circle()
                    .strokeBorder(
                        item.isDone ? CheckTheme.working.opacity(0.75) : Color.white.opacity(0.32),
                        lineWidth: 1.5
                    )
                    .todoBoardInkHalo()
                if item.isDone {
                    // 완료 표시의 **면**만 배율을 받는다. 체크 글리프는 잉크라 그대로다 —
                    // 면과 글리프가 같이 옅어지면 완료/미완료 구분 자체가 사라진다.
                    Circle().fill(CheckTheme.working.opacity(0.20).todoBoardSurface(appearance))
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(CheckTheme.working)
                        .todoBoardInkHalo()
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(item.isDone ? TodoBoardStrings.markUndone : TodoBoardStrings.markDone)
        .accessibilityLabel(item.isDone ? TodoBoardStrings.markUndone : TodoBoardStrings.markDone)
    }

    private var titleText: some View {
        Text(item.title)
            .font(.subheadline)
            .foregroundStyle(item.isDone ? Self.doneText : CheckTheme.primaryText)
            .strikethrough(item.isDone, color: Self.doneText)
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .todoBoardInkHalo()
            .fixedSize(horizontal: false, vertical: true)
            // 체크 원(16pt)의 중심과 첫 줄 글자의 중심을 맞추는 1pt. 이게 없으면 원이 글자보다 위로 뜬다.
            .padding(.top, 1)
            // 더블클릭만 편집으로 들어간다. 한 번 클릭으로 열리면 목록을 훑다가 눌린 손짓이 전부
            // 편집 모드가 되고, 그 상태에서 다음 줄을 누르면 방금 연 편집이 소리 없이 닫힌다.
            .onTapGesture(count: 2) { onBeginEdit(item.id) }
    }

    /// 이월 배지 문구. 완료한 항목에는 붙이지 않는다 — 배지는 '아직 안 끝냈다'는 신호라,
    /// 끝낸 줄에 남으면 이미 한 일을 두고 잔소리하는 것처럼 읽힌다.
    private var carryBadge: String? {
        guard !item.isDone else { return nil }
        let days = TodoRules.carriedDays(originDayKey: item.originDayKey, todayKey: todayKey)
        return TodoRules.carryBadge(days: days)
    }

    /// 무채색 캡슐. 빨강·주황 같은 경고색은 미룬 일을 실패로 낙인찍어서 보드를 열기 싫게 만든다.
    private func carryBadgeView(_ badge: String) -> some View {
        Text(badge)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(CheckTheme.secondaryText)
            .todoBoardInkHalo()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            // 캡슐은 면이다. 흰색 0.10 이라 어두운 보드 위에서는 살짝 밝은 칩으로 읽히는데, 배율 없이 두면
            // 바탕이 걷힌 뒤에도 같은 세기로 남아 밝은 화면 위에서 혼자 도드라진다.
            .background(Capsule().fill(Color.white.opacity(0.10).todoBoardSurface(appearance)))
            .fixedSize()
            .accessibilityLabel("\(badge)부터 이월됨")
    }

    private var deleteButton: some View {
        Button {
            onDelete(item.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CheckTheme.secondaryText)
                .todoBoardInkHalo()
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 자리는 늘 잡아 두고 보임 여부만 opacity 로 바꾼다. 마우스가 들어올 때 ✕ 가 '생기면' 제목 폭이
        // 그만큼 줄어 글자가 다시 흐르고, 그 리플로우가 방금 겨눈 클릭 목표를 옆으로 밀어낸다.
        .opacity(isDeleteVisible ? 1 : 0)
        // 보이지 않아도 접근성 트리에는 남긴다 — hover 로만 뜨는 버튼을 AX 에서까지 감추면
        // 포인터를 못 쓰는 사용자에게는 삭제 경로가 아예 없어진다.
        .help(TodoBoardStrings.deleteItem)
        .accessibilityLabel(TodoBoardStrings.deleteItem)
    }

    private var isDeleteVisible: Bool {
        hovering || previewHovering
    }
}

// MARK: - 인라인 제목 편집

/// 제목 자리에 그대로 뜨는 편집 필드. 편집 중 텍스트를 **자기 안에** 들고 있는 이유: 중간 입력이 store 로
/// 새어 나가면 Esc 로 되돌릴 원본이 이미 덮어써진 뒤다. 부모는 커밋된 값 또는 취소만 받는다.
/// 높이 18은 행이 평소(체크 16 + 여백)와 같은 34pt 로 유지되도록 고른 값이다.
struct TodoBoardTitleEditor: View {
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.todoBoardAppearance) private var appearance

    init(initialTitle: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self._text = State(initialValue: initialTitle)
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(CheckTheme.primaryText)
            .tint(CheckTheme.accent)
            .lineLimit(1)
            .focused($focused)
            .accessibilityLabel(TodoBoardStrings.editTitle)
            .todoBoardInkHalo()
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            // 입력 행과 같은 규칙: 검정 채움은 배율을 받고, accent 테두리는 받지 않는다.
            // 이 테두리가 이 수정의 안전망이다 — 채움이 옅어져도 "지금 이 줄을 고치는 중"이라는
            // 어포던스가 남아야 한다(파란 선은 보드 팔레트에서 유일하게 편집을 뜻하는 신호다).
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(CheckTheme.fieldFill.todoBoardSurface(appearance))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1)
                    .todoBoardInkHalo()
            )
            .onSubmit { onCommit(text) }
            // Esc 취소. onExitCommand 는 cancelOperation 을 여기서 삼켜, 같은 키가 패널까지 올라가
            // 보드째로 닫히는 일을 막는다.
            .onExitCommand(perform: onCancel)
            .onChange(of: text) { previous, next in
                // 입력 행과 같은 제한을 그대로 건다. 편집으로 들어오면 100자를 넘길 수 있다면
                // '막는다'는 규칙이 경로 하나로 우회된다.
                let accepted = TodoDraftInput.accepted(current: previous, proposed: next)
                if accepted != next { text = accepted }
            }
            .onAppear {
                // 더블클릭한 순간 바로 고칠 수 있어야 한다 — 한 번 더 클릭해서 커서를 넣게 하면 인라인 편집의 의미가 없다.
                focused = true
            }
    }
}
