import CoreImage
import SwiftUI
import CheckCore

// MARK: - QR 코드 (v0.3.40 — 아이폰 앱 설치 안내)
//
// 외부 의존성 없이 macOS 내장 CoreImage(`CIQRCodeGenerator`)로 만든다. 여기는 **"문자열 → 그림"** 뿐이다 —
// 화면에서 몇 pt 로, 어떤 여백으로 놓을지는 부르는 쪽(공지 카드·설정 행)이 정한다.

/// 문자열 하나를 QR 비트맵으로 바꾼다. 실패(빈 문자열·너무 긴 문자열)는 nil — 부르는 쪽은 QR 자리를 **통째로 비운다**
/// (빈 상자를 그리지 않는다. 찍을 수 없는 네모는 사용자를 속이는 그림이다).
enum CheckQRCode {
    /// 오류 정정 레벨 **M(15%)**. 근거(실측 2026-09-28, 앱스토어 주소 38바이트):
    ///   L · M → 29 모듈(버전 3), Q → 33(버전 4), H → 37(버전 5).
    /// 같은 pt 안에 모듈이 많을수록 모듈 하나가 작아져 카메라가 못 읽는다. L 과 M 은 이 길이에서 **모듈 수가 같다** —
    /// M 은 공짜로 15% 복원력(화면 글레어·모아레·손떨림)을 얹는다. Q 부터는 모듈이 12% 작아지는데, 화면에 그리는 코드는
    /// 인쇄물처럼 찢기거나 더러워지지 않으므로 그 대가를 치를 이유가 없다.
    static let correctionLevel = "M"

    /// 모듈 하나를 몇 픽셀로 굽는가. 화면은 이 그림을 **보간 없이**(`interpolation(.none)`) 목표 크기로 줄여 그린다 —
    /// 늘리면 흐릿한 모서리가 생기고 그게 곧 오독이다. 10 이면 카드의 72pt(레티나 144px ÷ 31모듈 ≈ 4.6px/모듈)까지
    /// 늘 **줄이는 쪽**이라 모듈 경계가 선명하다.
    static let pixelsPerModule = 10

    /// 바이트 모드 · 레벨 M 의 규격 상한(버전 40 = 2,331바이트). 그 위는 CIQRCodeGenerator 도 nil 을 낸다(실측 2026-09-28:
    /// 2,953·3,000바이트 → nil) — 애초에 부르지 않고 nil 로 답한다.
    static let maxInputBytes = 2_331

    /// 렌더 문맥은 하나면 된다(만들 때마다 세우면 렌더마다 수 ms 가 든다). 소프트웨어 렌더러 — GPU 유무·헤드리스 테스트에 무관하게 같은 픽셀.
    private static let context = CIContext(options: [.useSoftwareRenderer: true])

    /// 문자열 → 흰 바탕·검은 모듈 비트맵(CI 출력은 사방 1모듈 조용 영역을 이미 포함한다 — 실측 31×31 = 29 + 2).
    static func image(for string: String) -> CGImage? {
        guard !string.isEmpty, let payload = string.data(using: .utf8), payload.count <= maxInputBytes,
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(payload, forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // 최근접 샘플링으로 키운다 — 기본(양선형)으로 키우면 모듈 경계가 회색 띠가 된다.
        let scaled = output.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: CGFloat(pixelsPerModule), y: CGFloat(pixelsPerModule)))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

/// QR 한 장을 **흰 판 위에** 그린다. 크기(`side`, 코드 한 변 pt)는 부르는 쪽이 준다.
///
/// 왜 테마를 안 따르는가: QR 은 **명암 반전에 약하다.** 대부분의 스캐너(아이폰 카메라 포함)가 "밝은 바탕에 어두운
/// 모듈"을 전제하고 찾는다 — 이 앱의 카드는 어두운 남색이라 검은 모듈을 그 위에 바로 놓으면 코드 자체가 사라지고,
/// 모듈을 밝게 뒤집으면(반전) 못 읽는 폰이 많다. 그래서 다크/라이트·카드 색과 무관하게 **항상 흰 판 + 검은 코드**다.
/// 흰 판의 여백(`quietZone`)이 곧 QR 규격의 조용 영역이다: 규격은 4모듈인데 CI 출력이 1모듈을 품고 있어 나머지 3모듈
/// (72pt 기준 모듈 2.3pt × 3 ≈ 7pt)을 판 여백으로 준다 — 8pt 면 카드 색이 코드 가장자리에 붙지 않는다.
struct CheckQRCodeView: View {
    let image: CGImage
    /// 코드 한 변(pt). 판은 여기에 사방 `quietZone` 을 더한 크기다.
    let side: CGFloat

    static let quietZone: CGFloat = 8
    /// 판 모서리. 여백(8)보다 작아야 둥근 모서리가 조용 영역 안쪽을 깎지 않는다.
    static let plateCornerRadius: CGFloat = 6

    /// 판 한 변(pt). 높이 예산이 이 값을 읽는다.
    static func plateSide(for side: CGFloat) -> CGFloat { side + quietZone * 2 }

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            // 줄일 때도 보간 없이 — 회색 경계가 생기면 모듈 판정이 흔들린다.
            .interpolation(.none)
            .frame(width: side, height: side)
            .padding(Self.quietZone)
            // 테마 토큰이 아니라 순백이다(위 머리 주석) — CheckTheme 에 흰 판 토큰을 만들지 마라.
            .background(
                RoundedRectangle(cornerRadius: Self.plateCornerRadius, style: .continuous)
                    .fill(Color.white)
            )
            .accessibilityLabel("QR 코드")
    }
}
