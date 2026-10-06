import SwiftUI

// MARK: - 제공자 로고 (실제 벡터) + 브랜드색 — 맥·폰·위젯이 한 소스를 쓴다
//
// 로고 패스 출처: CodexBar (MIT License, github.com/steipete/CodexBar) —
// `/Applications/CodexBar.app/Contents/Resources/ProviderIcon-{claude,codex,antigravity}.svg`
// 세 파일 모두 `viewBox="0 0 100 100"` 의 단일 path · `fill="white"` 단색 실루엣이다. 아래 Path 코드는 그
// path 명령(M/L/H/V/C/Z)을 좌표 그대로 옮긴 것이다(H/V 는 절대 좌표로 풀었고, 상대 명령은 원본에 없다).
// 상표는 **어느 서비스의 리밋인지 식별하는 용도**(지시적 사용)로만 쓴다 — 앱 아이콘·브랜딩에 쓰지 않는다.
//
// ## 왜 이미지 파일이 아니라 코드인가
// 이 저장소에는 맥·폰·위젯이 **공유하는 이미지 리소스 경로가 아예 없다**:
//   · `CheckCore` 는 리소스 선언이 0건이다(Package.swift).
//   · 맥 앱 타깃은 `CheckMobileShared` 를 링크하지 않는다 — 폰이 쓰는 그림 자리를 맥은 못 본다.
//   · `ios/App/Assets.xcassets` 에 넣은 그림은 **위젯 확장 타깃이 못 본다**(별 번들이다).
// 이미지로 가면 캐릭터 아트처럼 에셋을 타깃마다 복제하고 픽셀 동치 테스트를 한 벌 더 만들어야 한다.
// 세 로고가 전부 **단일 패스**라서 코드로 그리면 세 타깃이 한 소스를 쓰고, 어떤 크기에서도 선명하며,
// 위젯 틴트 모드(색을 통째로 버리는 단색 렌더링)에서도 실루엣으로 구분된다. 결과물은 진짜 로고 그대로다.
//
// ## 색으로만 구분하지 않는다
// 위젯 틴트 모드는 브랜드색을 버린다. 그래서 타일 옆에는 **항상 이름 글자**(`AILimitProvider.compactName`)가
// 있어야 한다 — 색은 보조 신호다. 이 규약은 뷰 쪽에서 지켜야 하는 것이라 여기 적어 둔다.

/// 제공자 로고를 그리는 `Shape`. 원본 좌표계(100×100)를 `rect` 에 **비율 유지 + 중앙 정렬**로 맞춘다.
///
/// `Shape` 라서 색은 호출부가 정한다(`.fill(.white)` · 위젯 틴트의 단색). 여기서 색을 굽지 않는다 —
/// 굽으면 틴트 모드에서 타일과 마크가 같은 색이 돼 마크가 사라진다.
package struct AIProviderMark: Shape {
    package let provider: AILimitProvider

    package init(_ provider: AILimitProvider) {
        self.provider = provider
    }

    package func path(in rect: CGRect) -> Path {
        AIProviderLogoPath.path(for: provider, in: rect)
    }
}

/// 세 로고의 패스 데이터. `AIProviderMark` 와 테스트만 부른다.
package enum AIProviderLogoPath {
    /// 원본 SVG 좌표계의 한 변. 세 파일 모두 `viewBox="0 0 100 100"` 이다.
    package static let designSize: CGFloat = 100

    /// `rect` 안에 비율을 지켜 중앙 정렬로 그린 패스.
    ///
    /// 빈 rect(폭·높이 0 — 레이아웃 첫 패스나 썸네일 캡처에서 실제로 온다)에는 **빈 패스**를 준다.
    /// 0 으로 나누면 좌표가 NaN 이 되고, NaN 이 섞인 Path 는 그 프레임을 통째로 안 그린다.
    package static func path(for provider: AILimitProvider, in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }
        let scale = min(rect.width, rect.height) / designSize
        let originX = rect.minX + (rect.width - designSize * scale) / 2
        let originY = rect.minY + (rect.height - designSize * scale) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }
        switch provider {
        case .claude: appendClaude(&path, p)
        case .codex: appendCodex(&path, p)
        case .antigravity: appendAntigravity(&path, p)
        }
        return path
    }

    private typealias Mapper = (CGFloat, CGFloat) -> CGPoint

    /// Anthropic 선버스트(12갈래). 원본: ProviderIcon-claude.svg — 단일 서브패스, 직선뿐이고 끝에서 닫힌다.
    private static func appendClaude(_ path: inout Path, _ p: Mapper) {
        path.move(to: p(25.7146, 63.2153))
        path.addLine(to: p(41.4393, 54.3917))
        path.addLine(to: p(41.7025, 53.6226))
        path.addLine(to: p(41.4393, 53.1976))
        path.addLine(to: p(40.6705, 53.1976))
        path.addLine(to: p(38.0394, 53.0359))
        path.addLine(to: p(29.054, 52.7929))
        path.addLine(to: p(21.2624, 52.4691))
        path.addLine(to: p(13.7134, 52.0644))
        path.addLine(to: p(11.8111, 51.6594))
        path.addLine(to: p(10.0303, 49.3118))
        path.addLine(to: p(10.2123, 48.138))
        path.addLine(to: p(11.8111, 47.0657))
        path.addLine(to: p(14.0981, 47.2681))
        path.addLine(to: p(19.1574, 47.6119))
        path.addLine(to: p(26.7467, 48.138))
        path.addLine(to: p(32.2516, 48.4618))
        path.addLine(to: p(40.4073, 49.3118))
        path.addLine(to: p(41.7025, 49.3118))
        path.addLine(to: p(41.8846, 48.7857))
        path.addLine(to: p(41.4393, 48.4618))
        path.addLine(to: p(41.0955, 48.138))
        path.addLine(to: p(33.243, 42.8155))
        path.addLine(to: p(24.7432, 37.1894))
        path.addLine(to: p(20.2909, 33.9513))
        path.addLine(to: p(17.8824, 32.3119))
        path.addLine(to: p(16.6684, 30.774))
        path.addLine(to: p(16.1422, 27.4147))
        path.addLine(to: p(18.328, 25.0062))
        path.addLine(to: p(21.2624, 25.2088))
        path.addLine(to: p(22.0112, 25.4112))
        path.addLine(to: p(24.9861, 27.6979))
        path.addLine(to: p(31.3407, 32.616))
        path.addLine(to: p(39.6381, 38.7273))
        path.addLine(to: p(40.8525, 39.7391))
        path.addLine(to: p(41.3381, 39.395))
        path.addLine(to: p(41.399, 39.1523))
        path.addLine(to: p(40.8525, 38.2415))
        path.addLine(to: p(36.3394, 30.0858))
        path.addLine(to: p(31.5227, 21.7883))
        path.addLine(to: p(29.3775, 18.3478))
        path.addLine(to: p(28.811, 16.2837))
        path.addCurve(to: p(28.4669, 13.8549), control1: p(28.6087, 15.4334), control2: p(28.4669, 14.7252))
        path.addLine(to: p(30.9563, 10.4753))
        path.addLine(to: p(32.3321, 10.0303))
        path.addLine(to: p(35.6515, 10.4756))
        path.addLine(to: p(37.0479, 11.6897))
        path.addLine(to: p(39.112, 16.4052))
        path.addLine(to: p(42.4513, 23.8327))
        path.addLine(to: p(47.6321, 33.9313))
        path.addLine(to: p(49.15, 36.9265))
        path.addLine(to: p(49.9594, 39.6991))
        path.addLine(to: p(50.2632, 40.5491))
        path.addLine(to: p(50.7894, 40.5491))
        path.addLine(to: p(50.7894, 40.0632))
        path.addLine(to: p(51.2141, 34.3766))
        path.addLine(to: p(52.0035, 27.3944))
        path.addLine(to: p(52.7726, 18.4087))
        path.addLine(to: p(53.0358, 15.8793))
        path.addLine(to: p(54.2905, 12.8435))
        path.addLine(to: p(56.7795, 11.2041))
        path.addLine(to: p(58.7224, 12.135))
        path.addLine(to: p(60.3212, 14.422))
        path.addLine(to: p(60.0986, 15.899))
        path.addLine(to: p(59.1474, 22.0718))
        path.addLine(to: p(57.2857, 31.7458))
        path.addLine(to: p(56.0713, 38.2218))
        path.addLine(to: p(56.7795, 38.2218))
        path.addLine(to: p(57.5892, 37.4121))
        path.addLine(to: p(60.8677, 33.061))
        path.addLine(to: p(66.3723, 26.18))
        path.addLine(to: p(68.801, 23.448))
        path.addLine(to: p(71.6342, 20.4325))
        path.addLine(to: p(73.4556, 18.9957))
        path.addLine(to: p(76.8962, 18.9957))
        path.addLine(to: p(79.4255, 22.7601))
        path.addLine(to: p(78.2926, 26.6456))
        path.addLine(to: p(74.7509, 31.1384))
        path.addLine(to: p(71.8163, 34.943))
        path.addLine(to: p(67.607, 40.6097))
        path.addLine(to: p(64.9758, 45.1431))
        path.addLine(to: p(65.2188, 45.5072))
        path.addLine(to: p(65.8464, 45.4466))
        path.addLine(to: p(75.358, 43.4228))
        path.addLine(to: p(80.4984, 42.4917))
        path.addLine(to: p(86.6304, 41.4393))
        path.addLine(to: p(89.4033, 42.7346))
        path.addLine(to: p(89.7065, 44.0502))
        path.addLine(to: p(88.6135, 46.7419))
        path.addLine(to: p(82.0566, 48.3607))
        path.addLine(to: p(74.3662, 49.8989))
        path.addLine(to: p(62.9118, 52.6109))
        path.addLine(to: p(62.77, 52.7121))
        path.addLine(to: p(62.9321, 52.9144))
        path.addLine(to: p(68.0925, 53.4))
        path.addLine(to: p(70.2987, 53.5214))
        path.addLine(to: p(75.7021, 53.5214))
        path.addLine(to: p(85.7601, 54.2702))
        path.addLine(to: p(88.3912, 56.0108))
        path.addLine(to: p(89.9697, 58.1358))
        path.addLine(to: p(89.7065, 59.7545))
        path.addLine(to: p(85.6589, 61.8189))
        path.addLine(to: p(80.1949, 60.5236))
        path.addLine(to: p(67.4452, 57.4881))
        path.addLine(to: p(63.0735, 56.3952))
        path.addLine(to: p(62.4665, 56.3952))
        path.addLine(to: p(62.4665, 56.7596))
        path.addLine(to: p(66.1093, 60.3213))
        path.addLine(to: p(72.7877, 66.3523))
        path.addLine(to: p(81.1461, 74.1236))
        path.addLine(to: p(81.5707, 76.0462))
        path.addLine(to: p(80.4984, 77.5638))
        path.addLine(to: p(79.3649, 77.4021))
        path.addLine(to: p(72.0186, 71.8772))
        path.addLine(to: p(69.1854, 69.3879))
        path.addLine(to: p(62.77, 63.9844))
        path.addLine(to: p(62.3453, 63.9844))
        path.addLine(to: p(62.3453, 64.5509))
        path.addLine(to: p(63.8223, 66.7164))
        path.addLine(to: p(71.6342, 78.4544))
        path.addLine(to: p(72.0389, 82.0567))
        path.addLine(to: p(71.4725, 83.2308))
        path.addLine(to: p(69.4487, 83.939))
        path.addLine(to: p(67.2222, 83.534))
        path.addLine(to: p(62.6485, 77.1189))
        path.addLine(to: p(57.9333, 69.8937))
        path.addLine(to: p(54.1284, 63.4177))
        path.addLine(to: p(53.6631, 63.6809))
        path.addLine(to: p(51.4167, 87.8651))
        path.addLine(to: p(50.3644, 89.0995))
        path.addLine(to: p(47.9356, 90.0303))
        path.addLine(to: p(45.9121, 88.4924))
        path.addLine(to: p(44.8392, 86.0031))
        path.addLine(to: p(45.9118, 81.0852))
        path.addLine(to: p(47.2071, 74.6701))
        path.addLine(to: p(48.2594, 69.5699))
        path.addLine(to: p(49.2106, 63.2356))
        path.addLine(to: p(49.7773, 61.131))
        path.addLine(to: p(49.7367, 60.9892))
        path.addLine(to: p(49.2715, 61.0498))
        path.addLine(to: p(44.4954, 67.607))
        path.addLine(to: p(37.23, 77.4224))
        path.addLine(to: p(31.4825, 83.5746))
        path.addLine(to: p(30.1063, 84.1211))
        path.addLine(to: p(27.7181, 82.8864))
        path.addLine(to: p(27.9408, 80.6805))
        path.addLine(to: p(29.2763, 78.7177))
        path.addLine(to: p(37.2297, 68.5988))
        path.addLine(to: p(42.026, 62.3248))
        path.addLine(to: p(45.1227, 58.7025))
        path.addLine(to: p(45.1024, 58.176))
        path.addLine(to: p(44.9204, 58.176))
        path.addLine(to: p(23.7917, 71.8975))
        path.addLine(to: p(20.0274, 72.3831))
        path.addLine(to: p(18.4083, 70.8655))
        path.addLine(to: p(18.6106, 68.3761))
        path.addLine(to: p(19.3798, 67.5664))
        path.addLine(to: p(25.7343, 63.195))
        path.addLine(to: p(25.7146, 63.2153))
        path.closeSubpath()
    }

    /// OpenAI 블라썸 매듭. 원본: ProviderIcon-codex.svg — 서브패스 8개(가운데 다이아몬드가 구멍을 만든다).
    ///
    /// ⚠️ **채우기 규칙은 non-zero 여야 한다**(SwiftUI 기본값이고 원본 SVG 도 `fill-rule` 을 안 적었으니 non-zero).
    /// `FillStyle(eoFill: true)` 로 그리면 서브패스가 서로를 지워 매듭이 조각난다.
    private static func appendCodex(_ path: inout Path, _ p: Mapper) {
        path.move(to: p(83.7733, 42.8087))
        path.addCurve(to: p(84.6807, 34.4385), control1: p(84.6678, 40.1149), control2: p(84.9771, 37.2613))
        path.addCurve(to: p(82.0544, 26.4394), control1: p(84.3843, 31.6156), control2: p(83.489, 28.8885))
        path.addCurve(to: p(60.3548, 16.7725), control1: p(77.6908, 18.8436), control2: p(68.9203, 14.9365))
        path.addCurve(to: p(51.5864, 11.0673), control1: p(57.9831, 14.1344), control2: p(54.9591, 12.1668))
        path.addCurve(to: p(41.1402, 10.5084), control1: p(48.2137, 9.96772), control2: p(44.611, 9.77498))
        path.addCurve(to: p(31.8132, 15.2455), control1: p(37.6694, 11.2418), control2: p(34.4527, 12.8755))
        path.addCurve(to: p(26.1024, 24.0103), control1: p(29.1736, 17.6155), control2: p(27.204, 20.6383))
        path.addCurve(to: p(18.3958, 27.405), control1: p(23.3212, 24.5806), control2: p(20.6938, 25.738))
        path.addCurve(to: p(12.7765, 33.6772), control1: p(16.0977, 29.0721), control2: p(14.1819, 31.2104))
        path.addCurve(to: p(15.2527, 57.3327), control1: p(8.36538, 41.2609), control2: p(9.3669, 50.8267))
        path.addCurve(to: p(14.3361, 65.7012), control1: p(14.3549, 60.0251), control2: p(14.0424, 62.8782))
        path.addCurve(to: p(16.9558, 73.7017), control1: p(14.6298, 68.5241), control2: p(15.523, 71.2518))
        path.addCurve(to: p(38.6712, 83.3686), control1: p(21.325, 81.3002), control2: p(30.1011, 85.207))
        path.addCurve(to: p(45.4623, 88.3416), control1: p(40.5554, 85.4904), control2: p(42.8707, 87.1858))
        path.addCurve(to: p(53.6999, 90.0713), control1: p(48.0539, 89.4975), control2: p(50.8622, 90.0871))
        path.addCurve(to: p(72.9393, 76.0515), control1: p(62.4793, 90.079), control2: p(70.2575, 84.4114))
        path.addCurve(to: p(80.6449, 72.6555), control1: p(75.7201, 75.4802), control2: p(78.347, 74.3225))
        path.addCurve(to: p(86.2649, 66.3846), control1: p(82.9427, 70.9886), control2: p(84.8587, 68.8507))
        path.addCurve(to: p(83.7733, 42.8087), control1: p(90.6227, 58.8145), control2: p(89.6172, 49.3005))
        path.closeSubpath()
        path.move(to: p(53.6999, 84.8356))
        path.addCurve(to: p(44.1116, 81.3661), control1: p(50.1955, 84.8411), control2: p(46.801, 83.6129))
        path.addLine(to: p(44.5848, 81.098))
        path.addLine(to: p(60.5123, 71.9043))
        path.addCurve(to: p(61.4674, 70.942), control1: p(60.9087, 71.6718), control2: p(61.2379, 71.3402))
        path.addCurve(to: p(61.8215, 69.6333), control1: p(61.6969, 70.5439), control2: p(61.8189, 70.0929))
        path.addLine(to: p(61.8215, 47.1769))
        path.addLine(to: p(68.5553, 51.072))
        path.addCurve(to: p(68.6814, 51.2456), control1: p(68.6225, 51.1063), control2: p(68.6694, 51.1707))
        path.addLine(to: p(68.6814, 69.854))
        path.addCurve(to: p(53.6999, 84.8356), control1: p(68.6641, 78.1208), control2: p(61.9667, 84.8183))
        path.closeSubpath()
        path.move(to: p(21.4977, 71.0843))
        path.addCurve(to: p(19.7156, 61.0386), control1: p(19.7402, 68.0497), control2: p(19.1092, 64.4925))
        path.addLine(to: p(20.1885, 61.3225))
        path.addLine(to: p(36.1321, 70.5165))
        path.addCurve(to: p(37.4331, 70.87), control1: p(36.5266, 70.748), control2: p(36.9757, 70.87))
        path.addCurve(to: p(38.7341, 70.5165), control1: p(37.8905, 70.87), control2: p(38.3396, 70.748))
        path.addLine(to: p(58.21, 59.2883))
        path.addLine(to: p(58.21, 67.0628))
        path.addCurve(to: p(58.1782, 67.1779), control1: p(58.2081, 67.1031), control2: p(58.1973, 67.1424))
        path.addCurve(to: p(58.0996, 67.2678), control1: p(58.1591, 67.2134), control2: p(58.1322, 67.2441))
        path.addLine(to: p(41.9671, 76.5722))
        path.addCurve(to: p(21.4977, 71.0843), control1: p(34.798, 80.7022), control2: p(25.6388, 78.2463))
        path.closeSubpath()
        path.move(to: p(17.3026, 36.3898))
        path.addCurve(to: p(25.1878, 29.8138), control1: p(19.0723, 33.3357), control2: p(21.8655, 31.0062))
        path.addLine(to: p(25.1878, 48.7376))
        path.addCurve(to: p(25.5261, 50.042), control1: p(25.1818, 49.1949), control2: p(25.2986, 49.6453))
        path.addCurve(to: p(26.4809, 50.9928), control1: p(25.7535, 50.4387), control2: p(26.0833, 50.7671))
        path.addLine(to: p(45.8622, 62.1739))
        path.addLine(to: p(39.1283, 66.069))
        path.addCurve(to: p(39.0101, 66.0984), control1: p(39.0919, 66.0883), control2: p(39.0513, 66.0984))
        path.addCurve(to: p(38.8919, 66.069), control1: p(38.9689, 66.0984), control2: p(38.9283, 66.0883))
        path.addLine(to: p(22.7908, 56.7809))
        path.addCurve(to: p(17.3026, 36.3112), control1: p(15.6359, 52.6337), control2: p(13.1822, 43.4816))
        path.addLine(to: p(17.3026, 36.3898))
        path.closeSubpath()
        path.move(to: p(72.624, 49.2426))
        path.addLine(to: p(53.1792, 37.9512))
        path.addLine(to: p(59.8976, 34.0718))
        path.addCurve(to: p(60.016, 34.0423), control1: p(59.9341, 34.0524), control2: p(59.9747, 34.0423))
        path.addCurve(to: p(60.1344, 34.0718), control1: p(60.0573, 34.0423), control2: p(60.0979, 34.0524))
        path.addLine(to: p(76.2355, 43.3761))
        path.addCurve(to: p(82.0221, 49.4065), control1: p(78.6973, 44.7966), control2: p(80.7043, 46.8882))
        path.addCurve(to: p(83.6775, 57.5985), control1: p(83.3398, 51.9249), control2: p(83.914, 54.7661))
        path.addCurve(to: p(80.6867, 65.4027), control1: p(83.4411, 60.431), control2: p(82.4038, 63.1377))
        path.addCurve(to: p(73.9803, 70.3901), control1: p(78.9696, 67.6677), control2: p(76.6436, 69.3975))
        path.addLine(to: p(73.9803, 51.466))
        path.addCurve(to: p(73.5962, 50.1749), control1: p(73.9663, 51.0096), control2: p(73.834, 50.5647))
        path.addCurve(to: p(72.624, 49.2426), control1: p(73.3584, 49.7851), control2: p(73.0234, 49.4638))
        path.closeSubpath()
        path.move(to: p(79.3261, 39.1657))
        path.addLine(to: p(78.8529, 38.8815))
        path.addLine(to: p(62.9411, 29.6089))
        path.addCurve(to: p(61.6322, 29.2532), control1: p(62.5442, 29.376), control2: p(62.0924, 29.2532))
        path.addCurve(to: p(60.3233, 29.6089), control1: p(61.172, 29.2532), control2: p(60.7202, 29.376))
        path.addLine(to: p(40.8629, 40.8374))
        path.addLine(to: p(40.8629, 33.0628))
        path.addCurve(to: p(40.882, 32.9473), control1: p(40.8587, 33.0233), control2: p(40.8654, 32.9834))
        path.addCurve(to: p(40.9575, 32.8579), control1: p(40.8987, 32.9113), control2: p(40.9248, 32.8803))
        path.addLine(to: p(57.0586, 23.5692))
        path.addCurve(to: p(65.193, 21.5811), control1: p(59.5263, 22.1476), control2: p(62.3478, 21.458))
        path.addCurve(to: p(73.1253, 24.2642), control1: p(68.0382, 21.7042), control2: p(70.7896, 22.6348))
        path.addCurve(to: p(78.3825, 30.782), control1: p(75.461, 25.8936), control2: p(77.2845, 28.1543))
        path.addCurve(to: p(79.3257, 39.1025), control1: p(79.4806, 33.4097), control2: p(79.8077, 36.2957))
        path.addLine(to: p(79.3257, 39.1657))
        path.addLine(to: p(79.3261, 39.1657))
        path.closeSubpath()
        path.move(to: p(37.1888, 52.9484))
        path.addLine(to: p(30.455, 49.069))
        path.addCurve(to: p(30.3707, 48.9884), control1: p(30.4213, 49.0487), control2: p(30.3925, 49.0212))
        path.addCurve(to: p(30.3286, 48.8797), control1: p(30.3488, 48.9557), control2: p(30.3345, 48.9186))
        path.addLine(to: p(30.3286, 30.3188))
        path.addCurve(to: p(32.6761, 22.2822), control1: p(30.3323, 27.4714), control2: p(31.1466, 24.6839))
        path.addCurve(to: p(38.9661, 16.7564), control1: p(34.2057, 19.8805), control2: p(36.3874, 17.9639))
        path.addCurve(to: p(47.2381, 15.4636), control1: p(41.5448, 15.549), control2: p(44.4139, 15.1005))
        path.addCurve(to: p(54.9141, 18.8067), control1: p(50.0622, 15.8267), control2: p(52.7247, 16.9862))
        path.addLine(to: p(54.4409, 19.0748))
        path.addLine(to: p(38.5134, 28.2686))
        path.addCurve(to: p(37.5584, 29.2308), control1: p(38.117, 28.5011), control2: p(37.7879, 28.8327))
        path.addCurve(to: p(37.2045, 30.5395), control1: p(37.329, 29.629), control2: p(37.207, 30.0799))
        path.addLine(to: p(37.1888, 52.9487))
        path.addLine(to: p(37.1888, 52.9484))
        path.closeSubpath()
        path.move(to: p(40.8472, 45.0632))
        path.addLine(to: p(49.5209, 40.0643))
        path.addLine(to: p(58.21, 45.0635))
        path.addLine(to: p(58.21, 55.0615))
        path.addLine(to: p(49.5523, 60.0608))
        path.addLine(to: p(40.8632, 55.0615))
        path.addLine(to: p(40.8472, 45.0632))
        path.closeSubpath()
    }

    /// Antigravity 아치형 'A'. 원본: ProviderIcon-antigravity.svg — 단일 서브패스, 곡선 6개.
    private static func appendAntigravity(_ path: inout Path, _ p: Mapper) {
        path.move(to: p(85.2843, 88.0301))
        path.addCurve(to: p(90.7389, 82.5755), control1: p(90.1329, 91.6664), control2: p(97.4057, 89.2422))
        path.addCurve(to: p(50.1329, 9.84827), control1: p(70.7389, 63.1816), control2: p(74.9813, 9.84827))
        path.addCurve(to: p(9.52673, 82.5755), control1: p(25.2843, 9.84827), control2: p(29.5267, 63.1816))
        path.addCurve(to: p(14.9813, 88.0301), control1: p(2.25402, 89.8483), control2: p(10.1328, 91.6664))
        path.addCurve(to: p(50.1329, 52.8786), control1: p(33.7692, 75.3028), control2: p(32.5571, 52.8786))
        path.addCurve(to: p(85.2843, 88.0301), control1: p(67.7086, 52.8786), control2: p(66.4965, 75.3028))
        path.closeSubpath()
    }
}

/// 제공자 브랜드색. 출처: CodexBar 가 공식 자산에서 감사해 쓰는 값(scratchpad/AI-LIMITS-FACTS.md §8).
///
/// 타일 구조는 "브랜드색 라운드 사각 + 흰 마크" 하나다. 라이트/다크 둘 다에서 보여야 하므로
/// **배경을 테마색이 아니라 브랜드색으로 칠한다** — 그러면 마크의 대비(흰색 대 브랜드색)가 테마와 무관해진다.
package enum AIProviderPalette {
    /// Claude 공식 오렌지 `#D97757`.
    package static let claudeTile = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    /// OpenAI 는 흑백이 공식이다 `#0D0D0D`.
    package static let codexTile = Color(red: 0x0D / 255, green: 0x0D / 255, blue: 0x0D / 255)
    /// 구글 3색 `#4285F4` → `#34A853` → `#FBBC04`.
    package static let googleBlue = Color(red: 0x42 / 255, green: 0x85 / 255, blue: 0xF4 / 255)
    package static let googleGreen = Color(red: 0x34 / 255, green: 0xA8 / 255, blue: 0x53 / 255)
    package static let googleYellow = Color(red: 0xFB / 255, green: 0xBC / 255, blue: 0x04 / 255)

    /// 마크 색. 세 SVG 가 전부 흰 실루엣이므로 세 타일 모두 흰 마크다.
    package static let mark = Color.white

    /// 타일 배경. 안티그래비티만 그라데이션이라 단색 `Color` 가 아니라 `AnyShapeStyle` 로 돌려준다 —
    /// 호출부가 제공자별로 분기하면 한 군데만 그라데이션을 빼먹는 날이 온다.
    package static func tile(for provider: AILimitProvider) -> AnyShapeStyle {
        switch provider {
        case .claude: return AnyShapeStyle(claudeTile)
        case .codex: return AnyShapeStyle(codexTile)
        case .antigravity:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [googleBlue, googleGreen, googleYellow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    /// 어두운 타일(Codex 검정) 위에서는 흰 테두리가, 밝은 타일에서는 검은 테두리가 윤곽을 살린다.
    /// 다크 모드 배경과 Codex 타일이 거의 같은 색이라 테두리가 없으면 타일 자체가 사라진다.
    package static func tileBorder(for provider: AILimitProvider) -> Color {
        switch provider {
        case .codex: return Color.white.opacity(0.22)
        case .claude, .antigravity: return Color.black.opacity(0.12)
        }
    }
}

/// 브랜드색 라운드 사각 + 흰 마크 타일. 맥 카드·폰 카드·위젯이 같은 뷰를 쓴다.
///
/// ★ **이름 글자는 이 뷰가 그리지 않는다.** 타일 옆에 `AILimitProvider.compactName` 을 두는 것은 호출부 몫이다 —
/// 레이아웃(가로 줄/세로 칸)이 자리마다 다르기 때문이다. 색으로만 구분하지 말라는 규약은 그쪽에서 지킨다.
package struct AIProviderTile: View {
    package let provider: AILimitProvider
    package let size: CGFloat

    package init(provider: AILimitProvider, size: CGFloat = 20) {
        self.provider = provider
        self.size = size
    }

    package var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(AIProviderPalette.tile(for: provider))
            .overlay(
                AIProviderMark(provider)
                    .fill(AIProviderPalette.mark)
                    .padding(size * 0.2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(AIProviderPalette.tileBorder(for: provider), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)   // 이름 글자가 옆에 있으므로 이 타일은 장식이다.
    }
}
