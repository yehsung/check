import SwiftUI
import CheckCore

// MARK: - 아이폰 앱 안내 문구 (v0.3.40)

/// 아이폰 앱을 찾는 문구 한 벌. **순수 값이라 테스트가 글자 그대로 되묻는다** — 팝오버 공지 카드의 캡션과 설정의
/// 설치 QR 행이 같은 상수를 읽어, 검색어를 바꿀 일이 생기면 여기 한 줄만 고친다.
enum CheckIOSAppText {
    /// 앱스토어 **등록명 그대로** — 띄어쓰기 없이 "아잉체크"다(통합자 공개 조회 2026-09-28, `itunes.apple.com/lookup?id=6812768622`).
    /// 사용자는 "아잉 체크"로 말했지만 띄어 써서 검색해도 1위로 잡히므로 붙여 쓴 이름 하나로 둘 다 덮는다.
    /// ★ "아잉" 한 단어만 쓰지 마라 — 그 검색어로는 7위이고 위 여섯 개가 전부 데이팅·마사지 앱이다(같은 조회 실측).
    static let storeSearchName = "아잉체크"

    /// 팝오버 공지 카드 캡션. 검색어 + 최소 iOS — 서버 본문에는 이 둘을 넣지 않는다(설정 행과 같은 상수라 여기서만 바뀐다).
    static var noticeCaption: String {
        "앱스토어 검색 \(storeSearchName) · \(CheckAppLinks.iosMinimumVersionText)"
    }

    static let settingsTitle = "아이폰 앱"
    /// 설정 행 설명. QR 이 먼저, 검색어가 다음이다 — 찍는 쪽이 빠르고, 검색은 QR 을 못 찍는 사람의 길이다.
    /// 최소 iOS 는 **둘째 줄**에 따로 둔다(줄바꿈 명시): 글 열이 QR 판(88pt) 옆 228pt 라 한 문장에 이어 붙이면 "· iOS 18 이상"
    /// 만 다음 줄로 떨어져 부스러기처럼 보였다(실측 2026-09-28). 행 높이는 판이 정하므로 줄이 하나 늘어도 창 계약은 그대로다.
    static var settingsDetail: String {
        "QR 을 찍거나 앱스토어에서 \(storeSearchName)를 검색하세요\n\(CheckAppLinks.iosMinimumVersionText)에서 쓸 수 있어요"
    }
}

// MARK: - 팝오버 공지 카드

/// 팝오버 최상단 공지 카드(제목 · 본문 · QR · 닫기). **업데이트 배너와 같은 형제 슬롯**에 서고, 그 슬롯의 "한 번에 하나"
/// 예산(`CheckMenuView.TopBanner`)을 그대로 따른다 — 더 급한 배너가 있으면 이번 팝오버에서는 양보한다.
///
/// 크롬은 팝오버 카드들의 공용 `panelStyle()` 이다(헤더 카드·팀 카드와 한 몸으로 보인다). 업데이트 배너의 파란 틴트를
/// 베끼지 않은 이유: 저 틴트는 "지금 눌러 처리할 일"의 색이고, 이 카드는 읽고 닫는 안내다.
///
/// 높이는 **QR 판이 정한다**: 본문은 최대 3줄이라 글 열(3줄 + 캡션)이 판(88pt)보다 낮아, 본문 길이와 무관하게
/// 카드 높이가 한 값이다(`CheckMenuView.appNoticeCardHeight`). QR 이 없으면 글 열이 높이를 정하므로 그 예산은 본문 3줄
/// 최악값으로 잡는다(`appNoticeCardHeightWithoutQR` — 과대 추정은 안전측, 목록 행이 하나 덜 보일 뿐이다).
struct AppNoticeCard: View {
    let notice: AppNotice
    let onDismiss: () -> Void

    /// QR 한 변(pt). 근거는 실제 화면 밀도다: 가장 촘촘한 맥 화면(MacBook Pro 254ppi, 1pt = 0.2mm)에서 72pt 는
    /// **14.4mm**, 앱스토어 주소(31모듈)의 모듈 하나가 0.46mm 다. 아이폰 카메라는 10~20cm 거리에서 1.5cm 안팎의 코드를
    /// 무리 없이 읽는다(최소 초점 거리 안에서 프레임의 10% 남짓 — 모듈당 센서 픽셀 5개 이상). 외장 모니터(1x, 96~110ppi)
    /// 에서는 같은 72pt 가 17~19mm 라 더 넉넉하다. 더 키우면 팝오버 높이 예산(700pt)을 그만큼 먹는다.
    static let qrSide: CGFloat = 72
    /// 본문 줄 상한. 서버 문구가 길어도 카드 높이가 예측 가능해야 팝오버 높이 예산이 산다(업데이트 배너의 노트 lineLimit 과 같은 이유).
    static let bodyLineLimit = 3

    /// QR 을 그릴 수 있는가 — 주소가 있고 **실제로 그림이 나올 때만** true. 주소가 있어도 생성이 실패하면 자리를 통째로 비운다.
    static func qrImage(for notice: AppNotice) -> CGImage? {
        notice.linkURL.flatMap(CheckQRCode.image(for:))
    }

    /// 본문 아래 캡션. 링크가 아이폰 앱스토어면 검색어·최소 iOS 를 **클라 상수**로 붙인다(서버는 클라의 최소 iOS 문구를
    /// 모르고, 설정 행과 같은 상수여야 한 곳만 고쳐도 둘이 같이 바뀐다). 그 밖의 링크는 서버가 준 `linkLabel` 을 그대로 쓴다.
    static func caption(for notice: AppNotice) -> String? {
        if let link = notice.linkURL, link.hasPrefix(CheckAppLinks.iosAppStore.absoluteString) {
            return CheckIOSAppText.noticeCaption
        }
        return notice.linkLabel
    }

    var body: some View {
        let qr = Self.qrImage(for: notice)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "iphone")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                Text(notice.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                // 닫기 = `store.dismissAppNotice()` 한 줄. 기기별 영속이라 같은 공지는 다시 안 뜬다.
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .checkTooltip("닫기")
                .accessibilityLabel("공지 닫기")
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.body)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(Self.bodyLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption = Self.caption(for: notice) {
                        Text(caption)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CheckTheme.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let qr {
                    CheckQRCodeView(image: qr, side: Self.qrSide)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }
}
