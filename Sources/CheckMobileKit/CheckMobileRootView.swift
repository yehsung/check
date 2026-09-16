#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 폰 앱의 루트 화면(D1 골격). D2~D7 에서 탭 다섯 개(지금 · 메시지 · 순위 · 게임 · 나)로 채운다.
///
/// 지금은 **코어가 폰에서 실제로 연결되는지**만 보여 준다 — 맥과 같은 값(오목 판 크기 · 미니게임 종류 ·
/// 별명 상한 · 색 토큰)을 CheckCore 에서 읽어 그린다. 앱 타깃(Xcode)은 이 모듈의 public 만 본다.
public struct CheckMobileRootView: View {
    public init() {}

    public var body: some View {
        ZStack {
            CheckTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("aing-check")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(CheckTheme.primaryText)
                Text("iOS 골격 · CheckCore 연결됨")
                    .font(.headline)
                    .foregroundStyle(CheckTheme.working)
                VStack(alignment: .leading, spacing: 10) {
                    CheckMobileFactRow(label: "오목 판", value: "\(GomokuBoard.size)×\(GomokuBoard.size)")
                    CheckMobileFactRow(label: "미니게임", value: MiniGameKind.allCases.map(\.title).joined(separator: " · "))
                    CheckMobileFactRow(label: "별명 상한", value: "\(CheckCoreShared.displayNameMaxLength)자")
                    CheckMobileFactRow(label: "번들", value: Bundle.main.bundleIdentifier ?? "-")
                    CheckMobileFactRow(label: "App Group", value: CheckMobileIdentifiers.appGroupID)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
            }
            .padding(24)
        }
    }
}

struct CheckMobileFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(CheckTheme.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
        }
        .font(.body)
    }
}
#endif
