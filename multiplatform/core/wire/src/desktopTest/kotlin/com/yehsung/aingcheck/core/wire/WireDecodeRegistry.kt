// 원본: 없음 — Tests/CheckMobileKitTests/GoldenExport/wire/GoldenExportWireDecode.swift 의 `WireDecodeRegistry.decoders` 와 같은 이름 표
package com.yehsung.aingcheck.core.wire

import com.yehsung.aingcheck.core.wire.games.ChessActionResponse
import com.yehsung.aingcheck.core.wire.games.ChessLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ChessRankingResponse
import com.yehsung.aingcheck.core.wire.games.ChessStateResponse
import com.yehsung.aingcheck.core.wire.games.ChessWatchResponse
import com.yehsung.aingcheck.core.wire.games.GomokuActionResponse
import com.yehsung.aingcheck.core.wire.games.GomokuChatResponse
import com.yehsung.aingcheck.core.wire.games.GomokuInboxResponse
import com.yehsung.aingcheck.core.wire.games.GomokuLeaveResponse
import com.yehsung.aingcheck.core.wire.games.GomokuLobbyResponse
import com.yehsung.aingcheck.core.wire.games.GomokuRankingResponse
import com.yehsung.aingcheck.core.wire.games.GomokuStateResponse
import com.yehsung.aingcheck.core.wire.games.GomokuWatchResponse
import com.yehsung.aingcheck.core.wire.games.TetrisActionResponse
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.core.wire.games.TetrisRankingResponse
import com.yehsung.aingcheck.core.wire.games.TetrisWatchResponse
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftClaimResponse
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftPendingResponse
import com.yehsung.aingcheck.core.wire.models.*
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer

/** Swift 타입 이름 → Kotlin 디코더(이름은 Swift 그대로 — C§2.3). 여기에 없는 타입이 골든에 있으면 "미이식"으로 빨강. */
object WireDecodeRegistry {
    val decoders: Map<String, DeserializationStrategy<*>> = mapOf(
        "ChessActionResponse" to ChessActionResponse.serializer(),
        "ChessLobbyResponse" to ChessLobbyResponse.serializer(),
        "ChessStateResponse" to ChessStateResponse.serializer(),
        "ChessRankingResponse" to ChessRankingResponse.serializer(),
        "ChessWatchResponse" to ChessWatchResponse.serializer(),
        "GomokuActionResponse" to GomokuActionResponse.serializer(),
        "GomokuLobbyResponse" to GomokuLobbyResponse.serializer(),
        "GomokuStateResponse" to GomokuStateResponse.serializer(),
        "GomokuInboxResponse" to GomokuInboxResponse.serializer(),
        "GomokuChatResponse" to GomokuChatResponse.serializer(),
        "GomokuLeaveResponse" to GomokuLeaveResponse.serializer(),
        "GomokuRankingResponse" to GomokuRankingResponse.serializer(),
        "GomokuWatchResponse" to GomokuWatchResponse.serializer(),
        "TetrisActionResponse" to TetrisActionResponse.serializer(),
        "TetrisLobbyResponse" to TetrisLobbyResponse.serializer(),
        "TetrisRankingResponse" to TetrisRankingResponse.serializer(),
        "TetrisWatchResponse" to TetrisWatchResponse.serializer(),
        "[MessageHistoryRow]" to ListSerializer(MessageHistoryRow.serializer()),
        "[MessageHistoryReadsRow]" to ListSerializer(MessageHistoryReadsRow.serializer()),
        "MessageUnreadSummaryResponse" to MessageUnreadSummaryResponse.serializer(),
        "MessageReadMarkResponse" to MessageReadMarkResponse.serializer(),
        "PokeSendResponse" to PokeSendResponse.serializer(),
        "[TakenPokeRow]" to ListSerializer(TakenPokeRow.serializer()),
        "TodoSyncResponse" to TodoSyncResponse.serializer(),
        "ClientReleaseResponse" to ClientReleaseResponse.serializer(),
        "SignInResponse" to SignInResponse.serializer(),
        "SignUpResponse" to SignUpResponse.serializer(),
        "[MembershipRow]" to ListSerializer(MembershipRow.serializer()),
        "[AppUserCharacterRow]" to ListSerializer(AppUserCharacterRow.serializer()),
        "RegisterDeviceResponse" to RegisterDeviceResponse.serializer(),
        "SetPushPrefsResponse" to SetPushPrefsResponse.serializer(),
        "UnregisterDeviceResponse" to UnregisterDeviceResponse.serializer(),
        "[ProfilePrivacyRow]" to ListSerializer(ProfilePrivacyRow.serializer()),
        "[MiniGameBoardRow]" to ListSerializer(MiniGameBoardRow.serializer()),
        "[MiniGameWinnerRow]" to ListSerializer(MiniGameWinnerRow.serializer()),
        "[MiniGameAllTimeBoardRow]" to ListSerializer(MiniGameAllTimeBoardRow.serializer()),
        "MiniGameStartRoundResponse" to MiniGameStartRoundResponse.serializer(),
        "MiniGameSubmitScoreResponse" to MiniGameSubmitScoreResponse.serializer(),
        "[AILimitServerRow]" to ListSerializer(AILimitServerRow.serializer()),
        "[CharacterSyncProfileRow]" to ListSerializer(CharacterSyncProfileRow.serializer()),
        "[TokenUsageDailyRow]" to ListSerializer(TokenUsageDailyRow.serializer()),
        "[WorkSessionRow]" to ListSerializer(WorkSessionRow.serializer()),
        "[WorkStatusRow]" to ListSerializer(WorkStatusRow.serializer()),
        "ShopStateResponse" to ShopStateResponse.serializer(),
        "[DisplayNameChangedAtRow]" to ListSerializer(DisplayNameChangedAtRow.serializer()),
        "[MeProfileCardRow]" to ListSerializer(MeProfileCardRow.serializer()),
        "[ProfileCenterRow]" to ListSerializer(ProfileCenterRow.serializer()),
        "[ProfileStatusMessageRow]" to ListSerializer(ProfileStatusMessageRow.serializer()),
        "BuyCharacterResponse" to BuyCharacterResponse.serializer(),
        "CharacterGiftPendingResponse" to CharacterGiftPendingResponse.serializer(),
        "CharacterGiftClaimResponse" to CharacterGiftClaimResponse.serializer(),
        "[FeedbackReportRow]" to ListSerializer(FeedbackReportRow.serializer()),
        "String" to String.serializer(),
        "GachaExchangeResponse" to GachaExchangeResponse.serializer(),
        "GachaPullResponse" to GachaPullResponse.serializer(),
        "[InviteCodeRow]" to ListSerializer(InviteCodeRow.serializer()),
        "SetCharacterResponse" to SetCharacterResponse.serializer(),
        "DisplayNameChangeResponse" to DisplayNameChangeResponse.serializer(),
        "SetStatusMessageResponse" to SetStatusMessageResponse.serializer(),
        "[PokeDirectoryRow]" to ListSerializer(PokeDirectoryRow.serializer()),
        "[MessagePokeLossyRow]" to ListSerializer(MessagePokeLossyRow.serializer()),
        "PhoneWorkResponse" to PhoneWorkResponse.serializer(),
        "[SetTeamGoalRow]" to ListSerializer(SetTeamGoalRow.serializer()),
        "[TeamLeaderboardRow]" to ListSerializer(TeamLeaderboardRow.serializer()),
        "[TokenBoardRow]" to ListSerializer(TokenBoardRow.serializer()),
        "[CreateTeamRow]" to ListSerializer(CreateTeamRow.serializer()),
        "[JoinTeamRow]" to ListSerializer(JoinTeamRow.serializer()),
        "[TeamJoinPreviewRow]" to ListSerializer(TeamJoinPreviewRow.serializer()),
        "[WorkStatusDeviceRow]" to ListSerializer(WorkStatusDeviceRow.serializer()),
        "AppNotice" to AppNotice.serializer(),
        "AppLatestRelease" to AppLatestRelease.serializer(),
        "[BlockedUserRow]" to ListSerializer(BlockedUserRow.serializer()),
        "MessageConversationReadMarkResponse" to MessageConversationReadMarkResponse.serializer(),
        "SupabaseErrorResponse" to SupabaseErrorResponse.serializer(),
    )
}
