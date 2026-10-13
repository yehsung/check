import AppKit
import Foundation
import ServiceManagement
import SQLite3
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.51 맥 앱스토어 판(CHECK_MAS) · 두 판 공통 계정 삭제·약관 링크
//
// 기본 `swift test` 는 `-DCHECK_MAS` 없이 돈다 — 앱스토어 판의 **컴파일 갈래**는 여기서 한 줄도 컴파일되지 않는다. 그래서 이 스위트는
// 두 겹으로 지킨다:
//  ① **판정표**(`MacEdition`)를 `.appStore` 로 주입해 런타임 갈래를 기본 빌드에서 그대로 돌린다 — 업데이트 안내 끔 · 공지 링크 거름 ·
//     AI 기록 동의 게이트(스캔·업로드·리밋) · 로그인 시 자동 실행 기본 꺼짐 · 첫 실행 안내 · 다른 판 경고 · 키체인 service.
//  ② **소스 계약**: 앱스토어 판에서 바이너리에서 사라져야 하는 경로(자가 업데이트 · 외부 프로세스 · 컨테이너 홈)가 실제로
//     `#if !CHECK_MAS` 울타리 **안에** 있는지 `#if` 를 해석해 되묻는다(주석은 걷어내고 본다). 불변식 셋은 앞으로 생길 코드까지 잡는다:
//     `Process()` 는 전부 울타리 안, `homeDirectoryForCurrentUser` 는 진짜 홈 해석기와 테스트 전용 게이트 말고는 전부 울타리 안,
//     `expandingTildeInPath` 도 울타리 안.
// `swift build -Xswiftc -DCHECK_MAS` 가 컴파일되는지와 바이너리 금지어(strings·nm)는 이 스위트 밖에서 잰다(패키징 게이트).

@Suite("V0351 맥 앱스토어 판")
@MainActor
struct V0351MacAppStoreEditionTests {

    // MARK: ① 판정표

    @Test func 기본_빌드는_Developer_ID_판이다() {
        #expect(MacEdition.current == .developerID, "기본 빌드가 앱스토어 판으로 돈다 — CHECK_MAS 가 새어 들어왔다")
    }

    @Test func Developer_ID_판은_지금_동작을_한_톨도_바꾸지_않는다() {
        let e = MacEdition.developerID
        #expect(e.updatesItself)
        #expect(e.probesCodexAccount)
        #expect(e.readsClaudeLimits)
        #expect(e.readsAntigravityLimits)
        #expect(e.readsCodexLimits)
        #expect(!e.asksBeforeLaunchAtLogin)
        #expect(!e.asksBeforeReadingAITools)
        #expect(!e.showsFirstRunConsent)
        #expect(e.keychainService == "kingcheck", "brew 판의 키체인 service 가 바뀌면 전원이 로그아웃된다")
        #expect(e.otherEditionBundleIdentifiers.isEmpty)
        #expect(e.bundleIdentifier == "kingcheck")
        #expect(e.allowsNoticeLink("https://github.com/yehsung/check/releases/latest/download/aing-check.dmg"))
    }

    @Test func 앱스토어_판은_업데이트_외부프로세스를_끄고_동의를_묻는다() {
        let e = MacEdition.appStore
        #expect(!e.updatesItself)
        #expect(!e.probesCodexAccount)
        // 2026-10-14 결정: Claude 리밋도 남긴다(시스템 `security`, 동의 뒤에만) — 바꾸면 이 줄과 MacEdition 주석을 같이 고쳐라.
        #expect(e.readsClaudeLimits)
        #expect(!e.readsAntigravityLimits)
        // 2026-10-14 결정: Codex 리밋은 남긴다(동의 뒤에만 돈다) — 바꾸면 이 줄과 MacEdition 주석을 같이 고쳐라.
        #expect(e.readsCodexLimits)
        #expect(e.asksBeforeLaunchAtLogin)
        #expect(e.asksBeforeReadingAITools)
        #expect(e.showsFirstRunConsent)
        #expect(e.keychainService == "kingcheck.mas")
        #expect(e.keychainService != MacEdition.developerID.keychainService,
                "두 판이 같은 키체인 항목을 찾으면 남의 ACL 에서 SecItem 이 멈추거나 brew 판이 로그아웃된다")
        #expect(e.otherEditionBundleIdentifiers == ["kingcheck"])
        #expect(e.bundleIdentifier == "com.yehsung.aingcheck")
    }

    // MARK: 공지 링크

    @Test func 앱스토어_판은_앱스토어_주소만_공지_링크로_받는다() {
        let e = MacEdition.appStore
        #expect(e.allowsNoticeLink(CheckAppLinks.iosAppStore.absoluteString))
        #expect(e.allowsNoticeLink("https://apps.apple.com/kr/app/id6812768622?mt=12"))
        #expect(e.allowsNoticeLink("  https://APPS.apple.com/app/id1  "))
        for rejected in [
            "https://github.com/yehsung/check/releases/latest/download/aing-check.dmg",
            "https://brew.sh",
            "http://apps.apple.com/app/id6812768622",
            "https://apps.apple.com.evil.example/app",
            "https://evil.example/apps.apple.com",
            "https://user@apps.apple.com/app/id1",
            "macappstore://apps.apple.com/app/id1",
            "javascript:alert(1)",
            "",
        ] {
            #expect(!e.allowsNoticeLink(rejected), "앱스토어 판이 \(rejected) 를 공지 링크로 받았다")
        }
    }

    @Test func 걸러진_공지는_링크와_버튼문구만_잃는다() {
        let dmg = AppNotice(id: "dmg-1", title: "새 버전", body: "DMG 로 받아요",
                            linkURL: "https://github.com/yehsung/check/releases/latest/download/aing-check.dmg",
                            linkLabel: "직접 받기")
        let filtered = dmg.filtered(for: .appStore)
        #expect(filtered == AppNotice(id: "dmg-1", title: "새 버전", body: "DMG 로 받아요"))
        #expect(AppNoticeCard.qrImage(for: filtered) == nil, "QR 이 남았다")
        #expect(AppNoticeCard.caption(for: filtered) == nil, "바깥 링크의 버튼 문구가 남았다")
        // 대조군: 같은 공지가 brew 판에서는 그대로다.
        #expect(dmg.filtered(for: .developerID) == dmg)
        // 앱스토어 주소 공지는 앱스토어 판에서도 그대로다(QR · 캡션).
        let ios = AppNotice(id: "ios", title: "아이폰 앱", body: "나왔어요", linkURL: CheckAppLinks.iosAppStore.absoluteString)
        #expect(ios.filtered(for: .appStore) == ios)
        #expect(AppNoticeCard.qrImage(for: ios.filtered(for: .appStore)) != nil)
    }

    @Test func 스토어는_앱스토어_판에서_공지를_걸러_받는다() {
        let store = v0351Store()
        let dmg = AppNotice(id: "dmg-2", title: "t", body: "b", linkURL: "https://brew.sh/x", linkLabel: "brew")
        store.applyAppNotice(dmg)
        #expect(store.appNotice == dmg, "brew 판에서는 공지를 그대로 받아야 한다")
        store.macEdition = .appStore
        store.applyAppNotice(dmg)
        #expect(store.appNotice?.linkURL == nil)
        #expect(store.appNotice?.linkLabel == nil)
        #expect(store.appNotice?.body == "b")
        // 닫음 표식은 판과 무관하게 같은 id 를 가리킨다.
        store.dismissAppNotice()
        store.applyAppNotice(dmg)
        #expect(store.appNotice == nil)
    }

    // MARK: 업데이트 안내

    @Test func 앱스토어_판은_서버_릴리스를_받아도_업데이트를_알리지_않는다() {
        let devDefaults = CheckTestScratch.defaults("dev")
        let masDefaults = CheckTestScratch.defaults("mas")
        let release = AppLatestRelease(v: 1, version: "0.3.99", build: 999, notes: ["무언가"], publishedAt: nil)
        let dev = UpdateCheckStore(currentVersion: "0.3.51", defaults: devDefaults, currentBuild: 104,
                                   workspaceNotifications: nil, edition: .developerID)
        dev.applyServerRelease(release)
        #expect(dev.isUpdateAvailable, "대조군: brew 판은 더 큰 빌드를 업데이트로 본다")
        #expect(dev.shouldShowBubble())

        let mas = UpdateCheckStore(currentVersion: "0.3.51", defaults: masDefaults, currentBuild: 104,
                                   workspaceNotifications: nil, edition: .appStore)
        mas.applyServerRelease(release)
        #expect(!mas.isUpdateAvailable)
        #expect(mas.latestVersion == nil, "앱스토어 판이 서버 릴리스를 기록했다")
        #expect(!mas.shouldShowBubble())
        // 이전 실행이 남긴 기록(같은 키)이 있어도 앱스토어 판은 알리지 않는다 — 메뉴바 점·말풍선·배너가 이 값 하나를 본다.
        masDefaults.set("v0.3.99", forKey: UpdateCheckStore.latestVersionKey)
        masDefaults.set(999, forKey: UpdateCheckStore.latestBuildKey)
        let restored = UpdateCheckStore(currentVersion: "0.3.51", defaults: masDefaults, currentBuild: 104,
                                        workspaceNotifications: nil, edition: .appStore)
        #expect(!restored.isUpdateAvailable)
    }

    @Test func 앱스토어_판은_GitHub_을_치지_않고_공지만_묻는다() async {
        let calls = V0351Counter()
        let defaults = CheckTestScratch.defaults()
        let mas = UpdateCheckStore(
            currentVersion: "0.3.51",
            fetcher: { _ in calls.bump("github"); return Data("{\"tag_name\":\"v9.9.9\"}".utf8) },
            defaults: defaults, currentBuild: 104, workspaceNotifications: nil, edition: .appStore
        )
        mas.noticeFetcher = { calls.bump("notice"); return nil }
        await mas.checkIfStale()
        #expect(calls.count("github") == 0, "앱스토어 판이 GitHub 릴리스를 폴링했다")
        #expect(calls.count("notice") == 1, "공지 조회는 앱스토어 판에서도 돌아야 한다")
        #expect(!mas.isUpdateAvailable)

        // 대조군: brew 판은 같은 호출에서 GitHub 을 친다(기준선이 같은 입력이면 영원히 초록).
        let dev = UpdateCheckStore(
            currentVersion: "0.3.51",
            fetcher: { _ in calls.bump("github-dev"); return Data("{\"tag_name\":\"v9.9.9\"}".utf8) },
            defaults: CheckTestScratch.defaults("dev"), currentBuild: 104, workspaceNotifications: nil, edition: .developerID
        )
        await dev.checkIfStale()
        #expect(calls.count("github-dev") == 1)
    }

    // MARK: 진짜 홈

    @Test func 진짜_홈은_암호DB_컨테이너_프로세스홈_순으로_정한다() {
        let container = URL(fileURLWithPath: "/Users/aing/Library/Containers/com.yehsung.aingcheck/Data", isDirectory: true)
        #expect(AIToolHome.resolve(passwdHome: "/Users/aing", processHome: container).path == "/Users/aing")
        #expect(AIToolHome.resolve(passwdHome: nil, processHome: container).path == "/Users/aing",
                "암호 DB 를 못 읽으면 컨테이너 경로에서 잘라 내야 한다")
        #expect(AIToolHome.resolve(passwdHome: "", processHome: container).path == "/Users/aing")
        #expect(AIToolHome.resolve(passwdHome: "relative/home", processHome: container).path == "/Users/aing")
        #expect(AIToolHome.resolve(passwdHome: "/", processHome: container).path == "/Users/aing")
        let plain = URL(fileURLWithPath: "/Users/aing", isDirectory: true)
        #expect(AIToolHome.resolve(passwdHome: nil, processHome: plain) == plain)
    }

    @Test func 샌드박스_밖에서는_진짜_홈이_프로세스_홈과_같다() throws {
        // 테스트 프로세스는 샌드박스가 아니다 — 암호 DB 의 홈과 Foundation 의 홈이 같아야 한다(다르면 해석기가 틀렸다).
        let passwd = try #require(AIToolHome.passwdHomeDirectory(), "getpwuid_r 이 홈을 못 읽었다")
        let process = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        #expect(URL(fileURLWithPath: passwd).standardizedFileURL.path == process)
        #expect(AIToolHome.realHome().standardizedFileURL.path == process)
        // Developer ID 판은 예전 값 그대로(같은 API), 앱스토어 판은 진짜 홈 해석기다.
        #expect(AIToolHome.current(edition: .developerID) == FileManager.default.homeDirectoryForCurrentUser)
        #expect(AIToolHome.current(edition: .appStore).standardizedFileURL.path == process)
    }

    // MARK: AI 도구 기록 읽기 동의

    @Test func 동의_판정은_앱스토어_판만_키를_본다() {
        let defaults = CheckTestScratch.defaults()
        #expect(AIToolDataConsent.isAllowed(edition: .developerID, defaults: defaults))
        #expect(!AIToolDataConsent.isAllowed(edition: .appStore, defaults: defaults), "앱스토어 판의 기본은 거절이어야 한다")
        defaults.set(true, forKey: AIToolDataConsent.key)
        #expect(AIToolDataConsent.isAllowed(edition: .appStore, defaults: defaults))
        defaults.set(false, forKey: AIToolDataConsent.key)
        #expect(AIToolDataConsent.isAllowed(edition: .developerID, defaults: defaults), "brew 판이 동의 키를 읽었다")
    }

    @Test func 앱스토어_판의_토큰_스캔은_동의_전에_파일을_하나도_안_읽는다() async throws {
        let home = try v0351TempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try v0351WriteClaudeLog(into: home, input: 1_234)
        let defaults = CheckTestScratch.defaults()
        let cache = home.appendingPathComponent("cache/token-usage-cache.json")
        let store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: cache,
                                    notificationCenter: NotificationCenter(), codexHomeResolver: { nil },
                                    edition: .appStore)
        #expect(!store.isScanPermitted)
        await store.refreshNow()
        #expect(store.scanCount == 0, "동의 전에 스캔이 시작됐다")
        #expect(store.currentMonthUsage == nil)
        #expect(store.lastScanAt == nil)

        defaults.set(true, forKey: AIToolDataConsent.key)
        #expect(store.isScanPermitted)
        await store.refreshNow()
        #expect(store.scanCount == 1)
        #expect(store.currentMonthUsage?.claudeInput == 1_234, "동의한 뒤에는 같은 홈을 읽어야 한다")

        // 대조군: brew 판 스토어는 키 없이도 읽는다.
        let devDefaults = CheckTestScratch.defaults("dev")
        let dev = TokenUsageStore(defaults: devDefaults, homeDirectory: home,
                                  cacheURL: home.appendingPathComponent("cache/dev.json"),
                                  notificationCenter: NotificationCenter(), codexHomeResolver: { nil },
                                  edition: .developerID)
        await dev.refreshNow()
        #expect(dev.currentMonthUsage?.claudeInput == 1_234)
    }

    @Test func 앱스토어_판은_동의가_없으면_토큰을_올리지_않는다() async {
        let host = "v0351-upload-gate"
        let store = v0351Store(host: host)
        store.session = SupabaseSession(accessToken: "access", refreshToken: nil, userID: v0351UserID)
        store.macEdition = .appStore
        #expect(!store.aiToolDataAllowed)
        let usage = TokenUsageMonthly(month: TokenUsageMonthKey.current(), claudeInput: 100, codexInput: 5_000)
        await store.uploadTokenUsageIfNeeded(usage: usage, now: Date())
        #expect(URLProtocolStub.requests(forHost: host).isEmpty, "동의 없이 토큰 숫자가 나갔다")
        // 배경 스캔 · 스캔 하트비트는 각자 다른 가드(근무 중 · 스캔 사실)가 먼저 막아 여기서는 못 잰다 — 아래 두 테스트가
        // 그 가드를 다 통과시킨 채 **동의 하나만** 바꿔 잰다.

        // 대조군: 동의하면 같은 호출이 실제로 나간다(게이트가 전원을 죽이지 않는다).
        store.setAIToolDataConsent(true)
        #expect(store.aiToolDataAllowed)
        await store.uploadTokenUsageIfNeeded(usage: usage, now: Date())
        #expect(URLProtocolStub.requests(forHost: host).contains { $0.url?.path == "/rest/v1/token_usage_device_monthly" })
    }

    /// 배경 스캔(팝오버 없이 근무 중에 도는 스캔 → 업로드 → 하트비트)의 동의 게이트.
    /// 스캐너는 **일부러 Developer ID 판**(키 없이도 읽는다)으로 만든다 — 스캐너 입구의 게이트(위 `…파일을_하나도_안_읽는다`)를
    /// 빼고 **스토어 쪽 게이트 하나만** 잰다. 게이트는 짝으로 있다: 둘 중 하나가 빠져도 다른 하나가 빨개져야 한다.
    @Test func 앱스토어_판은_동의가_없으면_배경_스캔을_돌리지_않는다() async throws {
        let host = "v0351-background-gate"
        let home = try v0351TempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try v0351WriteClaudeLog(into: home, input: 4_321)
        let tokens = TokenUsageStore(defaults: CheckTestScratch.defaults("tokens"), homeDirectory: home,
                                     cacheURL: home.appendingPathComponent("cache/bg.json"),
                                     notificationCenter: NotificationCenter(), codexHomeResolver: { nil },
                                     edition: .developerID)
        let store = v0351Store(host: host, tokenUsage: tokens)
        store.session = SupabaseSession(accessToken: "access", refreshToken: nil, userID: v0351UserID)
        store.macEdition = .appStore
        // 다른 가드는 전부 연다: 근무 중 · 수집 허용 · 기기 신원 · 이번 달 값 없음(= 1분 주기 롤오버, 바로 돈다).
        store.startedAt = Date().addingTimeInterval(-600)
        #expect(store.tokenUsageCollect)
        try #require(store.hasDeviceIdentity)
        #expect(!store.aiToolDataAllowed)

        let now = Date()
        await store.refreshTokenUsageInBackgroundIfDue(now: now)
        #expect(tokens.scanCount == 0, "동의 없이 배경 스캔이 AI 도구 기록을 읽었다")
        #expect(store.lastBackgroundTokenScanAt == .distantPast, "동의 없이 배경 스캔 주기 도장이 찍혔다")
        #expect(URLProtocolStub.requests(forHost: host).isEmpty, "동의 없이 배경 스캔 경로가 서버를 쳤다")

        // 대조군: 같은 스토어 · 같은 시각에 동의 **하나만** 바꾸면 읽고 올린다(위 침묵이 다른 가드 덕이 아니다).
        store.setAIToolDataConsent(true)
        await store.refreshTokenUsageInBackgroundIfDue(now: now)
        #expect(tokens.scanCount == 1)
        #expect(tokens.currentMonthUsage?.claudeInput == 4_321)
        #expect(URLProtocolStub.requests(forHost: host).contains {
            $0.httpMethod == "POST" && $0.url?.path == "/rest/v1/token_usage_device_monthly"
        }, "동의한 뒤에도 배경 스캔이 올리지 않았다 — 이 테스트의 앞 절반이 헛돈다")
    }

    /// 스캔 하트비트("스캐너가 돌았다"는 사실)의 동의 게이트. 스캔 사실(`lastScanAt`)을 미리 만들어 두고 동의만 바꾼다.
    @Test func 앱스토어_판은_동의가_없으면_스캔_하트비트를_보내지_않는다() async throws {
        let host = "v0351-heartbeat-gate"
        let home = try v0351TempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try v0351WriteClaudeLog(into: home, input: 10)
        let tokens = TokenUsageStore(defaults: CheckTestScratch.defaults("tokens"), homeDirectory: home,
                                     cacheURL: home.appendingPathComponent("cache/hb.json"),
                                     notificationCenter: NotificationCenter(), codexHomeResolver: { nil },
                                     edition: .developerID)
        await tokens.refreshNow()
        try #require(tokens.lastScanAt != nil, "준비 실패: 스캔 사실이 없으면 하트비트는 동의와 무관하게 침묵한다")
        let store = v0351Store(host: host, tokenUsage: tokens)
        store.session = SupabaseSession(accessToken: "access", refreshToken: nil, userID: v0351UserID)
        store.macEdition = .appStore
        #expect(store.tokenUsageCollect)
        try #require(store.hasDeviceIdentity)
        #expect(!store.aiToolDataAllowed)

        await store.sendTokenScanHeartbeatIfNeeded(now: Date())
        #expect(URLProtocolStub.requests(forHost: host).isEmpty, "동의 없이 스캔 하트비트가 나갔다")
        #expect(store.lastTokenScanHeartbeatAt == nil)

        // 대조군: 동의 하나만 바꾸면 같은 스캔 사실이 하트비트로 나간다(본문은 하트비트 전용 두 칸).
        store.setAIToolDataConsent(true)
        await store.sendTokenScanHeartbeatIfNeeded(now: Date())
        let requests = URLProtocolStub.requests(forHost: host)
        let bodies = URLProtocolStub.bodies(forHost: host)
        #expect(requests.count == 1, "\(requests.map { $0.url?.path ?? "" })")
        #expect(requests.first?.url?.path == "/rest/v1/token_usage_device_monthly")
        #expect(bodies.first?.contains("\"last_scan_at\"") == true, "하트비트 본문이 아니다: \(bodies)")
        #expect(store.lastTokenScanHeartbeatAt == tokens.lastScanAt)
    }

    @Test func 동의를_거두면_리밋_마스터를_재우고_다시_주면_그것만_되살린다() async {
        let defaults = CheckTestScratch.defaults()
        let reads = V0351Counter()
        let limits = AILimitStore(defaults: CheckTestScratch.defaults("limits"), deviceLabelProvider: { nil },
                                  runner: { _, _ in reads.bump("read"); return AILimitReadOutcome() })
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "anon"], defaults: defaults,
                                   workspaceNotifications: nil, aiLimits: limits)
        store.macEdition = .appStore

        await store.refreshAILimitsIfNeeded(now: Date(), force: true)
        #expect(reads.count("read") == 0, "동의 전에 리밋 리더가 돌았다(~/.codex/auth.json 에 손이 닿는다)")

        store.setAIToolDataConsent(true)
        #expect(defaults.bool(forKey: AIToolDataConsent.key))
        await store.refreshAILimitsIfNeeded(now: Date(), force: true)
        #expect(reads.count("read") == 1)

        store.setAIToolDataConsent(false)
        #expect(!limits.visibility.masterEnabled, "동의를 거뒀는데 리밋 축이 깨어 있다")
        #expect(defaults.bool(forKey: WorkTimerStore.aiLimitsPausedByConsentKey))
        store.setAIToolDataConsent(true)
        #expect(limits.visibility.masterEnabled, "우리가 재운 마스터를 되살리지 않았다")
        #expect(!defaults.bool(forKey: WorkTimerStore.aiLimitsPausedByConsentKey))

        // 사용자가 **스스로** 꺼 둔 마스터는 동의를 줬다 거둬도 켜지지 않는다.
        store.setAILimitsVisible(false)
        store.setAIToolDataConsent(false)
        store.setAIToolDataConsent(true)
        #expect(!limits.visibility.masterEnabled, "사용자가 꺼 둔 리밋을 동의 스위치가 켰다")
    }

    @Test func Developer_ID_판의_동의_스위치는_아무것도_안_한다() {
        let defaults = CheckTestScratch.defaults()
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "anon"], defaults: defaults,
                                   workspaceNotifications: nil)
        #expect(store.aiToolDataAllowed)
        store.setAIToolDataConsent(false)
        #expect(store.aiToolDataAllowed, "brew 판의 집계가 동의 스위치로 꺼졌다")
        #expect(defaults.object(forKey: AIToolDataConsent.key) == nil, "brew 판이 동의 키를 썼다")
    }

    // MARK: 로그인 시 자동 실행

    @Test func 앱스토어_판은_켠_적이_없으면_자동_등록하지_않는다() {
        for status in [SMAppService.Status.notRegistered, .enabled, .requiresApproval, .notFound] {
            #expect(!LoginItemRegistrar.shouldRegister(edition: .appStore, userTurnedOff: false, userOptedIn: false, status: status))
            #expect(LoginItemRegistrar.shouldRegister(edition: .appStore, userTurnedOff: false, userOptedIn: true, status: status)
                    == (status == .notRegistered))
            #expect(!LoginItemRegistrar.shouldRegister(edition: .appStore, userTurnedOff: true, userOptedIn: true, status: status))
            // brew 판은 의도 키를 보지 않는다(옛 두 인자 판단과 같다).
            for optedIn in [false, true] {
                for turnedOff in [false, true] {
                    #expect(LoginItemRegistrar.shouldRegister(edition: .developerID, userTurnedOff: turnedOff,
                                                              userOptedIn: optedIn, status: status)
                            == LoginItemRegistrar.shouldRegister(userTurnedOff: turnedOff, status: status))
                }
            }
        }
    }

    @Test func 앱스토어_판의_매실행_복구는_동의한_사람에게만_돈다() {
        let defaults = CheckTestScratch.defaults()
        let calls = V0351Counter()
        let first = LoginItemRegistrar.registerIfNeeded(
            defaults: defaults, status: { .notRegistered },
            register: { calls.bump("register"); return true }, edition: .appStore
        )
        #expect(first == .skippedAwaitingConsent)
        #expect(calls.count("register") == 0, "동의 없이 로그인 항목을 등록했다(2.4.5(iii))")
        #expect(defaults.string(forKey: LoginItemRegistrar.lastAutoRegisterKey) == "skippedAwaitingConsent:notRegistered")

        defaults.set(true, forKey: LoginItemRegistrar.userOptedInKey)
        let second = LoginItemRegistrar.registerIfNeeded(
            defaults: defaults, status: { .notRegistered },
            register: { calls.bump("register"); return true }, edition: .appStore
        )
        #expect(second == .registered)
        #expect(calls.count("register") == 1)

        // 대조군: brew 판은 의도 키 없이도 되살린다(지금 동작).
        let devDefaults = CheckTestScratch.defaults("dev")
        let dev = LoginItemRegistrar.registerIfNeeded(
            defaults: devDefaults, status: { .notRegistered },
            register: { calls.bump("dev"); return true }, edition: .developerID
        )
        #expect(dev == .registered)
    }

    // MARK: 첫 실행 안내 · 다른 판 경고

    @Test func 첫_실행_안내는_앱스토어_판에서_한_번만_뜬다() {
        let defaults = CheckTestScratch.defaults()
        #expect(!MacAppStoreOnboarding.shouldShowFirstRun(edition: .developerID, defaults: defaults))
        #expect(MacAppStoreOnboarding.shouldShowFirstRun(edition: .appStore, defaults: defaults))
        defaults.set(true, forKey: MacAppStoreOnboarding.firstRunCompletedKey)
        #expect(!MacAppStoreOnboarding.shouldShowFirstRun(edition: .appStore, defaults: defaults))
    }

    @Test func 첫_실행을_끝내면_고른_대로_동의와_자동실행이_선다() {
        let defaults = CheckTestScratch.defaults()
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "anon"], defaults: defaults,
                                   workspaceNotifications: nil)
        store.macEdition = .appStore
        var applied: [Bool] = []
        MacAppStoreOnboarding.complete(store: store, allowAITools: true, launchAtLogin: true, defaults: defaults,
                                       applyLaunchAtLogin: { applied.append($0) })
        #expect(defaults.bool(forKey: MacAppStoreOnboarding.firstRunCompletedKey))
        #expect(store.aiToolDataConsent)
        #expect(defaults.bool(forKey: AIToolDataConsent.key))
        #expect(applied == [true])

        // [나중에] · 창 닫기: 동의 없음, 자동 실행은 **건드리지 않는다**(기본이 꺼짐이고 등록된 적도 없다).
        let laterDefaults = CheckTestScratch.defaults("later")
        let later = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "anon"], defaults: laterDefaults,
                                   workspaceNotifications: nil)
        later.macEdition = .appStore
        var laterApplied: [Bool] = []
        MacAppStoreOnboarding.complete(store: later, allowAITools: false, launchAtLogin: false, defaults: laterDefaults,
                                       applyLaunchAtLogin: { laterApplied.append($0) })
        #expect(laterDefaults.bool(forKey: MacAppStoreOnboarding.firstRunCompletedKey))
        #expect(!later.aiToolDataAllowed)
        #expect(laterApplied.isEmpty, "끈 채로 끝냈는데 로그인 항목을 건드렸다")
    }

    @Test func 다른_판_경고는_앱스토어_판에서_brew_판이_돌_때_한_번() {
        #expect(MacAppStoreOnboarding.shouldWarnAboutOtherEdition(
            edition: .appStore, runningBundleIdentifiers: ["com.apple.finder", "kingcheck"], alreadyWarned: false))
        #expect(!MacAppStoreOnboarding.shouldWarnAboutOtherEdition(
            edition: .appStore, runningBundleIdentifiers: ["kingcheck"], alreadyWarned: true))
        #expect(!MacAppStoreOnboarding.shouldWarnAboutOtherEdition(
            edition: .appStore, runningBundleIdentifiers: ["com.yehsung.aingcheck", "kingcheckx"], alreadyWarned: false))
        #expect(!MacAppStoreOnboarding.shouldWarnAboutOtherEdition(
            edition: .developerID, runningBundleIdentifiers: ["com.yehsung.aingcheck", "kingcheck"], alreadyWarned: false),
                "brew 판은 지금 동작 그대로다(경고하지 않는다)")
    }

    @Test func 첫_실행_안내와_경고는_작은_창에_든다() throws {
        let firstRun = try #require(v0351Height(CheckFirstRunView { _, _ in }, width: CheckFirstRunView.width))
        #expect(firstRun > 300, "첫 실행 안내가 거의 안 그려졌다(\(firstRun)pt)")
        #expect(firstRun <= 640, "첫 실행 안내가 \(firstRun)pt — 13\" 맥북에어 화면에서 버튼이 밀려난다")
        let notice = try #require(v0351Height(CheckOtherEditionNoticeView {}, width: CheckOtherEditionNoticeView.width))
        #expect(notice > 80 && notice <= 320)
    }

    // MARK: 안티그래비티 sqlite 2단 판정

    @Test func 사이드카_계열_실패만_immutable_로_내려간다() {
        #expect(AntigravityConversationReader.fallsBackToImmutable(primaryCode: SQLITE_CANTOPEN))
        #expect(AntigravityConversationReader.fallsBackToImmutable(primaryCode: SQLITE_READONLY))
        #expect(AntigravityConversationReader.fallsBackToImmutable(primaryCode: SQLITE_READONLY | (1 << 8)))   // READONLY_RECOVERY
        #expect(AntigravityConversationReader.fallsBackToImmutable(primaryCode: SQLITE_READONLY | (5 << 8)))   // READONLY_CANTINIT
        #expect(AntigravityConversationReader.fallsBackToImmutable(primaryCode: SQLITE_PERM))
        for code in [SQLITE_OK, SQLITE_ERROR, SQLITE_BUSY, SQLITE_CORRUPT, SQLITE_NOTADB, SQLITE_LOCKED] {
            #expect(!AntigravityConversationReader.fallsBackToImmutable(primaryCode: code),
                    "사이드카와 무관한 실패(\(code))가 2단으로 내려갔다 — 같은 실패를 두 번 한다")
        }
    }

    // MARK: ② 계정 삭제 (두 판 모두)

    @Test func 계정_삭제는_재로그인_사진_RPC_순서로_가고_로그인_화면으로_돌아온다() async throws {
        let host = "v0351-delete-ok"
        let store = v0351DeletionStore(host: host)
        store.accountDeletionPassword = "secret-pw"
        #expect(store.canDeleteAccount)
        let ok = await store.deleteMyAccount()
        #expect(ok)
        #expect(store.session == nil)
        #expect(store.email.isEmpty)
        #expect(store.defaults.string(forKey: WorkTimerStore.emailKey) == nil, "지운 계정의 이메일이 로그인 칸에 남는다")
        #expect(store.syncMessage == WorkTimerStore.accountDeletedMessage)
        #expect(AuthMessageKind(store.syncMessage) == .success, "삭제 완료 문구가 빨간 경고로 그려진다")
        #expect(!store.showsAccountDeletionInSettings)
        #expect(store.accountDeletionPassword.isEmpty)

        let requests = V0351DeletionURLProtocol.requests(forHost: host)
        let paths = requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
        let token = try #require(paths.firstIndex(of: "POST /auth/v1/token"), "재로그인이 없다: \(paths)")
        let avatar = try #require(paths.firstIndex { $0.hasPrefix("DELETE /storage/v1/object/avatars/") }, "사진 삭제가 없다: \(paths)")
        let rpc = try #require(paths.firstIndex(of: "POST /rest/v1/rpc/delete_my_account"), "RPC 가 없다: \(paths)")
        #expect(token < avatar && avatar < rpc, "순서가 재로그인 → 사진 → RPC 가 아니다: \(paths)")
        #expect(requests[rpc].value(forHTTPHeaderField: "Authorization") == "Bearer reauth-access",
                "RPC 는 재로그인으로 받은 새 토큰으로 가야 한다")
        let body = try JSONSerialization.jsonObject(with: V0351DeletionURLProtocol.bodies(forHost: host)[token]) as? [String: Any]
        #expect(body?["email"] as? String == "member@example.com")
        #expect(body?["password"] as? String == "secret-pw")
        #expect(!paths.contains("POST /auth/v1/logout"), "지운 계정의 세션으로 로그아웃을 또 불렀다")
    }

    @Test func 비밀번호가_틀리면_RPC_를_부르지_않고_로그인을_그대로_둔다() async {
        let host = "v0351-delete-wrong"
        V0351DeletionURLProtocol.setTokenReply(
            status: 400, body: "{\"code\":400,\"error_code\":\"invalid_credentials\",\"msg\":\"Invalid login credentials\"}",
            forHost: host)
        let store = v0351DeletionStore(host: host)
        store.accountDeletionPassword = "wrong"
        let ok = await store.deleteMyAccount()
        #expect(!ok)
        #expect(store.session != nil)
        #expect(store.accountDeletionNotice == AccountDeletionText.wrongPassword)
        let paths = V0351DeletionURLProtocol.requests(forHost: host).map { $0.url?.path ?? "" }
        #expect(!paths.contains("/rest/v1/rpc/delete_my_account"))
        #expect(!paths.contains { $0.hasPrefix("/storage/") })
    }

    @Test func 재로그인이_다른_계정이면_지우지_않는다() async {
        let host = "v0351-delete-mismatch"
        V0351DeletionURLProtocol.setTokenReply(
            status: 200,
            body: "{\"access_token\":\"reauth-access\",\"refresh_token\":\"r\",\"user\":{\"id\":\"99999999-0000-0000-0000-000000000009\"}}",
            forHost: host)
        let store = v0351DeletionStore(host: host)
        store.accountDeletionPassword = "pw"
        let ok = await store.deleteMyAccount()
        #expect(!ok)
        #expect(store.session?.userID == v0351UserID)
        #expect(store.accountDeletionNotice == AccountDeletionText.accountMismatch)
        let requests = V0351DeletionURLProtocol.requests(forHost: host)
        #expect(!requests.contains { $0.url?.path == "/rest/v1/rpc/delete_my_account" })
        #expect(requests.contains { $0.url?.path == "/auth/v1/logout"
                && $0.value(forHTTPHeaderField: "Authorization") == "Bearer reauth-access" },
                "재로그인으로 만든 두 번째 세션을 닫지 않았다")
    }

    @Test func 서버에_함수가_없으면_아직이라고_말하고_로그인을_지킨다() async {
        let host = "v0351-delete-missing"
        V0351DeletionURLProtocol.setRPCReply(
            status: 404,
            body: "{\"code\":\"PGRST202\",\"message\":\"Could not find the function public.delete_my_account without parameters in the schema cache\"}",
            forHost: host)
        let store = v0351DeletionStore(host: host)
        store.accountDeletionPassword = "pw"
        let ok = await store.deleteMyAccount()
        #expect(!ok)
        #expect(store.session != nil)
        #expect(store.accountDeletionNotice == AccountDeletionText.serverNotReady)
        #expect(V0351DeletionURLProtocol.requests(forHost: host).contains { $0.url?.path == "/auth/v1/logout" })
    }

    @Test func 비밀번호가_없거나_로그인_전이면_아무것도_안_보낸다() async {
        let host = "v0351-delete-guard"
        let store = v0351DeletionStore(host: host)
        #expect(!store.canDeleteAccount)
        #expect(await store.deleteMyAccount() == false)
        #expect(store.accountDeletionNotice == AccountDeletionText.passwordRequired)
        store.session = nil
        store.accountDeletionPassword = "pw"
        #expect(!store.canDeleteAccount)
        #expect(await store.deleteMyAccount() == false)
        #expect(store.accountDeletionNotice == AccountDeletionText.signedOut)
        #expect(V0351DeletionURLProtocol.requests(forHost: host).isEmpty)
    }

    @Test func 삭제_화면은_열고_닫을_때_비밀번호와_확인을_비운다() {
        let store = v0351DeletionStore(host: "v0351-delete-page")
        store.openAccountDeletionSettings()
        #expect(store.showsAccountDeletionInSettings)
        store.accountDeletionPassword = "pw"
        store.isConfirmingAccountDeletion = true
        store.closeAccountDeletionSettings()
        #expect(!store.showsAccountDeletionInSettings)
        #expect(store.accountDeletionPassword.isEmpty)
        #expect(!store.isConfirmingAccountDeletion)
        // 로그인 전에는 열리지 않는다(지울 계정이 없다).
        store.session = nil
        store.openAccountDeletionSettings()
        #expect(!store.showsAccountDeletionInSettings)
    }

    // MARK: 설정 창 높이 · 약관 링크

    @Test func 머리_줄_링크는_설정_높이를_한_점도_늘리지_않는다() throws {
        let signedOut = try v0351SettingsHeight { _ in }
        let signedIn = try v0351SettingsHeight { store in
            store.session = SupabaseSession(accessToken: "a", refreshToken: nil, userID: v0351UserID)
        }
        // 로그인하면 '내 정보' 머리 줄에 [계정 삭제]가 선다 — 같은 글자 크기의 한 줄이라 높이가 같아야 한다.
        #expect(signedIn == signedOut, "계정 삭제 링크가 설정 본문을 \(signedIn - signedOut)pt 늘렸다")
        // 그리고 그 높이가 창 계약(여유 5pt)을 그대로 지킨다(V0340 과 같은 등식 — 머리 줄 링크가 깨면 둘 다 빨개진다).
        #expect(CheckSettingsWindowController.defaultContentSize.height - (signedOut + AvatarRemovalSettingsRow.maxExtraHeight) == 5)
    }

    @Test func 앱스토어_판_설정에만_AI_기록_동의_행이_선다() throws {
        let dev = try v0351SettingsHeight { _ in }
        let mas = try v0351SettingsHeight { $0.macEdition = .appStore }
        #expect(mas > dev, "앱스토어 판 설정에 AI 기록 읽기 행이 안 그려졌다")
        // 정직한 계약: 앱스토어 판 본문은 창보다 높다 — 그 판은 `ViewThatFits` 의 스크롤 가지로 떨어져 **잘리지 않는다**
        // (V0347 의 소스 계약이 그 가지와 순서를 지킨다). 창을 키워서 풀 수 없는 이유는 13" 맥북에어 상한(~903pt)이다.
        #expect(mas + AvatarRemovalSettingsRow.maxExtraHeight > CheckSettingsWindowController.defaultContentSize.height)
    }

    @Test func 계정_삭제_화면은_창_안에_든다() throws {
        let page = try v0351SettingsHeight { store in
            store.session = SupabaseSession(accessToken: "a", refreshToken: nil, userID: v0351UserID)
            store.openAccountDeletionSettings()
            store.accountDeletionPassword = "pw"
            store.isConfirmingAccountDeletion = true
            store.accountDeletionNotice = AccountDeletionText.serverNotReady
        }
        #expect(page <= CheckSettingsWindowController.defaultContentSize.height,
                "계정 삭제 화면(확인 + 실패 문장)이 \(page)pt — 창에서 잘린다")
    }

    @Test func 가입_동의_한_줄의_두_낱말이_약관과_처리방침으로_간다() throws {
        let text = SignUpTermsText.attributed
        var links: [String: URL] = [:]
        for run in text.runs {
            if let url = run.link { links[String(text[run.range].characters)] = url }
        }
        #expect(links[SignUpTermsText.termsLink] == CheckAppLinks.termsOfService)
        #expect(links[SignUpTermsText.privacyLink] == CheckAppLinks.privacyPolicy)
        #expect(CheckAppLinks.privacyPolicy.absoluteString == "https://yehsung.github.io/check/privacy")
        #expect(CheckAppLinks.termsOfService.absoluteString == "https://yehsung.github.io/check/terms")
    }

    // MARK: 들어가는 문 — 심사 지침 5.1.1 · 첫 실행 동의에 닿는 자리 넷
    //
    // 위 테스트들은 삭제 흐름 · 링크 값 · `MacAppStoreOnboarding.complete` 를 **직접** 부른다. 화면이 그것들을 부르는지는 따로
    // 재야 한다 — 문 넷(설정 머리 줄 링크 둘 · 가입 한 줄 · 첫 실행 배선)은 지워도 높이가 그대로라(머리 줄 링크) 또는 화면을 못 띄워서
    // (가입 폼 · 앱 시작) 다른 테스트가 전부 초록인 채로 사라진다. 그래서 하나는 그림으로(기준선이 다른 두 장), 나머지는 소스로 잰다.

    @Test func 로그인하면_내_정보_머리_줄에_빨간_계정_삭제가_그려진다() throws {
        // 기준선이 **다른** 두 장: 로그인 전(문 없음)과 뒤(문 있음). 차이는 그 문 하나여야 하고, 그 문은 위험색(빨강) 글자다.
        let signedOut = try v0351SettingsRedPixels { _ in }
        let signedIn = try v0351SettingsRedPixels { store in
            store.session = SupabaseSession(accessToken: "a", refreshToken: nil, userID: v0351UserID)
        }
        // 실측(2026-10-14 · 폭 380 · 2배): 로그인 전 14,252 → 뒤 14,834(+582 = 그 두 낱말). 문을 지우거나(`if false`) 누구에게나
        // 세우거나(`if true`) helper 가 꼬리를 안 그리면 두 값이 같아진다. 문턱 200 은 '낱말 하나 크기의 빨강'이다.
        #expect(signedIn > signedOut + 200,
                "로그인했는데 '내 정보' 머리 줄에 [계정 삭제]가 안 그려졌다(빨강 \(signedOut) → \(signedIn)px)")
    }

    @Test func 설정_머리_줄의_약관_링크와_계정_삭제_문은_두_판_모두에_있다() throws {
        let raw = try v0351Source("CheckSettingsView.swift")
        let source = v0351Collapsed(raw)
        // ① 절 helper 가 꼬리(trailing)를 머리 줄에 **실제로 그린다**(인자만 받고 버리면 아래 배선이 전부 헛돈다).
        let helper = try #require(v0351Closure(
            after: "private func section( _ title: String, @ViewBuilder content: () -> some View, @ViewBuilder trailing: () -> some View ) -> some View",
            in: source), "머리 줄 꼬리를 받는 절 helper 가 없다")
        #expect(helper.body.contains("Text(title)") && helper.body.contains("trailing()") && helper.body.contains("content()"))
        let titleAt = try #require(helper.body.range(of: "Text(title)"))
        let trailingAt = try #require(helper.body.range(of: "trailing()"))
        let contentAt = try #require(helper.body.range(of: "content()"))
        #expect(titleAt.upperBound <= trailingAt.lowerBound && trailingAt.upperBound <= contentAt.lowerBound,
                "꼬리가 머리 줄(제목 옆)이 아닌 자리에 그려진다")

        // ② '일반' 머리 줄 = 개인정보 처리방침 · 이용약관(5.1.1(i)). 여는 줄은 링크 없는 절과 같고, 링크는 절 끝 꼬리 클로저다.
        #expect(source.components(separatedBy: "section(\"일반\") {").count == 2, "'일반' 절이 정확히 하나가 아니다")
        let general = try #require(v0351Closure(after: "section(\"일반\")", in: source))
        let generalTrailing = try #require(v0351TrailingClosure(labeled: "trailing", after: general, in: source),
                                           "'일반' 절에 머리 줄 꼬리가 없다 — 개인정보 처리방침 · 이용약관 링크가 사라졌다")
        #expect(generalTrailing.body.contains("SettingsLegalLinks()"))
        let legal = try #require(v0351Closure(after: "struct SettingsLegalLinks: View", in: source))
        #expect(legal.body.contains("openURL(CheckAppLinks.privacyPolicy)"))
        #expect(legal.body.contains("openURL(CheckAppLinks.termsOfService)"))

        // ③ '내 정보' 머리 줄 = [계정 삭제](5.1.1(v)) — 로그인했을 때만, 누르면 삭제 화면을 연다.
        //    본문의 첫 행이 별명이라는 것까지 같이 본다(상태메시지 계약이 같은 여는 줄을 붙잡는다 — 그 줄을 바꾸지 않았다는 증거).
        #expect(source.components(separatedBy: "section(\"내 정보\") {").count == 2, "'내 정보' 절이 정확히 하나가 아니다")
        let mine = try #require(v0351Closure(after: "section(\"내 정보\")", in: source))
        #expect(mine.body.hasPrefix("{ DisplayNameSettingsRow(store: store)"), "'내 정보' 본문 첫 행이 별명이 아니다")
        let mineTrailing = try #require(v0351TrailingClosure(labeled: "trailing", after: mine, in: source),
                                        "'내 정보' 절에 머리 줄 꼬리가 없다 — [계정 삭제] 문이 사라졌다")
        let gate = try #require(v0351Closure(after: "if store.session != nil", in: mineTrailing.body),
                                "[계정 삭제] 문이 로그인 여부로 갈리지 않는다")
        #expect(gate.body.contains("SettingsHeaderLinkButton( title: AccountDeletionText.entry"))
        #expect(gate.body.contains("action: { store.openAccountDeletionSettings() }"))

        // ④ 두 판 모두에서 컴파일된다(앱스토어 심사가 보는 판이 바로 CHECK_MAS 판이다).
        try v0351ExpectIncluded("CheckSettingsView.swift", ["SettingsLegalLinks()", "title: AccountDeletionText.entry",
                                                            "CheckAccountDeletionSettingsPage(store: store)"])
    }

    @Test func 가입_폼에만_약관_동의_한_줄이_선다() throws {
        let source = v0351Collapsed(try v0351Source("CheckMenuView.swift"))
        let panel = try #require(v0351Closure(after: "private struct LoginPanel: View", in: source)).body
        // 가입 모드 분기(`if mode == .signUp { … }`)들 중 **하나**가 동의 한 줄을 세운다(분기가 여럿이라 전부 훑는다).
        var signUpBlocks: [String] = []
        var searchFrom = panel.startIndex
        while let hit = panel.range(of: "if mode == .signUp", range: searchFrom..<panel.endIndex) {
            if let block = v0351BraceBlock(from: hit.upperBound, in: panel) { signUpBlocks.append(block.body) }
            searchFrom = hit.upperBound
        }
        #expect(!signUpBlocks.isEmpty, "로그인 패널에 가입 모드 분기가 없다 — 이 계약이 헛돈다")
        #expect(signUpBlocks.contains { $0.contains("SignUpTermsNotice()") },
                "가입 폼(`if mode == .signUp`)에 약관 동의 한 줄(SignUpTermsNotice)이 없다 — 심사 지침 5.1.1(i)")
        #expect(source.components(separatedBy: "SignUpTermsNotice()").count == 2, "약관 동의 한 줄이 가입 폼 밖에도 섰다")
        let notice = try #require(v0351Closure(after: "struct SignUpTermsNotice: View", in: source))
        #expect(notice.body.contains("Text(SignUpTermsText.attributed)"), "동의 한 줄이 링크를 심은 문장을 그리지 않는다")
        try v0351ExpectIncluded("CheckMenuView.swift", ["SignUpTermsNotice()"])
    }

    @Test func 첫_실행_안내는_앱이_뜨는_자리에서_두_판_모두_불린다() throws {
        let raw = try v0351Source("CheckApp.swift")
        let source = v0351Collapsed(raw)
        let launch = try #require(v0351Closure(after: "func applicationDidFinishLaunching(_ notification: Notification)", in: source))
        let make = try #require(launch.body.range(of: "masOnboarding = MacAppStoreOnboardingController(store: store)"),
                                "앱 시작이 첫 실행 안내 컨트롤러를 만들지 않는다 — 앱스토어 판 사용자는 동의를 영영 못 고른다")
        let start = try #require(launch.body.range(of: "masOnboarding?.start()", range: make.upperBound..<launch.body.endIndex),
                                 "만든 컨트롤러를 시작하지 않는다")
        #expect(make.upperBound <= start.lowerBound)
        // 판 울타리 밖이다: 판정은 `start()` 안의 판 값이 한다(Developer ID 판에서는 창을 만들지 않는다).
        try v0351ExpectIncluded("CheckApp.swift", ["masOnboarding = MacAppStoreOnboardingController(store: store)",
                                                   "masOnboarding?.start()"])
        // 그리고 `start()` 는 정말로 첫 실행 안내를 띄운다(판 · 완료 키 판정 뒤).
        let controller = v0351Collapsed(try v0351Source("CheckMacAppStoreOnboarding.swift"))
        let startBody = try #require(v0351Closure(after: "func start()", in: controller))
        let decide = try #require(startBody.body.range(of: "MacAppStoreOnboarding.shouldShowFirstRun(edition: store.macEdition, defaults: defaults)"))
        let show = try #require(startBody.body.range(of: "showFirstRun()"), "start() 가 첫 실행 안내를 띄우지 않는다")
        #expect(decide.upperBound <= show.lowerBound)
        // 만드는 자리는 하나다(두 번 만들면 안내가 두 번 뜬다).
        let sites = try v0351AllSources().map { $0.1.components(separatedBy: "MacAppStoreOnboardingController(store:").count - 1 }
        #expect(sites.reduce(0, +) == 1)
    }

    // MARK: ③ 소스 계약 — 앱스토어 판에서 사라져야 하는 경로는 `#if !CHECK_MAS` 안에 있다

    @Test func 자가_업데이트_경로는_앱스토어_판에서_컴파일되지_않는다() throws {
        try v0351ExpectExcluded("CheckUpdateCheck.swift", [
            "static let latestReleaseURL", "private func performCheck(", "enum InstallSource",
            "enum UpdateStage", "struct UpdateProgress", "final class UpdateRunner",
            "static let dmgUpdateScript", "static func upgradeScript(", "static func detachedSpawn(",
        ])
        try v0351ExpectExcluded("CheckMenuView.swift", ["private struct UpdateBanner", "UpdateBanner(versionText:"])
        try v0351ExpectExcluded("CheckApp.swift", ["updateCheck.serverFetcher =", "updateCheck.onNewVersionAvailable ="])
        // 공지 배선은 두 판 모두 남는다(공지 카드는 판과 무관하다).
        try v0351ExpectIncluded("CheckApp.swift", ["updateCheck.noticeFetcher =", "updateCheck.onNoticeFetched =",
                                                   "updateCheck.startServerWatch()"])
        // SIGTERM 마무리는 로그아웃·시스템 종료에도 쓰여 남는다.
        try v0351ExpectIncluded("CheckUpdateCheck.swift", ["enum GracefulTerminationSignal"])
    }

    @Test func 외부_프로세스를_띄우는_리더는_앱스토어_판에서_컴파일되지_않는다() throws {
        // 사용자 설치 실행 파일(`agy`)을 띄우는 리더만 빠진다. Claude 리더와 실행기는 시스템 `security` 하나를 위해 남는다
        // (2026-10-14 결정 · 샌드박스 실측).
        try v0351ExpectExcluded("AILimitReaders.swift", ["struct AILimitAntigravityReader"])
        try v0351ExpectIncluded("AILimitReaders.swift", [
            "struct AILimitClaudeReader", "static func live() -> AILimitCommandRunner", "private final class Session",
        ])
        try v0351ExpectExcluded("CheckCodexAccountUsage.swift", [
            "private static func shellLookup(", "private static func runSession(", "private final class ProcessSession",
            "static var shellLookupScript", "package static func run(",
        ])
        // 앱스토어 판 러너는 Claude·Codex 리더 둘이고, 브루 판 러너(세 리더)의 안티그래비티는 그 판에서 빠진다.
        try v0351ExpectExcluded("AILimitStore.swift", ["AILimitAntigravityReader("])
        try v0351ExpectIncluded("AILimitStore.swift", ["AILimitCodexReader(", "AILimitClaudeReader("])
        // Codex 계정 프로브의 라이브 조립은 그 판에서 무해 인스턴스다(호출 지점 CheckApp 의 한 줄은 두 판이 같다).
        try v0351ExpectExcluded("CheckCoreBridge.swift", ["CodexAccountUsageProbe.fetch(", "CodexAccountUsageProbe.resolveCodexHome()"])
        // 실행 인자로 여는 진단 명령 루프도 그 판에는 없다.
        try v0351ExpectExcluded("CheckSettingsWindow.swift", ["readLine(strippingNewline: true)"])
    }

    /// 앱스토어 판에서 컴파일되는 자식 프로세스는 **리밋 실행기(`AILimitProcess.live()` 의 `Session`) 하나**뿐이다 —
    /// Claude 리밋이 시스템 도구 `/usr/bin/security` 를 띄우는 자리(2026-10-14 사용자 결정 · 샌드박스 실측). 그 실행기로
    /// 사용자 설치 실행 파일을 띄우던 안티그래비티 리더는 울타리 안에 있다(위 테스트). 그 밖의 `Process()` 가 울타리 밖에
    /// 새로 생기면 빨개진다.
    @Test func 불변식_Process_는_전부_앱스토어_판_울타리_안에_있다() throws {
        var hits = 0
        var allowedUnfenced = 0
        for (name, source) in try v0351AllSources() {
            let excluded = V0351IfConfig.linesExcludedUnderMAS(source)
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains("Process()") || line.contains(".executableURL =") {
                hits += 1
                if excluded.contains(index) { continue }
                if name == "AILimitReaders.swift" { allowedUnfenced += 1; continue }
                Issue.record("앱스토어 판에서 컴파일되는 자식 프로세스: \(name):\(index + 1) \(line)")
            }
        }
        #expect(hits >= 4, "검사가 헛돈다 — Process() 를 하나도 못 찾았다")
        #expect(allowedUnfenced >= 1, "리밋 실행기가 울타리 안으로 들어갔다 — Claude 리밋을 앱스토어 판에서 뺐다면 MacEdition.readsClaudeLimits·이 테스트를 같이 고쳐라")
    }

    @Test func 불변식_컨테이너_홈을_쓰는_자리는_앱스토어_판에서_사라진다() throws {
        var hits = 0
        for (name, source) in try v0351AllSources() where name != "MacEdition.swift" {
            let excluded = V0351IfConfig.linesExcludedUnderMAS(source)
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains("homeDirectoryForCurrentUser") || line.contains("expandingTildeInPath") {
                hits += 1
                // 예외 하나: 테스트 프로세스가 실홈을 읽지 못하게 막는 게이트(프로덕션에서는 늘 거짓 — V0312).
                if line.contains("realHomeScanIsBlocked") || source.v0351Line(index - 2).contains("func realHomeScanIsBlocked") {
                    continue
                }
                #expect(excluded.contains(index),
                        "앱스토어 판에서 샌드박스 컨테이너를 '홈'으로 읽는 자리: \(name):\(index + 1) \(line) — AIToolHome 을 써라")
            }
        }
        #expect(hits >= 3, "검사가 헛돈다")
        // 그리고 기본값들이 진짜 홈 해석기를 거친다.
        // 쪼갠 파일(코어 스캐너 + 맥 행)이라 두 조각을 이어 읽는다(CheckCoreSourceLayoutTests 의 반쪽 읽기 금지).
        let usage = V0351IfConfig.strippingComments(try CheckCoreSourceLayout.joinedSplitSource("CheckTokenUsage.swift"))
        #expect(usage.contains("homeDirectory: URL = AIToolHome.current()"))
        let limits = try v0351Source("AILimitStore.swift")
        #expect(limits.contains("home: URL = AIToolHome.current()"))
        let sync = try v0351Source("WorkTimerStoreSync.swift")
        #expect(sync.contains("let home = AIToolHome.current(edition: macEdition)"))
    }

    @Test func 키체인_기본_service_는_판을_따른다() throws {
        let vault = try v0351Source("TokenVault.swift")
        #expect(vault.contains("package init(service: String = MacEdition.current.keychainService, accessGroup: String? = nil)"))
        // 생성 지점은 여전히 하나이고 인자 없이 부른다(V0237 계약) — 그래서 판마다 service 가 갈리는 자리는 기본값 하나다.
        let store = try v0351Source("WorkTimerStore.swift")
        #expect(store.contains(": KeychainTokenVault()"))
    }

    @Test func 계정_삭제를_부르는_곳은_확인_버튼_하나다() throws {
        var sites: [String] = []
        for (name, source) in try v0351AllSources() {
            let n = source.components(separatedBy: "deleteMyAccount()").count - 1
            if n > 0 { sites.append("\(name):\(n)") }
        }
        // 정의(스토어) 1 + 화면의 [영구 삭제] 1.
        #expect(sites.sorted() == ["CheckAccountDeletionPage.swift:1", "WorkTimerStoreMacEdition.swift:1"], "\(sites)")
        let page = try v0351Source("CheckAccountDeletionPage.swift")
        let confirm = try #require(page.range(of: "label: deleting ? AccountDeletionText.inFlight : AccountDeletionText.confirm"))
        let call = try #require(page.range(of: "await store.deleteMyAccount()"))
        #expect(confirm.lowerBound < call.lowerBound, "삭제 호출이 [영구 삭제](2단계) 버튼 밖에 있다")
        #expect(!page.contains(".onSubmit"), "비밀번호 칸의 Enter 가 삭제를 부를 수 있다")
    }

    // MARK: 개인정보 매니페스트

    @Test func 개인정보_매니페스트가_실제로_쓰는_필수사유_API_를_빠짐없이_적는다() throws {
        let url = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/check/Resources/PrivacyInfo.xcprivacy")
        let plist = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        let accessed = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var declared: [String: [String]] = [:]
        for entry in accessed {
            let type = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            declared[type] = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        }
        let joined = try v0351AllSources().map(\.1).joined(separator: "\n")
        // 소스가 부르는 범주는 반드시 선언돼 있어야 한다(드리프트 — 새 API 를 쓰면 여기가 빨개진다).
        if joined.contains("UserDefaults") { #expect(declared["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"]) }
        if joined.contains("contentModificationDate") || joined.contains("st_mtimespec") || joined.contains("modificationDate") {
            #expect(declared["NSPrivacyAccessedAPICategoryFileTimestamp"]?.isEmpty == false)
        }
        if joined.contains("systemUptime") || joined.contains("mach_absolute_time") {
            #expect(declared["NSPrivacyAccessedAPICategorySystemBootTime"] == ["35F9.1"])
        }
        let usesDiskSpace = ["volumeAvailableCapacity", "systemFreeSize", "statfs(", "volumeTotalCapacity"].contains { joined.contains($0) }
        #expect((declared["NSPrivacyAccessedAPICategoryDiskSpace"] != nil) == usesDiskSpace)
        let collected = try #require(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(!collected.isEmpty)
        for item in collected {
            #expect(item["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
        }
    }
}

// MARK: - 헬퍼

private let v0351UserID = "00000000-0000-0000-0000-000000000002"

/// 호출 수를 센다(병렬 안전 — 클로저가 아무 스레드에서나 불린다).
private final class V0351Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func bump(_ key: String) { lock.lock(); counts[key, default: 0] += 1; lock.unlock() }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[key] ?? 0 }
}

@MainActor
private func v0351Store(host: String = "v0351-default", tokenUsage: TokenUsageStore = .shared,
                        function: String = #function) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: CheckTestScratch.defaults(host, function: function),
        workspaceNotifications: nil,
        tokenUsage: tokenUsage
    )
    store.currentTeamID = URLProtocolStub.stubTeamID
    // 빌드를 모르게 둔다 — 알면 업로드가 Codex 진단(홈 디렉터리 전량 순회)을 하루 1회 계산하는데, 이 스위트가 재는 것은
    // 동의 게이트뿐이라 테스트가 개발자의 실제 `~/.codex` 를 훑을 이유가 없다.
    store.appVersionProvider = { nil }
    return store
}

@MainActor
private func v0351DeletionStore(host: String, function: String = #function) -> WorkTimerStore {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [V0351DeletionURLProtocol.self]
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: URLSession(configuration: configuration)
    )
    let defaults = CheckTestScratch.defaults(host, function: function)
    defaults.set("member@example.com", forKey: WorkTimerStore.emailKey)
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "old-access", refreshToken: "old-refresh", userID: v0351UserID)
    return store
}

/// 계정 삭제 왕복 셋(재로그인 · 사진 · RPC)과 로그아웃만 답하는 스텁. 호스트별로 응답을 바꾼다(병렬 안전).
final class V0351DeletionURLProtocol: URLProtocol {
    private nonisolated(unsafe) static var recorded: [(host: String, request: URLRequest, body: Data)] = []
    private nonisolated(unsafe) static var tokenReplies: [String: (Int, String)] = [:]
    private nonisolated(unsafe) static var rpcReplies: [String: (Int, String)] = [:]
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let body = Self.bodyData(request)
        Self.lock.lock()
        Self.recorded.append((host, request, body))
        let token = Self.tokenReplies[host]
        let rpc = Self.rpcReplies[host]
        Self.lock.unlock()

        let (status, text): (Int, String)
        switch path {
        case "/auth/v1/token":
            (status, text) = token
                ?? (200, "{\"access_token\":\"reauth-access\",\"refresh_token\":\"reauth-refresh\",\"user\":{\"id\":\"\(v0351UserID)\"}}")
        case "/rest/v1/rpc/delete_my_account":
            (status, text) = rpc ?? (204, "")
        case "/auth/v1/logout":
            (status, text) = (204, "")
        default:
            (status, text) = path.hasPrefix("/storage/") ? (200, "{}") : (200, "[]")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func setTokenReply(status: Int, body: String, forHost host: String) {
        lock.lock(); tokenReplies[host] = (status, body); lock.unlock()
    }

    static func setRPCReply(status: Int, body: String, forHost host: String) {
        lock.lock(); rpcReplies[host] = (status, body); lock.unlock()
    }

    static func requests(forHost host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded.filter { $0.host == host }.map(\.request)
    }

    static func bodies(forHost host: String) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        return recorded.filter { $0.host == host }.map(\.body)
    }

    private static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

private func v0351TempHome() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("v0351-home-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 이번 달 Claude 기록 한 줄(assistant · usage)을 임시 홈의 `~/.claude/projects` 에 쓴다.
private func v0351WriteClaudeLog(into home: URL, input: Int) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = "{\"type\":\"assistant\",\"timestamp\":\"\(formatter.string(from: Date()))\","
        + "\"requestId\":\"req_v0351\",\"message\":{\"id\":\"msg_v0351\",\"usage\":{\"input_tokens\":\(input)}}}\n"
    let file = home.appendingPathComponent(".claude/projects/p/session.jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(line.utf8).write(to: file)
}

@MainActor
private func v0351Height(_ view: some View, width: CGFloat) -> CGFloat? {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return CGFloat(bitmap.pixelsHigh) / 2
}

private enum V0351Error: Error { case renderFailed }

/// 설정 창 본문을 폭 하한(380)에서 그린 높이(pt). 다른 높이 스위트(V0340 · V0347)와 같은 시드: 센터 확인 · 단축키 안내 한 줄(가장 높은 상태).
@MainActor
private func v0351SettingsHeight(function: String = #function, line: Int = #line,
                                 _ configure: (WorkTimerStore) -> Void) throws -> CGFloat {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: CheckTestScratch.defaults("settings-L\(line)", function: function),
        workspaceNotifications: nil
    )
    store.myCenterLoaded = true
    store.myCenter = CenterLabel.seoul
    store.workShortcutStatus = .conflict
    configure(store)
    let characters = CheckTestScratch.defaults("chars-L\(line)", function: function)
    guard let height = v0351Height(
        CheckSettingsView(store: store, launchAtLoginSeed: false, characterDefaults: characters),
        width: CheckSettingsView.preferredWidth
    ) else { throw V0351Error.renderFailed }
    return height
}

/// 설정 창 본문을 그려 **위험색(CheckTheme.danger ≈ 1.0/0.45/0.46) 계열 픽셀**을 센다. 시드는 높이 헬퍼와 같되 단축키 충돌
/// 안내는 세우지 않는다(그 줄도 빨강이라 기준선을 흐린다). 글자 가장자리의 섞인 색까지 잡도록 '빨강이 초록·파랑보다 확연히 큰' 픽셀로 센다.
@MainActor
private func v0351SettingsRedPixels(function: String = #function, line: Int = #line,
                                   _ configure: (WorkTimerStore) -> Void) throws -> Int {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: CheckTestScratch.defaults("red-L\(line)", function: function),
        workspaceNotifications: nil
    )
    store.myCenterLoaded = true
    store.myCenter = CenterLabel.seoul
    configure(store)
    let characters = CheckTestScratch.defaults("red-chars-L\(line)", function: function)
    let view = CheckSettingsView(store: store, launchAtLoginSeed: false, characterDefaults: characters)
        .frame(width: CheckSettingsView.preferredWidth).fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3
    else { throw V0351Error.renderFailed }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            if r >= 120 && r - g >= 50 && r - b >= 50 { count += 1 }
        }
    }
    return count
}

/// 공백(줄바꿈·들여쓰기)을 한 칸으로 접는다 — 소스 조각을 줄 모양과 무관하게 찾는다.
private func v0351Collapsed(_ source: String) -> String {
    source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// `anchor` 뒤 첫 `{` 부터 짝이 맞는 `}` 까지(양 끝 괄호 포함)와, 그 `}` 바로 뒤 위치. 문자열 리터럴 안의 괄호는 건너뛴다.
private func v0351Closure(after anchor: String, in source: String) -> (body: String, end: String.Index)? {
    guard let hit = source.range(of: anchor) else { return nil }
    return v0351BraceBlock(from: hit.upperBound, in: source)
}

/// 앞 클로저(`previous`) 바로 뒤에 붙은 **이름표 달린 꼬리 클로저**(`label: { … }`). 다른 것이 끼어 있으면 nil.
private func v0351TrailingClosure(labeled label: String, after previous: (body: String, end: String.Index),
                                  in source: String) -> (body: String, end: String.Index)? {
    let rest = source[previous.end...].drop { $0.isWhitespace }
    guard rest.hasPrefix("\(label): {") else { return nil }
    return v0351BraceBlock(from: rest.startIndex, in: source)
}

private func v0351BraceBlock(from start: String.Index, in source: String) -> (body: String, end: String.Index)? {
    guard let open = source[start...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var index = open
    while index < source.endIndex {
        let c = source[index]
        if inString {
            if c == "\\" {
                index = source.index(after: index)
                if index == source.endIndex { break }
            } else if c == "\"" {
                inString = false
            }
        } else if c == "\"" {
            inString = true
        } else if c == "{" {
            depth += 1
        } else if c == "}" {
            depth -= 1
            if depth == 0 {
                let end = source.index(after: index)
                return (String(source[open..<end]), end)
            }
        }
        index = source.index(after: index)
    }
    return nil
}

// MARK: 소스 읽기 · `#if` 해석

/// 맥 앱이 컴파일하는 두 소스 폴더(Sources/check · Sources/CheckCore)의 Swift 파일 전부(주석 걷어냄).
private func v0351AllSources() throws -> [(String, String)] {
    var out: [(String, String)] = []
    for directory in [CheckCoreSourceLayout.macDirectory, CheckCoreSourceLayout.coreDirectory] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }
        for name in names.sorted() {
            let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            out.append((name, V0351IfConfig.strippingComments(text)))
        }
    }
    return out
}

private func v0351Source(_ name: String) throws -> String {
    let directory = FileManager.default.fileExists(atPath: CheckCoreSourceLayout.macDirectory.appendingPathComponent(name).path)
        ? CheckCoreSourceLayout.macDirectory : CheckCoreSourceLayout.coreDirectory
    return V0351IfConfig.strippingComments(try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8))
}

/// 이 바늘들이 **전부** 앱스토어 판에서 컴파일되지 않는 줄에만 있는가(하나도 없으면 빨강 — 헛도는 검사를 막는다).
private func v0351ExpectExcluded(_ file: String, _ needles: [String],
                                 sourceLocation: SourceLocation = #_sourceLocation) throws {
    let source = try v0351Source(file)
    let excluded = V0351IfConfig.linesExcludedUnderMAS(source)
    let lines = source.components(separatedBy: "\n")
    for needle in needles {
        let hits = lines.indices.filter { lines[$0].contains(needle) }
        #expect(!hits.isEmpty, "\(file) 에 '\(needle)' 이 없다 — 이 계약이 헛돈다", sourceLocation: sourceLocation)
        for index in hits {
            #expect(excluded.contains(index), "\(file):\(index + 1) '\(needle)' 이 앱스토어 판에서도 컴파일된다",
                    sourceLocation: sourceLocation)
        }
    }
}

/// 이 바늘들이 앱스토어 판에서도 **남는** 줄에 있는가.
private func v0351ExpectIncluded(_ file: String, _ needles: [String],
                                 sourceLocation: SourceLocation = #_sourceLocation) throws {
    let source = try v0351Source(file)
    let excluded = V0351IfConfig.linesExcludedUnderMAS(source)
    let lines = source.components(separatedBy: "\n")
    for needle in needles {
        let hits = lines.indices.filter { lines[$0].contains(needle) }
        #expect(!hits.isEmpty, "\(file) 에 '\(needle)' 이 없다", sourceLocation: sourceLocation)
        #expect(hits.contains { !excluded.contains($0) }, "\(file) '\(needle)' 이 앱스토어 판에서 사라졌다",
                sourceLocation: sourceLocation)
    }
}

private extension String {
    func v0351Line(_ index: Int) -> String {
        let lines = components(separatedBy: "\n")
        return lines.indices.contains(index) ? lines[index] : ""
    }
}

/// `#if` 해석기(테스트 전용 · 이 저장소의 조건 모양만 안다). **앱스토어 판(`CHECK_MAS` 정의 · macOS)에서 컴파일되지 않는 줄**을 돌려준다.
///
/// 아는 조건: `CHECK_MAS` · `!CHECK_MAS` · `os(macOS)`(참) · `os(iOS)`(거짓) 와 그 `&&` 조합. 나머지(`DEBUG` · `canImport` …)는
/// '모름'이라 **빼지 않은 것**으로 친다 — 모르는 울타리를 '빠진다'로 읽으면 이 계약이 거짓 초록이 된다(안전한 쪽으로 기운다).
enum V0351IfConfig {
    private enum Truth { case yes, no, unknown }

    private static func evaluate(_ raw: String) -> Truth {
        let condition = raw.replacingOccurrences(of: " ", with: "")
        if condition.contains("||") { return .unknown }
        var result = Truth.yes
        for part in condition.components(separatedBy: "&&") {
            switch part {
            case "CHECK_MAS", "os(macOS)": continue
            case "!CHECK_MAS", "os(iOS)", "!os(macOS)": return .no
            default: result = .unknown
            }
        }
        return result
    }

    static func linesExcludedUnderMAS(_ source: String) -> Set<Int> {
        struct Frame { var branches: [Truth]; var current: Truth }
        var stack: [Frame] = []
        var excluded = Set<Int>()
        for (index, rawLine) in source.components(separatedBy: "\n").enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#if ") {
                let truth = evaluate(String(line.dropFirst(4)))
                stack.append(Frame(branches: [truth], current: truth))
                continue
            }
            if line.hasPrefix("#elseif "), var frame = stack.popLast() {
                let truth: Truth
                if frame.branches.contains(.yes) { truth = .no }
                else if frame.branches.allSatisfy({ $0 == .no }) { truth = evaluate(String(line.dropFirst(8))) }
                else { truth = evaluate(String(line.dropFirst(8))) == .no ? .no : .unknown }
                frame.branches.append(truth)
                frame.current = truth
                stack.append(frame)
                continue
            }
            if line == "#else", var frame = stack.popLast() {
                let truth: Truth
                if frame.branches.contains(.yes) { truth = .no }
                else if frame.branches.allSatisfy({ $0 == .no }) { truth = .yes }
                else { truth = .unknown }
                frame.branches.append(truth)
                frame.current = truth
                stack.append(frame)
                continue
            }
            if line.hasPrefix("#endif") {
                _ = stack.popLast()
                continue
            }
            if stack.contains(where: { $0.current == .no }) { excluded.insert(index) }
        }
        return excluded
    }

    /// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(줄 수는 지킨다 — 줄 번호로 판정하므로). 문자열 리터럴 안의 `//` 는 남긴다.
    static func strippingComments(_ source: String) -> String {
        var out = ""
        var chars = Array(source)
        var i = 0
        var inString = false
        var inMultilineString = false
        var blockDepth = 0
        func peek(_ offset: Int) -> Character? { i + offset < chars.count ? chars[i + offset] : nil }
        while i < chars.count {
            let c = chars[i]
            if blockDepth > 0 {
                if c == "*", peek(1) == "/" { blockDepth -= 1; i += 2; continue }
                if c == "/", peek(1) == "*" { blockDepth += 1; i += 2; continue }
                if c == "\n" { out.append("\n") }
                i += 1
                continue
            }
            if inMultilineString {
                if c == "\"", peek(1) == "\"", peek(2) == "\"" { inMultilineString = false; out += "\"\"\""; i += 3; continue }
                out.append(c); i += 1; continue
            }
            if inString {
                if c == "\\", let next = peek(1) { out.append(c); out.append(next); i += 2; continue }
                if c == "\"" { inString = false }
                if c == "\n" { inString = false }
                out.append(c); i += 1; continue
            }
            if c == "\"", peek(1) == "\"", peek(2) == "\"" { inMultilineString = true; out += "\"\"\""; i += 3; continue }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", peek(1) == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", peek(1) == "*" { blockDepth = 1; i += 2; continue }
            out.append(c)
            i += 1
        }
        chars.removeAll()
        return out
    }
}
