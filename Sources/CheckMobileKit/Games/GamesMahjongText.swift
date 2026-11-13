import CheckCore
import Foundation

// 아잉 마작 폰 문구(1.0.18 — 대표 판 나누기 답 "한 판에 전부" #d_xB6BJcn2nsCq · 루비 판돈 그대로 #d_t103CxfPGinB).
// 맥 `MahjongText`(Sources/check/MahjongPanel.swift)를 글자 그대로 옮겼다 — 같은 서버 · 같은 규칙을 두 기기가 다르게 말하지 않게.
// 서버 응답 문구는 코어 `MahjongNoticeText` 한 곳(스토어 `notice`). 폰에서만 다른 것은 아래 `phone` 절(손짓 · 가로 안내)뿐이다.

/// 화면 고정 글자 — 서버 응답 문구는 여기 두지 않는다(스토어 `notice`).
package enum GamesMahjongText {
    package static let title = MahjongNoticeText.gameName
    package static let subtitle = "리치 마작 4인 대국 — 가장 널리 쓰이는 온라인 리치 마작 규칙과 같아요"
    package static let rules = "규칙"
    package static let yaku = "역"
    package static let scoreTable = "점수표"
    package static let close = "닫기"
    package static let practice = "혼자 연습"
    package static let usersTab = "사람"
    package static let rankTab = "순위"
    package static let invite = "초대"
    package static let invited = "초대함"
    package static let join = "참가"
    package static let decline = "거절"
    package static let emptyUsers = "함께할 사람이 아직 없어요"
    package static let loadingUsers = "사람 목록을 불러오는 중…"
    package static let inMatchChip = "대국 중"
    package static let outdatedChip = "업데이트 필요"
    package static let focusChip = "집중 모드"
    package static let workingChip = "근무 중"
    package static let invitesTitle = "받은 초대"
    package static let publicRoomsTitle = "공개 방"
    package static let noJoinables = "받은 초대나 열린 공개 방이 없어요"
    package static let createTitle = "방 만들기"
    package static let createButton = "만들기"
    package static let createHint = "판돈은 시작할 때 모두에게서 걷고, 등수대로 나눠 가져요."
    package static let stakeLabel = "판돈"
    package static let formatLabel = "판 길이"
    package static let publicLabel = "공개"
    package static let publicOn = "누구나 참가"
    package static let publicOff = "초대한 사람만"
    package static let myRoomTitle = "내 방"
    package static let start = "시작"
    package static let leave = "나가기"
    package static let emptySeat = "빈자리"
    package static let hostTag = "방장"
    package static let invitedTag = "초대 중"
    package static let joinedTag = "참가"
    package static let needFour = "4명이 모여야 시작해요"
    package static let unseenDrop = "앱을 끈 사람은 시작할 때 빠져요"
    package static let waitingHost = "방장이 시작하기를 기다리고 있어요"
    package static let noRoomHint = "[초대]를 누르면 방이 열리고 바로 불러요 · 방에서 넷째를 기다리며 혼자 연습할 수 있어요"
    package static let roomViewButton = "방 보기"
    package static let practiceViewButton = "연습판 보기"
    package static let practiceTitle = "혼자 연습"
    package static let practiceTimedOff = "넉넉히"
    package static let practiceTimedOn = "실전처럼 5+20"
    package static let practiceTimeLabel = "생각 시간"
    package static let practiceSeatNote = "내 자리는 무작위예요"
    package static let practiceNoRuby = "연습판은 루비·기록이 없어요"
    package static let practiceStart = "연습 시작"
    package static let practiceAgain = "다시 하기"
    package static let practiceEnd = "연습 끝내기"
    package static let comeBack = "돌아왔어요"
    package static let awayHint = "자리 비움 — 차례가 오면 저절로 버려요"
    package static let autoChip = "자동"
    package static let deletedChip = "탈퇴"
    package static let dealerChip = "친"
    package static let riichiChip = "리치"
    package static let waitingOthers = "기다리는 중…"
    package static let wallRemaining = "남은 패"
    package static let tsumo = "쯔모"
    package static let ron = "론"
    package static let riichi = "리치"
    package static let kan = "깡"
    package static let kanMore = "깡 ▸"
    package static let kyuushu = "구종구패"
    package static let pon = "퐁"
    package static let chi = "치"
    package static let pass = "넘기기"
    package static let cancel = "취소"
    package static let riichiArmedHint = "리치 — 버릴 패를 고르세요(밝은 패만)"
    package static let kuikaeHint = "방금 운 패와 같은 패는 이번에 못 버려요"
    package static let noYakuHint = "역 없음 — 쯔모나 리치로만 화료"
    package static let furitenChip = "후리텐 — 론 불가, 쯔모만"
    package static let waitsTitle = "기다리는 패"
    package static let reserve = "예비"
    package static let toLobby = "로비로"
    package static let rematch = "한 판 더"
    package static let crampedNotice = "화면이 좁아 마작 판이 잘려요"
    package static let updateRequired = "앱을 업데이트해 주세요"
    package static let unavailable = MahjongNoticeText.unavailable
    package static let aidAutoWin = "자동 화료"
    package static let aidNoCalls = "울지 않기"
    package static let aidTsumogiri = "쯔모기리"
    package static let recordUnranked = "10판부터 순위"
    package static let rankHeader = "평균 등수 순 · 10판 이상"
    package static let emptyRanking = "아직 10판을 채운 사람이 없어요"
    package static let gamesUntilRanked = "판 더 하면 순위에 올라요"
    package static let firstTimeTitle = "처음이에요"
    /// 사람 줄 잠금(대국 중 · 업데이트 필요 · 집중 모드) — SF Symbol(이모지 아님).
    package static let lockSymbol = "lock.fill"
    package static let lockedLabel = "지금은 초대할 수 없어요"
    /// 연습판 봇 자리 카드 꼬리표(UX:359).
    package static let practiceBotTag = "연습 상대"

    package static func record(avg: Double?, games: Int) -> String {
        guard games >= MahjongRules.rankingMinGames, let avg else { return "\(games)판 · \(recordUnranked)" }
        return String(format: "평균 %.2f등 · %d판", avg, games)
    }

    package static func stake(_ stake: Int?) -> String { "판돈 \(stake ?? 0)" }
    package static func seats(_ joined: Int) -> String { "\(joined)/4명" }
    package static func roomOf(_ name: String) -> String { "\(name)님의 방" }
    package static func inviteFrom(_ name: String) -> String { "\(name)님이 초대했어요" }
    package static func format(_ format: MahjongFormat?) -> String {
        switch format {
        case .hanchan: "반장전"
        default: "동풍전"
        }
    }

    package static func formatDetail(_ format: MahjongFormat) -> String {
        switch format {
        case .tonpuu: "동장 4국(기본)"
        case .hanchan: "동장·남장 8국"
        }
    }

    package static let windNames = ["동", "남", "서", "북"]
    package static let windGlyphs = ["東", "南", "西", "北"]

    package static func wind(_ wire: String?) -> String {
        switch wire {
        case "E": "동"
        case "S": "남"
        case "W": "서"
        case "N": "북"
        default: "—"
        }
    }

    /// "동 1국".
    package static func roundName(round: Int?, handNo: Int?) -> String {
        let r = windNames[max(0, min(3, round ?? 0))]
        return "\(r) \((handNo ?? 0) + 1)국"
    }

    package static func honba(_ honba: Int?, kyotaku: Int?) -> String { "\(honba ?? 0)본장 · 공탁 \(kyotaku ?? 0)" }
    package static func wall(_ count: Int?) -> String { "\(wallRemaining) \(count ?? 0)" }

    package static func score(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.grouping(.automatic))
    }

    package static func delta(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : (value < 0 ? "−\((-value).formatted())" : "0")
    }

    package static func net(_ value: Int) -> String {
        value > 0 ? "+\(value)" : (value < 0 ? "−\(-value)" : "0")
    }

    package static func rank(_ rank: Int?) -> String { rank.map { "\($0)위" } ?? "—" }
    package static func avgRank(_ avg: Double?) -> String { avg.map { String(format: "평균 %.2f등", $0) } ?? "—" }
    package static func remaining(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
    package static func nextHand(_ seconds: Int) -> String { "다음 국까지 \(seconds)초" }
    package static func backIn(_ seconds: Int) -> String { "\(comeBack) · \(seconds)초" }

    /// "방 3/4 · 남은 7:12".
    package static func roomBand(joined: Int, seconds: Int) -> String { "방 \(joined)/4 · 남은 \(remaining(seconds))" }
    package static let roomBandReady = "4명이 모였어요"

    /// 분배 안내(카드 ② — `[3N, N, 0, 0]` 지급, 순수익 +2N · 0 · −N · −N). 실제 분배는 서버, 결과 화면은 서버 값만.
    package static func split(stake: Int) -> String {
        "1위 +\(stake * 2) · 2위 본전 · 3·4위 −\(stake)"
    }

    package static func handEnd(_ reason: String?) -> String {
        switch reason {
        case "exhaustive": "황패 유국"
        case "kyuushu": "구종구패 유국"
        case "suufon": "사풍연타 유국"
        case "suukaikan": "사개깡 유국"
        case "suucha_riichi": "사가 리치 유국"
        case "nagashi": "유국만관"
        default: "유국"
        }
    }

    package static func matchEnd(_ reason: String?) -> String {
        switch reason {
        case "tobi": "점수가 0 아래로 내려간 사람이 나와 끝났어요"
        case "agari_yame", "tenpai_yame": "마지막 국의 친이 1위로 끝냈어요"
        case "target_reached": "연장에서 30000점을 넘은 사람이 나와 끝났어요"
        case "max_round": "마지막 국까지 마쳤어요"
        case "void": "판이 무효가 되어 판돈을 돌려줬어요"
        default: "판이 끝났어요"
        }
    }

    package static func limitName(_ limit: String?) -> String? {
        switch limit {
        case "mangan": "만관"
        case "haneman": "하네만"
        case "baiman": "배만"
        case "sanbaiman": "삼배만"
        case "yakuman": "역만"
        default: nil
        }
    }
}

/// 폰에서만 쓰는 글자(맥에 없는 손짓 · 화면 안내).
package enum GamesMahjongPhoneText {
    package static let entrySymbol = "square.grid.3x3.square"
    package static let cardSubtitle = "리치 마작 4인 대국 · 방을 열어 초대하거나 혼자 연습해요"
    package static let cardOpenHint = "아잉 마작 로비를 열어요"
    package static let rotating = "가로로 돌리면 판이 보여요"
    package static let twoTapHint = "한 번 누르면 들리고, 한 번 더 누르면 버려요"
    package static let aidTwoTap = "두 번 눌러 버리기"
    package static let aidCorner = "패 귀퉁이 글자"
    package static let aidsTitle = "보조"
    package static let leaveTitle = "판에서 나갈까요?"
    package static let leaveDetail = "기권이 아니에요. 판은 끝까지 가고, 차례가 오면 저절로 버려요. 다시 들어와 손패를 누르면 돌아와요."
    package static let leaveConfirm = "나가기"
    package static let stay = "계속 두기"
    package static let roomTitle = "내 방"
    package static let roomEmpty = "방을 열고 사람을 초대하면 넷이 모일 때 시작할 수 있어요"
    package static let createRoomHint = "방을 열면 초대한 사람(또는 공개면 누구나)이 들어올 수 있어요"
    package static let rankingTitle = "마작 순위"
    package static let lobbyCaption = "근무 중이 아니어도 초대하고 참가할 수 있어요"
    package static let practiceHelp = "봇 셋과 루비 · 기록 없이 둬요"
}

/// 화면 고르기(맥 `MahjongScreen.of` 와 같은 판정 — 순수, 맥 스위트가 잰다).
package enum GamesMahjongScreenRule: Equatable, Sendable {
    case unavailable, lobby, table

    /// `dismissedMatchID` = 판 결과에서 [로비로]를 누른 판(그 판이 finished 로 남아 있어도 로비를 보인다).
    @MainActor
    package static func of(_ store: MahjongStore, dismissedMatchID: String?) -> GamesMahjongScreenRule {
        if store.availability != .available, !store.isPractice { return .unavailable }
        if store.isPractice { return .table }
        if let match = store.match?.match, store.match?.mySeat != nil,
           match.matchStatus == .active || (match.matchStatus == .finished && match.id != dismissedMatchID) {
            return .table
        }
        return .lobby
    }
}

/// 규칙 · 역 표(맥 `MahjongRulesText` 글자 그대로 — 다른 마작 서비스 이름은 쓰지 않는다).
package enum GamesMahjongRulesText {
    /// (제목, 설명, 예시 손 — `MahjongTiles.parse` 표기).
    package static let rules: [(title: String, detail: String, example: String)] = [
        ("목표", "4몸통(같은 패 셋 또는 이어진 셋) + 1머리(같은 패 둘)를 먼저 만들면 화료예요.", "123m456p789s11122z"),
        ("역이 하나는 있어야 화료", "리치 · 멘젠쯔모 · 탕야오(2~8만 쓴 손) · 역패(백·발·중 셋)가 가장 흔해요.", "234m345p456s678s55p"),
        ("버리기 · 울기", "내 차례에 한 장 가져와 한 장 버려요. 남이 버린 패로 퐁(같은 패 셋)·깡(넷)·론을 할 수 있고, "
            + "치(이어진 셋)는 왼쪽 사람이 버린 패로만 돼요.", ""),
        ("리치", "울지 않은 손이 텐파이(한 장만 더 오면 화료)일 때 1000점을 걸고 선언해요. 그 뒤로는 손을 바꿀 수 없어요.", ""),
        ("후리텐", "기다리는 패를 내가 이미 버렸다면 론으로 날 수 없어요. 쯔모로는 날 수 있어요.", ""),
        ("유국", "패산이 다 떨어지면 텐파이한 사람이 노텐인 사람에게서 점수를 받아요.", ""),
        ("판 길이", "동풍전(동장 4국, 기본) · 반장전(동·남장 8국). 마지막에 1위가 30000점 미만이면 연장해요.", ""),
        ("생각 시간", "한 번에 5초 + 국마다 예비 20초 · 넘기면 저절로 버리거나 넘겨요. 날 수 있으면 저절로 화료해요.", ""),
        ("자리 비움", "창을 닫거나 [나가기]를 눌러도 판은 끝까지 가요. 차례가 오면 저절로 버리고, 손패를 한 번 누르면 돌아와요.", ""),
        ("판돈", "시작할 때 넷 모두에게서 판돈을 걷고 1위 +2N · 2위 본전 · 3·4위 −N 으로 나눠요. 새로 생기는 루비는 없어요.", ""),
    ]

    package static let footer = "가장 널리 쓰이는 온라인 리치 마작 규칙과 같아요 · 적도라 3장 · 쿠이탕 있음 · 후리텐·쿠이카에 있음"

    /// 역 표(멘젠 판 · 울음 판 — nil 은 멘젠만). 역만은 판 대신 "역만".
    package static let yakuTable: [(yaku: MahjongYaku, closed: Int, open: Int?)] = [
        (.riichi, 1, nil), (.doubleRiichi, 2, nil), (.ippatsu, 1, nil), (.menzenTsumo, 1, nil), (.pinfu, 1, nil),
        (.iipeikou, 1, nil), (.tanyao, 1, 1), (.yakuhaiHaku, 1, 1), (.yakuhaiHatsu, 1, 1), (.yakuhaiChun, 1, 1),
        (.bakaze, 1, 1), (.jikaze, 1, 1), (.chankan, 1, 1), (.rinshan, 1, 1), (.haitei, 1, 1), (.houtei, 1, 1),
        (.chiitoitsu, 2, nil), (.sanshoku, 2, 1), (.ittsu, 2, 1), (.chanta, 2, 1), (.toitoi, 2, 2), (.sanankou, 2, 2),
        (.sanshokuDoukou, 2, 2), (.sankantsu, 2, 2), (.honroutou, 2, 2), (.shousangen, 2, 2), (.honitsu, 3, 2),
        (.junchan, 3, 2), (.ryanpeikou, 3, nil), (.chinitsu, 6, 5),
    ]

    package static let yakumanList: [MahjongYaku] = [
        .heavenly, .earthly, .kokushi, .kokushi13, .suuankou, .suuankouTanki, .daisangen, .shousuushii, .daisuushii,
        .tsuuiisou, .ryuuiisou, .chinroutou, .suukantsu, .chuuren, .junseiChuuren,
    ]

    /// 점수표 칸(부 × 판).
    package static let fuRows = [30, 40, 50, 60, 70]
    package static let hanColumns = [1, 2, 3, 4]
}

/// 점수표 칸(론 점수 자 / 친 — 숫자는 규칙 Swift `MahjongScoring.scoreOf` 에서, 화면이 손으로 적지 않는다).
package enum GamesMahjongScoreCell {
    package static func text(han: Int, fu: Int) -> String {
        let child = MahjongScoring.scoreOf(han: han, fu: fu, dealer: false, tsumo: false).total
        let dealer = MahjongScoring.scoreOf(han: han, fu: fu, dealer: true, tsumo: false).total
        return "\(child)/\(dealer)"
    }

    package static let caption = "칸 = 론 점수(자 / 친) · 만관 이상은 판으로만 정해져요"
}

/// 더블론 넘김(맥 `MahjongResultPaging` 과 같은 식 — 순수).
package enum GamesMahjongResultPaging {
    /// 서버 쉬는 시간(초) = 7 + 4 × (화료자 − 1).
    package static func restSeconds(winners: Int) -> Double { 7 + 4 * Double(max(1, winners) - 1) }
    /// 지금 보일 화료자 번호.
    package static func index(winners: Int, nextHand: Date?, now: Date) -> Int {
        guard winners > 1, let nextHand else { return 0 }
        let rest = restSeconds(winners: winners)
        let interval = (rest - 1.5) / Double(winners)
        let elapsed = now.timeIntervalSince(nextHand.addingTimeInterval(-rest))
        return max(0, min(winners - 1, Int(elapsed / interval)))
    }
}

/// 폰 보조 기본값(두 번 눌러 버리기 — 폰은 켜짐으로 시작한다. 한 번 켜고 끈 값은 기기에 남는다).
@MainActor
package enum GamesMahjongPhoneAids {
    package static let seededKey = "check.mahjong.phone.twoTapSeeded"

    /// 처음 한 번, 폰 기본(두 번 눌러 버리기 켜짐)을 심는다.
    package static func seedIfNeeded(_ store: MahjongStore, defaults: UserDefaults?) {
        guard let defaults, !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)
        if !store.aids.twoClickDiscard { store.aids.twoClickDiscard = true }
    }

    package static func twoTap(_ store: MahjongStore) -> Bool { store.aids.twoClickDiscard }
}
