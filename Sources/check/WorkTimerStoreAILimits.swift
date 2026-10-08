import CheckCore
import Foundation

// MARK: - AI 리밋: 갱신 + 업로드 배선 (v0.3.45)
//
// 이 확장이 하는 일은 둘이다: 리밋 스토어의 주기를 돌려 주고, 받은 숫자를 서버에 올린다.
// 둘을 한 함수에 둔 이유는 **순서가 계약**이기 때문이다 — 올리는 값은 방금 읽은 값이어야 하고,
// 읽기가 실패했으면 올릴 새 값도 없다(들고 있던 값은 이미 서버에 가 있다).
//
// ## 게이트
//  ① 로그인(세션) — 올릴 자리가 있어야 읽는 보람이 있다. 다만 **읽기는 로그인 없이도 한다**:
//     팝오버의 한 줄과 창은 서버 없이도 맞고, 로그인 안 한 사람에게 리밋을 숨길 이유가 없다.
//  ② `hasDeviceIdentity` — 기기 식별자가 **저장으로 확인되지 않았으면** 서버에 쓰지 않는다.
//     ★ 새로 지어내지 **않는다**: 저장 확인 없이 만든 ID 로 올렸다가 순위표가 2배가 된 전례가 있다
//     (관례: '기기 신원을 지어내지 마라'). 기존 `deviceID` 를 **그대로** 재사용한다 — 리밋 축을 위해
//     두 번째 기기 신원을 만들면 같은 맥이 서버에 두 사람으로 보인다.
//  ③ 업로드는 **지문이 바뀌었을 때만**(`lastUploadedAILimits`). 지문이 재는 것은 둘이다 — 값이 바뀌었거나,
//     값이 같아도 **관측 시각이 한 칸(15분) 넘게 움직였거나**(폰·위젯의 신선도 축이 서버 `observed_at` 하나로
//     서 있다 — `AILimitUploadLedger` 머리말). 실패하면 장부를 갱신하지 않아 다음 주기가 재시도한다.
//
// ## 사용자 설정(v0.3.47)이 이 모든 것보다 **앞**에 있다
// 읽기 게이트는 스토어가 쥔다(`AILimitStore.isDue` · 러너의 `providers`). 여기서는 **올리는 쪽** 둘을 지킨다:
//  · 끈 제공자는 값 행을 만들지 않는다(`aiLimits.enabledBundle` 이 이미 걸렀다).
//  · 끈 **그 순간** 그 제공자의 행을 비우는 행 하나로 덮는다(`pendingClear`) — 폰·위젯에서도 같이 사라진다.
//
// ## 수집 설정(`tokenUsageCollect`)을 게이트로 쓰지 않는 이유
// 그 설정은 **토큰 축의 순위판 공개 여부**다(남에게 내 숫자를 보일지). 리밋 축은 본인만 보기(RLS)이고
// 순위판 RPC 가 이 표를 읽지 않으므로(마이그레이션 §5⑦·⑧) "남에게 안 보이게"와 아무 관계가 없다.
// 두 축을 한 스위치에 묶으면, 순위판에서 빠지려고 끈 사람이 자기 화면의 리밋까지 잃는다.
// 다만 **프로세스를 띄우는 일**(`security`·`agy`)은 수집 설정과 무관하게 이 기기의 자기 자격증명을 읽는
// 것뿐이고 외부로 아무것도 나가지 않는다 — Codex 계정 프로브가 수집 설정을 기다리는 이유(그 값이
// 순위판으로 간다)가 여기에는 없다.

extension WorkTimerStore {
    /// 리밋 스토어를 돌리고 받은 숫자를 올린다. 팝오버 열림·30초 틱이 부르는 진입점이다.
    ///
    /// `force` 는 "사용자가 방금 팝오버·창을 열었다"일 때 참이다(스토어의 5분 하한은 유지 — Claude 가
    /// 5분에 5회로 막기 때문에 여닫기만으로 429 를 맞을 수 있다).
    func refreshAILimitsIfNeeded(now: Date = Date(), force: Bool = false) async {
        await aiLimits.refreshIfDue(now: now, force: force)
        await uploadAILimitsIfNeeded(now: now)
    }

    /// 업로드 진입점. **직렬화만** 한다 — 본문을 만드는 일은 `sendAILimitsUpload` 가 한다.
    ///
    /// ## ★★ 비행 중이면 새로 쏘지 않고 **트레일링 한 번**으로 합친다 (v0.3.47 P1 — 2026-10-08 실증)
    /// 설정 세터는 토글마다 Task 를 띄우는데, `WorkTimerStore` 가 MainActor 라도
    /// `await service.upsertAILimits` 에서 액터가 풀려 **두 업로드가 동시에 난다.** 스위치 둘을 연달아 끄는
    /// 평범한 사용에서 실측된 모습은 이것이다:
    ///   · 본문 A = `claude=값, antigravity=값, codex=null`(첫 토글 시점의 진실)
    ///   · 본문 B = `claude=값, codex=null, antigravity=null`(둘째 토글 시점의 진실)
    /// 같은 PK(`user_id,device_id,provider`)가 한쪽에는 값 행으로, 다른 쪽에는 비우는 행으로 들어가고
    /// **두 요청의 도착 순서는 아무도 보장하지 않는다.** 값 본문이 나중에 닿으면 끈 제공자가 되살아나고,
    /// 그때 `markCleared` 둘이 이미 대기열을 비워 **다시는 안 비운다** — 그 사람의 폰은 끈 제공자를 계속 본다.
    ///
    /// 그래서 한 번에 하나만 난다(`uploadPeakConcurrency == 1` 이 계약이고 테스트가 그걸 잰다). 줄 세우는
    /// 것이 아니라 **합치는** 까닭: 뒤엣것이 재는 것은 "지금 상태를 올려라"이고, 그 사이 토글이 열 번
    /// 울렸어도 마지막 상태 한 번이면 같은 뜻이다(요청만 아홉 번 는다).
    ///
    /// ★ `defer` 로 핸들을 비우지 **않는다**: 트레일링을 소비하는 동안에도 핸들이 non-nil 이어야 그 사이에
    ///   들어온 요청이 또 쏘지 않는다. 루프로 소비하고 **그 뒤에** 비운다(`requestDrain` 과 같은 관용구).
    ///
    /// ## ★★ 트레일링은 **그 시점의 `now`** 로 돈다 (2026-10-08 재검)
    /// 초안의 루프는 첫 호출의 `now` 를 두 번째 바퀴에도 그대로 넘겼다. 그 값은 **이미 과거**다 — 첫 바퀴가
    /// 왕복(네트워크)을 돌고 온 뒤니까. 백오프 창이 그 사이에 끝났는데도 트레일링이 옛 시각으로 판정하면
    /// `uploadRetryAllowed` 가 거짓이 되어, **소비된 채 아무것도 보내지 않는다**:
    ///   비우기 백오프 창 안에서 값 변화 없이 토글만 들어온 경우가 그 자리다. 다음 30초 틱이 구해 주지만
    ///   "끈 즉시 폰에서 사라진다"는 약속이 최대 30초 늦는다 — 그 30초는 사용자가 폰을 들여다보는 시간이다.
    /// 그래서 루프의 둘째 바퀴부터는 **스토어의 시계**를 다시 읽는다(`aiLimits.clockNow` — 테스트 시계가
    /// 주입되는 그 시계다. `Date()` 를 직접 부르면 고정 시계 테스트가 진짜 벽시계로 샌다).
    func uploadAILimitsIfNeeded(now: Date = Date()) async {
        guard aiLimits.uploadInFlight == nil else {
            aiLimits.uploadPendingTrailing = true
            return
        }
        let limits = aiLimits
        let task = Task { @MainActor [weak self] in
            var at = now
            repeat {
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 업로드가 도는 동안 도착한 신호를 지운다.
                limits.uploadPendingTrailing = false
                guard let self else { break }
                await sendAILimitsUpload(now: at)
                // 다음 바퀴는 **지금**이다(위 주석). 첫 바퀴만 호출자가 준 시각을 쓴다 — 그 시각은
                // 30초 틱·팝오버 열기가 재 둔 "이 바퀴의 기준"이라 첫 판정의 주인이다.
                at = limits.clockNow
            } while limits.uploadPendingTrailing
            limits.uploadInFlight = nil
        }
        aiLimits.uploadInFlight = task
        await task.value
    }

    /// 변경 게이트 + 업로드 한 번. 실패는 조용히 — 장부를 성공 시에만 갱신해 다음 주기에 재시도된다.
    ///
    /// **부르는 자리는 위 진입점 하나다**(직렬화를 건너뛰면 P1 이 그대로 돌아온다).
    ///
    /// ## ★ 비우기는 "묶음이 비었으면 반환"보다 **앞**에 있다 (v0.3.47)
    /// 올릴 값이 하나도 없는 바로 그 상태(마스터 끔 · 셋 다 끔)가 **비워야 하는 상태**다. 초안처럼
    /// `guard !visibleProviders.isEmpty` 를 맨 위에 두면 전체 끄기가 서버에 영원히 닿지 못하고,
    /// 폰·위젯은 맥이 끈 뒤에도 옛 숫자를 3일간(유령 게이트까지) 계속 보여 준다.
    private func sendAILimitsUpload(now: Date) async {
        guard let session, hasDeviceIdentity else { return }
        // 비우기는 **집어서** 보낸다. await 뒤에 비우는 것은 이 집음이지 '그때의 대기열'이 아니다 —
        // 떠난 사이에 다시 끈 제공자를 비웠다고 표시하면 그 끄기는 영원히 서버에 닿지 않는다
        // (`AILimitClearClaim` 머리말).
        let claim = aiLimits.claimPendingClear()
        // 설정이 **켠** 제공자만 담긴 묶음. 끈 제공자는 여기 없고, 대신 위 대기열에 있다.
        let bundle = aiLimits.enabledBundle
        let hasValues = !bundle.visibleProviders.isEmpty
        let fingerprint = AILimitUploadLedger.fingerprint(bundle)
        let valuesChanged = hasValues && fingerprint != lastUploadedAILimits
        guard valuesChanged || !claim.isEmpty else { return }
        // ★★ 백오프는 **값 업로드에도** 걸린다(2026-10-08 재검). 초안의 게이트는 `if !valuesChanged, …` 라
        //   값이 바뀐 업로드를 비껴갔는데, 스키마 없는 서버에서는 장부가 **성공에만** 갱신되므로
        //   `valuesChanged` 가 영원히 참이다 — 그래서 마스터를 켜 둔 평범한 사용자는 30초마다 영원히 POST 했다
        //   (비우기만 막던 가드는 그 사람에게 아무것도 아니었다). 영구 포기는 없다: 느려지되 멈추지 않는다
        //   (60초 → 두 배씩 → 상한 1시간, 성공 한 번이면 즉시 풀린다).
        guard aiLimits.uploadRetryAllowed(now: now) else { return }
        aiLimits.noteUploadStarted()
        defer { aiLimits.noteUploadFinished() }
        do {
            try await service.upsertAILimits(
                accessToken: session.accessToken,
                userID: session.userID,
                deviceID: deviceID,
                // 기기 이름(v0.3.47). **그때그때 읽는다** — 사용자가 시스템 설정에서 맥 이름을 바꾸면
                // 앱을 다시 켜지 않아도 다음 업로드가 새 이름을 싣는다. 빈 값이면 nil 로 간다(싣지 않는다).
                deviceLabel: aiLimits.deviceLabel,
                bundle: bundle,
                clearedProviders: claim.providers,
                clearedAt: now
            )
            if valuesChanged { lastUploadedAILimits = fingerprint }
            // 성공한 비우기만 대기열에서 뺀다. 실패하면 그대로 남아 다음 주기(30초 틱·팝오버 열기)가 다시 보낸다 —
            // 영구히 안 지워지는 조합이 있으면 그 사람의 폰은 끈 제공자를 계속 보여 준다.
            aiLimits.markCleared(claim)
            aiLimits.noteUploadSucceeded()
        } catch {
            // 조용히. 스키마가 없는 서버(앱이 db push 보다 먼저 나간 경우)도 여기로 떨어지고, 사용자를 막을
            // 이유는 없다(리밋은 정보성 표시다). 다만 **간격은 벌린다** — 포기는 하지 않는다(대기열이 사라지면
            // 그 행은 영영 안 지워진다). 느려지되 멈추지 않는다: 60초 → 두 배씩 → 상한 1시간.
            aiLimits.noteUploadFailed(now: now)
        }
    }

    // MARK: - 설정 스위치 (v0.3.47)
    //
    // 설정 화면의 스위치가 부르는 자리. 스토어(`AILimitStore`)가 값을 쥐고, 여기는 **그 순간 서버에 반영**하는 일만 한다.
    // 집이 둘이 되지 않게 설정 화면은 반드시 이 두 함수만 부른다(소스 계약 테스트가 호출 지점 수를 되묻는다).

    /// 마스터 스위치. 끄면 읽기·타이머가 멈추고 **연동된 모든 제공자**의 행이 그 순간 비워진다.
    func setAILimitsVisible(_ enabled: Bool) {
        aiLimits.setMasterEnabled(enabled)
        noteAILimitsSettingChanged()
    }

    /// 제공자 하나의 스위치. 끄면 그 제공자만 읽기·업로드가 멈추고 행이 비워진다.
    func setAILimitProviderEnabled(_ provider: AILimitProvider, _ enabled: Bool) {
        aiLimits.setProviderEnabled(provider, enabled)
        noteAILimitsSettingChanged()
    }

    // MARK: - 메인 맥 고르개 (v0.3.47)
    //
    // ## 이 둘은 **설정 창 전용 경로**다
    // 30초 틱도 팝오버도 부르지 않는다(`refreshAILimitsIfNeeded` 와 나란히 두지 않은 까닭이다). 고르개가
    // 필요한 것은 "지금 내 맥이 몇 대이고 어느 것을 골랐나"뿐이고, 그 질문은 설정 창을 열 때만 생긴다 —
    // 틱에 얹으면 아무도 안 보는 동안 계정당 두 번씩 GET 이 더 난다(무료 플랜이다).
    //
    // ## on/off 토글과 달리 이것은 **계정 값**이다
    // 제공자 스위치는 기기 로컬이 옳다(각 맥이 자기 줄을 통제한다). 메인 맥은 반대다 — "폰·위젯에 무엇을
    // 보여 줄까"는 사람 하나당 하나의 답이고, 어느 맥에서 바꿔도 같은 곳(`ai_limits_prefs.main_device_id`)이
    // 바뀌어야 한다. 그래서 이 값만 서버에 있다.

    /// 서버의 내 기기 목록과 고른 메인 맥을 받아 온다. 설정 창이 열릴 때 부른다.
    ///
    /// ★ **둘 다 성공해야 반영한다.** 목록만 받아 두고 선택을 못 읽으면 고르개가 "아무것도 안 고름"으로
    ///   그려지는데, 그건 사실이 아니라 **못 읽었다**는 뜻이다 — 그 상태에서 사용자가 보는 기본 선택(가장 최근에
    ///   일한 맥)은 서버에 저장된 선택과 다를 수 있고, 그 어긋남은 조용하다. 둘은 같은 마이그레이션 한 장이
    ///   만든 표들이라 실패도 같이 온다(한쪽만 없는 서버는 없다).
    /// ★ 실패는 **조용하다**: 목록이 비면 고르개 줄 자체가 안 보인다(`showsMainDevicePicker`). 설정 창에
    ///   "불러오지 못했어요"를 적지 않는다 — 그 사람이 할 수 있는 일이 없다(관례: 사용자 툴팁은 진단이 아니다).
    func loadAILimitDevicesIfNeeded(now: Date = Date(), force: Bool = false) async {
        guard let session, hasDeviceIdentity else { return }
        guard force || aiLimits.devicesAreDue(now: now) else { return }
        aiLimits.noteDevicesLoading(true)
        defer { aiLimits.noteDevicesLoading(false) }
        do {
            let devices = try await service.fetchAILimitDevices(
                accessToken: session.accessToken, userID: session.userID)
            let chosen = try await service.fetchAILimitMainDeviceID(
                accessToken: session.accessToken, userID: session.userID)
            aiLimits.applyDevices(devices, mainDeviceID: chosen, now: now)
        } catch {
            // 조용히. 다음에 설정 창을 열면 다시 묻는다(스탬프를 안 찍었으므로 `devicesAreDue` 가 참이다).
        }
    }

    /// 메인 맥을 고른다. **먼저 화면에 반영하고** 서버에 쓰고, 실패하면 되돌린다.
    ///
    /// 되돌리는 까닭: 안 되돌리면 설정 창에는 내가 고른 맥이 떠 있는데 폰·위젯은 옛 맥을 계속 보여 준다 —
    /// 사용자가 고친 줄 아는 바로 그 결함이 남는다(화면만 바뀌는 거짓말). 칩이 제자리로 튀는 쪽이 정직하다.
    /// (`CheckCharacterSettingsRow` 가 "저장이 이긴 경우에만 칩을 옮긴다"로 같은 규약을 쓴다 — 여기는 왕복이
    ///  있어서 순서만 뒤집혔다.)
    func setAILimitMainDevice(_ deviceID: String) async {
        guard let session, hasDeviceIdentity else { return }
        let previous = aiLimits.setMainDeviceLocally(deviceID)
        do {
            try await service.upsertAILimitMainDeviceID(
                accessToken: session.accessToken, userID: session.userID, mainDeviceID: deviceID)
        } catch {
            aiLimits.setMainDeviceLocally(previous)
        }
    }

    /// 설정이 바뀐 뒤에 하는 일 둘.
    ///
    /// ① **장부를 버린다.** 장부가 재는 것은 "값이 바뀌었나"뿐이라, 끈 뒤 같은 값으로 다시 켠 사람의 지문이
    ///    장부와 똑같을 수 있다(퍼센트·리셋·플랜이 그대로고 관측 칸도 15분 안이면 그렇다). 그러면 비우기만
    ///    올라간 채 값이 다시 안 올라가, 맥에는 숫자가 보이는데 폰은 빈 채로 남는다. 설정 변경은 값과 무관한
    ///    사건이므로 장부로 걸러서는 안 된다.
    /// ② **그 순간 올린다.** 30초 틱을 기다리면 "껐는데 폰에 아직 있다"가 그 사이에 존재한다(설계 ③).
    private func noteAILimitsSettingChanged() {
        lastUploadedAILimits = nil
        Task { [weak self] in await self?.uploadAILimitsIfNeeded() }
    }
}

/// 업로드 변경 게이트의 지문(순수).
///
/// ## 조건이 **둘**이다 (2026-10-07 실증한 P1 — 초안은 하나였다)
/// 초안은 `observedAt` 을 통째로 뺐다. 근거는 "포함하면 게이트가 영원히 참이다"였고 그건 맞다 — 초 단위로 보면
/// 갱신마다 바뀐다. 그런데 **폰·위젯의 신선도 축은 서버 `observed_at` 하나로 서 있다.** 값만 보는 게이트는
/// 그 칸을 "마지막으로 **값이 바뀐** 시각"으로 만들어 버린다:
///   맥이 10분마다 정상으로 읽는데 사용률이 4시간째 그대로면 → 폰은 `60% 이상 · 4시간 전`,
///   같은 순간 맥 팝오버는 `60% · 방금`. 두 화면이 같은 장부를 보고 다른 말을 한다.
/// 초안 주석은 "서버 `updated_at` 이 보상한다"고 적었는데 **`fetchMyAILimits` 의 select 가 그 칸을 안 읽는다**
/// (`MeAILimitsService.swift`) — 보상 경로는 없었다.
///
/// 그래서 지문에 관측 시각을 **거친 칸**(`observedBucketSeconds`)으로 넣는다. 뜻은 OR 둘이다:
///   ① 값(퍼센트·리셋·플랜·계정)이 바뀌었다 → 올린다.
///   ② 값이 같아도 **관측 시각이 한 칸 넘게 움직였다** → 올린다(폰의 나이 캡션이 다시 젊어진다).
/// 매번 올리지는 않는다: 10분 주기 × 15분 칸이면 실제 재전송은 **20분에 한 번**으로 유계이고, 그 20분은
/// 신선도 경계(`AILimitFreshnessRule.recentWithin` = 30분, 넘으면 숫자에 "이상"이 붙는다)보다 넉넉히 짧다.
/// 그래서 맥이 켜져 있는 동안 폰이 `stale` 로 떨어지는 조합이 **구조적으로** 없다.
///
/// ★ 칸은 `now` 가 아니라 **관측 시각**에서 뽑는다. 못 읽고 있는 동안(네트워크 없음·만료) 관측 시각은 안 움직이고,
///   그때 다시 올려도 서버에 가는 `observed_at` 은 **똑같은 옛 시각**이라 폰에 아무 도움이 안 된다 —
///   요청만 늘어난다. 올릴 값어치가 있는 변화는 "새로 봤다" 하나뿐이다.
///
/// 올릴 행이 아니라 **스냅샷**에서 뽑는 이유: 행을 만드는 함수는 서비스(actor)에 있어 동기 비교에 쓸 수 없고,
/// 무엇보다 이 게이트가 재는 것은 "무엇이 바뀌었나"이지 전송 포맷이 아니다.
enum AILimitUploadLedger {
    /// 관측 시각을 재는 칸의 크기(초). 15분 — 위 산식(10분 주기 → 최대 20분 간격 < 30분 경계)의 근거다.
    /// 초 단위로 보면 게이트가 없는 것과 같고, 30분을 넘기면 폰이 `stale` 로 떨어지는 창이 열린다.
    static let observedBucketSeconds: TimeInterval = 900

    /// 관측 시각의 칸 번호. 같은 칸이면 "같은 때 본 것"으로 친다(내림 — 음수 시각에서도 단조롭다).
    static func observedBucket(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / observedBucketSeconds).rounded(.down))
    }

    static func fingerprint(_ bundle: AILimitSnapshotBundle) -> String {
        bundle.visibleProviders
            .map { snapshot -> String in
                var parts = [snapshot.provider.rawValue]
                for window in AILimitWindow.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    let row = snapshot.window(window)
                    // 퍼센트는 서버에 double 로 가므로 소수 세 자리까지 본다(0.0005 차이로 재전송하지 않게).
                    parts.append(row.map { String(format: "%.3f", $0.usedPercent) } ?? "-")
                    parts.append(row?.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-")
                }
                parts.append(snapshot.planLabel ?? "-")
                parts.append(snapshot.accountFingerprint ?? "-")
                // ② 관측 시각의 칸. 제공자별로 따로 본다 — 한 제공자만 새로 읽힌 주기에도 그 칸이 움직여야
                //    그 줄의 나이가 폰에서 다시 젊어진다.
                parts.append(snapshot.latestObservedAt.map { String(observedBucket($0)) } ?? "-")
                return parts.joined(separator: "|")
            }
            .joined(separator: ";")
    }
}
