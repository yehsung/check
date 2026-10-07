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

    /// 변경 게이트 + 업로드. 실패는 조용히 — 장부를 성공 시에만 갱신해 다음 주기에 재시도된다.
    func uploadAILimitsIfNeeded(now: Date = Date()) async {
        guard let session, hasDeviceIdentity else { return }
        guard let bundle = aiLimits.bundle, !bundle.visibleProviders.isEmpty else { return }
        let fingerprint = AILimitUploadLedger.fingerprint(bundle)
        guard fingerprint != lastUploadedAILimits else { return }
        do {
            try await service.upsertAILimits(
                accessToken: session.accessToken,
                userID: session.userID,
                deviceID: deviceID,
                bundle: bundle
            )
            lastUploadedAILimits = fingerprint
        } catch {
            // 조용히. 스키마가 없는 서버(앱이 db push 보다 먼저 나간 경우)도 여기로 떨어지고, 그때 해야 할 일은
            // 아무것도 안 하는 것이다 — 리밋은 정보성 표시이고 사용자를 막을 이유가 없다.
        }
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
