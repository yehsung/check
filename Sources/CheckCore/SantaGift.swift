import Foundation

// MARK: - 얻는 길 — 크리스마스 선물(선물 종류 'santa' · 대표 #d_3VZdglOgRABx "산타아잉이는 그냥 주고")
//
// 빼빼로 데이 선물(`'pepero'`)과 같은 틀의 **기간 선물**이다: 운영자가 `grant_santa_gift(p_user uuid, p_note text)` 로 맥 사용자에게 지급하고,
// 앱은 받는 창(초대장 화면 — 고를 것 없이 받기)을 띄우고, 받지 않고 닫으면 다시 열기 카드가 남는다. 기간이 끝나면 안 받은 선물은 서버가 거둔다
// (기간은 대표 #d_jdcyBSon9oZ3 "A 크리스마스 주간(12-21~25)" — 12-21 아침에 걸고 12-26 00:00 KST 에 거둔다. 거두는 시각은 서버 등록 단계가 갖고
// 클라는 그 시각을 모른다). 받은 캐릭터는 영원히 남는다.
// 서버는 능력 번호 11 미만인 클라에게 산타 행 · 산타 선물을 **싣지 않고**(shop_state · character_gift_pending), 수령은 `needs_update` 다.

/// 크리스마스 선물(산타 아잉이) 문구 — **한 곳**. 받는 창 · 상점 잠긴 칸 · 다시 열기 카드가 같이 쓴다. 실패 · 거절 줄은 생일과 한 벌이다.
///
/// 받는 창 말투는 대표 결정 #d_4wR1Qzn9OKmt "C 띵동! 산타 왔어요 🎁"(깜짝 방문 느낌, 단추 '선물 열기'). 다시 열기 카드는 그 말투에 맞췄다.
/// 바뀌면 이 묶음만 고친다.
package nonisolated enum SantaGiftText {
    /// 문구가 대표 결정으로 정해졌는가. **출시 게이트**: false 인 채로 맥 버전을 0.3.86 다음으로 올리면
    /// `SantaGiftWireTests.santaGiftCopyDecidedBeforeNextRelease` 가 빨갛다 — 정하지 않은 문구(잠긴 칸 안내는 모두가 본다)가 판에 실려 나가는 것을 막는다.
    /// 정해지면: 아래 글자를 바꾸고 · 이 값을 true 로 · 이 파일과 `CharacterGiftCopy.santa` 주석의 임시 표시를 걷는다(게이트가 그 표시 셋을 찾는다).
    package static let copyDecided = true

    /// 받는 창 제목(대표 원문 그대로).
    package static let title = "띵동! 산타 왔어요 🎁"
    /// 받는 창 본문(운영자 한 줄 `note` 가 있으면 화면이 그 위에 크게, 빼빼로 초대장과 같은 틀).
    package static let body = "착한 아잉이에게 산타가 찾아왔어요"
    /// 확인 단추(고를 것이 없다, 선택지는 산타 아잉이 하나).
    package static let confirmButton = "선물 열기"
    /// 받은 뒤의 단추 둘(생일과 같은 글자).
    package static let wearNowButton = CakeGiftText.wearNowButton
    package static let closeButton = CakeGiftText.closeButton
    /// 상점 잠긴 칸 캡션(가격 · 사기 단추 자리).
    package static let lockedCaption = "크리스마스 선물"
    /// 잠긴 칸을 골랐을 때의 안내.
    package static let lockedHint = "크리스마스에만 주는 선물이에요. 루비나 뽑기로는 얻을 수 없어요."
    /// 받지 않고 닫은 뒤 메뉴 팝오버 · 상점에 남는 카드(받는 창 말투 C 에 맞춤).
    package static let reopenTitle = "띵동! 산타 선물이 기다려요 🎁"
    package static let reopenButton = "선물 열기"
    /// 결과를 모르는 수령의 한 줄 — 생일과 같은 글자다(다시 눌러도 안전하다).
    package static let claimFailed = CakeGiftText.claimFailed

    /// 받은 뒤 한 줄 — "산타 아잉이를 받았어요!"(조사 규칙은 생일과 한 곳).
    package static func received(name: String) -> String {
        CakeGiftText.received(name: name)
    }

    /// 수령 결과 중 받은 화면이 아닌 것의 한 줄 — 생일과 같은 어휘 · 같은 글자(`CakeGiftText.notice`).
    package static func notice(for outcome: CharacterGiftClaimOutcome, name: (String) -> String) -> String? {
        CakeGiftText.notice(for: outcome, name: name)
    }
}
