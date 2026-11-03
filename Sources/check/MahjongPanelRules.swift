import SwiftUI
import CheckCore

// MARK: - 아잉 마작 규칙 · 역 · 점수표 창 (SPEC §5.7)
//
// 줄 목록 + 예시 손 그림(툴팁만으로 설명하지 않는다). 다른 마작 서비스 이름은 쓰지 않는다 — "가장 널리 쓰이는 온라인 리치 마작
// 규칙과 같아요" 같은 설명만. 넣지 않는 것: 추천 버림패 · 위험 표시 · 샹텐 수 숫자 · 효율 계산기(UX:446-452).
// 점수표 숫자는 규칙 Swift(`MahjongScoring.scoreOf`)에서 — 화면이 숫자를 손으로 적지 않는다.

enum MahjongRulesText {
    /// (제목, 설명, 예시 손 — `MahjongTiles.parse` 표기).
    static let rules: [(title: String, detail: String, example: String)] = [
        ("목표", "4몸통(같은 패 셋 또는 이어진 셋) + 1머리(같은 패 둘)를 먼저 만들면 화료예요.", "123m456p789s11122z"),
        ("역이 하나는 있어야 화료", "리치 · 멘젠쯔모 · 탕야오(2~8만 쓴 손) · 역패(백·발·중 셋)가 가장 흔해요.", "234m345p456s678s55p"),
        ("버리기 · 울기", "내 차례에 한 장 가져와 한 장 버려요. 남이 버린 패로 퐁(같은 패 셋)·깡(넷)·론을 할 수 있고, "
            + "치(이어진 셋)는 왼쪽 사람이 버린 패로만 돼요.", ""),
        ("리치", "울지 않은 손이 텐파이(한 장만 더 오면 화료)일 때 1000점을 걸고 선언해요. 그 뒤로는 손을 바꿀 수 없어요.", ""),
        ("후리텐", "기다리는 패를 내가 이미 버렸다면 론으로 날 수 없어요. 쯔모로는 날 수 있어요.", ""),
        ("유국", "패산이 다 떨어지면 텐파이한 사람이 노텐인 사람에게서 점수를 받아요.", ""),
        ("판 길이", "동풍전(동장 4국, 기본) · 반장전(동·남장 8국). 마지막에 1위가 30000점 미만이면 연장해요.", ""),
        ("생각 시간", "한 번에 5초 + 국마다 예비 20초 · 넘기면 저절로 버리거나 넘겨요. 날 수 있으면 저절로 화료해요.", ""),
        ("자리 비움", "창을 닫거나 [나가기]를 눌러도 판은 끝까지 가요. 차례가 오면 저절로 버리고, 손패를 한 번 누르면 돌아와요.", ""),
        ("판돈", "시작할 때 넷 모두에게서 판돈을 걷고 1위 +2N · 2위 본전 · 3·4위 −N 으로 나눠요. 새로 생기는 루비는 없어요.", ""),
    ]

    static let footer = "가장 널리 쓰이는 온라인 리치 마작 규칙과 같아요 · 적도라 3장 · 쿠이탕 있음 · 후리텐·쿠이카에 있음"

    /// 역 표(멘젠 판 · 울음 판 — nil 은 멘젠만). 역만은 판 대신 "역만".
    static let yakuTable: [(yaku: MahjongYaku, closed: Int, open: Int?)] = [
        (.riichi, 1, nil), (.doubleRiichi, 2, nil), (.ippatsu, 1, nil), (.menzenTsumo, 1, nil), (.pinfu, 1, nil),
        (.iipeikou, 1, nil), (.tanyao, 1, 1), (.yakuhaiHaku, 1, 1), (.yakuhaiHatsu, 1, 1), (.yakuhaiChun, 1, 1),
        (.bakaze, 1, 1), (.jikaze, 1, 1), (.chankan, 1, 1), (.rinshan, 1, 1), (.haitei, 1, 1), (.houtei, 1, 1),
        (.chiitoitsu, 2, nil), (.sanshoku, 2, 1), (.ittsu, 2, 1), (.chanta, 2, 1), (.toitoi, 2, 2), (.sanankou, 2, 2),
        (.sanshokuDoukou, 2, 2), (.sankantsu, 2, 2), (.honroutou, 2, 2), (.shousangen, 2, 2), (.honitsu, 3, 2),
        (.junchan, 3, 2), (.ryanpeikou, 3, nil), (.chinitsu, 6, 5),
    ]

    static let yakumanList: [MahjongYaku] = [
        .heavenly, .earthly, .kokushi, .kokushi13, .suuankou, .suuankouTanki, .daisangen, .shousuushii, .daisuushii,
        .tsuuiisou, .ryuuiisou, .chinroutou, .suukantsu, .chuuren, .junseiChuuren,
    ]

    /// 점수표 칸(부 × 판).
    static let fuRows = [30, 40, 50, 60, 70]
    static let hanColumns = [1, 2, 3, 4]
}

struct MahjongRulesSheet: View {
    let store: MahjongStore
    let tab: MahjongRulesTab
    let onSelect: (MahjongRulesTab) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(MahjongText.title) 규칙").font(.title3.weight(.heavy))
                MahjongChoiceRow(options: [(MahjongRulesTab.rules, MahjongText.rules), (.yaku, MahjongText.yaku),
                                           (.scores, MahjongText.scoreTable)],
                                 selected: tab, onSelect: onSelect)
                    .frame(width: 300)
                Spacer()
                MahjongCapsuleButton(title: MahjongText.close, tint: CheckTheme.secondaryText, filled: false, height: 30,
                                     action: onClose)
                    .frame(width: 80)
            }
            switch tab {
            case .rules: rulesBody
            case .yaku: yakuBody
            case .scores: scoresBody
            }
            Spacer(minLength: 0)
            Text(MahjongRulesText.footer).font(.caption2).foregroundStyle(CheckTheme.secondaryText)
        }
        .padding(20)
        .frame(width: MahjongWindowLayout.rulesSize.width, height: MahjongWindowLayout.rulesSize.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(CheckTheme.panelElevated))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CheckTheme.border, lineWidth: 1))
    }

    // MARK: 규칙

    private var rulesBody: some View {
        let rows = MahjongRulesText.rules
        let half = (rows.count + 1) / 2
        return HStack(alignment: .top, spacing: 16) {
            column(Array(rows[0..<half]))
            column(Array(rows[half...]))
        }
    }

    private func column(_ rows: [(title: String, detail: String, example: String)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.callout.weight(.bold)).foregroundStyle(CheckTheme.pending)
                    Text(row.detail).font(.caption).foregroundStyle(CheckTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let tiles = MahjongTiles.parse(row.example), !tiles.isEmpty {
                        MahjongTileStrip(tiles: tiles.enumerated().map { MahjongStripTile(face: MahjongTileFace($1), size: .smallMeld,
                                                                                          origin: CGPoint(x: CGFloat($0) * 25, y: 0)) },
                                         size: CGSize(width: CGFloat(tiles.count) * 25, height: 32), cornerLabels: false,
                                         accessibilityText: "\(row.title) 예시 손")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: 역

    private var yakuBody: some View {
        let table = MahjongRulesText.yakuTable
        let third = (table.count + 2) / 3
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(0..<3, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(table.dropFirst(column * third).prefix(third).enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(row.yaku.koreanName).font(.caption.weight(.semibold))
                                Spacer()
                                Text(row.open.map { "\(row.closed)판 · 울면 \($0)판" } ?? "\(row.closed)판 · 멘젠만")
                                    .font(.caption.monospacedDigit()).foregroundStyle(CheckTheme.secondaryText)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(CheckTheme.fieldFill))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Text("역만").font(.callout.weight(.bold)).foregroundStyle(CheckTheme.pending)
            Text(MahjongRulesText.yakumanList.map(\.koreanName).joined(separator: " · "))
                .font(.caption).foregroundStyle(CheckTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 점수표

    private var scoresBody: some View {
        HStack(alignment: .top, spacing: 16) {
            scoreGrid(dealer: false, title: "자(친이 아닐 때)")
            scoreGrid(dealer: true, title: "친")
        }
    }

    private func scoreGrid(dealer: Bool, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.bold)).foregroundStyle(CheckTheme.pending)
            HStack(spacing: 0) {
                Text("부 \\ 판").frame(width: 56, alignment: .leading)
                ForEach(MahjongRulesText.hanColumns, id: \.self) { han in Text("\(han)판").frame(maxWidth: .infinity) }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(CheckTheme.secondaryText)
            ForEach(MahjongRulesText.fuRows, id: \.self) { fu in
                HStack(spacing: 0) {
                    Text("\(fu)부").frame(width: 56, alignment: .leading)
                    ForEach(MahjongRulesText.hanColumns, id: \.self) { han in
                        Text(cell(han: han, fu: fu, dealer: dealer)).frame(maxWidth: .infinity)
                    }
                }
                .font(.caption.monospacedDigit())
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(CheckTheme.fieldFill))
            }
            ForEach([(5, "만관"), (6, "하네만"), (8, "배만"), (11, "삼배만")], id: \.0) { han, name in
                limitRow(name: name, han: han, dealer: dealer)
            }
            limitRow(name: "역만", han: 13, dealer: dealer, yakuman: 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func limitRow(name: String, han: Int, dealer: Bool, yakuman: Int = 0) -> some View {
        let ron = MahjongScoring.scoreOf(han: han, fu: 30, dealer: dealer, tsumo: false, yakuman: yakuman)
        let tsumo = MahjongScoring.scoreOf(han: han, fu: 30, dealer: dealer, tsumo: true, yakuman: yakuman)
        return HStack {
            Text(name).font(.caption.weight(.semibold))
            Spacer()
            Text("론 \(ron.total.formatted()) · 쯔모 \(tsumoText(tsumo.points, dealer: dealer))")
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(CheckTheme.fieldFill))
    }

    /// 칸: "론 N / 쯔모 a·b"(자) · "론 N / 쯔모 a 모두"(친).
    private func cell(han: Int, fu: Int, dealer: Bool) -> String {
        let ron = MahjongScoring.scoreOf(han: han, fu: fu, dealer: dealer, tsumo: false)
        let tsumo = MahjongScoring.scoreOf(han: han, fu: fu, dealer: dealer, tsumo: true)
        return "\(ron.total) / \(tsumoText(tsumo.points, dealer: dealer))"
    }

    private func tsumoText(_ points: MahjongPoints, dealer: Bool) -> String {
        if dealer { return "\(points.fromEach ?? 0)∀" }
        return "\(points.fromChild ?? 0)·\(points.fromDealer ?? 0)"
    }
}
