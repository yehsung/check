import Foundation
import SQLite3

// MARK: - v0.3.12: 안티그래비티 CLI(agy) 토큰 사용량 — 파서 + 증분 스캐너
//
// 이 파일은 **순수 계약**이다. "경로를 주면 파싱해 준다"까지만 하고, 스토어·UI·업로드에는 손대지 않는다
// (다음 단계가 꽂는다). CheckTokenUsage.swift 는 읽기 전용으로 취급했다 — 월 경계(monthBounds)·일 키(dayBounds)
// 는 거기서 **그대로 빌려 쓴다**. 두 스캐너가 각자 KST 캘린더를 만들면 언젠가 월 경계가 하루 어긋나고,
// 그때 잔디와 월 합계가 조용히 갈라진다.
//
// ## 프라이버시 (이 파일의 1번 규칙)
// gen_metadata.data 블롭 안에는 대화 본문이 통째로 들어 있다. 우리가 가져가는 값은 **토큰 수 · 모델 식별자**뿐이다.
// 워커는 태그를 따라 걸으면서 **길이만 보고 본문 페이로드를 건너뛴다** — 문자열로 디코드하는 자리는
// 모델 필드(1.19) 하나뿐이고, 거기서도 64바이트 이하 인쇄 가능한 ASCII 가 아니면 버린다(§모델 식별자).
// 어떤 경로로도 본문을 상태·합계·로그에 남기지 않는다.
//
// ## 디스크 모양 (2026-09-11 이 맥에서 실측, agy 1.2.0)
// `~/.gemini/antigravity-cli/conversations/<conversation_id>.db` — 대화 하나당 sqlite 파일 하나(WAL).
// 그 안의 `gen_metadata(idx INTEGER PK, data BLOB, size INTEGER)` 는 **생성(턴) 하나당 행 하나**.
// data 는 스키마 없는 protobuf 이다.
//
// ## ⚠️ 픽스처는 이미 넉넉하다 — `agy` 를 더 돌리지 마라 (사용자 구글 쿼터)
// 이 맥의 `conversations/` 에 있는 대화 **4건**이 이 파일의 근거 전부다. 무엇이 무엇인지는
// `V0312AntigravityUsageTests.swift` 의 `v0312Fixtures` 표에 conversation id 와 로그 파일까지 적어 뒀다.
// 필드 번호·압축·사이드카 세 가지가 이 4건으로 모두 덮인다. **새 대화를 만들 이유가 없다.**
//
// ## stdout 과의 관계 — 행은 턴당, stdout 은 대화 누적
// `agy -p ... --output-format json` 의 usage 는 **그 대화의 누적치**다. 픽스처 ②(클로드 1턴 + 이어서 제미나이 1턴)로
// 확정했다: 행별 값은 (15426/13/0/0) 과 (5567/67/66/8126) 인데 두 번째 턴의 stdout 은 (20993/80/66/8126) 이었다.
//   15426 + 5567 = 20993 · 13 + 67 = 80 · 0 + 66 = 66 · 0 + 8126 = 8126 — 네 필드가 전부 맞는다.
// 즉 **행을 더하면 stdout 이 된다**. 이 항등식이 아래 필드 번호의 증명이다(우연 일치로는 네 필드가 동시에 맞을 수 없다).
//
// ## 왜 정규식·바이트 검색이 아니라 구조 파싱인가
// facts.md 는 "값이 varint 로 그대로 보인다"고 적었지만, 같은 바이트열은 다른 자리에도 나타난다 — 픽스처 ②의
// idx1 에는 출력 토큰 13 과 같은 varint 가 `1.9.10.3.1.5.3`(스텝 내부)에도 있었고, 사용량 메시지 자체가
// `1.4` 와 `1.17.2` 두 곳에 **똑같이** 실린다. 값만 긁으면 어떤 날 조용히 두 배가 되거나 남의 숫자를 줍는다.
// 그래서 태그(field number + wire type)를 따라 걸어 **경로로 고정**한다.

// MARK: - 최소 protobuf 워커 (스키마 없음)

/// 스키마 없이 태그만 따라 걷는 protobuf 리더. 값을 "찾지" 않고 **구조를 걷는다** — 길이 접두 필드는 길이만큼 건너뛰므로
/// 본문 바이트를 들여다보는 일이 없고, 경로가 맞는 자리에서만 값을 꺼낸다.
enum AntigravityProto {
    /// base-128 varint. 버퍼 끝이거나 10바이트를 넘으면 nil(= 깨진 메시지) — 호출자는 그 메시지를 통째로 버린다.
    static func readVarint(_ b: UnsafeRawBufferPointer, _ i: inout Int, _ end: Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < end {
            let byte = b[i]
            i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    /// `[start, end)` 를 하나의 메시지로 보고 필드를 나온 순서대로 방문한다.
    ///
    /// visit 인자: (필드 번호, 와이어 타입, varint 값, 길이 접두 페이로드 범위).
    /// - wire 0 → varint 값이 유효, 범위는 빈 구간.
    /// - wire 2 → 범위가 유효(값은 길이). **여기서 재귀하지 않는다** — 호출자가 아는 경로에서만 다시 부른다.
    /// - wire 1/5 → 고정폭 범위(우리는 안 쓴다).
    ///
    /// 반환 false = 형식 오류(필드 번호 0, 길이 초과, 폐기된 group 태그 3·4). **부분 결과를 쓰지 마라** —
    /// 중간에서 어긋난 파싱은 그 뒤의 모든 태그가 무작위 바이트라 값을 지어낸다.
    @discardableResult
    static func walk(
        _ b: UnsafeRawBufferPointer, from start: Int, to end: Int,
        _ visit: (_ field: Int, _ wire: UInt8, _ value: UInt64, _ payload: Range<Int>) -> Void
    ) -> Bool {
        var i = start
        while i < end {
            guard let tag = readVarint(b, &i, end) else { return false }
            let field = Int(truncatingIfNeeded: tag >> 3)
            let wire = UInt8(tag & 7)
            guard field > 0 else { return false }
            switch wire {
            case 0:
                guard let v = readVarint(b, &i, end) else { return false }
                visit(field, wire, v, i..<i)
            case 1:
                guard end - i >= 8 else { return false }
                visit(field, wire, 0, i..<(i + 8))
                i += 8
            case 2:
                guard let n = readVarint(b, &i, end), n <= UInt64(end - i) else { return false }
                let len = Int(n)
                visit(field, wire, n, i..<(i + len))
                i += len
            case 5:
                guard end - i >= 4 else { return false }
                visit(field, wire, 0, i..<(i + 4))
                i += 4
            default:
                // 3·4 = 폐기된 start/end group, 6·7 = 정의 없음. 어느 쪽이든 우리가 읽는 메시지가 아니다.
                return false
            }
        }
        return true
    }
}

// MARK: - 한 행(= 생성 턴 하나)에서 뽑은 값

/// gen_metadata 한 행에서 뽑은 전부. **여기 없는 것은 우리가 안 가져간다**(본문·프롬프트·도구 인자 전부 제외).
struct AntigravityGenRow: Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var thinking: Int = 0
    /// 캐시 읽기. **total 에 들어간다** — Codex 의 codexCacheRead 와 정반대 규약이다.
    /// agy 의 cache_read 는 input 과 겹치지 않는다(2026-09-11 실측: input 5282 · cache_read 8128 — 캐시가 입력보다 커서
    /// 부분집합일 수 없다). Codex 는 input_tokens 가 캐시 히트를 **포함**하므로 더하면 이중 계상이지만 여기는 아니다.
    var cacheRead: Int = 0
    /// 모델 식별자(예 "gemini-3.8-flash" · "claude-sonnet-4-6"). 없으면 nil.
    var model: String?

    /// 합계 규약: **네 값 전부**(input + output + thinking + cacheRead).
    ///
    /// ★ 이 정의는 `TokenUsageMonthly.antigravityTotal`·서버 컬럼 주석(20260911120000)과 **한 몸이다**.
    ///   여기서 cacheRead 를 빼면 일별(dayContrib → antigravityDaily)과 월별(antigravity_* 네 컬럼 합)이 갈라져
    ///   잔디의 하루 합이 그 달 총합보다 작아진다(실측 26,422 vs 42,676 — 38% 차이). 한쪽만 고치지 마라:
    ///   V0312 테스트가 "두 정의는 같아야 한다"를 항등식으로 못 박아 뒀다.
    var total: Int { input + output + thinking + cacheRead }
}

// MARK: - gen_metadata 파서

/// gen_metadata.data(스키마 없는 protobuf)에서 토큰 네 갈래와 모델 식별자를 꺼낸다.
///
/// ## 필드 번호 — 2026-09-11 실측으로 확정(추정 아님)
/// facts.md 의 두 픽스처를 구조 워커로 끝까지 걸어 경로별 varint 를 뽑고, stdout 값과 맞춘 결과다.
///
/// | 경로 | 픽스처 ①(제미나이 1턴) | 픽스처 ② idx0(클로드) | ② idx1(제미나이) | stdout 이름 |
/// |---|---|---|---|---|
/// | `1.4.2`  | 5282 | 15426 | 5567 | input_tokens |
/// | `1.4.3`  | 1    | 13    | 67   | output_tokens |
/// | `1.4.5`  | 8128 | (없음)| 8126 | cache_read_tokens |
/// | `1.4.9`  | (없음)| (없음)| 66  | thinking_tokens |
/// | `1.19`   | "gemini-3.8-flash" | "claude-sonnet-4-6" | "gemini-3.8-flash" | model |
///
/// ①은 1턴짜리라 stdout(5282/1/0/8128)과 행이 그대로 같고, ②는 두 행의 합이 두 번째 턴 stdout(20993/80/66/8126)과 같다.
/// **필드 없음 = 0** 이다(protobuf 기본값) — 클로드 턴에 cache_read·thinking 필드가 아예 없었고 stdout 도 0 이었다.
/// `total_tokens` 는 저장되지 않는다(5283·15439 어디에도 없음) — 합은 우리가 계산한다.
///
/// ## 미러(1.17.2)를 더하면 안 된다
/// 같은 사용량 메시지가 `1.17.2` 에도 **바이트 단위로 같은 값**으로 한 번 더 실린다(facts.md 가 본 "varint 2회"의 정체).
/// 그래서 우리는 `1.4` 를 정본으로 쓰고, `1.4` 가 아예 없을 때만 미러로 떨어진다. 둘을 더하면 모든 숫자가 두 배가 된다.
///
/// ## 압축(compaction)에서 살아남는 것
/// 앞 행은 나중에 다시 써지며 줄어든다(실측 78,206B → 1,067B). 줄어든 행에서 사라진 것은 최상위 필드 3(요청 설정,
/// 여기에 `gemini-3.8-flash-low` 같은 **티어 접미사 붙은** 모델 문자열이 있다)이고, **남은 것**은 `1.4`(토큰),
/// `1.19`(모델), `1.20`(used_claude 등 문자열 맵)이다. 그래서 모델 식별자는 3.28 이 아니라 **1.19** 를 쓴다 —
/// 3.28 을 쓰면 같은 턴이 압축 전후로 다른 모델로 보여 모델별 집계가 저 혼자 움직인다.
enum AntigravityGenMetadataParser {
    // 최상위 → 생성 결과 메시지.
    static let genField = 1
    // 생성 메시지 안: 사용량 정본 / 미러(17 → 2) / 모델 식별자.
    static let usageField = 4
    static let usageMirrorOuterField = 17
    static let usageMirrorInnerField = 2
    static let modelField = 19
    // 사용량 메시지 안의 토큰 네 갈래.
    static let inputTokensField = 2
    static let outputTokensField = 3
    static let cacheReadTokensField = 5
    static let thinkingTokensField = 9

    /// 한 행이 가질 수 있는 토큰 수의 상한(정상성 검사). 실측 최대는 수만이고 모델 컨텍스트 상한이 수백만이라
    /// 1억을 넘는 값은 "우리가 남의 필드를 읽고 있다"는 증거다. 그런 행은 **부분 채택 없이 통째로 버린다** —
    /// 어긋난 파싱의 나머지 필드도 똑같이 못 믿기 때문이다.
    static let maxPlausibleTokens = 100_000_000

    /// 모델 식별자로 받아줄 최대 길이. 이보다 길면 모델 필드가 아니라 본문이 흘러든 것이다 → 버린다.
    static let maxModelIdentifierBytes = 64

    /// 실패(파싱 깨짐 / 정상성 검사 탈락 / 사용량 메시지 없음)면 nil. 호출자는 그 행을 건너뛴다.
    static func parse(_ b: UnsafeRawBufferPointer) -> AntigravityGenRow? {
        var gen: Range<Int>?
        // 최상위에서 필드 1 만 집는다. 실측상 행마다 정확히 한 번 나온다(다른 최상위 필드 2·3·4·8·10 은 건너뛴다).
        guard AntigravityProto.walk(b, from: 0, to: b.count, { field, wire, _, payload in
            if field == genField, wire == 2 { gen = payload }
        }), let genRange = gen else { return nil }

        var primary: AntigravityGenRow?
        var mirror: AntigravityGenRow?
        var mirrorOuter: Range<Int>?
        var model: String?
        var broken = false
        guard AntigravityProto.walk(b, from: genRange.lowerBound, to: genRange.upperBound, { field, wire, _, payload in
            guard wire == 2 else { return }
            switch field {
            case usageField:
                if let u = usage(b, payload) { primary = u } else { broken = true }
            case usageMirrorOuterField:
                mirrorOuter = payload
            case modelField:
                model = modelIdentifier(b, payload)
            default:
                break
            }
        }), !broken else { return nil }

        // 미러는 정본이 없을 때만 판다(정본이 있으면 굳이 같은 값을 한 번 더 걷지 않는다).
        if primary == nil, let outer = mirrorOuter {
            var inner: Range<Int>?
            if AntigravityProto.walk(b, from: outer.lowerBound, to: outer.upperBound, { field, wire, _, payload in
                if field == usageMirrorInnerField, wire == 2 { inner = payload }
            }), let innerRange = inner {
                mirror = usage(b, innerRange)
            }
        }

        guard var row = primary ?? mirror else { return nil }
        row.model = model
        return row
    }

    /// `[UInt8]` 편의 진입점(테스트의 합성 바이트열이 쓴다).
    static func parse(_ bytes: [UInt8]) -> AntigravityGenRow? {
        bytes.withUnsafeBytes { AntigravityGenMetadataParser.parse($0) }
    }

    /// 사용량 메시지 하나를 읽는다. 깨졌거나 정상성 검사에 걸리면 nil.
    private static func usage(_ b: UnsafeRawBufferPointer, _ r: Range<Int>) -> AntigravityGenRow? {
        var row = AntigravityGenRow()
        var insane = false
        func take(_ v: UInt64) -> Int {
            guard v <= UInt64(maxPlausibleTokens) else { insane = true; return 0 }
            return Int(v)
        }
        guard AntigravityProto.walk(b, from: r.lowerBound, to: r.upperBound, { field, wire, value, _ in
            guard wire == 0 else { return }
            switch field {
            case inputTokensField: row.input = take(value)
            case outputTokensField: row.output = take(value)
            case cacheReadTokensField: row.cacheRead = take(value)
            case thinkingTokensField: row.thinking = take(value)
            default: break
            }
        }), !insane else { return nil }
        return row
    }

    /// 모델 필드를 문자열로 받아준다 — **인쇄 가능한 ASCII 64바이트 이하만**. 이 게이트가 프라이버시 방벽이다:
    /// 필드 번호가 언젠가 바뀌어 본문 조각이 이 자리에 오더라도 (개행·한글·긴 텍스트라) 전부 걸러진다.
    private static func modelIdentifier(_ b: UnsafeRawBufferPointer, _ r: Range<Int>) -> String? {
        guard !r.isEmpty, r.count <= maxModelIdentifierBytes else { return nil }
        var scalars = [UInt8]()
        scalars.reserveCapacity(r.count)
        for i in r {
            let c = b[i]
            guard c >= 0x20, c <= 0x7E else { return nil }
            scalars.append(c)
        }
        return String(decoding: scalars, as: UTF8.self)
    }
}

// MARK: - sqlite 읽기 (읽기 전용)

/// 대화 db 하나를 **읽기 전용으로** 열어 새 idx 행만 가져온다.
///
/// 읽기 전용이 규약인 이유: 이 파일들은 살아 있는 WAL db 이고 `agy` 가 지금 쓰고 있을 수 있다. 쓰기 가능으로 열면
/// 우리가 체크포인트를 돌리거나 WAL 을 잘라내 실행 중인 CLI 와 경쟁한다(최악은 그 대화가 깨지는 것이다).
/// 잠금 대기도 200ms 로 끊는다 — 스캔은 배경 작업이고, 못 읽은 파일은 다음 스캔에 다시 잡힌다.
///
/// ## ★ 2단 전략 — 사이드카의 사실관계 (2026-09-11 실측, macOS 시스템 libsqlite3 3.51.0)
///
/// 상태가 셋이고 셋이 전부 다르다. **앞 판의 주석은 이 표를 거꾸로 적어 놨다.**
///
/// | db 옆에 있는 것 | 1단(`SQLITE_OPEN_READONLY`) | 우리가 만드는 파일 |
/// |---|---|---|
/// | 아무것도 없음 | **`prepare` 가 CANTOPEN(14)** | **없다** |
/// | `-wal` 있음(0바이트라도) · `-shm` 없음 | **성공** | **`-shm` 을 만든다** |
/// | `-wal` + `-shm` 있음 (= `agy` 가 열어 둔 상태) | **성공** | 없다(있는 걸 붙여 쓴다) |
///
/// 읽기 전용 연결이 `-shm` 을 못 만드는 것은 **`-wal` 이 아예 없을 때뿐**이다. `-wal` 이 있으면 sqlite 는 그 인덱스를
/// 복구해야 하고, **디렉터리에 쓸 수만 있으면 읽기 전용 연결도 `-shm` 을 만든다.** 즉 "읽기 전용이니 사용자 파일을
/// 하나도 안 만든다"는 거짓이다 — 합성 db 로 재현해 못 박아 두었다(`v0312StageOneReadsWalDatabaseAndLeavesOnlyShm`).
///
/// ⚠️ 이 맥의 실제 `conversations/` 에 남아 있는 0바이트 `-wal` 두 개와 그 옆의 `*-shm` 은 **`agy` 의 상태가 아니라
/// 우리가 남긴 잔여다**: 네 파일의 birth 가 전부 2026-09-11 15:52:10~11 이고(그 시각 `agy` 로그가 없다) 그때
/// 우리 프로브가 그 db 둘을 **읽기쓰기로** 열었다. 그 폴더의 나머지 db 두 개(17:38 · 17:54 — `agy` 가 만들고 정상
/// 종료한 것들)에는 사이드카가 하나도 없다. **깨끗한 사용자 맥의 정상은 사이드카 0 이다**(아래 (i)).
///
/// 그게 괜찮은 이유는 셋이다:
///   (1) `-shm` 은 **파생 파일**이다. 내용이 전부 `-wal` 에서 재계산되는 공유 메모리 인덱스이고 사용자 데이터가
///       한 바이트도 들어가지 않는다. 지워도 sqlite 가 다시 만들고, 지워진 사이에 잃는 것이 없다.
///   (2) `.db` 본체는 어느 단계에서도 쓰기 모드로 열지 않는다 — 크기·mtime 이 전후로 같다(테스트가 못 박는다).
///   (3) `agy` 자신이 열 때마다 만드는 파일이다. 우리가 남긴 것이 `agy` 를 방해하지도, 구별되지도 않는다.
///
/// ⚠️ **"마지막 연결이 닫히면 sqlite 가 지운다"에 기대지 마라.** 애플 libsqlite3(3.51.0 실측)는 마지막 연결을 닫아도
/// `-wal`·`-shm` 을 **지우지 않는다**(persistent WAL). 그래서 우리가 만든 `-shm` 은 남는다 — 위 (1)~(3) 이 진짜 근거다.
/// (`agy` 는 자기 sqlite 를 안고 있어 정상 종료하면 둘을 지운다. 그래서 사이드카 없는 db 가 존재한다.)
///
/// ### 그럼 왜 **항상** immutable 로 읽지 않는가 — 최신 턴을 통째로 놓친다
/// `agy` 가 **지금 돌고 있으면** 마지막 턴은 아직 `.db` 로 체크포인트되지 않고 `-wal` 안에만 있다.
/// 실측(살아 있는 쓰기 연결 + 커밋 한 번): 1단은 최신 행까지 봤고 `?immutable=1` 은 그 행을 **못 봤다** —
/// immutable 은 `-wal` 을 아예 읽지 않기 때문이다. 항상 immutable 로 열면 스캔이 늘 한 턴씩 뒤처지고,
/// 그 턴은 다음 쓰기가 올 때까지(= 대화가 끝나면 영원히) 안 잡힌다. **그래서 1단이 먼저다.**
/// 이 근거는 테스트로 묶여 있다(`v0312ReadsUncheckpointedWalContent`): 1단을 immutable 로 바꾸면 그 테스트가 빨개진다.
///
/// ### 2단이 필요한 자리 — 1단이 **정말** 못 여는 두 경우
///   (i) 사이드카가 아예 없다 = `agy` 가 정상 종료했다. 깨끗한 사용자 맥의 **정상**이다(개발 맥에서 안 보인 이유는
///       `agy` 를 띄워 둬서가 아니라 **우리 프로브가 두 db 를 읽기쓰기로 열어** 사이드카를 남겨 놨기 때문이다 — 위 ⚠️).
///       고치기 전에는 그런 사람의 안티그래비티 집계가 통째로 0 이었다.
///  (ii) **디렉터리에 쓸 수 없다.** `-wal` 이 있어도 `-shm` 을 만들 수 없으니 1단은 CANTOPEN 이다(실측: 대화 폴더를
///       0500 으로 두면 그렇게 된다). 2단이 구한다 — 그리고 이 경로에서는 우리가 파일을 만들 **수 없다**는 것이
///       그 자체로 증명된다. 두 경우 모두 `sqlite3_open_v2` 는 성공하고 `sqlite3_prepare_v2` 가 CANTOPEN 으로 죽는다.
///
/// 후보를 셋 다 재 봤다(2026-09-11, 사이드카 없는 WAL db 를 합성해 20회 평균, M-계열):
///
/// | 방법 | 131KB(2행) | 2.4MB(40행) | 4.9MB(400행) | 위험 |
/// |---|---|---|---|---|
/// | 1단만(READONLY) | **CANTOPEN** | **CANTOPEN** | **CANTOPEN** | 집계 전량 0 |
/// | (a) 항상 `?immutable=1` | 0.08ms | 0.28ms | 0.66ms | **체크포인트 안 된 최신 턴을 놓친다** · 쓰는 중이면 찢긴 값 |
/// | (b) 임시폴더 복사 후 읽기 | 0.60ms | 5.01ms | 11.03ms | 복사 자체가 찢길 수 있고 비용이 **파일 크기**에 비례 |
///
/// (b) 는 "안전해 보이지만" 복사도 원자적이지 않아 찢김 위험이 사라지지 않고, 읽는 행 수가 아니라 **파일 크기**에
/// 값을 매긴다(4.9MB 에서 17배). 게다가 사본은 우리 것이라 READWRITE 로 열어야 -shm 을 만들 수 있어 코드가 한 겹 는다.
/// 그래서 **(c) 2단**을 택했다:
///   1단 — `SQLITE_OPEN_READONLY`. `-wal` 이 있으면(0바이트라도) 여기서 끝나고, **WAL 내용까지 본 가장 최신
///          스냅샷**이다. 늘 이쪽이 먼저다.
///   2단 — 1단이 **SQLITE_CANTOPEN 으로만** 실패하면 `file:…?immutable=1` 로 다시 연다.
///
/// 2단의 찢김 위험이 실제로는 거의 없는 이유(그리고 그 '거의'를 어떻게 막았는지):
/// 살아 있는 WAL 연결은 `-shm` 없이 존재할 수 없다. 그래서 1단이 CANTOPEN 이었다는 것은 **그 순간 아무도 이 db 를
/// 열고 있지 않다**는 뜻이다(역은 성립하지 않는다 — 애플 sqlite 가 지우지 않으므로 `-shm` 이 남아 있어도 연 사람은
/// 없을 수 있다. 우리가 쓰는 방향은 앞쪽이다). 그래도 우리가 2단을 도는 사이에 `agy` 가 끼어들 수 있으므로,
/// 읽기 **전후로 크기·mtime 울타리**를 친다(`fence`). 울타리가 깨지면 읽은 값을 통째로 버리고 `.changedDuringRead` 를
/// 돌려준다 — 부분 채택은 없다(찢긴 블롭은 파서가 거를 수도, 못 거를 수도 있다).
///
/// **어느 단계에서도 `.db` 를 쓰기 모드로 열지 않는다.** 1단이 만들 수 있는 것은 파생 파일 `-shm` 하나뿐이고,
/// 2단(immutable)은 잠금도 `-shm` 생성도 아예 끄므로 파일을 하나도 만들지 않는다.
enum AntigravityConversationReader {
    /// 한 번의 스캔에서 파일 하나가 내놓을 수 있는 최대 행 수. 넘치면 다음 스캔이 이어간다(lastIdx 가 단조 증가하므로
    /// 유실이 아니라 지연이다). 행 하나가 80KB 에 이르므로 상한 없이 읽으면 거대한 대화 하나가 스캔을 통째로 물고 늘어진다.
    static let maxRowsPerScan = 1024

    /// 실패를 두 칸으로 가르는 이유: v0.3.12 의 P0 은 사이드카 없는 WAL db 를 **통째로 못 읽고 있다는 사실이
    /// 어느 계측에도 안 남은** 것이었다. 지금은 그 db 를 2단이 읽어 내고(계측은 `immutableReads`), 2단까지 실패하면
    /// `.openFailed` 로 서서 `openFailures` 에 남는다 — 집계만 조용히 0 이 되는 길이 없다.
    enum Outcome: Equatable, Sendable {
        case ok
        /// `sqlite3_open_v2` 가 파일을 못 열었다(삭제·권한·경로가 디렉터리 — 1단과 2단 **양쪽에서** 실패).
        /// 재시도로 풀릴 수 있는 실패다 — 상태를 건드리지 않고 다음 스캔에 다시 시도한다.
        case openFailed
        /// 열긴 열었는데 질의를 못 세웠다: 표가 없다(다른 스키마의 db) · 쓰레기 헤더 · 손상. 재시도로는 풀리지 않는다.
        /// 1단이 사이드카 문제로 여기 떨어져도 `read` 가 `code`(CANTOPEN)를 보고 2단으로 내려가므로 묻히지 않는다.
        case queryFailed
        /// 2단(immutable)으로 읽는 동안 파일의 크기·mtime 이 바뀌었다 = 누가 쓰는 중이었다.
        /// 읽은 값은 찢겼을 수 있어 **통째로 버린다**. 다음 스캔이 (그때는 사이드카가 있을 테니) 1단으로 제대로 읽는다.
        case changedDuringRead
    }

    /// 파일이 읽는 동안 바뀌지 않았음을 확인하는 울타리(크기 + mtime 초/나노초). 2단에서만 쓴다.
    /// `stat` 두 번이라 비용은 사실상 0 이다. mtime 을 바꾸지 않는 sqlite 쓰기는 없다.
    private struct Fence: Equatable {
        var size: Int64
        var seconds: Int
        var nanoseconds: Int
    }

    private static func fence(_ path: String) -> Fence? {
        var st = stat()
        guard path.withCString({ stat($0, &st) }) == 0 else { return nil }
        return Fence(size: Int64(st.st_size), seconds: st.st_mtimespec.tv_sec, nanoseconds: st.st_mtimespec.tv_nsec)
    }

    /// sqlite URI 파일명에서 그대로 둬도 되는 문자 — **ASCII 비예약 문자 + `/`** 뿐이다.
    /// `CharacterSet.alphanumerics` 를 쓰면 안 된다: 그건 한글·한자까지 '영숫자'로 쳐서 통과시킨다(사용자 이름이
    /// 한글인 맥이 드물지 않다). 여기서 막지 않으면 `?` 가 들어간 경로에서 쿼리 파라미터가 잘못 잘리고,
    /// `#` 이 들어간 경로는 뒤가 통째로 날아간다.
    private static let uriAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")

    /// 경로를 `?immutable=1` 붙은 sqlite URI 파일명으로 감싼다.
    static func immutableURI(path: String) -> String {
        "file:" + (path.addingPercentEncoding(withAllowedCharacters: uriAllowed) ?? path) + "?immutable=1"
    }

    struct ReadResult: Sendable {
        var rows: [(idx: Int, row: AntigravityGenRow)] = []
        /// 이번에 **본** 가장 큰 idx(파싱 실패한 행 포함). 진행 상태는 이 값으로 전진한다 —
        /// 못 읽은 행을 매번 다시 읽으면 영영 같은 자리에 묶인다.
        var maxIdx: Int = -1
        /// 파싱이 거부한 행 수(계측용).
        var rejected: Int = 0
        /// 상한에 걸려 잘렸는가. **호출자는 이 파일을 '다 읽었다'고 표시하면 안 된다** —
        /// 크기·mtime 을 갱신해 버리면 무변경 스킵에 걸려 남은 행이 다음 쓰기 전까지 영영 안 읽힌다(토큰 유실).
        var truncated: Bool = false
        var outcome: Outcome = .ok
        /// 2단(`?immutable=1`)으로 구해 낸 읽기인가. 계측용 — 이 값이 파일 수와 같다면 그 기기의 `agy` 는
        /// 늘 정상 종료하고 있다는 뜻이고, 1단만 있던 시절엔 그 기기의 집계가 전부 0 이었다는 뜻이다.
        var usedImmutableFallback: Bool = false
    }

    /// 2단 전략(위 주석 §사이드카 없는 WAL db). 1단이 **SQLITE_CANTOPEN 으로만** 실패했을 때 immutable 로 한 번 더 간다.
    ///
    /// - duringImmutableRead: **테스트 전용 이음매**. 2단이 파일을 읽는 동안 누가 끼어드는 상황을 결정적으로 만들려고
    ///   둔 자리다(그 경쟁은 실물로는 재현할 수 없고, 재현 못 하는 방어벽은 조용히 썩는다). 프로덕션 호출자는
    ///   아무도 넘기지 않는다 — 넘기지 마라. nil 이면 비용도 분기도 없다.
    static func read(
        path: String, afterIdx: Int, limit: Int = maxRowsPerScan,
        duringImmutableRead: (() -> Void)? = nil
    ) -> ReadResult {
        let direct = attempt(path: path, afterIdx: afterIdx, limit: limit, immutable: false)
        // 성공했거나, CANTOPEN 이 아닌 다른 이유(표 없음·잠금·손상)로 실패했으면 2단은 답이 아니다.
        // 특히 `.queryFailed`(= 표가 없는 남의 db)에서 immutable 로 다시 여는 것은 같은 실패를 두 번 하는 낭비다.
        guard direct.code & 0xFF == SQLITE_CANTOPEN else { return direct.result }

        // 울타리를 치고 2단. 울타리를 못 세우면(그 사이 파일이 사라졌다) 열기 실패로 돌린다.
        guard let before = fence(path) else {
            var out = direct.result
            out.outcome = .openFailed
            return out
        }
        var fallback = attempt(path: path, afterIdx: afterIdx, limit: limit, immutable: true)
        // 울타리를 닫기 전에 이음매를 부른다 — 테스트가 여기서 파일을 건드려 '읽는 중 변경'을 만든다.
        duringImmutableRead?()
        fallback.result.usedImmutableFallback = true
        // 읽는 동안 파일이 바뀌었으면 값이 찢겼을 수 있다 → 부분 채택 없이 통째로 버린다.
        if fallback.result.outcome == .ok, fence(path) != before {
            var out = ReadResult()
            out.outcome = .changedDuringRead
            out.usedImmutableFallback = true
            return out
        }
        return fallback.result
    }

    /// 한 번의 열기+질의 시도. `code` 는 sqlite 가 돌려준 원인 코드(성공이면 SQLITE_OK)로, 호출자가
    /// CANTOPEN 만 골라 2단으로 넘기는 데 쓴다.
    private static func attempt(
        path: String, afterIdx: Int, limit: Int, immutable: Bool
    ) -> (result: ReadResult, code: Int32) {
        var out = ReadResult()
        var db: OpaquePointer?
        // immutable 은 URI 로만 켤 수 있어 SQLITE_OPEN_URI 가 함께 필요하다. 쓰기 플래그는 어느 쪽에도 없다.
        let target = immutable ? immutableURI(path: path) : path
        let flags = SQLITE_OPEN_READONLY | (immutable ? SQLITE_OPEN_URI : 0)
        let openRC = target.withCString { sqlite3_open_v2($0, &db, flags, nil) }
        guard openRC == SQLITE_OK, let handle = db else {
            if db != nil { sqlite3_close(db) }
            out.outcome = .openFailed
            return (out, openRC)
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 200)

        var stmt: OpaquePointer?
        let sql = "select idx, data from gen_metadata where idx > ? order by idx limit ?"
        let prepareRC = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard prepareRC == SQLITE_OK, let query = stmt else {
            if stmt != nil { sqlite3_finalize(stmt) }
            // `prepare` 실패는 `.queryFailed` 하나로 둔다. 여기서 CANTOPEN 을 골라 `.openFailed` 로 돌리는
            // 분기가 있었는데, **그 값은 호출자에게 도달하지 않는다** — 그래서 지웠다(2026-09-11 실측):
            //   · 1단에서 CANTOPEN 이면 `read` 가 `code` 를 보고 2단으로 내려가므로 이 `outcome` 은 버려진다.
            //     (그 자리에서 outcome 이 쓰이는 유일한 경로는 울타리를 못 세운 경우인데, 거기서는 `.openFailed`
            //      로 **덮어쓴다**.)
            //   · 2단(immutable)의 `prepare` 는 CANTOPEN 을 내지 않는다. 열기 실패는 전부 `sqlite3_open_v2`
            //     단계에서 14 로 떨어지고(없는 경로 · 권한 000 파일 · 경로가 디렉터리), `prepare` 가 실패하는
            //     경우는 진짜로 "읽을 수 없는 db"뿐이다 — 쓰레기 헤더 26(NOTADB) · 잘린 파일 11(CORRUPT) ·
            //     표가 없다 1(ERROR) · 파일 포맷 버전 위장 26. 열 가지 입력을 다 재 봤고 immutable 이 이 자리에서
            //     14 를 내는 입력은 만들 수 없었다.
            // 즉 분기를 되돌려도 아무 테스트가 못 잡는 게 당연했다(뮤테이션 M2 생존). 검증할 수 없는 코드를
            // 'P0 수리'라는 이름으로 남기지 않는다. **열기 실패 계측은 `openRC` 쪽에서 선다**
            // (`v0312OpenFailuresStandWhenBothStagesFail` 이 그걸 못 박는다).
            out.outcome = .queryFailed
            return (out, prepareRC)
        }
        defer { sqlite3_finalize(query) }
        let cap = max(0, limit)
        sqlite3_bind_int64(query, 1, Int64(afterIdx))
        sqlite3_bind_int64(query, 2, Int64(cap))

        var seen = 0
        while sqlite3_step(query) == SQLITE_ROW {
            seen += 1
            let idx = Int(sqlite3_column_int64(query, 0))
            out.maxIdx = max(out.maxIdx, idx)
            let size = Int(sqlite3_column_bytes(query, 1))
            guard size > 0, let raw = sqlite3_column_blob(query, 1) else { out.rejected += 1; continue }
            // 블롭 포인터는 다음 step 까지만 유효하다 — 파싱은 여기서 끝내고 숫자만 들고 나간다(본문은 복사조차 하지 않는다).
            if let row = AntigravityGenMetadataParser.parse(UnsafeRawBufferPointer(start: raw, count: size)) {
                out.rows.append((idx, row))
            } else {
                out.rejected += 1
            }
        }
        out.truncated = seen >= cap
        return (out, SQLITE_OK)
    }
}

// MARK: - 파일별 증분 상태

/// 대화 파일 하나의 증분 진행 상태 + 월/일 기여분.
///
/// ## 왜 바이트 오프셋이 아니라 idx 인가 (Codex 스캐너와 갈리는 자리)
/// Codex rollout 은 append-only 라 오프셋으로 이어읽는다. 안티그래비티 대화 db 는 **앞 행을 나중에 다시 쓴다**
/// (2026-09-11 실측: idx0 행이 78,206B → 1,067B 로 압축됐다). 그래서 파일 크기가 줄고 바이트 오프셋은 의미가 없다.
/// 규약은 하나뿐이다: **idx 가 lastIdx 보다 큰 행만 더한다.** 압축으로 줄어든 파일을 "축소 = 전체 재파싱"으로
/// 다루면(Codex 규칙) 이미 센 행을 통째로 다시 세서 그 대화의 토큰이 두 배가 된다.
///
/// ## 처음 보는 파일의 잔여 위험
/// lastIdx 가 없으면(신규/퇴거 후 재등장) 그 파일의 **모든 행**을 이번 달에 싣는다. 지난달에 시작한 대화를
/// 이번 달에 `-c` 로 이어 쓰면 지난달 턴들이 재개한 날로 딸려 온다. 두 가지로 막는다:
///   (1) mtime 프리필터 — 이번 달에 손대지 않은 파일은 아예 열지 않는다.
///   (2) 상태 보관을 90일로 길게 잡는다(`AntigravityUsageScanner.stateRetention`). 월 단위로 퇴거하면
///       한 달 쉬었다 재개한 대화마다 전량 재계상이 난다 — 상태 몇백 바이트가 그 오차보다 훨씬 싸다.
/// 안티그래비티는 `agy` 호출마다 새 conversation id 를 만들고 `-c` 일 때만 이어붙이므로 이 경로는 드물다.
struct AntigravityFileProgress: Equatable, Sendable {
    var size: Int
    var mtimeMicros: Int
    /// 마지막으로 처리한 gen_metadata.idx(포함). -1 = 아직 한 행도 안 봤다.
    var lastIdx: Int
    /// 이 상태가 귀속된 KST 'YYYY-MM'. 월이 바뀌면 month*/day/model 기여를 비우고 키만 갈아 끼운다(과거분 자연 탈락).
    var monthKey: String
    var monthInput: Int
    var monthOutput: Int
    var monthThinking: Int
    var monthCacheRead: Int
    /// KST 'YYYY-MM-DD' → 그 날 귀속 total(**네 값 전부** — input+output+thinking+cacheRead). 잔디가 읽는다.
    /// 현재 월 키만 담는다. 월 기여(monthInput…monthCacheRead)와 **같은 정의**여야 한다 — 갈리면 잔디의 하루 합이
    /// 그 달 총합과 어긋난다(v0.3.12 실측 38% 차이).
    var dayContrib: [String: Int]
    /// 모델 식별자 → total 기여. 모델을 못 읽은 행은 어디에도 안 담는다(합계와 어긋나도 괜찮은 보조 지표다).
    var modelContrib: [String: Int]

    init(
        size: Int = 0, mtimeMicros: Int = 0, lastIdx: Int = -1, monthKey: String = "",
        monthInput: Int = 0, monthOutput: Int = 0, monthThinking: Int = 0, monthCacheRead: Int = 0,
        dayContrib: [String: Int] = [:], modelContrib: [String: Int] = [:]
    ) {
        self.size = size
        self.mtimeMicros = mtimeMicros
        self.lastIdx = lastIdx
        self.monthKey = monthKey
        self.monthInput = monthInput
        self.monthOutput = monthOutput
        self.monthThinking = monthThinking
        self.monthCacheRead = monthCacheRead
        self.dayContrib = dayContrib
        self.modelContrib = modelContrib
    }

    /// 이 파일의 현재 월 기여 합 = **네 값 전부**. `dayContrib` 값의 합과 같은 정의다(같은 달 안이면 항등식).
    var monthTotal: Int { monthInput + monthOutput + monthThinking + monthCacheRead }
}

// 압축 배열-튜플 인코딩(10원소). CheckTokenUsage 의 CodexFileProgress 와 같은 결 —
// 이름키 JSON 은 대화 수천 개에서 캐시를 몇 배로 불린다. 잘린 튜플은 기본값으로 떨어진다.
extension AntigravityFileProgress: Codable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        size = try c.decode(Int.self)
        mtimeMicros = try c.decode(Int.self)
        lastIdx = try c.decodeIfPresent(Int.self) ?? -1
        monthKey = try c.decodeIfPresent(String.self) ?? ""
        monthInput = try c.decodeIfPresent(Int.self) ?? 0
        monthOutput = try c.decodeIfPresent(Int.self) ?? 0
        monthThinking = try c.decodeIfPresent(Int.self) ?? 0
        monthCacheRead = try c.decodeIfPresent(Int.self) ?? 0
        dayContrib = try c.decodeIfPresent([String: Int].self) ?? [:]
        modelContrib = try c.decodeIfPresent([String: Int].self) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(size); try c.encode(mtimeMicros); try c.encode(lastIdx)
        try c.encode(monthKey)
        try c.encode(monthInput); try c.encode(monthOutput)
        try c.encode(monthThinking); try c.encode(monthCacheRead)
        try c.encode(dayContrib); try c.encode(modelContrib)
    }
}

// MARK: - 합계

/// 현재 KST 월의 안티그래비티 합계. 표시·업로드는 다음 단계가 한다 — 여기서는 숫자만 낸다.
struct AntigravityUsageTotals: Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var thinking: Int = 0
    /// 합에 **들어간다**(AntigravityGenRow.cacheRead 주석 — agy 의 캐시읽기는 입력과 겹치지 않는다).
    var cacheRead: Int = 0
    /// KST 'YYYY-MM-DD' → 그 날의 total. 잔디용.
    var daily: [String: Int] = [:]
    /// 모델 식별자 → total. 도구 믹스용 보조 지표.
    var models: [String: Int] = [:]

    /// 합계 규약: **네 값 전부**. `TokenUsageMonthly.antigravityTotal` 과 같은 정의이고, 같은 달 안이면
    /// `daily.values.reduce(0,+) == total` 이 항등식이다.
    var total: Int { input + output + thinking + cacheRead }
    var isEmpty: Bool { total == 0 }
}

// MARK: - 증분 스캐너

/// `~/.gemini/antigravity-cli/conversations/*.db` 를 증분으로 훑어 이번 달 합계와 KST 일별 맵을 낸다.
///
/// 월 창 규약은 Codex 와 같다(`TokenUsageIncrementalScanner.monthBounds`): 이번 KST 월 1일 0시 ~ 다음 달 1일 0시,
/// 합계는 `monthKey == 이번 달` 인 파일 상태만 더한다. 같은 함수를 부르는 것이 중요하다 — 월 경계를 따로 구현하면
/// 잔디(일별)와 월 합계가 언젠가 하루 어긋난다.
enum AntigravityUsageScanner {
    /// 홈 아래 대화 디렉터리의 상대 경로.
    static let conversationsSubpath = ".gemini/antigravity-cli/conversations"

    /// 파일 상태 보관 기간. 월이 아니라 90일인 이유는 AntigravityFileProgress 주석 참고 —
    /// lastIdx 를 잃으면 그 대화를 통째로 재계상한다.
    static let stateRetention: TimeInterval = 90 * 24 * 3_600

    struct Stats: Equatable, Sendable {
        var filesStatted = 0
        var filesRead = 0
        var rowsIngested = 0
        var rowsRejected = 0
        /// **열기** 실패(삭제·권한·경로가 디렉터리 — 2단까지 `open_v2` 가 실패, 그리고 읽는 중 파일이 바뀐 경우).
        /// 재시도로 풀릴 수 있다.
        var openFailures = 0
        /// **질의** 실패 = 열긴 열었는데 gen_metadata 가 없다(다른 스키마의 db) · 헤더가 쓰레기 · 손상. 재시도로 안 풀린다.
        /// 둘을 갈라 세는 이유: v0.3.12 의 P0 은 "사이드카 없는 WAL 을 통째로 못 읽는데 계측이 전부 0" 이었다.
        /// 지금은 그 db 가 2단으로 읽히고(`immutableReads`), 2단까지 못 열면 `openFailures` 에 선다.
        var queryFailures = 0
        /// 2단(`?immutable=1`)으로 구해 낸 파일 수. `agy` 가 정상 종료해 사이드카가 없는 db 들이다 —
        /// 이 값이 0 이 아니면 1단만 있던 빌드에서는 그만큼의 대화가 통째로 안 잡히고 있었다는 뜻이다.
        var immutableReads = 0
        var statesChanged = false

        /// 이번 스캔에서 못 읽은 파일 수(열기 + 질의). 진단의 '눈먼 스캔' 판정이 이 값을 본다.
        var readFailures: Int { openFailures + queryFailures }
    }

    struct Result: Sendable {
        var totals: AntigravityUsageTotals
        var stats: Stats
    }

    static func conversationsDirectory(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(conversationsSubpath, isDirectory: true)
    }

    /// 빈 상태로 도는 전체 스캔(호환 진입점). "첫 스캔 == 전체 스캔"을 코드로 묶어 둔다.
    static func scan(homeDirectory: URL, now: Date = Date()) -> AntigravityUsageTotals {
        var states: [String: AntigravityFileProgress] = [:]
        let directory = conversationsDirectory(homeDirectory: homeDirectory)
        return update(states: &states, conversationsDirectory: directory, now: now).totals
    }

    /// 증분 갱신. `states` 는 호출자(다음 단계의 캐시)가 들고 있다 — 이 파일은 저장하지 않는다.
    /// `rowLimit` 은 한 파일이 한 번의 스캔에서 내놓을 최대 행 수다(테스트가 이어읽기를 싸게 재현하려고 낮춘다).
    static func update(
        states: inout [String: AntigravityFileProgress],
        conversationsDirectory directory: URL,
        now: Date = Date(),
        rowLimit: Int = AntigravityConversationReader.maxRowsPerScan
    ) -> Result {
        var stats = Stats()
        let window = TokenUsageIncrementalScanner.monthBounds(now: now)
        let files = recentFiles(in: directory, cutoff: window.start)
        stats.filesStatted = files.count

        for f in files {
            let path = f.url.path
            let known = states[path]
            var state = known ?? AntigravityFileProgress(monthKey: window.month)

            // 월 롤오버: 기여분을 비우고 키만 갈아 끼운다. lastIdx 는 **유지한다** — 지난달에 이미 센 행을
            // 이번 달에 다시 세면 안 되기 때문이다(Codex 의 월 리셋과 같은 자리, 다만 거기선 오프셋이 그 역할이다).
            if state.monthKey != window.month {
                state.monthKey = window.month
                state.monthInput = 0; state.monthOutput = 0
                state.monthThinking = 0; state.monthCacheRead = 0
                state.dayContrib = [:]; state.modelContrib = [:]
                states[path] = state
                stats.statesChanged = true
            }

            // 무변경(크기·mtime 동일) → 파일을 열지 않는다. 압축은 크기를 바꾸므로 여기 걸리지 않는다
            // (걸리더라도 idx 규약이 이중 계상을 막는다 — 이 분기는 성능일 뿐 정확성의 방벽이 아니다).
            if let k = known, k.size == f.size, k.mtimeMicros == f.mtimeMicros { continue }

            let read = AntigravityConversationReader.read(path: path, afterIdx: state.lastIdx, limit: rowLimit)
            if read.outcome != .ok {
                // 못 읽은 파일은 상태를 건드리지 않는다 — 다음 스캔에 크기·mtime 이 여전히 달라 다시 잡힌다.
                switch read.outcome {
                // 읽는 중에 바뀐 파일(.changedDuringRead)은 '열기' 칸에 센다: 원인이 스키마가 아니라 타이밍이고
                // 처방도 열기 실패와 같다(다음 스캔 재시도).
                case .openFailed, .changedDuringRead: stats.openFailures += 1
                case .queryFailed: stats.queryFailures += 1
                case .ok: break
                }
                continue
            }
            stats.filesRead += 1
            if read.usedImmutableFallback { stats.immutableReads += 1 }
            stats.rowsRejected += read.rejected

            // 귀속 시각 = min(파일 mtime, now).
            // **gen_metadata 에는 구조적 시각 필드가 없다**(2026-09-11 실측: 두 픽스처의 모든 중첩 경로를 걸어
            // epoch varint·ISO 문자열 필드를 찾았으나 없었다. facts.md 가 본 "2026-09-11T15:35:36" 은 독립 필드가 아니라
            // 프롬프트 텍스트 **안에** 박힌 문자열이었고, 그건 대화 본문이라 우리가 읽지 않는다). 그래서 새 행은
            // 그 행이 쓰인 시점 = 파일의 현재 mtime 으로 떨어뜨린다. 새 행만 더하는 규약이라 오차는
            // "이번 쓰기에서 늘어난 행들이 전부 이번 쓰기 시각에 몰린다" 수준으로 묶인다(자정을 걸친 한 번의 스캔 간격).
            // min(now) 을 씌우는 이유: 시계 역행·미래 mtime 이 다음 달 키를 만들어 합계에서 사라지는 것을 막는다.
            let attribution = min(f.mtimeDate, now)
            let dayKey = TokenUsageIncrementalScanner.dayBounds(now: attribution).date

            for entry in read.rows {
                let row = entry.row
                state.monthInput += row.input
                state.monthOutput += row.output
                state.monthThinking += row.thinking
                state.monthCacheRead += row.cacheRead
                if row.total > 0 {
                    state.dayContrib[dayKey, default: 0] += row.total
                    if let model = row.model { state.modelContrib[model, default: 0] += row.total }
                }
                stats.rowsIngested += 1
            }

            // 상한에 걸려 잘렸으면 크기를 -1(실제 크기와 절대 같지 않은 센티널)로 둬서 다음 스캔이 반드시 이어읽게 한다.
            // mtime 은 그대로 찍는다 — 퇴거 하한이 그 값을 보기 때문에 0 으로 두면 상태가 바로 쓸려 나간다.
            state.size = read.truncated ? -1 : f.size
            state.mtimeMicros = f.mtimeMicros
            state.lastIdx = max(state.lastIdx, read.maxIdx)
            states[path] = state
            stats.statesChanged = true
        }

        if evict(&states, now: now) { stats.statesChanged = true }
        return Result(totals: totals(states, month: window.month), stats: stats)
    }

    /// `monthKey == 이번 달` 인 상태만 더한다. 월이 바뀐 상태는 다음 순회에서 리셋되고, 그 전까지는 합계에서 빠진다.
    static func totals(_ states: [String: AntigravityFileProgress], month: String) -> AntigravityUsageTotals {
        var out = AntigravityUsageTotals()
        for s in states.values where s.monthKey == month {
            out.input += s.monthInput
            out.output += s.monthOutput
            out.thinking += s.monthThinking
            out.cacheRead += s.monthCacheRead
            for (day, v) in s.dayContrib { out.daily[day, default: 0] += v }
            for (model, v) in s.modelContrib { out.models[model, default: 0] += v }
        }
        return out
    }

    /// mtime 이 보관 하한보다 오래된 상태를 지운다. 반환 = 실제로 지웠는가.
    @discardableResult
    static func evict(_ states: inout [String: AntigravityFileProgress], now: Date) -> Bool {
        let floor = Int((now.addingTimeInterval(-stateRetention).timeIntervalSince1970 * 1_000_000).rounded())
        let before = states.count
        states = states.filter { $0.value.mtimeMicros >= floor }
        return states.count != before
    }

    /// 디렉터리의 `*.db` 중 mtime 이 컷오프(이번 달 시작) 이후인 정규 파일. 하위 디렉터리는 훑지 않는다
    /// (실측상 conversations/ 는 평평하다). `-wal`·`-shm` 은 확장자가 달라 자연히 빠진다.
    private static func recentFiles(
        in directory: URL, cutoff: Date
    ) -> [(url: URL, size: Int, mtimeMicros: Int, mtimeDate: Date)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [(url: URL, size: Int, mtimeMicros: Int, mtimeDate: Date)] = []
        for url in items where url.pathExtension == "db" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate, mtime >= cutoff else { continue }
            let micros = Int((mtime.timeIntervalSince1970 * 1_000_000).rounded())
            out.append((url, values.fileSize ?? 0, micros, mtime))
        }
        return out
    }
}
