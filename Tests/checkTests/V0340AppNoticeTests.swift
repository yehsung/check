import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.40 서버가 내려 주는 공지 (app_current_notice → UpdateCheckStore → WorkTimerStore.appNotice)
//
// 아이폰 앱 출시를 맥 사용자에게 알리려는데, 새 팝업은 "보려면 먼저 업데이트해야 한다"는 모순이 있다. 그래서 서버가 내려 주는
// **닫을 수 있는 공지 카드**를 만들었다 — 이번 소식만이 아니라 앞으로 릴리스 없이 공지를 보내는 통로다. 이 스위트가 재는 것:
//  ① 서비스 — 요청 모양(anon Bearer · POST · 본문 {})과 실서버 응답 픽스처 디코드(링크 null · 키 누락 · 모르는 키 · 공백 걷기),
//     그리고 "없음"의 모든 모양(`{}` · `null` · 빈 본문 · id 없음 · 옛 서버 404 · 장애 5xx/429 · JSON 아님)이 **던지지 않고 nil** 인 것,
//  ② 스토어 — 닫으면 nil, 스토어를 새로 만들어도 닫힘 유지, 같은 id 는 안 돌아오고 **새 id 는 다시 뜬다**, 기기별·계정 무관,
//  ③ 주기 — 공지 조회가 릴리스 조회와 **같은 checkServerNow** 에 얹혀 스로틀·재진입 가드를 나눠 쓰고, 조회 실패는 카드를 안 내린다,
//  ④ 배선 — AppDelegate 가 조회기와 결과 수신을 물리는 두 줄(없으면 공지 경로가 조용히 no-op 이라 컴파일도 테스트도 초록이다),
//  ⑤ 설치 주소 — 지역 코드 없음 · 추적 쿼리 없음 · **저장소에 한 곳**(공지 카드 QR 과 설정 QR 이 둘 다 이걸 쓴다),
//  ⑥ 마이그레이션 계약 — 표 자물쇠·RPC 속성·실행권·사후 단언·프로브가 글자로 남아 있고, 공지 **행을 넣는 SQL 이 없다**.
// 네트워크는 건드리지 않는다 — 서비스는 URLProtocol 스텁, 스토어는 주입 조회기만 쓴다. UserDefaults 는 CheckTestScratch 경유.

@MainActor
@Suite struct V0340AppNoticeTests {

    // MARK: ① 서비스 — 요청 모양 · 디코드 · 없음의 모양들

    @Test func appCurrentNoticePostsTheRPCWithAnonBearerAndAnEmptyObjectBody() async throws {
        let host = "v0340-notice-shape"
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
        // 공용 스텁은 이 RPC 의 응답 모양을 모른다 — 여기선 **나간 요청**만 잰다(디코드는 아래 전용 스텁이 잰다).
        _ = try? await service.appCurrentNotice()

        let requests = URLProtocolStub.requests(forHost: host)
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.path == "/rest/v1/rpc/app_current_notice")
        #expect(request.httpMethod == "POST")
        // 로그인 전에도 공지는 봐야 하므로 로그인 토큰이 아니라 anon 키를 Bearer 로 싣는다(fetchLatestRelease 와 같은 문).
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-test-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon-test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(URLProtocolStub.bodyText(forHost: host) == "{}")
    }

    @Test func appCurrentNoticeDecodesTheServerFixtureIncludingNullAndMissingLinks() async throws {
        // 마이그레이션 프로브 ③ 이 돌려주는 모양 그대로(PostgREST 가 jsonb 를 그대로 싣는다).
        let full = try await anService("v0340-decode-full").appCurrentNotice()
        #expect(full == AppNotice(
            id: "ios-launch-2026-09",
            title: "아이폰 앱이 나왔어요",
            body: "근무 현황·메시지·할 일·미니게임을 폰에서도 볼 수 있어요. iOS 18 이상.",
            linkURL: "https://apps.apple.com/app/id6812768622",
            linkLabel: "앱스토어에서 받기"
        ))
        // 프로브 ② 의 모양 — 링크 둘이 **null 로 온다**(키는 있다). nil 로 읽혀야 QR 을 안 그린다.
        let nullLinks = try await anService("v0340-decode-null-links").appCurrentNotice()
        #expect(nullLinks == AppNotice(id: "plain", title: "제목", body: "본문"))
        #expect(nullLinks?.linkURL == nil)
        #expect(nullLinks?.linkLabel == nil)
        // 키 자체가 빠져도 같다(서버가 필드를 줄여도 죽지 않는다).
        let missingKeys = try await anService("v0340-decode-missing-link-keys").appCurrentNotice()
        #expect(missingKeys == AppNotice(id: "plain", title: "제목", body: "본문"))
        // 뒤에 필드가 늘어도 옛 앱이 디코드에서 죽으면 안 된다(v 도 여기 속한다 — 클라는 읽지 않는다).
        let extra = try await anService("v0340-decode-extra").appCurrentNotice()
        #expect(extra == AppNotice(id: "plain", title: "제목", body: "본문", linkURL: "https://example.com", linkLabel: "열기"))
        // 운영자가 SQL 편집기에 붙여 넣은 본문은 끝에 개행이 따라온다 — 카드에 빈 줄을 그리지 않게 앞뒤를 걷는다. 빈 링크는 nil.
        let padded = try await anService("v0340-decode-padded").appCurrentNotice()
        #expect(padded == AppNotice(id: "padded", title: "제목", body: "본문\n둘째 줄"))
        #expect(padded?.linkURL == nil, "빈 문자열 링크가 nil 로 접히지 않았다 — 빈 QR 이 뜬다")
    }

    @Test func noNoticeOldServersAndOutagesAreAllNilWithoutThrowing() async throws {
        // "없음"의 모든 모양이 같은 답이다 — 어느 쪽이든 화면이 할 일은 "카드를 안 그린다" 하나뿐이다.
        let hosts = [
            "v0340-none-empty-object",     // 서버 계약: 지금 보여 줄 공지가 없다 → {}
            "v0340-none-null",             // 혹시 null 로 실려도
            "v0340-none-empty-body",       // 빈 본문
            "v0340-none-no-id",            // id 없는 객체(반쪽짜리 카드는 그리지 않는다)
            "v0340-none-blank-id",         // 공백뿐인 id
            "v0340-none-blank-body",       // 공백뿐인 본문
            "v0340-status-404",            // 함수가 없는 옛 서버(PGRST202)
            "v0340-status-500",            // 일시 장애
            "v0340-status-429",            // 레이트리밋
            "v0340-garbled",               // JSON 아님
        ]
        for host in hosts {
            let notice = try await anService(host).appCurrentNotice()
            #expect(notice == nil, "\(host) 가 nil 이 아니다: \(String(describing: notice))")
        }
    }

    // MARK: ② 스토어 — 닫기 영속(기기별 · 계정 무관)

    @Test func aNoticeShowsUntilDismissedAndTheDismissalSurvivesRelaunchWhileANewIDShowsAgain() {
        let (defaults, cleanUp) = anIsolatedDefaults()
        defer { cleanUp() }
        let store = anStore(defaults: defaults)
        #expect(store.appNotice == nil)

        store.applyAppNotice(anNotice("ios-launch-2026-09"))
        #expect(store.appNotice == anNotice("ios-launch-2026-09"))

        store.dismissAppNotice()
        #expect(store.appNotice == nil)
        #expect(WorkTimerStore.noticeDismissedKey("ios-launch-2026-09") == "check.notice.dismissed.ios-launch-2026-09")
        #expect(defaults.bool(forKey: "check.notice.dismissed.ios-launch-2026-09"), "닫음 표식이 defaults 에 id 기준으로 남지 않았다")

        // 5분 뒤 같은 공지가 다시 와도 카드는 돌아오지 않는다.
        store.applyAppNotice(anNotice("ios-launch-2026-09"))
        #expect(store.appNotice == nil, "닫은 공지가 다음 조회에 다시 떴다")
        // 문구만 고친 같은 id 도 마찬가지(전원에게 다시 띄우려면 새 id).
        store.applyAppNotice(AppNotice(id: "ios-launch-2026-09", title: "고친 제목", body: "고친 본문"))
        #expect(store.appNotice == nil)

        // 재실행: 같은 defaults 로 새 스토어 — 닫힘이 그대로다.
        let relaunched = anStore(defaults: defaults)
        relaunched.applyAppNotice(anNotice("ios-launch-2026-09"))
        #expect(relaunched.appNotice == nil, "재실행 뒤 닫은 공지가 다시 떴다 — 닫힘이 영속되지 않았다")

        // 새 id 는 다시 뜬다.
        relaunched.applyAppNotice(anNotice("winter-2026-12"))
        #expect(relaunched.appNotice == anNotice("winter-2026-12"))
        // 서버가 공지를 내리면(nil) 카드도 내려간다 — 닫지 않았어도.
        relaunched.applyAppNotice(nil)
        #expect(relaunched.appNotice == nil)
        #expect(!defaults.bool(forKey: WorkTimerStore.noticeDismissedKey("winter-2026-12")), "안 닫은 공지에 닫음 표식이 남았다")
        // 보이는 공지가 없을 때 닫기는 아무 키도 남기지 않는다.
        let keysBefore = Set(defaults.dictionaryRepresentation().keys)
        relaunched.dismissAppNotice()
        #expect(Set(defaults.dictionaryRepresentation().keys) == keysBefore)
    }

    @Test func theDismissalIsPerDeviceNotPerAccount() {
        let (defaults, cleanUp) = anIsolatedDefaults()
        defer { cleanUp() }
        let store = anStore(defaults: defaults)
        store.session = SupabaseSession(accessToken: "a", refreshToken: nil, userID: "user-1")
        store.applyAppNotice(anNotice("ios-launch-2026-09"))
        store.dismissAppNotice()
        #expect(store.appNotice == nil)

        // 계정을 바꿔도(다른 사람이 같은 맥에 로그인) 같은 공지는 안 돌아온다 — 공지는 이 기기에서 본 것이다.
        store.session = SupabaseSession(accessToken: "b", refreshToken: nil, userID: "user-2")
        store.applyAppNotice(anNotice("ios-launch-2026-09"))
        #expect(store.appNotice == nil, "계정이 바뀌자 닫은 공지가 다시 떴다 — 닫음이 계정별로 갈렸다")
        // 로그아웃(anon)해도 같다.
        store.session = nil
        store.applyAppNotice(anNotice("ios-launch-2026-09"))
        #expect(store.appNotice == nil)
        // 키에 사용자 id 가 섞이지 않는다.
        let noticeKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("check.notice.dismissed.") }
        #expect(noticeKeys == ["check.notice.dismissed.ios-launch-2026-09"], "닫음 키 모양이 다르다: \(noticeKeys)")
    }

    // MARK: ③ 주기 — 릴리스 조회와 같은 checkServerNow 에 얹힌다

    @Test func theNoticeRidesTheSameServerCheckAsTheReleaseAndSharesItsThrottle() async {
        let (defaults, cleanUp) = anIsolatedDefaults()
        defer { cleanUp() }
        var now = Date(timeIntervalSince1970: 2_000_000)
        let store = anUpdateStore(defaults: defaults, clock: { now })
        let release = ANReleaseStub(AppLatestRelease(v: 1, version: "0.3.19", build: 71, notes: [], publishedAt: nil))
        let notice = ANNoticeStub(.success(anNotice("ios-launch-2026-09")))
        let received = ANLog()
        store.serverFetcher = { try await release.fetch() }
        store.noticeFetcher = { try await notice.fetch() }
        store.onNoticeFetched = { received.entries.append($0?.id ?? "<nil>") }

        await store.checkServerNow()
        #expect(release.count == 1)
        #expect(notice.count == 1, "공지 조회가 릴리스 조회와 같은 호출에 얹히지 않았다")
        #expect(received.entries == ["ios-launch-2026-09"])

        // 팝오버 경로의 60초 스로틀을 그대로 나눠 쓴다 — 공지만 따로 더 치지 않는다.
        now = now.addingTimeInterval(59)
        await store.checkServerNow(minimumInterval: 60)
        #expect(notice.count == 1, "60초 안에 공지를 다시 쳤다")
        now = now.addingTimeInterval(2)
        await store.checkServerNow(minimumInterval: 60)
        #expect(notice.count == 2)
        #expect(release.count == 2)

        // 서버가 "없음"(nil)을 주면 그것도 결과다 — 받는 쪽이 카드를 내릴 수 있게 nil 로 부른다.
        notice.result = .success(nil)
        await store.checkServerNow()
        #expect(received.entries == ["ios-launch-2026-09", "ios-launch-2026-09", "<nil>"])

        // 조회기가 **던지면** 부르지 않는다 — 장애 한 번이 떠 있던 카드를 내리면 안 된다. 그리고 릴리스 경로는 그대로 돈다.
        notice.result = .failure(ANBoom())
        await store.checkServerNow()
        #expect(notice.count == 4)
        #expect(release.count == 4, "공지 조회 실패가 릴리스 조회를 막았다")
        #expect(received.entries.count == 3, "던진 조회가 결과 콜백을 불렀다")

        // 반대로 릴리스 조회가 던져도 공지는 간다.
        release.shouldThrow = true
        notice.result = .success(anNotice("winter-2026-12"))
        await store.checkServerNow()
        #expect(received.entries.last == "winter-2026-12", "릴리스 조회 실패가 공지 조회를 막았다")
    }

    @Test func aNoticeFetcherAloneRunsAndNoFetchersMeansNoWorkAndConcurrentChecksShareOneRequest() async {
        let (defaults, cleanUp) = anIsolatedDefaults()
        defer { cleanUp() }
        let store = anUpdateStore(defaults: defaults)
        let received = ANLog()
        store.onNoticeFetched = { received.entries.append($0?.id ?? "<nil>") }

        // 조회기가 둘 다 없으면 아무것도 하지 않는다(테스트·프리뷰 기본값).
        await store.checkServerNow()
        #expect(received.entries.isEmpty)

        // 공지 조회기만 있어도 돈다 — 릴리스 조회기에 묶이지 않는다.
        let notice = ANNoticeStub(.success(anNotice("only-notice")), delay: .milliseconds(80))
        store.noticeFetcher = { try await notice.fetch() }
        let first = Task { await store.checkServerNow() }
        let second = Task { await store.checkServerNow() }
        await first.value
        await second.value
        #expect(notice.count == 1, "겹친 조회가 공지를 두 번 쳤다 — 재진입 가드를 나눠 쓰지 않는다")
        #expect(received.entries == ["only-notice"])

        // 스토어는 공지를 defaults 에 남기지 않는다(재실행 5초 뒤 첫 조회가 다시 채운다) — 남는 키는 릴리스 경로 것뿐.
        let noticeKeys = defaults.dictionaryRepresentation().keys.filter { $0.contains("notice") }
        #expect(noticeKeys.isEmpty, "UpdateCheckStore 가 공지를 영속했다: \(noticeKeys)")
    }

    // MARK: ④ 배선 소스 계약

    /// AppDelegate 배선 두 줄을 소스로 못 박는다(주석은 걷어내고 본다). 조회기가 nil 이면 공지 경로가 no-op 이라 이 두 줄을 지워도
    /// 컴파일도 단위 테스트도 **조용히 초록**이다 — 그 순간 모든 앱이 공지를 잃는다. 릴리스 배선(V0320)과 같은 자리·같은 순서다.
    @Test func theAppDelegateWiresTheNoticeFetcherAndHandsTheResultToTheStoreBeforeStartingTheWatch() throws {
        let app = anStrippingComments(try String(contentsOf: anSourceURL("CheckApp.swift"), encoding: .utf8))
        let wiringInOrder = [
            "updateCheck.serverFetcher =",
            "updateCheck.noticeFetcher =",
            "updateCheck.onNoticeFetched =",
            "updateCheck.startServerWatch()",
        ]
        var previousEnd = app.startIndex
        for needle in wiringInOrder {
            #expect(app.components(separatedBy: needle).count - 1 == 1, "\(needle) 가 정확히 한 번이 아니다")
            let found = try #require(app.range(of: needle), "\(needle) 배선이 사라졌다")
            #expect(previousEnd <= found.lowerBound, "\(needle) 가 앞 배선보다 먼저 온다 — 감시가 켜진 뒤에 물리면 첫 조회를 놓친다")
            previousEnd = found.upperBound
        }
        let fetcher = try #require(app.range(of: "updateCheck.noticeFetcher ="))
        #expect(app[fetcher.upperBound...].prefix(80).contains("appCurrentNotice()"), "조회기가 app_current_notice 를 안 부른다")
        let handoff = try #require(app.range(of: "updateCheck.onNoticeFetched ="))
        #expect(app[handoff.upperBound...].prefix(120).contains("store.applyAppNotice("), "조회 결과가 스토어(닫음 판정)로 안 간다")
    }

    // MARK: ⑤ 설치 주소 — 한 곳 · 지역 코드 없음

    @Test func theAppStoreLinkHasNoRegionCodeNoTrackingQueryAndPointsAtTheListedAppID() throws {
        let url = CheckAppLinks.iosAppStore
        #expect(url.scheme == "https")
        #expect(url.host == "apps.apple.com")
        // 지역 코드를 넣지 않는다 — 애플이 보는 사람의 지역으로 보낸다. `/kr/app/…` 로 되돌리면 해외에서 엉뚱한 스토어로 간다.
        #expect(url.path == "/app/id\(CheckAppLinks.iosAppStoreID)", "주소 경로가 다르다: \(url.path)")
        let segments = url.pathComponents.filter { $0 != "/" }
        #expect(segments == ["app", "id\(CheckAppLinks.iosAppStoreID)"], "경로에 지역 코드 같은 조각이 끼었다: \(segments)")
        #expect(segments.allSatisfy { $0.count != 2 }, "두 글자 조각(지역 코드)이 있다: \(segments)")
        // itunes lookup 의 trackViewUrl 에 붙는 ?uo=4 는 제휴 추적 파라미터다 — QR 에 싣지 않는다.
        #expect(url.query == nil, "추적 쿼리가 붙었다: \(url.query ?? "")")
        #expect(url.fragment == nil)
        // 앱 ID 는 2026-09-28 lookup 실측값(아잉체크 · 1.0.2) — 숫자 10자리.
        #expect(CheckAppLinks.iosAppStoreID == "6812768622")
        #expect(CheckAppLinks.iosAppStoreID.allSatisfy(\.isNumber) && CheckAppLinks.iosAppStoreID.count == 10)
        // 최소 iOS 버전 문구 — 스토어 실측 minimumOsVersion 18.0 과 같은 숫자여야 한다.
        #expect(CheckAppLinks.iosMinimumVersionText.hasPrefix("iOS 18"), "최소 버전 문구가 스토어(18.0)와 갈렸다: \(CheckAppLinks.iosMinimumVersionText)")
    }

    /// 주소·앱 ID 는 `CheckAppLinks` **한 곳**에만 있다. 공지 카드 QR 과 설정 QR 이 둘 다 이걸 쓰는데, 화면 코드가 글자로 다시 적으면
    /// 언젠가 한쪽만 고쳐진다. `Sources/` 전체를 훑는다(테스트·마이그레이션 예시는 제외 — 저긴 값을 **대조**하는 자리다).
    @Test func theAppStoreAddressAndIDLiveInCheckAppLinksOnly() throws {
        let sourcesRoot = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        var seenCheckAppLinks = false
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = anStrippingComments(try String(contentsOf: file, encoding: .utf8))
            let mentions = text.contains("apps.apple.com") || text.contains(CheckAppLinks.iosAppStoreID)
            guard mentions else { continue }
            if file.lastPathComponent == "CheckAppLinks.swift" {
                seenCheckAppLinks = true
            } else {
                offenders.append(file.path.replacingOccurrences(of: sourcesRoot.path + "/", with: ""))
            }
        }
        #expect(seenCheckAppLinks, "CheckAppLinks.swift 에 주소가 없다 — 이 검사가 헛돈다")
        #expect(offenders.isEmpty, "앱스토어 주소/ID 가 CheckAppLinks 밖에도 적혀 있다(한쪽만 고쳐진다): \(offenders)")
    }

    // MARK: ⑥ 마이그레이션 계약 (20260928120000_app_notice.sql)

    @Test func theMigrationLocksTheTableAndOpensOnlyTheReadRPC() throws {
        let sql = try anMigrationSQL()
        // 표 — 필요한 칸이 전부 있고, id 가 PK 다(닫음 표식 키).
        #expect(sql.contains("create table if not exists public.app_notice ("))
        for column in ["id          text        primary key", "title       text        not null", "body        text        not null",
                       "link_url    text", "link_label  text", "active      boolean     not null default true",
                       "starts_at   timestamptz", "ends_at     timestamptz", "created_at  timestamptz not null default now()"] {
            #expect(sql.contains(column), "app_notice 칸이 없다: \(column)")
        }
        // id 글자 집합 — 클라 defaults 키에 그대로 들어간다.
        #expect(sql.contains("check (id ~ '^[a-z0-9][a-z0-9._-]{0,63}$')"), "id 글자 집합 CHECK 가 사라졌다")
        // 자물쇠 — 회수가 grant 보다 **앞**이고, RLS on, 정책 0, service_role 만 직접 쓴다. app_release 와 정확히 같은 세 줄.
        let revoke = try #require(sql.range(of: "revoke all on table public.app_notice from public, anon, authenticated;"))
        let rls = try #require(sql.range(of: "alter table public.app_notice enable row level security;"))
        let grant = try #require(sql.range(of: "grant select, insert, update, delete on public.app_notice to service_role;"))
        #expect(revoke.upperBound <= rls.lowerBound && rls.upperBound <= grant.lowerBound, "revoke → RLS → grant 순서가 아니다")
        #expect(!sql.contains("create policy"), "app_notice 에 정책이 생겼다 — 읽기는 definer RPC 로만")
        #expect(!sql.contains("references "), "app_notice 에 외래키가 걸렸다 — PostgREST 임베드 모호성")
        // RPC — definer · stable · search_path · jsonb, 실행권은 anon·authenticated·service_role, PUBLIC 은 회수.
        let rpc = try anFunctionBody(sql, header: "create or replace function public.app_current_notice()")
        #expect(rpc.contains("n.active"))
        #expect(rpc.contains("n.starts_at <= now()") && rpc.contains("n.ends_at   >  now()"), "기간 조건(포함/배타)이 바뀌었다")
        #expect(rpc.contains("order by n.created_at desc, n.id desc") && rpc.contains("limit 1"))
        #expect(rpc.contains("'{}'::jsonb"), "없을 때 {} 를 돌려주지 않는다 — 클라는 id 없는 응답을 '없음'으로 읽는다")
        for key in ["'v',          1", "'id',         n.id", "'title',      n.title", "'body',       n.body",
                    "'link_url',   n.link_url", "'link_label', n.link_label"] {
            #expect(rpc.contains(key), "응답 키가 빠졌다: \(key)")
        }
        let signature = anSquash(sql)
        #expect(signature.contains("returns jsonb language sql stable security definer set search_path = public"),
                "app_current_notice 의 속성(stable · definer · search_path)이 다르다")
        #expect(sql.contains("revoke execute on function public.app_current_notice() from public;"))
        #expect(sql.contains("grant execute on function public.app_current_notice() to anon, authenticated, service_role;"))
        // 발행 RPC 는 없다(운영자 SQL 로 넣는다) — 클라가 부를 수 있는 쓰기 문이 생기면 안 된다.
        #expect(!sql.contains("create or replace function public.app_publish_notice"), "발행 RPC 가 생겼다 — 실행권 검토 없이 열리면 아무나 공지를 띄운다")
        #expect(sql.contains("notify pgrst, 'reload schema';"))
    }

    @Test func theMigrationAssertsItselfLikeAppReleaseAndInsertsNoNoticeRows() throws {
        let raw = try anMigrationRaw()
        let sql = anStrip(raw)
        // 사후 단언 — app_release 와 같은 밀도: RLS · 정책 0 · anon/authenticated 표 권한 0 · service_role · CHECK 개수 · FK 0 ·
        // 함수 속성 · 실행권 · 소스 계약.
        for needle in [
            "relrowsecurity from pg_class where oid = 'public.app_notice'::regclass",
            "from pg_policies where schemaname = 'public' and tablename = 'app_notice'",
            "has_table_privilege('anon', 'public.app_notice'",
            "has_any_column_privilege('anon', 'public.app_notice'",
            "has_table_privilege('authenticated', 'public.app_notice'",
            "has_any_column_privilege('authenticated', 'public.app_notice'",
            "has_table_privilege('service_role', 'public.app_notice', 'DELETE')",
            "conrelid = 'public.app_notice'::regclass and contype = 'c'",
            "if v_n <> 7 then",
            "contype = 'f'",
            "p.prosecdef and p.provolatile = 's' and p.prorettype = 'jsonb'::regtype",
            "c = 'search_path=public'",
            "has_function_privilege('anon', 'public.app_current_notice()', 'EXECUTE')",
            "has_function_privilege('authenticated', 'public.app_current_notice()', 'EXECUTE')",
            "has_function_privilege('service_role', 'public.app_current_notice()', 'EXECUTE')",
            "if has_function_privilege('public', 'public.app_current_notice()', 'EXECUTE') then",
        ] {
            #expect(sql.contains(needle), "사후 단언이 빠졌다: \(needle)")
        }
        // 소스 계약 (5) 의 주석 걷기 패턴은 문자열 리터럴 안에 `--` 가 있어 anStrip 이 그 줄을 자른다 — **원문**에서 본다.
        #expect(raw.contains("regexp_replace(prosrc, '--[^\\n]*', '', 'g')"), "사후 단언 (5) 가 함수 본문의 주석을 걷지 않는다")
        // 프로브 — 실행 역할 캡처 · set local role(RESET ROLE 금지) · 센티널 롤백 · 롤백 확인 · 건수 단언.
        for needle in [
            "v_exec_role text := current_user",
            "execute 'set local role anon'",
            "execute 'set local role authenticated'",
            "raise exception 'APP_NOTICE_PROBE_ROLLBACK'",
            "if sqlerrm <> 'APP_NOTICE_PROBE_ROLLBACK' then raise; end if;",
            "if current_user <> v_exec_role then",
            "if v_after is distinct from v_before then",
            "if probes <> v_expected then",
            "exception when insufficient_privilege then",
            "exception when check_violation then",
        ] {
            #expect(sql.contains(needle), "프로브 장치가 빠졌다: \(needle)")
        }
        #expect(!sql.lowercased().contains("reset role"), "RESET ROLE 이 있다 — CLI 링크드 연결에서 세션 사용자로 떨어져 42501")
        // 프로브 안 주석에 달러 태그 글자가 없어야 한다(있으면 본문이 거기서 끝난다). 태그는 여는 자리와 닫는 자리 두 번뿐이다.
        #expect(raw.components(separatedBy: "$probe$").count - 1 == 2, "$probe$ 태그가 두 번이 아니다 — 블록 안 주석에 태그 글자가 들어갔다")
        #expect(raw.components(separatedBy: "$assert$").count - 1 == 2)
        // ★ 공지 **행을 넣는 SQL 이 없다.** 주석을 걷은 텍스트에서 insert 는 전부 프로브 블록(롤백) 안에만 있어야 한다.
        let probeStart = try #require(sql.range(of: "do $probe$")).upperBound
        let probeEnd = try #require(sql.range(of: "$probe$;", range: probeStart..<sql.endIndex)).lowerBound
        var searchFrom = sql.startIndex
        var insertsOutsideProbe = 0
        while let hit = sql.range(of: "insert into public.app_notice", range: searchFrom..<sql.endIndex) {
            if !(probeStart <= hit.lowerBound && hit.upperBound <= probeEnd) { insertsOutsideProbe += 1 }
            searchFrom = hit.upperBound
        }
        #expect(insertsOutsideProbe == 0, "프로브 밖에서 app_notice 에 행을 넣는다 — 문구는 사용자와 정한 뒤 운영자가 넣는다")
        // 대신 발행 예시는 **주석으로** 남아 있어야 한다(운영자가 베낀다).
        #expect(raw.contains("--   insert into public.app_notice (id, title, body, link_url, link_label, starts_at, ends_at)"),
                "발행 예시 주석이 사라졌다")
        #expect(raw.contains("apps.apple.com/app/id\(CheckAppLinks.iosAppStoreID)"), "발행 예시의 앱스토어 주소가 CheckAppLinks 와 다르다")
    }

    @Test func theMigrationIsNewerThanEveryAppliedOneInTheChain() throws {
        let names = try FileManager.default
            .contentsOfDirectory(at: try anMigrationsDirectory(), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .map(\.lastPathComponent)
            .sorted()
        #expect(names.contains(anMigrationName))
        // 선례(app_release)보다 뒤에 온다 — 같은 규약을 베낀 파일이 그 앞에 놓이면 이 파일을 읽는 사람이 근거를 못 찾는다.
        let precedent = try #require(names.firstIndex(of: "20260914160000_app_release.sql"))
        let mine = try #require(names.firstIndex(of: anMigrationName))
        #expect(precedent < mine)
    }
}

// MARK: - 헬퍼

private let anMigrationName = "20260928120000_app_notice.sql"

private struct ANBoom: Error {}

private struct ANContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private func anNotice(_ id: String) -> AppNotice {
    AppNotice(id: id, title: "제목 \(id)", body: "본문 \(id)", linkURL: "https://example.com/\(id)", linkLabel: "열기")
}

/// 소스 파일 URL(이 테스트 파일에서 저장소 루트로 올라간다).
private func anSourceURL(_ name: String) -> URL {
    CheckCoreSourceLayout.repoRoot.appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸 코드(V0320ServerReleaseTests 의 srStrippingComments 와 같은 규칙 —
/// 이 저장소의 소스 계약 도구는 파일마다 private 사본을 둔다). 걷어내지 않으면 설명문의 낱말이 단언에 걸린다.
private func anStrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]
                rest = rest[block.upperBound...]
                inBlock = true
                continue
            }
            if let comment = lineComment {
                kept += rest[..<comment.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}

/// 격리 defaults(테스트·자리마다 다른 스위트). CheckTestScratch 경유 — 직접 `UserDefaults(suiteName:)` 을 만들면
/// ~/Library/Preferences 를 오염시켜 누수 게이트를 빨갛게 만든다(2026-09-22 사고).
private func anIsolatedDefaults(_ label: String = "",
                                function: String = #function,
                                line: Int = #line) -> (defaults: UserDefaults, cleanUp: () -> Void) {
    let tag = label.isEmpty ? "L\(line)" : "\(label)-L\(line)"
    let suite = CheckTestScratch.suitePath(tag, function: function)
    let defaults = CheckTestScratch.defaults(tag, function: function)
    return (defaults, { defaults.removePersistentDomain(forName: suite) })
}

/// 공지 테스트용 근무 스토어. 서비스는 스텁 세션(요청이 나가도 네트워크에 닿지 않는다).
@MainActor
private func anStore(defaults: UserDefaults) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://v0340-store")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    return WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
}

/// 서버 경로 테스트용 업데이트 스토어(V0320 의 srStore 와 같은 모양). 워크스페이스 노티는 끊는다(실제 센터 미접촉).
@MainActor
private func anUpdateStore(
    defaults: UserDefaults,
    clock: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000_000) }
) -> UpdateCheckStore {
    UpdateCheckStore(
        currentVersion: "0.3.39",
        fetcher: { _ in Data(#"{"tag_name":"v0.3.39"}"#.utf8) },
        clock: clock,
        defaults: defaults,
        currentBuild: 90,
        serverWatchInterval: 3_600,
        serverWatchInitialDelay: 3_600,
        wakeSettleDelay: 10,
        workspaceNotifications: nil
    )
}

/// 콜백 값을 모으는 상자(메인 액터 전용).
@MainActor
private final class ANLog {
    var entries: [String] = []
}

/// 릴리스 조회기 스텁 — 호출 횟수를 세고 정해 둔 응답을 돌려준다(던지게 바꿀 수 있다).
@MainActor
private final class ANReleaseStub {
    private(set) var count = 0
    var shouldThrow = false
    private let release: AppLatestRelease

    init(_ release: AppLatestRelease) { self.release = release }

    func fetch() async throws -> AppLatestRelease {
        count += 1
        if shouldThrow { throw ANBoom() }
        return release
    }
}

/// 공지 조회기 스텁 — 호출 횟수를 세고 정해 둔 결과(공지 · nil · 예외)를 돌려준다(지연 선택).
@MainActor
private final class ANNoticeStub {
    private(set) var count = 0
    var result: Result<AppNotice?, any Error>
    private let delay: Duration?

    init(_ result: Result<AppNotice?, any Error>, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func fetch() async throws -> AppNotice? {
        count += 1
        if let delay { try? await Task.sleep(for: delay) }
        return try result.get()
    }
}

private func anService(_ host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: ANNoticeURLProtocol.session()
    )
}

/// app_current_notice 응답 전용 스텁. 공용 URLProtocolStub 은 이 경로를 모르므로(단일 객체 jsonb) 호스트로만 갈라
/// 정해 둔 본문을 돌려준다 — 프로세스 전역 가변 상태 없이(병렬 스위트가 서로의 설정을 지우지 않게).
private final class ANNoticeURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.response(host: request.url?.host ?? "")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ANNoticeURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// 본문은 마이그레이션 프로브가 돌려주는 jsonb 모양 그대로다(키 순서까지 jsonb 정렬 그대로).
    private static func response(host: String) -> (Int, String) {
        switch host {
        case "v0340-decode-full":
            return (200, #"{"v":1,"id":"ios-launch-2026-09","body":"근무 현황·메시지·할 일·미니게임을 폰에서도 볼 수 있어요. iOS 18 이상.","title":"아이폰 앱이 나왔어요","link_url":"https://apps.apple.com/app/id6812768622","link_label":"앱스토어에서 받기"}"#)
        case "v0340-decode-null-links":
            return (200, #"{"v":1,"id":"plain","body":"본문","title":"제목","link_url":null,"link_label":null}"#)
        case "v0340-decode-missing-link-keys":
            return (200, #"{"v":1,"id":"plain","body":"본문","title":"제목"}"#)
        case "v0340-decode-extra":
            return (200, #"{"v":1,"id":"plain","body":"본문","title":"제목","link_url":"https://example.com","link_label":"열기","starts_at":"2026-09-28T00:00:00Z","priority":3}"#)
        case "v0340-decode-padded":
            return (200, #"{"v":1,"id":" padded ","body":"본문\n둘째 줄\n","title":"  제목  ","link_url":"","link_label":"  "}"#)
        case "v0340-none-empty-object":
            return (200, "{}")
        case "v0340-none-null":
            return (200, "null")
        case "v0340-none-empty-body":
            return (200, "")
        case "v0340-none-no-id":
            return (200, #"{"v":1,"title":"제목","body":"본문"}"#)
        case "v0340-none-blank-id":
            return (200, #"{"v":1,"id":"   ","title":"제목","body":"본문"}"#)
        case "v0340-none-blank-body":
            return (200, #"{"v":1,"id":"x","title":"제목","body":"\n"}"#)
        case "v0340-status-404":
            return (404, #"{"code":"PGRST202","message":"Could not find the function public.app_current_notice without parameters in the schema cache"}"#)
        case "v0340-status-429":
            return (429, #"{"message":"Request rate limit reached"}"#)
        case "v0340-garbled":
            return (200, "<html>maintenance</html>")
        default:
            return (500, "")
        }
    }
}

// MARK: 마이그레이션 읽기

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라가며 **이 파일이 있는** `supabase/migrations` 를 잡는다
/// (V0333 과 같은 방식인데, 첫 디렉토리가 아니라 파일이 있는 디렉토리를 고른다 — 워크트리에 초안만 있는 반쪽 폴더가 저장소 루트의
/// 전체 체인을 가리지 않게). `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다.
private func anMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ANContractError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var visited: [String] = []
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(anMigrationName).path) {
            return candidate
        }
        visited.append(directory.path)
        directory = directory.deletingLastPathComponent()
    }
    throw ANContractError(
        "\(anMigrationName) 이 있는 supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", ")). "
            + "워크트리라면 초안을 supabase/migrations/ 에 두거나 CHECK_MIGRATIONS_DIR 로 알려 줘라."
    )
}

private func anMigrationRaw() throws -> String {
    try String(contentsOf: try anMigrationsDirectory().appendingPathComponent(anMigrationName), encoding: .utf8)
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
/// ⚠️ 사후 단언 (5) 의 `'--[^\n]*'` 패턴은 문자열 리터럴 안의 `--` 라 이 헬퍼가 그 줄을 자른다 — 그 패턴은 raw 원문에서 확인하지
/// 않고, 걷어낸 텍스트에서 `regexp_replace(prosrc, '` 까지만 본다.
private func anStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func anMigrationSQL() throws -> String { anStrip(try anMigrationRaw()) }

private func anSquash(_ text: String) -> String {
    text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
}

/// `create or replace function public.<헤더>` 부터 그 함수의 달러 인용 본문 끝까지(`as $태그$` 를 읽어 그 태그로 닫는다).
private func anFunctionBody(_ sql: String, header: String) throws -> String {
    guard let start = sql.range(of: header)?.lowerBound else { throw ANContractError("함수 헤더가 없다: \(header)") }
    let rest = sql[start...]
    guard let asRange = rest.range(of: "as $") else { throw ANContractError("\(header): 달러 인용 시작을 못 찾았다") }
    let tagStart = rest.index(asRange.upperBound, offsetBy: -1)
    guard let tagEnd = rest[rest.index(after: tagStart)...].firstIndex(of: "$") else {
        throw ANContractError("\(header): 달러 인용 태그가 안 닫힌다")
    }
    let tag = String(rest[tagStart...tagEnd])
    let bodyStart = rest.index(after: tagEnd)
    guard let close = rest.range(of: tag, range: bodyStart..<rest.endIndex) else {
        throw ANContractError("\(header): 달러 인용 종료 태그 \(tag) 가 없다")
    }
    return String(rest[bodyStart..<close.lowerBound])
}
