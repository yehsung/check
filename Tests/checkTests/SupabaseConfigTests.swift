import Foundation
import Testing
@testable import check

@Test
func loadsProvidedProjectURL() {
    #expect(SupabaseConfig.projectURL.absoluteString == "https://xfnhfjvubetkdnfkfljg.supabase.co")
}

@Test
func loadsProvidedTeamIdentity() {
    #expect(SupabaseConfig.teamID == "10000000-0000-0000-0000-000000000001")
    #expect(SupabaseConfig.teamName == "sudo 박수")
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

private func makeConfigBundle(anonKey: String) throws -> Bundle {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
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
