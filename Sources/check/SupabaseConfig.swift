import Foundation

enum SupabaseConfig {
    static let projectURL = URL(string: "https://xfnhfjvubetkdnfkfljg.supabase.co")!
    // 멀티팀 전환: 팀 식별자(teamID)/팀 이름(teamName) 하드코딩은 모두 제거했다. 팀 이름은 로그인 후
    // store.teamName(멤버십 조회로 확정)이 유일한 출처이고, 뷰는 이를 그대로 표시한다.
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
