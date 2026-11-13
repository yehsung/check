import Foundation

/// 스캐너 빌드 상수. 서버 주소는 맥 앱(SupabaseConfig.projectURL)과 같다.
enum AingScanBuild {
    /// 스캐너 자체 판 번호(설치 명령·상태 표시용).
    static let version = "0.1.0"

    /// 공유 읽기 코드를 떼어 온 **맥 앱 빌드**. 하루 한 번 진단(codex_diag_*)에 실려 서버에 간다 —
    /// 순위판의 Codex 안전 게이트(`codex_diag_build >= 52`, 20260907140000)가 이 값으로 이 기기의 로컬 Codex 를 센다.
    /// 공유 파일(Sources/CheckCore 의 토큰 스캐너)을 바꾼 앱 판에서 스캐너를 다시 낼 때 그 빌드로 올린다.
    static let sharedCodeAppBuild = 131

    /// 운영 서버(맥 앱과 같은 프로젝트). 시험은 `AING_SCAN_SERVER` 로 바꾼다.
    static let defaultServer = URL(string: "https://xfnhfjvubetkdnfkfljg.supabase.co")!

    /// 공개 anon 키. 저장소에는 두지 않는다(맥 앱도 빌드 때 CheckConfig.plist 로 넣는다) —
    /// 릴리스 빌드가 이 줄을 CI 비밀로 채운 사본으로 컴파일한다. 비어 있으면 `AING_SCAN_ANON_KEY` 를 읽는다.
    static let embeddedAnonKey: String? = nil
}
