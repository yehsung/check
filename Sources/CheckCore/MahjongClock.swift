import Foundation

// 아잉 마작 생각 시간 5초 + 예비 20초(MJ-53, DEC:11) — SQL `mahjong_clock_deadline`·`mahjong_clock_charge` 쌍둥이(SPEC §3.7 (b)).
// 직접 작성, 외부 판정 코드 없음 — 정본 rules.md MJ-53, SPEC §2.3(유예 1000ms · 마감에만 더하고 차감에는 안 더한다, D8).
//
// - 결정 하나마다 기본 5000ms. 자리마다 bank(국 시작 때 20000, 국 안 회복 없음).
// - 마감 deadline = 시작 + 5000 + bank. 판정 마감 = deadline + 유예 1000.
// - 차감 used = max(도착 − 시작, 0), bankLeft = bank − min(max(used − 5000, 0), bank). 유예 안에서 온 답은 받고 bank 를 0 으로.
// 판정은 도착 시각, 새 시계 시작은 처리 시각(D14) — 그 구분은 부르는 쪽(서버·판 진행)의 몫이다.

package nonisolated struct MahjongClock: Equatable, Sendable {
    /// 결정마다 기본 시간.
    package static let baseMs = 5_000
    /// 국 시작 때 채우는 예비.
    package static let bankFullMs = 20_000
    /// 네트워크 유예(마감에만, D8).
    package static let graceMs = 1_000

    /// 마감 = 시작 + 기본 + 남은 예비(유예 제외). = SQL `mahjong_clock_deadline(started, bank_ms)`.
    package static func deadline(started: Date, bankMs: Int) -> Date {
        started.addingTimeInterval(Double(baseMs + max(bankMs, 0)) / 1000)
    }

    /// 도착한 답의 차감. timedOut = 도착이 판정 마감(마감 + 유예)을 넘었다(같으면 받는다). = SQL `mahjong_clock_charge`.
    /// 경과 ms = **µs 로 맞춘 뒤 ms 아래를 버린다** — 서버는 timestamptz(µs 정수)에서 `floor(extract(epoch from 도착 − 시작) * 1000)`
    /// (체스 `chess__clock_charge` 틀, CD:837)로 잰다. Date 는 Double 초라 `5.1 초 × 1000` 이 5099.99… 로 떨어져 바로 버리면
    /// 서버보다 1ms 적게 센다(MahjongClockTests 의 기준선). 음수 경과(시계 역행)는 0.
    package static func charge(started: Date, arrived: Date, bankMs: Int) -> (bankLeft: Int, usedMs: Int, timedOut: Bool) {
        let bank = max(bankMs, 0)
        let micros = Int((arrived.timeIntervalSince(started) * 1_000_000).rounded())
        let used = max(micros >= 0 ? micros / 1000 : -((-micros + 999) / 1000), 0)
        let bankLeft = bank - min(max(used - baseMs, 0), bank)
        let timedOut = used > baseMs + bank + graceMs
        return (bankLeft, used, timedOut)
    }

    /// 표시용 두 칸(초) — 남은 기본 시간 · 남은 예비. 유예는 보이지 않는다. 초 단위로 바뀌는 값은 잎 뷰만 읽는다.
    package static func remaining(started: Date, bankMs: Int, now: Date) -> (baseLeft: Double, bankLeft: Double) {
        let elapsed = max(now.timeIntervalSince(started), 0)
        let base = Double(baseMs) / 1000
        let bank = Double(max(bankMs, 0)) / 1000
        return (max(base - elapsed, 0), max(bank - max(elapsed - base, 0), 0))
    }
}
