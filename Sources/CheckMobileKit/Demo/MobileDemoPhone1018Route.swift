#if DEBUG
import Foundation

/// 데모 스크린샷 라우트 `games/mahjong…` · `games/alkkagi…`(폰 1.0.18 — 아잉 마작 · 1:1 알까기)를 **값으로 푼 것**(DEBUG 전용).
/// 왜 `Demo/` 안이고 파일 통째가 `#if DEBUG` 인가는 `MobileDemoTetrisRoute` 머리말과 같다(출시 게이트 · 맥 스위트가 값으로 재는 자리).
///
/// 두 게임 모두 **서버 없이 서는 장면만** 둔다 — 마작 혼자 연습(봇 셋)과 알까기 한 폰 연습은 기기 안에서만 돈다(픽스처가 필요 없다).
/// 시뮬레이터 화면을 손으로 누르지 않고(합성 입력 금지) 판 화면을 캡처로 확인하려고 만든 길이다.
///
/// | 라우트                    | 쌓는 화면   | 그 밖                                      |
/// | ------------------------- | ----------- | ------------------------------------------ |
/// | `games/mahjong`           | `.mahjong`  | 로비(픽스처 없음 — 빈 로비)                 |
/// | `games/mahjong/practice`  | `.mahjong`  | 로비가 서면 동풍전 · 시간 제한 없음 연습을 연다(가로 판) |
/// | `games/alkkagi`           | `.alkkagi`  | 로비(픽스처 없음 — 빈 로비)                 |
/// | `games/alkkagi/practice`  | `.alkkagi`  | 한 폰 둘이 번갈아 하는 연습 판을 연다        |
///
/// 실행:
/// ```
/// xcrun simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute games/mahjong/practice
/// ```
package struct MobileDemoPhone1018Route: Hashable, Sendable {
    package enum Scene: String, Hashable, Sendable, CaseIterable {
        case mahjongLobby = "games/mahjong"
        case mahjongPractice = "games/mahjong/practice"
        case alkkagiLobby = "games/alkkagi"
        case alkkagiPractice = "games/alkkagi/practice"

        /// 게임 탭이 쌓을 화면.
        package var destination: GamesDestination {
            switch self {
            case .mahjongLobby, .mahjongPractice: .mahjong
            case .alkkagiLobby, .alkkagiPractice: .alkkagi
            }
        }
    }

    package let scene: Scene

    /// 라우트 글자 → 값. 두 게임의 라우트가 아니면 nil(빈 칸 · 앞뒤 슬래시 · 대문자는 다듬는다 — 다른 데모 라우트와 같은 규약).
    package init?(demoRoute raw: String) {
        let path = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard let scene = Scene(rawValue: path) else { return nil }
        self.scene = scene
    }

    /// 마작 화면이 서면 연습을 열어야 하는가.
    package var opensMahjongPractice: Bool { scene == .mahjongPractice }

    /// 알까기 화면이 서면 연습 판으로 시작하는가.
    package var opensAlkkagiPractice: Bool { scene == .alkkagiPractice }
}
#endif
