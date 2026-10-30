// 원본: 없음 — G5 요청 골든 대조(G §2-3 W1-d ①). 골든: Tests/CheckMobileKitTests/GoldenExport/wire/GoldenExportWireRequests.swift
//       6차 c-fold(G §8-17 4): core/net 에서 core/stores 로 옮겼다 — net 과 rules 를 둘 다 보는 가장 낮은 모듈이라, 시험용 글자 규칙 근사 대신
//       실제 RulesWireTextRules 를 꽂고 resultOtherLanes case 의 결과를 core/stores `service` 의 앱 함수로 대조한다(빠지는 case 0).
//       그 case 들은 실제 응답(데모 픽스처 · 경계 본문)을 싣는다 — 응답이 `{}` 뿐이면 rules 디코드 · 합성이 틀려도 초록이다(c-fold 검증 지적).
package com.yehsung.aingcheck.core.stores.wiregolden

import com.yehsung.aingcheck.core.net.*
import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.text.MegaphoneInfoResponse
import com.yehsung.aingcheck.core.rules.text.MegaphoneSendResponse
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.stores.service.achievementClaim
import com.yehsung.aingcheck.core.stores.service.achievementsStatus
import com.yehsung.aingcheck.core.stores.service.dailyMissionClaim
import com.yehsung.aingcheck.core.stores.service.fetchMyAILimits
import com.yehsung.aingcheck.core.stores.service.megaphoneInfo
import com.yehsung.aingcheck.core.stores.service.sendMegaphone
import com.yehsung.aingcheck.core.stores.service.setStatusMessageOutcome
import com.yehsung.aingcheck.core.stores.service.weeklyWorkClaim
import com.yehsung.aingcheck.core.stores.service.weeklyWorkStatus
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.CharacterSyncFetchError
import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse
import com.yehsung.aingcheck.testkit.dump.GoldenDump
import com.yehsung.aingcheck.testkit.dump.GoldenScrub
import kotlinx.serialization.SerializationException
import com.yehsung.aingcheck.core.wire.games.GomokuChatKind
import com.yehsung.aingcheck.core.wire.games.TetrisReportRequest
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.models.ContentReportReason
import com.yehsung.aingcheck.core.wire.models.FeedbackKind
import com.yehsung.aingcheck.core.wire.models.FeedbackStatus
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.core.wire.models.TodoSyncRequest
import com.yehsung.aingcheck.core.wire.models.TodoSyncWireItem
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.decodeURLQueryComponent
import io.ktor.http.headersOf
import io.ktor.client.request.get
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import java.util.Base64
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail



/** Swift `GoldenExportWireRequests.megaphoneBodies` 와 같은 본문(빈 · 상한+1 은 요청 없이 즉답, 나머지는 정규화한 글자로 RPC). */
private val MEGAPHONE_BODIES = listOf(
    " \n\u200B ", "가".repeat(199), "가".repeat(198), "  오늘 3시\r\n라운지에서  간식 나눠요\u0007 ", "다들", "다들",
)

class WireRequestsGoldenTest {
    private val u = "aa000000-0000-4000-8000-0000000000a1"
    private val p = "bb000000-0000-4000-8000-0000000000b2"
    private val m = "cc000000-0000-4000-8000-0000000000c3"
    private val rid = "dd000000-0000-4000-8000-0000000000d4"
    private val now = SwiftDate(1_789_621_500.0)
    private val t = ACCESS

    /**
     * 결과 타입이 rules·stores 에 있는 case(골든 spec.resultOtherLanes — 받는 갈래 이름이 적혀 있다). Swift 서비스 함수 하나 =
     * Kotlin core/stores `service` 의 **앱 함수**(net 요청 + rules 디코드 · 합성 — 스토어가 부르는 그 함수). 시험 안에서 따로 합성하지 않는다
     * (그러면 앱이 다르게 합성해도 초록이다 — 6차 c-fold 검증 지적). 이 집합이 spec.resultOtherLanes 와 **정확히** 같아야 한다.
     */
    private val rulesComposed: Map<String, suspend (SupabaseWorkService) -> Any?> = linkedMapOf(
        // 상태메시지 저장 결과(Swift setStatusMessage → StatusMessageSaveOutcome): 함수 없음은 serverNotReady, 나머지는 응답 세 칸.
        "setStatusMessage" to { s -> s.setStatusMessageOutcome(t, "집중 중") },
        "setStatusMessage(nil)" to { s -> s.setStatusMessageOutcome(t, null) },
        "setStatusMessage#outcomes" to { s -> (1..11).map { s.setStatusMessageOutcome(t, "집중 중") } },
        // 업적 · 일일 미션(AchievementStatus — 관대한 디코드, 최상위가 객체가 아닐 때만 throw).
        "achievementsStatus" to { s -> s.achievementsStatus(t) },
        "achievementsStatus#data" to { s -> s.achievementsStatus(t) },
        "achievementsStatus#lossy" to { s -> s.achievementsStatus(t) },
        "achievementsStatus#notObject" to { s -> s.achievementsStatus(t) },
        "achievementsStatus#missing" to { s -> s.achievementsStatus(t) },
        "achievementClaim" to { s -> s.achievementClaim(t, "poke10") },
        "achievementClaim#data" to { s -> s.achievementClaim(t, "poke10") },
        "achievementClaim(nil)" to { s -> s.achievementClaim(t, null) },
        "achievementClaim(nil)#data" to { s -> s.achievementClaim(t, null) },
        "dailyMissionClaim" to { s -> s.dailyMissionClaim(t, "daily_gomoku") },
        "dailyMissionClaim#data" to { s -> s.dailyMissionClaim(t, "daily_gomoku") },
        "dailyMissionClaim(nil)" to { s -> s.dailyMissionClaim(t, null) },
        // 주간 근무 보상(WeeklyWorkStatus — 받기 응답도 같은 모양).
        "weeklyWorkStatus" to { s -> s.weeklyWorkStatus(t) },
        "weeklyWorkStatus#data" to { s -> s.weeklyWorkStatus(t) },
        "weeklyWorkStatus#lossy" to { s -> s.weeklyWorkStatus(t) },
        "weeklyWorkClaim" to { s -> s.weeklyWorkClaim(t) },
        "weeklyWorkClaim#data" to { s -> s.weeklyWorkClaim(t) },
        "weeklyWorkClaim(args)" to { s -> s.weeklyWorkClaim(t, "2026-09-14", 40) },
        // 확성기(Swift sendMegaphone: 본문 사전 판정 → 정규화한 글자로 RPC → MegaphoneSendResponse · megaphoneInfo → MegaphoneInfoResponse).
        "sendMegaphone" to { s -> s.sendMegaphone(t, "다들 화이팅", rid) },
        "sendMegaphone#outcomes" to { s -> MEGAPHONE_BODIES.map { body -> s.sendMegaphone(t, body, rid) } },
        "sendMegaphone#missing" to { s -> s.sendMegaphone(t, "다들 화이팅", rid) },
        "sendMegaphone#badType" to { s -> s.sendMegaphone(t, "다들 화이팅", rid) },
        "megaphoneInfo" to { s -> s.megaphoneInfo(t) },
        "megaphoneInfo#data" to { s -> listOf(s.megaphoneInfo(t), s.megaphoneInfo(t)) },
        "megaphoneInfo#badType" to { s -> s.megaphoneInfo(t) },
        // 내 AI 리밋(Swift fetchMyAILimits → [AILimitFetchedRow] — 행 거르기 · 라벨 정규화 AILimitDeviceLabelContract · AILimitPlanLabelContract).
        "fetchMyAILimits" to { s -> s.fetchMyAILimits(t, u) },
        "fetchMyAILimits#data" to { s -> s.fetchMyAILimits(t, u) },
        "fetchMyAILimits#filters" to { s -> s.fetchMyAILimits(t, u) },
        "fetchMyAILimits#labels" to { s -> s.fetchMyAILimits(t, u) },
    )

    /** Swift `GoldenExportWireRequests.calls` 와 같은 id · 같은 인자. 여기 없는 id 가 골든에 있으면 "미이식". */
    private val registry: Map<String, suspend (SupabaseWorkService) -> Any?> = rulesComposed + linkedMapOf(
        // ---- 인증 ----
        "signIn" to { s -> s.signIn("a@b.invalid", "pw-123456") },
        "signUp" to { s -> s.signUp("a@b.invalid", "pw-123456", "아잉") },
        "signUp(center)" to { s -> s.signUp("a@b.invalid", "pw", "아잉", "busan") },
        "refreshSession" to { s -> s.refreshSession("refresh-1") },
        "signOut" to { s -> s.signOut(t) },
        "logoutLocalScope" to { s -> s.logoutLocalScope(t) },
        "deleteMyAccount" to { s -> s.deleteMyAccount(t) },
        "sendPasswordResetCode" to { s -> s.sendPasswordResetCode("a@b.invalid") },
        "verifyPasswordResetCode" to { s -> s.verifyPasswordResetCode("a@b.invalid", "123456") },
        "updatePassword" to { s -> s.updatePassword(t, "new-pw-1") },
        "verifySignUpCode" to { s -> s.verifySignUpCode("a@b.invalid", "654321") },
        "resendSignUpCode" to { s -> s.resendSignUpCode("a@b.invalid") },
        // ---- 팀 ----
        "lookupTeamByCode" to { s -> s.lookupTeamByCode(" ab-c 12 ") },
        "fetchMyInviteCode" to { s -> s.fetchMyInviteCode(t) },
        "setTeamWeeklyGoal" to { s -> s.setTeamWeeklyGoal(t, 40) },
        "joinTeam" to { s -> s.joinTeam(t, "xyz-789") },
        "createTeam" to { s -> s.createTeam(t, "새 팀", 60) },
        "fetchTeamLeaderboard" to { s -> s.fetchTeamLeaderboard(t) },
        "fetchTeamLeaderboard(weekOffset)" to { s -> s.fetchTeamLeaderboard(t, 3L) },
        "fetchTeamLeaderboard(weekOffset)#clamp" to { s -> s.fetchTeamLeaderboard(t, 99L) },
        "fetchTeamLeaderboard(weekOffset)#fallback" to { s -> s.fetchTeamLeaderboard(t, 2L) },
        "fetchOwnMembership" to { s -> s.fetchOwnMembership(t, u) },
        "fetchTeamStatuses" to { s -> s.fetchTeamStatuses(t, "team-1", now) },
        // ---- 기록 · 토큰 · 프로필 ----
        "fetchMySessions" to { s -> s.fetchMySessions(t, u, now.addingTimeInterval(-86_400.0 * 30)) },
        "fetchMyTokenDaily" to { s -> s.fetchMyTokenDaily(t, u, "2026-08-01") },
        "fetchTokenBoard" to { s -> s.fetchTokenBoard(t, "2026-09") },
        "fetchMiniGamePublic" to { s -> s.fetchMiniGamePublic(t, u) },
        "updateMiniGamePublic" to { s -> s.updateMiniGamePublic(t, u, false) },
        "fetchMyCenter" to { s -> s.fetchMyCenter(t, u) },
        "fetchMyStatusMessage" to { s -> s.fetchMyStatusMessage(t, u) },
        "fetchTokenUsageSettings" to { s -> s.fetchTokenUsageSettings(t, u) },
        "updateTokenUsagePublic" to { s -> s.updateTokenUsagePublic(t, u, true) },
        "setDisplayName" to { s -> s.setDisplayName(t, "새이름") },
        "fetchDisplayNameChangedAt" to { s -> s.fetchDisplayNameChangedAt(t, u) },
        "setCharacter" to { s -> s.setCharacter(t, "aing_cake_choco") },
        "setCharacter(nil)" to { s -> s.setCharacter(t, null) },
        "fetchEquippedCharacter" to { s -> s.fetchEquippedCharacter(t, u) },
        "fetchMyProfileCard" to { s -> s.fetchMyProfileCard(t, u) },
        // ---- 사진 ----
        "uploadAvatar" to { s -> s.uploadAvatar(t, u, "JPEG-BYTES".encodeToByteArray()) },
        "removeAvatar" to { s -> s.removeAvatar(t, u) },
        "deleteAvatarFile" to { s -> s.deleteAvatarFile(t, u) },
        "deleteAvatarIfAny" to { s -> s.deleteAvatarIfAny(t, u) },
        // ---- 미니게임 ----
        "startMiniGameRound" to { s -> s.startMiniGameRound(t, "flappy") },
        "submitMiniGameScore" to { s -> s.submitMiniGameScore(t, "tetris", 3_000_000_000, "tok") },
        "fetchMiniGameBoard" to { s -> s.fetchMiniGameBoard(t, "timing_bar") },
        "fetchMiniGameBoard(day)" to { s -> s.fetchMiniGameBoard(t, "crossy", "2026-09-16") },
        "fetchMiniGameYesterdayWinner" to { s -> s.fetchMiniGameYesterdayWinner(t, "flappy") },
        "fetchMiniGameAllTimeBoard" to { s -> s.fetchMiniGameAllTimeBoard(t, "crossy") },
        // ---- 상점 ----
        "fetchShopState" to { s -> s.fetchShopState(t) },
        "fetchShopState(protocol)" to { s -> s.fetchShopState(t, 4) },
        "fetchShopState(protocol)#fallback" to { s -> listOf(s.fetchShopState(t, 4), s.fetchShopState(t, 4)) },
        "fetchShopState(protocol)#plain404" to { s ->
            try { s.fetchShopState(t, 4) } catch (e: SupabaseWorkServiceError) { /* authMessage("nope") — 되묻기 없음 */ }
            s.fetchShopState(t, 4)
        },
        "buyCharacter" to { s -> s.buyCharacter(t, "robot") },
        "buyCharacter(protocol)" to { s -> s.buyCharacter(t, "robot", 3) },
        "buyCharacter(protocol)#fallback" to { s -> s.buyCharacter(t, "fox", 3) },
        // ---- 메시지 ----
        "sendMessage" to { s -> s.sendMessage(t, p, "  안녕하세요\n") },
        "sendMessage#empty" to { s -> s.sendMessage(t, p, " \n ") },
        "sendMessage#tooLong" to { s -> s.sendMessage(t, p, "가".repeat(201)) },
        "fetchMessageHistory" to { s -> s.fetchMessageHistory(t) },
        "fetchMessageHistory#clamp" to { s -> s.fetchMessageHistory(t, 99, 0) },
        "fetchPokeDirectory" to { s -> s.fetchPokeDirectory(t) },
        "fetchMessageHistoryWithReads" to { s -> s.fetchMessageHistoryWithReads(t, 24, 600) },
        "fetchMessageUnreadSummary" to { s -> s.fetchMessageUnreadSummary(t) },
        "markMessagesRead" to { s -> s.markMessagesRead(t, p, "msg-9") },
        "markMessagesRead(nil)" to { s -> s.markMessagesRead(t, p, null) },
        "fetchMessageHistoryWithPokes" to { s -> s.fetchMessageHistoryWithPokes(t, 0, 50) },
        "markConversationRead" to { s -> s.markConversationRead(t, p, "msg-9", "poke-3") },
        "markConversationRead(nil)" to { s -> s.markConversationRead(t, p, null, null) },
        // ---- 릴리스 · 공지 ----
        "fetchLatestRelease" to { s -> s.fetchLatestRelease() },
        "appCurrentNotice" to { s -> s.appCurrentNotice() },
        // ---- 제보 ----
        "submitFeedback" to { s -> s.submitFeedback(t, FeedbackKind.bug, "버튼이 안 눌려요", "1.0.14", "17.6") },
        "fetchFeedbackList" to { s -> s.fetchFeedbackList(t, null, 50) },
        "fetchFeedbackList(status)" to { s -> s.fetchFeedbackList(t, FeedbackStatus.InProgress, 20) },
        "setFeedbackStatus" to { s -> s.setFeedbackStatus(t, "fb-1", FeedbackStatus.Held, null) },
        "setFeedbackStatus(note)" to { s -> s.setFeedbackStatus(t, "fb-1", FeedbackStatus.Done, "고쳤어요") },
        "replyFeedback" to { s -> nowMarked(s.replyFeedback(t, "fb-1", "답장")) },
        "fetchFeedbackReplyLatest" to { s -> s.fetchFeedbackReplyLatest(t) },
        "fetchFeedbackOpenCount" to { s -> s.fetchFeedbackOpenCount(t) },
        // ---- 차단 · 신고 ----
        "blockUser" to { s -> s.blockUser(t, p) },
        "unblockUser" to { s -> s.unblockUser(t, p) },
        "fetchBlocks" to { s -> s.fetchBlocks(t) },
        "reportContent" to { s -> s.reportContent(t, p, ContentReportReason.harassment, "욕설", "msg-1", true) },
        "reportContent#empty" to { s -> s.reportContent(t, p, ContentReportReason.spam, "", null, false) },
        // ---- 캐릭터 · 선물 · 뽑기 ----
        "fetchAppUserCharacters" to { s -> s.fetchAppUserCharacters(t) },
        "fetchCharacterGiftPending" to { s -> s.fetchCharacterGiftPending(t, 4) },
        "claimCharacterGift" to { s -> s.claimCharacterGift(t, "gift-1", "aing_cake_strawberry", 4) },
        "gachaPull" to { s -> s.gachaPull(t, 4, rid.uppercase()) },
        "gachaExchange" to { s -> s.gachaExchange(t, "aing_rainbow", 4, rid.uppercase()) },
        // ---- 할 일 ----
        "todoSync" to { s -> s.todoSync(t, TodoSyncRequest(emptyList(), null)) },
        "todoSync(changes)" to { s ->
            val item = TodoSyncWireItem("0000000a-0000-4000-8000-00000000000a", "할 일", 1_726_500_000_000, 1_726_500_005_000, null, null, "20240917")
            s.todoSync(t, TodoSyncRequest(listOf(item), 1_726_400_000_000))
        },
        // ---- 기기 · 폰 근무 ----
        "fetchClientRelease" to { s -> s.fetchClientRelease("ios") },
        "registerDevice" to { s -> s.registerDevice(t, "ios", "11111111-2222-4333-8444-555555555555", 2_147_483_648, "1.0.14", "tok", "production") },
        "registerDevice#tokenOnly" to { s -> s.registerDevice(t, "ios", "i", 7, null, "tok", null) },
        "unregisterDevice" to { s -> s.unregisterDevice(t, "i") },
        "setPushPrefs" to { s -> s.setPushPrefs(t, "i", PushPrefs(message = false)) },
        "startPhoneWork" to { s -> s.startPhoneWork(t) },
        "stopPhoneWork" to { s -> s.stopPhoneWork(t, "ABCDEF00-0000-4000-8000-000000000001") },
        "stopPhoneWork(nil)" to { s -> s.stopPhoneWork(t, null) },
        "touchPhoneWork" to { s -> s.touchPhoneWork(t) },
        // ---- 오목 ----
        "gomokuLobby" to { s -> s.gomokuLobby(t) },
        "gomokuChallenge" to { s -> s.gomokuChallenge(t, p, 10) },
        "gomokuCancel" to { s -> s.gomokuCancel(t, m) },
        "gomokuRespond" to { s -> s.gomokuRespond(t, m, true) },
        "gomokuMove" to { s -> s.gomokuMove(t, m, 4, 7, 8) },
        "gomokuMove#deadlock" to { s -> s.gomokuMove(t, m, 4, 7, 8) },
        "gomokuResign" to { s -> s.gomokuResign(t, m) },
        "gomokuState" to { s -> s.gomokuState(t, m, 3, 1) },
        "gomokuState#deadlock" to { s -> s.gomokuState(t, m, 0, 0) },
        "gomokuInbox" to { s -> s.gomokuInbox(t) },
        "gomokuChatSend" to { s -> s.gomokuChatSend(t, m, GomokuChatKind.quick, "잘 부탁해요") },
        "gomokuLeave" to { s -> s.gomokuLeave(t, m) },
        "gomokuChatMute" to { s -> s.gomokuChatMute(t, m, true) },
        "gomokuRanking" to { s -> s.gomokuRanking(t) },
        "gomokuWatch" to { s -> s.gomokuWatch(t, m, 12) },
        "gomokuWatchLive" to { s -> s.gomokuWatchLive(t, m, 12) },
        // ---- 체스 ----
        "chessLobby" to { s -> s.chessLobby(t) },
        "chessChallenge" to { s -> s.chessChallenge(t, p, 5) },
        "chessCancel" to { s -> s.chessCancel(t, m) },
        "chessRespond" to { s -> s.chessRespond(t, m, false) },
        "chessMove" to { s -> s.chessMove(t, m, 2, "e7e8q") },
        "chessMove#deadlock" to { s -> s.chessMove(t, m, 2, "e2e4") },
        "chessResign" to { s -> s.chessResign(t, m) },
        "chessOfferDraw" to { s -> s.chessOfferDraw(t, m) },
        "chessRespondDraw" to { s -> s.chessRespondDraw(t, m, true) },
        "chessState" to { s -> s.chessState(t, m, 9) },
        "chessRanking" to { s -> s.chessRanking(t) },
        "chessWatch" to { s -> s.chessWatch(t, m, 0) },
        "chessWatchLive" to { s -> s.chessWatchLive(t, m, 0) },
        // ---- 테트리스 ----
        "tetrisLobby" to { s -> s.tetrisLobby(t) },
        "tetrisChallenge" to { s -> s.tetrisChallenge(t, p, 3) },
        "tetrisCancel" to { s -> s.tetrisCancel(t, m) },
        "tetrisRespond" to { s -> s.tetrisRespond(t, m, true) },
        "tetrisReport" to { s ->
            s.tetrisReport(t, TetrisReportRequest(pMatchId = m, pSeq = 12, pBoard = ".".repeat(200), pLines = 4, pGarbageSent = 2, pGarbageApplied = 1, pPending = 3, pToppedOut = false))
        },
        "tetrisState" to { s -> s.tetrisState(t, m) },
        "tetrisResign" to { s -> s.tetrisResign(t, m) },
        "tetrisRanking" to { s -> s.tetrisRanking(t) },
        "tetrisWatchLive" to { s -> s.tetrisWatchLive(t, m) },
        "tetrisWatch" to { s -> s.tetrisWatch(t, m) },
        // ---- 결과 대조(서비스 후처리) ----
        "signIn#data" to { s -> s.signIn("a@b.invalid", "pw-123456") },
        "signUp#session" to { s -> s.signUp("a@b.invalid", "pw-123456", "아잉") },
        "signUp#confirm" to { s -> s.signUp("a@b.invalid", "pw-123456", "아잉") },
        "signUp#exists" to { s -> s.signUp("a@b.invalid", "pw-123456", "아잉") },
        "signUp#noIdentitiesKey" to { s -> s.signUp("a@b.invalid", "pw-123456", "아잉") },
        "verifySignUpCode#expired" to { s -> s.verifySignUpCode("a@b.invalid", "654321") },
        "sendPasswordResetCode#rateLimited" to { s -> s.sendPasswordResetCode("a@b.invalid") },
        "updatePassword#same" to { s -> s.updatePassword(t, "new-pw-1") },
        "lookupTeamByCode#data" to { s -> s.lookupTeamByCode("abc-123") },
        "lookupTeamByCode#none" to { s -> s.lookupTeamByCode("abc-123") },
        "fetchMyInviteCode#data" to { s -> s.fetchMyInviteCode(t) },
        "joinTeam#data" to { s -> s.joinTeam(t, "xyz-789") },
        "joinTeam#none" to { s -> s.joinTeam(t, "xyz-789") },
        "createTeam#data" to { s -> s.createTeam(t, "새 팀", 60) },
        "fetchTeamLeaderboard#data" to { s -> s.fetchTeamLeaderboard(t) },
        "fetchOwnMembership#data" to { s -> s.fetchOwnMembership(t, u) },
        "fetchOwnMembership#defaults" to { s -> s.fetchOwnMembership(t, u) },
        "fetchOwnMembership#none" to { s -> s.fetchOwnMembership(t, u) },
        "fetchTeamStatuses#data" to { s -> s.fetchTeamStatuses(t, "team-1", now) },
        "fetchTeamStatuses#devicesFail" to { s -> s.fetchTeamStatuses(t, "team-1", now) },
        "fetchMySessions#data" to { s -> s.fetchMySessions(t, u, now.addingTimeInterval(-86_400.0)) },
        "fetchMiniGamePublic#data" to { s -> s.fetchMiniGamePublic(t, u) },
        "fetchMyCenter#data" to { s -> s.fetchMyCenter(t, u) },
        "fetchMyStatusMessage#data" to { s -> s.fetchMyStatusMessage(t, u) },
        "fetchTokenUsageSettings#data" to { s -> s.fetchTokenUsageSettings(t, u) },
        "fetchTokenUsageSettings#none" to { s -> s.fetchTokenUsageSettings(t, u) },
        "setDisplayName#data" to { s -> s.setDisplayName(t, "새이름") },
        "fetchDisplayNameChangedAt#data" to { s -> s.fetchDisplayNameChangedAt(t, u) },
        "fetchEquippedCharacter#data" to { s -> s.fetchEquippedCharacter(t, u) },
        "fetchEquippedCharacter#noRow" to { s -> s.fetchEquippedCharacter(t, u) },
        "fetchAILimitMainDeviceID" to { s -> s.fetchAILimitMainDeviceID(t, u) },
        "fetchAILimitMainDeviceID#blank" to { s -> s.fetchAILimitMainDeviceID(t, u) },
        "fetchAILimitMainDeviceID#none" to { s -> s.fetchAILimitMainDeviceID(t, u) },
        "fetchAILimitMainDeviceID#null" to { s -> s.fetchAILimitMainDeviceID(t, u) },
        "removeAvatar#gone404" to { s -> s.removeAvatar(t, u) },
        "removeAvatar#left" to { s -> s.removeAvatar(t, u) },
        "deleteAvatarFile#notFoundBody" to { s -> s.deleteAvatarFile(t, u) },
        "fetchMiniGameBoard#data" to { s -> s.fetchMiniGameBoard(t, "flappy") },
        "fetchMiniGameYesterdayWinner#data" to { s -> s.fetchMiniGameYesterdayWinner(t, "crossy") },
        "fetchMiniGameYesterdayWinner#none" to { s -> s.fetchMiniGameYesterdayWinner(t, "crossy") },
        "fetchMiniGameAllTimeBoard#data" to { s -> s.fetchMiniGameAllTimeBoard(t, "crossy") },
        "sendMessage#data" to { s -> s.sendMessage(t, p, "안녕") },
        "fetchMessageHistory#data" to { s -> s.fetchMessageHistory(t) },
        "fetchMessageHistoryWithReads#data" to { s -> s.fetchMessageHistoryWithReads(t, 24, 600) },
        "fetchMessageHistoryWithPokes#data" to { s -> s.fetchMessageHistoryWithPokes(t, 24, 500) },
        "appCurrentNotice#error" to { s -> s.appCurrentNotice() },
        "submitFeedback#data" to { s -> s.submitFeedback(t, FeedbackKind.request, "기능 요청", "1.0.14", "17.6") },
        "fetchFeedbackList#data" to { s -> s.fetchFeedbackList(t, null, 50) },
        "replyFeedback#data" to { s -> nowMarked(s.replyFeedback(t, "fb-1", "답장")) },
        "replyFeedback#garbage" to { s -> nowMarked(s.replyFeedback(t, "fb-1", "답장")) },
        "signOut#serverError" to { s -> s.signOut(t) },
        "fetchFeedbackReplyLatest#data" to { s -> s.fetchFeedbackReplyLatest(t) },
        "fetchFeedbackOpenCount#data" to { s -> s.fetchFeedbackOpenCount(t) },
        "fetchBlocks#data" to { s -> s.fetchBlocks(t) },
        "fetchAppUserCharacters#data" to { s -> s.fetchAppUserCharacters(t) },
        "fetchAppUserCharacters#missing" to { s -> s.fetchAppUserCharacters(t) },
        "fetchAppUserCharacters#plain404" to { s -> s.fetchAppUserCharacters(t) },
        "fetchAppUserCharacters#serverError" to { s -> s.fetchAppUserCharacters(t) },
        "fetchCharacterGiftPending#missing" to { s -> s.fetchCharacterGiftPending(t, 4) },
        "startPhoneWork#data" to { s -> s.startPhoneWork(t) },
        // ---- 상점 번호 깃발(C§4 #9) ----
        "fetchShopState(protocol)#html404" to { s -> listOf(s.fetchShopState(t, 4), s.fetchShopState(t, 4)) },
        "fetchShopState(protocol)#recheck" to { s ->
            val first = s.fetchShopState(t, 4)
            clockNow = now.addingTimeInterval(299.999)
            val second = s.fetchShopState(t, 4)
            clockNow = now.addingTimeInterval(300.0)
            val third = s.fetchShopState(t, 4)
            listOf(first, second, third)
        },
    )

    /** 서비스 시계(Swift `WireClock`) — case 마다 [now] 로 되돌린다. */
    private var clockNow = now

    /** Swift `nowMarked`: 응답 시각을 못 읽어 시계로 떨어진 값 → "$now"(Swift = 벽시계 Date(), Kotlin = 주입 시계 — 앱 조립에서 시스템 시계). */
    private fun nowMarked(date: SwiftDate): Any = if (date == clockNow) "\$now" else date

    private val dumper = GoldenDump(leaf = { v ->
        when (v) {
            is SwiftDate -> GoldenDump.date(v.timeIntervalSince1970)
            is SwiftURL -> JsonObject(mapOf("\$url" to JsonPrimitive(v.absoluteString)))
            // Swift 에 없는 Kotlin 칸 셋(latest_version·download_url·updated_at — 모델 주석)만 빼고 Swift 덤프와 맞춘다(fetchClientRelease).
            is ClientReleaseResponse -> JsonObject(
                (GoldenDump().dump(v) as JsonObject) -
                    setOf(ClientReleaseResponse::latestVersion.name, ClientReleaseResponse::downloadUrl.name, ClientReleaseResponse::updatedAt.name),
            )
            // Swift 기준선(이 레인 골든 = main 75c31cd2) **뒤에** 더한 확성기 칸(main a6791165 b056075b — 앱 전체 5분 대기). 이 칸만 빼고 맞춘다.
            // 골든을 a6791165 이후로 다시 뜨면 Swift 덤프에 이 칸이 생긴다 — 그때 이 두 줄을 지운다.
            is MegaphoneInfoResponse -> JsonObject(
                (GoldenDump().dump(v) as JsonObject) -
                    setOf(MegaphoneInfoResponse::globalCooldownSeconds.name, MegaphoneInfoResponse::globalCooldownRemainingSeconds.name,
                        MegaphoneInfoResponse::cooldownScope.name),
            )
            is MegaphoneSendResponse -> JsonObject((GoldenDump().dump(v) as JsonObject) - MegaphoneSendResponse::scope.name)
            else -> null
        }
    })

    /** Swift `WireResult` 와 같은 모양: {"ok": 덤프} · {"throws": …}. 글자 잎은 같은 자리표시로. */
    private fun resultOf(value: Any?): JsonElement = when (value) {
        null -> JsonObject(mapOf("ok" to JsonNull))
        Unit -> JsonObject(mapOf("ok" to JsonPrimitive("\$void")))
        else -> JsonObject(mapOf("ok" to scrubLeaves(dumper.dump(value))))
    }

    private fun thrownOf(e: Throwable): JsonElement = JsonObject(
        mapOf(
            "throws" to when (e) {
                is SupabaseWorkServiceError -> dumpError(e)
                is SerializationException -> JsonPrimitive("\$decoding")
                is SwiftDecodingError -> JsonPrimitive("\$decoding")   // rules 의 관대한 디코드가 던지는 Swift DecodingError
                is CharacterSyncFetchError.NoProfileRow ->
                    JsonObject(mapOf("\$dump" to JsonPrimitive("noProfileRow"), "\$type" to JsonPrimitive("CharacterSyncFetchError")))
                else -> JsonObject(mapOf("\$type" to JsonPrimitive(e::class.qualifiedName ?: "?"), "\$message" to JsonPrimitive(e.message ?: "")))
            },
        ),
    )

    private fun scrubLeaves(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.mapValues { scrubLeaves(it.value) })
        is JsonArray -> JsonArray(e.map { scrubLeaves(it) })
        is JsonPrimitive -> if (e.isString) JsonPrimitive(GoldenScrub.text(GoldenRecorder.scrub(e.content))) else e
        else -> e
    }

    private class Recorded(val requests: List<JsonObject>, val result: JsonElement)

    private fun record(
        script: List<Pair<Int, String>>,
        routes: List<GoldenRoute> = emptyList(),
        call: suspend (SupabaseWorkService) -> Any?,
    ): Recorded {
        clockNow = now
        val recorder = GoldenRecorder(script, routes)
        val client = HttpClient(recorder.engine) { SupabaseWorkService.clientConfig(this) }
        val service = SupabaseWorkService(
            projectURL = "https://golden.invalid", anonKey = ANON, client = client,
            clock = { clockNow }, text = RulesWireTextRules, newUUIDString = { "ABCDEF12-3456-4789-8ABC-DEF012345678" },
        )
        val result = runBlocking {
            try {
                resultOf(call(service))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                thrownOf(e)
            }
        }
        client.close()
        return Recorded(recorder.requests.toList(), result)
    }

    private fun recordRequests(script: List<Pair<Int, String>>, call: suspend (SupabaseWorkService) -> Any?): List<JsonObject> =
        record(script, emptyList(), call).requests

    @Test
    fun everyGoldenRequestIsPortedAndMatches() {
        val golden = Golden.load("wire/requests")
        val problems = mutableListOf<String>()
        val missing = mutableListOf<String>()
        // 결과는 **모든** case 를 대조한다(빠지는 case 0). spec.resultOtherLanes 는 결과 타입이 rules·stores 에 있는 case 의 이름표다 —
        // 그 집합이 이 시험의 rules 합성(rulesComposed)과 정확히 같아야 한다(새 case 가 그 이름표로 오면 합성을 더할 때까지 빨강).
        val otherLaneResults = golden.spec.obj("resultOtherLanes").keys
        val skippedResults = mutableSetOf<String>()
        var comparedResults = 0
        var comparedOtherLane = 0
        for (c in golden.cases) {
            val id = c.string("id")
            val call = registry[id]
            if (call == null) {
                missing += id
                continue
            }
            val script = c.array("responses").map { (it as JsonObject).int("status") to it.string("body") }
            val routes = c.array("routes").map {
                val o = it as JsonObject
                val q = o["query"] as? JsonArray
                GoldenRoute(o.string("path"), q?.let { p -> (p[0] as JsonPrimitive).content to (p[1] as JsonPrimitive).content }, o.int("status"), o.string("body"))
            }
            val recorded = record(script, routes, call)
            var got: List<JsonElement> = recorded.requests
            val unordered = (c["unordered"] as JsonPrimitive).booleanOrNull == true
            if (unordered) got = got.sortedWith { a, b -> GoldenCanonical.codePointOrder.compare(GoldenCanonical.text(a), GoldenCanonical.text(b)) }
            val want = c.array("requests")
            val wantText = GoldenCanonical.text(want)
            val gotText = GoldenCanonical.text(JsonArray(got))
            if (wantText != gotText) problems += golden.failure(id, "요청이 다르다\n  Swift : $wantText\n  Kotlin: $gotText")
            val wantResultElement = c["result"]
            if (wantResultElement == null) {
                skippedResults += id
            } else {
                comparedResults++
                if (id in otherLaneResults) comparedOtherLane++
                val wantResult = GoldenCanonical.text(wantResultElement)
                val gotResult = GoldenCanonical.text(recorded.result)
                if (wantResult != gotResult) problems += golden.failure(id, "결과가 다르다\n  Swift : $wantResult\n  Kotlin: $gotResult")
            }
        }
        val extra = registry.keys - golden.cases.map { it.string("id") }.toSet()
        val excluded = golden.spec.obj("excluded")
        val wronglyPorted = registry.keys.map { it.substringBefore('(').substringBefore('#') }.filter { it in excluded.keys }
        println(
            "AINGCHECK-G5 cases=${golden.cases.size} ported=${golden.cases.size - missing.size} 미이식=${missing.size} excluded=${excluded.size} " +
                "results=$comparedResults otherLaneCompared=$comparedOtherLane skipped=${skippedResults.size} text=RulesWireTextRules problems=${problems.size}",
        )
        assertEquals(otherLaneResults, rulesComposed.keys, "spec.resultOtherLanes 와 rules 합성 case 가 다르다")
        assertEquals(otherLaneResults.size, comparedOtherLane, "resultOtherLanes case 가 결과 대조에서 빠졌다")
        assertTrue(skippedResults.isEmpty(), "결과 칸이 없어 대조하지 못한 case: $skippedResults")
        assertEquals(golden.cases.size, comparedResults + missing.size, "결과를 대조하지 않은 case 가 있다")
        assertTrue(comparedResults >= 214, "결과를 대조한 case 가 적다($comparedResults)")
        assertTrue(missing.isEmpty(), "미이식 ${missing.size}: $missing")
        assertTrue(extra.isEmpty(), "골든에 없는 Kotlin id(오타?): $extra")
        assertTrue(wronglyPorted.isEmpty(), "H·I·admin 태그 이름이 W1-d 레지스트리에 있다: $wronglyPorted")
        assertTrue(golden.cases.size >= 140, "G5 case 가 적다(${golden.cases.size})")
        if (problems.isNotEmpty()) fail("G5 불일치 ${problems.size}건(처음 12):\n" + problems.take(12).joinToString("\n\n"))
    }

    /**
     * 녹음기가 동시 요청을 하나도 잃지 않는다(팀 상태 4 GET 처럼 서비스가 요청을 병렬로 보낸다 — MockEngine 처리기는 IO 스레드에서 겹쳐 돈다).
     * 처리기 안 `synchronized(this)` 는 요청마다 새 scope 를 잠가 아무것도 막지 않았다(Windows CI 의 fetchTeamStatuses#devicesFail AIOOBE).
     */
    @Test
    fun recorderKeepsEveryConcurrentRequest() {
        val n = 512
        val recorder = GoldenRecorder(emptyList())
        val client = HttpClient(recorder.engine)
        try {
            runBlocking { (0 until n).map { i -> async(Dispatchers.IO) { client.get("https://golden.invalid/r?i=$i") } }.awaitAll() }
        } finally {
            client.close()
        }
        val seen = recorder.requests.map { ((it["query"] as JsonArray)[0] as JsonArray)[1].let { v -> (v as JsonPrimitive).content } }
        assertEquals(n, seen.size, "동시 요청 $n 개 중 ${seen.size} 개만 녹음했다")
        assertEquals((0 until n).map { it.toString() }.toSet(), seen.toSet(), "녹음한 요청이 겹치거나 빠졌다")
    }

    /** 경계(G §2-3 W1-d ⑥): 2^31 넘는 정수는 정밀도 그대로, 상점 번호 0 이면 키 생략, p_since_ms 는 null 이어도 싣는다. */
    @Test
    fun boundaryCases() {
        val big = recordRequests(emptyList()) { s -> s.submitMiniGameScore(t, "tetris", 3_000_000_000, "tok") }.single()
        assertEquals("3000000000", (big["body"] as JsonObject)["p_score"].toString())
        val legacy = recordRequests(emptyList()) { s -> s.fetchShopState(t, 0) }.single()
        assertEquals(JsonObject(emptyMap()), legacy["body"], "p_protocol 0 이면 키를 뺀다(옛 서명 `{}`)")
        val withProtocol = recordRequests(emptyList()) { s -> s.fetchShopState(t, 4) }.single()
        assertEquals("4", (withProtocol["body"] as JsonObject)["p_protocol"].toString())
        val todo = recordRequests(emptyList()) { s -> s.todoSync(t, TodoSyncRequest(emptyList(), null)) }.single()
        val body = todo["body"] as JsonObject
        assertTrue("p_since_ms" in body && body["p_since_ms"] is JsonNull, "p_since_ms 는 null 이어도 키가 있어야 한다: $body")
    }
}
