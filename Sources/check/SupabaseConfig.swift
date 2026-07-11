import Foundation

enum SupabaseConfig {
    static let projectURL = URL(string: "https://xfnhfjvubetkdnfkfljg.supabase.co")!
    static let teamID = "10000000-0000-0000-0000-000000000001"
    static let teamName = "sudo 박수"
    static let anonKeyEnvironmentName = "CHECK_SUPABASE_ANON_KEY"

    static func anonKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> String? {
        let key = environment[anonKeyEnvironmentName]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if key?.isEmpty == false {
            return key
        }

        return bundledAnonKey(bundle: bundle)
    }

    private static func bundledAnonKey(bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "CheckConfig", withExtension: "plist"),
              let data = NSDictionary(contentsOf: url),
              let key = data[anonKeyEnvironmentName] as? String
        else {
            return nil
        }

        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedKey.isEmpty ? nil : trimmedKey
    }
}
