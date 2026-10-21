// 원본: Sources/CheckMobileKit/Demo/MobileStubURLProtocol.swift:178-215 (MobileForbiddenCalls) @ a63fea2
// 폰(Android)이 **절대 부르면 안 되는** 서버 호출. 스토어 시나리오 시험 끝에 위반 `[]` 을 단언한다(W2-b ①).
package com.yehsung.aingcheck.testkit.mock

object PhoneForbiddenCalls {
    /** 이름만으로 금지인 RPC 8개. `join_team`·`create_team` 은 폰 가입 화면이 부른다(목록에서 빠짐). */
    val forbiddenRpcs: Set<String> = setOf(
        "take_pokes", "work_tick", "close_abandoned_work_sessions", "ultra_wallet_sync", "buy_ultra",
        "poke_user", "ultra_poke_user", "away_sync",
    )

    /** GET 말고는 금지인 표 7개(근무·기기 상태·토큰 원장·AI 리밋 원장 — 올리는 쪽은 맥·Windows). */
    val readOnlyTables: Set<String> = setOf(
        "work_sessions", "work_statuses", "work_status_devices",
        "token_usage_device_monthly", "token_usage_device_daily", "token_usage_monthly",
        "ai_limits",
    )

    /** profiles 쓰기 본문에 실리면 금지인 칸 3개(맥 빌드·집중 모드). */
    val forbiddenProfileColumns: List<String> = listOf("app_build", "app_version", "focus_mode")

    /** 위반이면 사람이 읽는 한 줄, 아니면 null. */
    fun violation(request: RecordedRequest): String? {
        request.rpcName?.let { rpc -> return if (rpc in forbiddenRpcs) "${request.method} rpc/$rpc" else null }
        val restPrefix = "/rest/v1/"
        if (!request.path.startsWith(restPrefix)) return null
        val table = request.path.removePrefix(restPrefix).substringBefore('/')
        val isRead = request.method.equals("GET", ignoreCase = true)
        if (table in readOnlyTables && !isRead) return "${request.method} $table"
        if (table == "profiles" && !isRead) {
            for (column in forbiddenProfileColumns) {
                if (request.bodyText.contains("\"$column\"")) return "${request.method} profiles.$column"
            }
        }
        return null
    }

    fun violations(requests: List<RecordedRequest>): List<String> = requests.mapNotNull(::violation)
}
