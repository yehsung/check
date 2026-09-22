import Foundation
import Testing
@testable import check
@testable import CheckCore

@Test
func loadsProvidedProjectURL() {
    #expect(SupabaseConfig.projectURL.absoluteString == "https://xfnhfjvubetkdnfkfljg.supabase.co")
}

@Test
func anonKeyComesFromEnvironment() {
    let key = SupabaseConfig.anonKey(environment: [
        "CHECK_SUPABASE_ANON_KEY": "local-test-key"
    ])

    #expect(key == "local-test-key")
}

@Test
func emptyAnonKeyIsTreatedAsMissing() {
    let key = SupabaseConfig.anonKey(environment: [
        "CHECK_SUPABASE_ANON_KEY": "   "
    ])

    #expect(key == nil)
}

@Test
func anonKeyFallsBackToBundledConfig() throws {
    let bundle = try makeConfigBundle(anonKey: " bundled-test-key ")
    let key = SupabaseConfig.anonKey(environment: [:], bundle: bundle)

    #expect(key == "bundled-test-key")
}

@Test
func environmentAnonKeyOverridesBundledConfig() throws {
    let bundle = try makeConfigBundle(anonKey: "bundled-test-key")
    let key = SupabaseConfig.anonKey(
        environment: ["CHECK_SUPABASE_ANON_KEY": "environment-test-key"],
        bundle: bundle
    )

    #expect(key == "environment-test-key")
}

private func makeConfigBundle(anonKey: String, function: String = #function) throws -> Bundle {
    // 이름이 UUID 면 지우는 코드가 없어 $TMPDIR 에 .bundle 이 실행마다 쌓인다 — 테스트 신원에서 뽑아 스크래치 뿌리에 둔다.
    let rootURL = CheckTestScratch.directory(function: function)
        .appendingPathComponent("config")
        .appendingPathExtension("bundle")
    let resourcesURL = rootURL
        .appendingPathComponent("Contents")
        .appendingPathComponent("Resources")
    try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

    let configURL = resourcesURL.appendingPathComponent("CheckConfig.plist")
    let config = NSDictionary(dictionary: ["CHECK_SUPABASE_ANON_KEY": anonKey])
    #expect(config.write(to: configURL, atomically: true))

    guard let bundle = Bundle(url: rootURL) else {
        Issue.record("temporary config bundle should load")
        throw CocoaError(.fileNoSuchFile)
    }

    return bundle
}
