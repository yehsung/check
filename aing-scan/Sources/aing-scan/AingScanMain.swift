import Foundation

/// 진입점. 명령: link <코드> · run · status · unlink · version.
@main
struct AingScanMain {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        let env = ScanEnvironment.live()
        let commands = ScanCommands(env: env)
        guard let command = args.first else {
            printUsage()
            exit(ScanExit.usage.rawValue)
        }
        args.removeFirst()
        let code: ScanExit
        switch command {
        case "link":
            var name: String?
            var force = false
            var schedule = true
            var positional: [String] = []
            var i = 0
            while i < args.count {
                switch args[i] {
                case "--name" where i + 1 < args.count:
                    name = args[i + 1]
                    i += 1
                case "--force": force = true
                case "--no-schedule": schedule = false
                default: positional.append(args[i])
                }
                i += 1
            }
            // 코드는 인자나 표준입력(AING_SCAN_CODE)으로 받는다 — 설치 스크립트는 환경 변수로 넘긴다.
            let raw = positional.first ?? env.environment["AING_SCAN_CODE"] ?? ""
            code = await commands.link(code: raw, name: name, force: force, schedule: schedule)
        case "run":
            // 예약 실행은 인자 없이 `run` — 사람이 친 `run` 과 같다. 출력은 예약 쪽이 버린다.
            code = await commands.run(quiet: args.contains("--quiet"))
        case "status":
            code = commands.status()
        case "unlink":
            code = await commands.unlink()
        case "version", "--version", "-v":
            // 배포판은 서버 키가 들어 있다 — 개발판이면 그렇다고 밝힌다(릴리스 확인이 이 줄을 본다).
            print("aing-scan \(AingScanBuild.version)" + (AingScanBuild.embeddedAnonKey == nil ? " (개발판)" : ""))
            code = .ok
        default:
            printUsage()
            code = .usage
        }
        exit(code.rawValue)
    }

    static func printUsage() {
        print("""
        아잉체크 스캐너 \(AingScanBuild.version) — 이 기기의 AI 토큰 사용량(숫자만)을 아잉체크 계정에 올립니다.

          aing-scan link <연결코드>   맥 아잉체크 → 설정 → [다른 기기 또는 서버 연결]에서 받은 코드로 연결
          aing-scan run              지금 한 번 집계해 올리기(평소엔 10분마다 저절로)
          aing-scan status           연결·마지막 집계 보기
          aing-scan unlink           연결 끊기(자동 실행도 꺼짐)
        """)
    }
}
