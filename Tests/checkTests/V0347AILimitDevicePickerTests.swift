import AppKit
import CheckCore
import Foundation
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.47 P2 — '폰·위젯에 보여줄 맥' 고르개가 **맥을 가를 수 있는가**
//
// ## 고친 결함 (적대적 검증이 실측으로 재현했다)
// 초안의 고르개는 칩을 `HStack` 한 줄에 넣고 `frame(maxWidth: 160)` + tail 말줄임으로 뒀다(줄바꿈도 가로
// 스크롤도 없다). 2·3대는 멀쩡했지만 **4대부터** 칩마다 70pt 안팎이 되어 글자 자리가 ~53pt 로 줄고,
// 같은 이름 두 맥이 둘 다 `Mac min…` 으로 떴다 — **고르개는 그 둘을 가르는 것이 존재 이유인 화면이다.**
// 이름을 한 번도 올린 적 없는 옛 맥 둘(`이름 모를 맥 9F8E`/`2B1C`)도 같은 꼴이었다.
// 그리고 칩 개수에 대한 테스트가 **0건**이었다.
//
// ## 이 파일이 지키는 것
//  ① **그림으로** 두 줄이 다르게 보인다. 값·폭 계산이 아니라 `ImageRenderer` 가 구운 픽셀을 비교한다 —
//     말줄임은 높이를 바꾸지 않으므로(한 줄 고정) 이 결함을 잡는 길은 픽셀뿐이다.
//  ② 기기 수 **4·5·6대**에서 쌍둥이가 갈린다(그 수가 초안이 깨지던 구간이다).
//  ③ **초안 배치는 같은 조건에서 두 줄이 바이트까지 같다** — 기준선이 같은 입력이면 그 테스트는 영원히
//     초록이므로(저장소 관례), 고친 쪽이 다르고 **고치기 전 쪽은 같다**를 둘 다 잰다.
//     이 짝이 없으면 렌더가 빈 그림을 굽는 날 ①이 조용히 무의미해진다.
//  ④ 이름 자리가 **기기 수와 무관**하다(목록으로 바꾼 이유가 그것이다).

/// 고정 기준 시각(다른 리밋 스위트와 같은 세계).
private let dpNow = Date(timeIntervalSince1970: 1_791_300_000)

/// 상한 길이(64 스칼라)로 **글자 그대로 같은** 이름. 서버 CHECK 가 받아 주는 가장 긴 이름이고,
/// 한글 64자는 어떤 자리에서도 한 줄에 들지 않는다 — 그 구간이 초안이 깨지던 자리다.
private let dpMaxName = String(repeating: "가", count: AILimitDeviceLabelContract.maxScalars)

private func dpDevice(_ id: String, _ label: String?, agoSeconds: Double) -> AILimitDevice {
    AILimitDevice(deviceID: id, label: label, lastObservedAt: dpNow.addingTimeInterval(-agoSeconds))
}

/// 쌍둥이 둘 + 나머지는 서로 다른 이름. **고른 맥은 쌍둥이가 아닌 맥**이다 — 쌍둥이 한쪽이 선택되면
/// 배경색이 달라져 두 줄이 "그래서" 달라지고, 이 그물이 재려던 것(글자가 갈리는가)을 재지 못한다.
private func dpRoster(count: Int) -> [AILimitDevice] {
    var devices = [
        dpDevice("twin-aaaa-a1b2", dpMaxName, agoSeconds: 120),
        dpDevice("twin-bbbb-c3d4", dpMaxName, agoSeconds: 180),
        dpDevice("anchor-0001", "사무실 iMac", agoSeconds: 60)
    ]
    while devices.count < count {
        let index = devices.count
        devices.append(dpDevice("extra-\(index)-9f8\(index)", "맥 스튜디오 \(index)", agoSeconds: 300 + Double(index)))
    }
    return Array(devices.prefix(max(3, count)))
}

@MainActor
private func dpPickerRow(function: String = #function, line: Int = #line) -> AILimitMainDeviceSettingsRow {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: CheckTestScratch.defaults("picker-L\(line)", function: function),
        workspaceNotifications: nil
    )
    return AILimitMainDeviceSettingsRow(store: store)
}

/// 줄 하나를 **굳은 비트맵**으로 굽는다(같은 입력이면 같은 바이트가 참이 되는 자리 — `CheckRenderSettle`).
@MainActor
private func dpBitmap(_ view: some View) throws -> Data {
    let settled = try #require(
        CheckRenderSettle.bitmap(
            view.frame(width: AILimitDevicePickerBudget.sectionInnerWidth).background(CheckTheme.background),
            scale: 2
        ),
        "고르개 줄을 굽지 못했다"
    )
    return try #require(settled.tiffRepresentation, "구운 그림에서 바이트를 못 얻었다")
}

/// 글자 폭 실측(`(s as NSString).size(withAttributes:)` — 글자수로 재면 한글·라틴이 배 이상 다르다).
private func dpWidth(_ text: String, weight: NSFont.Weight = .semibold) -> CGFloat {
    let font = NSFont.systemFont(ofSize: AILimitDevicePickerBudget.fontSize, weight: weight)
    return (text as NSString).size(withAttributes: [.font: font]).width
}

@MainActor
@Suite("v0.3.47 — 메인 맥 고르개(기기 4대 이상)")
struct V0347AILimitDevicePickerTests {
    /// ★★ **그림으로** 잰다: 상한 길이 이름이 겹친 두 맥의 줄이 **다르게 보인다**.
    ///
    /// 그리고 기준선을 같이 굽는다 — 초안 배치(합친 글자 하나 + 칩 폭 상한 + tail 말줄임)에서는 같은 입력의
    /// 두 줄이 **바이트까지 같다**. 그 단언이 없으면 렌더가 빈 그림을 굽는 날 위 단언이 조용히 무의미해진다
    /// (빈 그림끼리는 "다르다"가 거짓이 되어 빨개지므로 방향도 맞다).
    @Test("쌍둥이 두 줄이 그림으로 갈린다 · 같은 줄은 두 번 구워도 같다 · 초안 배치에서는 두 줄이 똑같다")
    func twinRowsLookDifferentWhenActuallyRendered() throws {
        let roster = dpRoster(count: 4)
        let parts = AILimitDeviceRoster.displayNameParts(roster)
        let picker = dpPickerRow()
        let twinA = try #require(roster.first { $0.deviceID == "twin-aaaa-a1b2" })
        let twinB = try #require(roster.first { $0.deviceID == "twin-bbbb-c3d4" })
        let partsA = try #require(parts[twinA.deviceID]), partsB = try #require(parts[twinB.deviceID])
        #expect(partsA.base == partsB.base, "전제: 두 맥의 이름 글자가 같다(다르면 이 그물은 아무것도 재지 못한다)")

        let imageA = try dpBitmap(picker.deviceRow(twinA, parts: partsA, isOn: false))
        let imageB = try dpBitmap(picker.deviceRow(twinB, parts: partsB, isOn: false))
        let imageAgain = try dpBitmap(picker.deviceRow(twinA, parts: partsA, isOn: false))

        #expect(imageA == imageAgain, "같은 줄을 두 번 구웠더니 바이트가 달라졌다 — 이 비교 자체를 믿을 수 없다")
        #expect(imageA != imageB,
                "같은 이름 두 맥의 줄이 **픽셀까지 똑같다** — 고르개가 가를 수 없는 화면이다(꼬리가 잘렸다)")

        // 기준선: 초안 배치(합친 글자 + 칩 폭 상한 160 + tail 말줄임). 같은 두 맥이 **같은 그림**이 된다.
        func legacyChip(_ parts: AILimitDeviceNameParts) -> some View {
            Text(parts.combined)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160)
                .padding(.horizontal, 12)
                .frame(height: AILimitDevicePickerBudget.rowHeight)
                .background(Capsule().fill(CheckTheme.trackFill))
        }
        let legacyA = try dpBitmap(legacyChip(partsA))
        let legacyB = try dpBitmap(legacyChip(partsB))
        #expect(legacyA == legacyB,
                "초안 배치에서 두 줄이 달라 보인다 — 기준선이 재던 결함이 사라졌다면 이 파일의 전제를 다시 써라")
    }

    /// ★ **4·5·6대**에서 모든 줄이 서로 다르게 보인다(쌍둥이 포함). 초안이 깨지던 구간이 바로 거기다.
    ///
    /// 왜 전부 돌려 보나: 목록 배치의 요점은 "이름 자리가 기기 수와 무관하다"이고, 그 성질이 깨지면 특정
    /// 개수에서만 두 줄이 같아진다(초안은 4대에서 그랬다). 개수를 하나만 재면 그 함정을 되묻지 못한다.
    @Test("4·5·6대: 모든 줄이 그림으로 서로 다르다(개수가 늘어도 이름 자리가 줄지 않는다)", arguments: [4, 5, 6])
    func everyRowStaysDistinctAsMacsPileUp(count: Int) throws {
        let roster = dpRoster(count: count)
        #expect(roster.count == count, "전제: 명부가 \(count)대다")
        let parts = AILimitDeviceRoster.displayNameParts(roster)
        let picker = dpPickerRow(line: 1_000 + count)

        var images: [String: Data] = [:]
        for device in roster {
            let piece = try #require(parts[device.deviceID])
            // 고른 맥은 **쌍둥이가 아닌** 맥 하나다(배경색 차이가 글자 차이를 가리지 않게).
            images[device.deviceID] = try dpBitmap(
                picker.deviceRow(device, parts: piece, isOn: device.deviceID == "anchor-0001"))
        }
        #expect(Set(images.values).count == count,
                "\(count)대 가운데 같은 그림의 줄이 있다 — 그 두 맥은 고를 수가 없다")
    }

    /// 예산: 이름 자리가 **기기 수와 무관**하고, 현실적인 이름은 꼬리까지 그 자리에 든다.
    /// 그리고 초안의 칩 산식이 **4대에서 무너진다**(그 수가 이 수리의 근거다).
    @Test("예산: 이름 자리는 기기 수와 무관하다 · 초안 칩 산식은 4대에서 이름을 잘랐다")
    func theNameRoomNoLongerShrinksWithTheNumberOfMacs() {
        // 카드 안쪽 폭의 출처를 못 박는다(설정 창 폭 380 − 본문 14×2 − 카드 12×2).
        #expect(AILimitDevicePickerBudget.sectionInnerWidth
                == CheckSettingsView.preferredWidth - 14 * 2 - 12 * 2,
                "고르개 예산의 카드 안쪽 폭이 설정 창의 실제 폭에서 나오지 않는다")

        // ★ 초안 산식(기준선): 칩이 한 줄에서 남는 폭을 나눠 가진다. 4대부터 쌍둥이 이름이 안 든다.
        func legacyChipTextWidth(deviceCount: Int) -> CGFloat {
            let gaps = CGFloat(deviceCount - 1) * 6
            return (AILimitDevicePickerBudget.sectionInnerWidth - gaps) / CGFloat(deviceCount) - 12 * 2
        }
        // 실측으로 다시 재 보니 **신고보다 한 대 일찍** 깨진다: 쌍둥이 머리글(`Mac mini (A1B2)` 95.3pt)이
        // 들어가는 것은 **2대까지**(137pt)이고, 3대에서 이미 81.3pt 로 줄어 **꼬리가 먼저 잘린다**
        // (= 그 순간 두 칩이 글자 그대로 같아진다). 4대에서는 53.5pt 라 `사무실 iMac`(62.2pt) 같은 평범한
        // 이름조차 못 쓰고, 5대부터는 `Mac mini`(52.6pt)도 안 든다.
        let twinName = dpWidth("Mac mini (A1B2)")
        #expect(legacyChipTextWidth(deviceCount: 2) >= twinName,
                "전제: 2대에서는 초안도 멀쩡했다(그래서 2·3대만 보던 눈에 이 결함이 안 보였다)")
        for count in [3, 4, 5, 6] {
            #expect(legacyChipTextWidth(deviceCount: count) < twinName,
                    "전제: 초안은 \(count)대에서 쌍둥이 머리글의 꼬리를 잘랐다 — 이 수리의 근거가 사라졌다")
        }
        #expect(legacyChipTextWidth(deviceCount: 4) < dpWidth("사무실 iMac"),
                "전제: 4대에서는 평범한 한글 이름조차 안 들어갔다")
        #expect(legacyChipTextWidth(deviceCount: 5) < dpWidth("Mac mini"),
                "전제: 5대에서는 가장 짧은 이름조차 안 들어갔다")

        // 지금 배치: 이름 자리가 기기 수를 **인자로 받지 않는다**(그게 수리의 전부다). 현실적인 이름은 든다.
        let room = AILimitDevicePickerBudget.nameWidth(hasTail: true)
        #expect(room > 0)
        // ★ 꼬리가 있는 줄에서는 **꼬리가 먼저 자리를 가져간다** — 그만큼 이름 자리가 좁다.
        //   이 등식을 빼면 예산이 현실보다 넓다고 말하고, "잘릴 이름"을 든다고 판정한다(위 `name` 단언이 무의미해진다).
        #expect(room == AILimitDevicePickerBudget.nameWidth(hasTail: false)
                - AILimitDevicePickerBudget.worstTailWidth - AILimitDevicePickerBudget.itemGap,
                "꼬리 폭을 이름 자리에서 빼지 않았다 — 꼬리는 `fixedSize` 로 먼저 자리를 받는다")
        #expect(room < AILimitDevicePickerBudget.nameWidth(hasTail: false))
        for name in ["Mac mini", "사무실 iMac", "예성의 MacBook Pro", "이름 모를 맥 9F8E"] {
            #expect(dpWidth(name) <= room,
                    "`\(name)` \(dpWidth(name))pt 가 이름 자리 \(room)pt 를 넘는다 — 현실적인 이름이 잘린다")
        }
        // 꼬리는 **가장 넓은 꼬리**로도 자리를 갖는다(이름이 아무리 길어도 먼저 자리를 받는다).
        let widestTail = dpWidth(AILimitDeviceNameParts.tailText("WWWW"))
        #expect(abs(widestTail - AILimitDevicePickerBudget.worstTailWidth) < 1.5,
                "가장 넓은 꼬리 실측이 \(widestTail)pt 인데 상수는 \(AILimitDevicePickerBudget.worstTailWidth)pt 다")
        #expect(AILimitDevicePickerBudget.tailAlwaysFits(widestTail),
                "가장 넓은 꼬리가 줄에 안 든다 — 긴 이름 앞에서 눌린다")
        // 상한 길이 이름은 **잘린다**(그것이 설계다 — 겹쳐도 같은 글자다). 전제가 참이어야 위 그림 비교가 뜻을 갖는다.
        #expect(dpWidth(dpMaxName) > room, "상한 길이 이름이 줄에 다 든다 — 이 파일이 재는 구간이 사라졌다")

        // 세로는 기기 수만큼 자란다(창은 넘치면 스크롤한다 — 잘림이 아니다).
        #expect(AILimitDevicePickerBudget.listHeight(deviceCount: 0) == 0)
        #expect(AILimitDevicePickerBudget.listHeight(deviceCount: 1) == AILimitDevicePickerBudget.rowHeight)
        #expect(AILimitDevicePickerBudget.listHeight(deviceCount: 4)
                > AILimitDevicePickerBudget.listHeight(deviceCount: 3))
    }

    /// ★ 고른 줄이 **그림으로 갈린다**(체크 표시 + 배경). 선택이 보이지 않으면 고르개가 아니다.
    /// 그리고 고르지 않은 줄에도 체크 자리를 비워 두므로, 선택이 바뀌어도 **이름 자리는 그대로**다.
    @Test("선택 표시: 고른 줄과 아닌 줄이 그림으로 다르다 · 선택이 이름 자리를 흔들지 않는다")
    func theChosenRowIsVisiblyChosen() throws {
        let roster = dpRoster(count: 4)
        let parts = AILimitDeviceRoster.displayNameParts(roster)
        let picker = dpPickerRow()
        let anchor = try #require(roster.first { $0.deviceID == "anchor-0001" })
        let piece = try #require(parts[anchor.deviceID])

        let on = try dpBitmap(picker.deviceRow(anchor, parts: piece, isOn: true))
        let off = try dpBitmap(picker.deviceRow(anchor, parts: piece, isOn: false))
        #expect(on != off, "고른 줄과 아닌 줄이 똑같이 보인다 — 무엇을 골랐는지 알 수 없다")

        // 체크 자리를 비워 두지 않으면 이 둘의 **이름 자리**가 달라진다 — 예산이 그 사실을 값으로 말한다.
        #expect(AILimitDevicePickerBudget.nameWidth(hasTail: false)
                == AILimitDevicePickerBudget.rowInnerWidth - AILimitDevicePickerBudget.itemGap
                   - AILimitDevicePickerBudget.checkWidth,
                "이름 자리 계산이 체크 표시 자리를 빼지 않는다 — 고른 줄만 이름이 더 일찍 잘린다")
    }
}
