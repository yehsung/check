import CheckCore
import Foundation

/// 폰 아잉 뒤집기(1.0.17 · 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)") 문구 표.
///
/// ── 어디까지가 이 표의 몫인가 ───────────────────────────────────────────────────────────────
/// **안내·결과 사유는 코어가 쥔다**(`ReversiNoticeText` — 신청·취소·수락·착수·기권 응답 · 패스 · 자동 착수 · 관전 · 배포 창).
/// 맥과 폰이 같은 서버 응답을 같은 말로 옮겨야 하므로 그 표를 **다시 쓰지 마라.** 게임 이름 글자도 그 표 한 곳이다(`gameName`).
/// 이 표는 **화면에 붙는 글자**(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다. 맥 `ReversiText`(Sources/check — 폰 빌드에 안 들어간다)는
/// 배치·낱말 참고로만 쓴다 — 맥 표를 코어로 옮기면 맥 시험이 흔들린다(조사 impl_notes).
///
/// ── 상표 ──
/// 게임 이름은 '아잉 뒤집기'뿐이다. '리버시'는 **규칙 설명**으로만 쓴다(맥 `ReversiText.subtitle` 과 같은 자리). 다른 상표 낱말은
/// 저장소 어디에도 쓰지 않는다(`V03xxReversiTrademarkTests` 가 저장소 전역을 훑는다).
///
/// 레인 규약: 키를 더할 때는 **자기 절 끝**에만 더한다(화면 갈래들이 같은 줄을 고치지 않게).
/// 이 파일에 `#if os(iOS)` 를 두지 마라 — 맥 스위트가 값으로 재는 자리라야 폰 화면의 글자가 검증된다.
package enum ReversiPhoneText {

    // MARK: - 공용 · 게임 탭 카드 (배선 갈래 1/4)

    package static let title = ReversiNoticeText.gameName
    /// 게임 탭 카드 부제 · 로비 머리글 부제(맥 `ReversiText.subtitle` 과 같은 한 줄 — 규칙 · 선공 · 한 수 시간).
    package static let subtitle = "리버시 규칙 · 흑 선공 · 한 수 30초"
    package static let cardSubtitle = subtitle
    /// 게임 탭 카드의 보이스오버 힌트(막히지 않았을 때).
    package static let cardOpenHint = "\(ReversiNoticeText.gameName) 대결 화면을 열어요"
    /// 카드 칩: 받은 신청이 있다(몇 건인지는 칩이 말한다 — 탭 배지와 같은 수).
    package static func incomingChip(_ count: Int) -> String { "받은 신청 \(count)건" }
    /// 카드 보조 줄: 보낸 신청의 답을 기다린다.
    package static let outgoingLine = "보낸 신청의 답을 기다리고 있어요"
    /// 칩도 보조 줄 재료도 없을 때의 카드 한 줄(= 할 일을 말한다). AI 연습이 있다는 것도 함께 말한다(체스 카드 부제와 같은 자리).
    package static let idleLine = "사람을 골라 신청하거나 로봇과 연습해 보세요"

    package static let recordTitle = "내 전적"
    package static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }

    package static func record(_ record: ReversiRecord?) -> String {
        guard let record else { return self.record(wins: 0, losses: 0, draws: 0) }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }
}
