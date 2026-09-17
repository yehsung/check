import Foundation
import Testing
@testable import CheckMobileKit

/// 지금 탭 재디자인(w15 · 시안 B 01·02) 문구·서식과 모양 계약. 값은 순수 함수로, 모양은 주석을 걷어낸 소스로 본다.
@MainActor
@Suite struct NowRedesignTests {
    private static func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test("이번 주 줄 · 우리 팀 경과: 시간 분 표기는 내림이고 0 시간·0 분 칸은 뺀다")
    func hoursMinutesText() {
        #expect(NowFormat.hoursMinutesText(89_280) == "24시간 48분")
        #expect(NowFormat.hoursMinutesText(15_000) == "4시간 10분")
        #expect(NowFormat.hoursMinutesText(3_600) == "1시간")
        #expect(NowFormat.hoursMinutesText(2_999) == "49분")
        #expect(NowFormat.hoursMinutesText(59) == "0분")
        #expect(NowFormat.hoursMinutesText(-5) == "0분")
        // 39시간 59분 59초를 "40시간"으로 올리지 않는다(목표를 채운 것처럼 보이지 않게).
        #expect(NowFormat.hoursMinutesText(40 * 3600 - 1) == "39시간 59분")
    }

    @Test("상태 카드 부제 시각 · 머리 날짜는 기기 시간대와 무관하게 KST")
    func kstClockAndDate() throws {
        #expect(NowFormat.clockTime(try Self.date("2026-09-17T01:20:00Z")) == "10:20")
        #expect(NowFormat.clockTime(try Self.date("2026-09-16T15:05:00Z")) == "0:05")
        #expect(NowFormat.longDate(MobileClock.demoInstant) == "9월 17일 목요일")
        // UTC 로는 17일 16시지만 KST 로는 18일 금요일 새벽이다.
        #expect(NowFormat.longDate(try Self.date("2026-09-17T16:00:00Z")) == "9월 18일 금요일")
    }

    @Test("머리 부제: 펼침 = 날짜 · 팀(팀 없으면 날짜만) · 접힘 = 시계 · 이번 주 퍼센트")
    func headerSubtitles() {
        #expect(NowText.expandedSubtitle(date: "9월 17일 목요일", teamName: "아잉 데모팀") == "9월 17일 목요일 · 아잉 데모팀")
        #expect(NowText.expandedSubtitle(date: "9월 17일 목요일", teamName: nil) == "9월 17일 목요일")
        #expect(NowText.expandedSubtitle(date: "9월 17일 목요일", teamName: "") == "9월 17일 목요일")
        #expect(NowText.collapsedSubtitle(clock: "5:10:00", percent: 62) == "5:10:00 · 이번 주 62%")
    }

    @Test("근무 중 줄 문구: 끊긴 팀원은 마지막 확인 시각을 붙이고(모르면 '연결 끊김'만) · 사람 수 · 말 걸기 · 아래 안내")
    func workingTexts() {
        #expect(NowText.staleLastSeen("13분 전") == "연결 끊김 · 마지막 확인 13분 전")
        #expect(NowText.staleLastSeen(nil) == "연결 끊김")
        #expect(NowText.peopleCount(6) == "6명")
        #expect(NowText.talkTo("모래") == "모래에게 말 걸기")
        #expect(NowText.workingFooter == "근무 시작과 종료는 맥 앱에서 해요")
        #expect(NowText.sessionSince("10:20") == "이번 세션 10:20부터")
        #expect(NowText.goalSuffix(hours: 40) == "/ 40시간")
    }

    @Test("모양 계약: 할 일 체크는 파랑 · 이월 배지는 회색 칩 · 설명 줄 없음 · 다른 팀은 말 걸기(대화 라우트) · 상태 카드는 착용 캐릭터 초상")
    func nowShapeContracts() throws {
        let todo = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTodoSection.swift")
        #expect(!todo.contains("MobileTheme.working"), "할 일 체크·배지에 근무 초록을 쓴다(색은 뜻으로만)")
        #expect(!todo.contains("tint: MobileTheme.pending"), "이월 배지가 앰버다(앰버는 연결 끊김·대기 전용)")
        #expect(todo.contains("AingChip(text: badge, tint: MobileTheme.label2, background: MobileTheme.fill)"), "이월 배지가 회색 칩이 아니다")
        #expect(todo.contains("Circle().fill(MobileTheme.accentFill)"), "끝낸 할 일 체크 원이 파랑 채움이 아니다")
        #expect(!todo.contains("footer:"), "첫 화면 아래 설명 줄('내 계정에 저장돼…')이 되살아났다")

        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        #expect(tab.contains("router.open(.message(peerID: person.id))"), "다른 팀 줄의 말 걸기가 대화를 열지 않는다")
        #expect(tab.contains("CharacterPortrait(id: characterID, mood: mood"), "상태 카드가 착용 캐릭터 초상을 그리지 않는다")
        #expect(tab.contains("PersonAvatar(name: person.name, status:"), "근무 중 줄이 상태 점 아바타를 쓰지 않는다")
        #expect(!tab.contains("NowChip("), "다른 팀 줄에 '근무 중' 틴트 칩이 남았다(상태는 아바타 점 하나)")
    }

    @Test("모양 계약: 로그인 버튼만 시작 그라디언트 · 자리표시는 회색 · 알림 설명 기호 원은 뜻 색(초록·보라)을 쓰지 않는다")
    func entryScreensShapeContracts() throws {
        let session = try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSessionViews.swift")
        #expect(session.contains("MobileTheme.startGradient"), "로그인 버튼이 맥 시작 그라디언트가 아니다")
        #expect(session.contains("foregroundStyle(MobileTheme.label3Text)"), "입력칸 자리표시가 3단 회색이 아니다")
        #expect(session.contains("CharacterPortrait(id: nil"), "로그인·업데이트 머리에 아잉이 없다")
        #expect(!session.contains("arrow.down.app.fill"), "업데이트 화면이 옛 다운로드 타일을 쓴다")

        let primer = try IntegrationContractTests.code("Sources/CheckMobileKit/Push/PushPermissionPrimerView.swift")
        #expect(!primer.contains("MobileTheme.working") && !primer.contains("MobileTheme.aiToken"), "알림 종류 기호가 근무 초록·AI 보라를 쓴다")
        #expect(primer.contains("AingButton(PushText.primerAllow, kind: .filled"), "알림 켜기가 공용 채움 버튼이 아니다")
        #expect(!primer.contains(".fixedSize()"), "SwiftUI `fixedSize()` 는 가로까지 고정해 큰 글자에서 설명이 화면 밖으로 잘린다(AX3 실측)")
    }
}
