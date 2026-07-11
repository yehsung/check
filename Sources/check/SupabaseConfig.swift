import Foundation

enum SupabaseConfig {
    static let projectURL = URL(string: "https://xfnhfjvubetkdnfkfljg.supabase.co")!
    // 멀티팀 전환: 팀 식별자(teamID) 하드코딩은 제거하고 서비스/스토어가 팀을 파라미터로 전달한다.
    // teamName 은 로그인 전(비인증) 헤더의 기본 표시에만 남아 있는 뷰 소유 상수라 여기 유지한다.
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
