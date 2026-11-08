import AppKit
import AVFoundation
import SwiftUI
import Combine
import Observation
#if ALKKAGI_PLAYGROUND
import AlkkagiCore
#else
import CheckCore
#endif

struct AlkkagiPlayerProfile: Equatable {
    let name: String
    var characterID: String? = nil
}

// 오목과 같은 판/오른쪽 상태·대화 열을 쓴다. 실행기와 본앱은 이 화면을 공유한다.
@MainActor
struct AlkkagiGameView: View {
    var onReturn: (() -> Void)? = nil
    var me = AlkkagiPlayerProfile(name: "플레이어 1")
    var opponent = AlkkagiPlayerProfile(name: "플레이어 2")
    var onlineStore: AlkkagiOnlineStore? = nil
    @State private var model = AlkkagiLocalModel()
    @State private var confirmsResign = false
    @GestureState private var dragIsActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let timer = Timer.publish(every: 1.0 / 120, on: .main, in: .common).autoconnect()
    private var boardSide: CGFloat { BoardGameLayout.boardSide - 48 }

    var body: some View {
        VStack(alignment: .leading, spacing: BoardGameLayout.headerSpacing) {
            header
            BoardGameMatchLayout {
                board
            } sidebar: {
                BoardGameMatchSidebar {
                    VStack(spacing: BoardGameLayout.matchSideSpacing) {
                        playerCard(model.myColor.opponent)
                        playerCard(model.myColor)
                    }
                } status: {
                    statusCard
                } chat: {
                    AlkkagiChatPanel(model: model)
                } actions: {
                    onlineActions
                }
            }
        }
        .padding(BoardGameLayout.contentPadding)
        .frame(width: BoardGameLayout.contentSize.width, height: BoardGameLayout.contentSize.height)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        .preferredColorScheme(.dark)
        .onAppear { model.attachOnline(onlineStore) }
        .onReceive(timer) { _ in model.tick() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.cancelAim() }
        .onExitCommand { model.cancelAim() }
        .onChange(of: dragIsActive) { _, active in
            if !active { model.finishGesture() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(CheckTheme.accent)
            Text("알까기").font(.title2.weight(.bold))
            Text(onlineStore == nil ? "로컬 2인" : "온라인 1:1").font(.caption).foregroundStyle(CheckTheme.secondaryText)
            Spacer()
            if let onReturn {
                Button(action: onReturn) { Label("게임 목록", systemImage: "chevron.left") }.buttonStyle(.bordered)
            }
            Button { model.soundEnabled.toggle() } label: {
                Image(systemName: model.soundEnabled ? "speaker.wave.2" : "speaker.slash").frame(width: 22, height: 22)
            }.buttonStyle(.plain).accessibilityLabel(model.soundEnabled ? "소리 끄기" : "소리 켜기")
            if onlineStore == nil {
                Button { model.restart() } label: { Label("새 판", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).keyboardShortcut("r", modifiers: .command).help("새 판 시작 (⌘R)")
            }
        }.frame(height: BoardGameLayout.headerHeight)
    }

    private func playerCard(_ player: AlkkagiGame.Player) -> some View {
        let currentPlayer = onlineStore?.state?.currentPlayer ?? model.game.currentPlayer
        let finished = onlineStore.map { $0.state?.phase == .finished } ?? (model.game.phase == .finished)
        let simultaneousPlacement = onlineStore?.state?.phase == .placing
        let concealedLayout = simultaneousPlacement || (onlineStore?.state.map {
            $0.phase == .finished && (!$0.myReady || !$0.opponentReady)
        } ?? false)
        let isMe = player == model.myColor
        let ready = isMe ? onlineStore?.state?.myReady == true : onlineStore?.state?.opponentReady == true
        let active = simultaneousPlacement ? !ready : (currentPlayer == player && !finished)
        let peer = player == .black ? onlineStore?.state?.black : onlineStore?.state?.white
        let profile = peer.map { AlkkagiPlayerProfile(name: $0.displayName, characterID: $0.characterID) }
            ?? (player == .black ? me : opponent)
        let detail: String
        if concealedLayout && !isMe {
            detail = "\(player.title) 배치 비공개"
        } else {
            detail = model.game.phase == .placing ? "\(player.title) 배치 \(model.game.placedCount(player))/5" : "\(player.title) \(model.game.remaining(player))개"
        }
        let message = simultaneousPlacement
            ? (ready ? "준비 완료" : (isMe ? "돌을 배치해 주세요" : "배치 중"))
            : (active ? (model.game.phase == .placing ? "돌을 배치해 주세요" : "내 차례예요") : "기다리는 중")
        return BoardGamePlayerCard(name: profile.name, stoneColor: player == .black ? .black : .white,
                                   stoneText: detail, isTurn: active, isMe: player == model.myColor) {
            playerPortrait(profile)
        } message: {
            Text(message)
                .font(.caption).foregroundStyle(active ? CheckTheme.working : CheckTheme.secondaryText)
        } clock: {
            if active {
                BoardGameClockRing(remaining: model.remainingSeconds, duration: 30, tint: model.clockTint)
            }
        }
        .frame(height: BoardGameLayout.playerCardHeight)
    }

    @ViewBuilder
    private func playerPortrait(_ profile: AlkkagiPlayerProfile) -> some View {
#if !ALKKAGI_PLAYGROUND
        if let characterID = profile.characterID {
            CharacterPortrait(characterID: characterID)
        } else {
            Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(CheckTheme.secondaryText)
        }
#else
        Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(CheckTheme.secondaryText)
#endif
    }

    private var board: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.25))
                .frame(width: boardSide, height: boardSide + 12).offset(y: -6)
            Canvas { context, _ in
                AlkkagiDrawing.falling(model.falls, context: context, scale: boardSide / AlkkagiGame.boardSize,
                                       origin: CGPoint(x: 24, y: 12), reduced: reduceMotion)
            }.allowsHitTesting(false)
            playSurface.offset(y: -12)
        }
        .frame(width: BoardGameLayout.boardSide, height: BoardGameLayout.boardSide)
        .clipped()
        .offset(shakeOffset)
        .overlay { resultOverlay }
    }

    private var shakeOffset: CGSize {
        guard !reduceMotion else { return .zero }
        let recoil = model.launchRecoil
        return CGSize(width: sin(model.time * 155) * model.jolt * 3.5 + recoil.x,
                      height: cos(model.time * 183) * model.jolt * 2.6 + recoil.y)
    }

    private var playSurface: some View {
        Canvas { context, size in
            AlkkagiDrawing.board(context: context, size: size)
            let scale = size.width / AlkkagiGame.boardSize
            if model.game.phase == .placing {
                let y: CGFloat = model.game.currentPlayer == .black ? size.height / 2 : 0
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: size.height / 2)),
                             with: .color(CheckTheme.accent.opacity(0.10)))
            }
            for stone in model.game.stones where stone.isPlaced && !stone.isOut {
                AlkkagiDrawing.stone(stone, context: context, scale: scale,
                    selected: stone.id == model.selectedID, pull: model.pull,
                    launch: model.launch, hits: model.hits, trails: !reduceMotion)
            }
            if let selected = model.selectedStone, model.game.phase == .aiming {
                AlkkagiDrawing.aim(stone: selected, pull: model.pull, context: context, scale: scale)
            }
            if let preview = model.placementPoint, let id = model.dragPlacementID,
               let stone = model.game.stones.first(where: { $0.id == id }) {
                var layer = context
                layer.opacity = 0.65
                AlkkagiDrawing.disc(center: CGPoint(x: preview.x * scale, y: preview.y * scale),
                    radius: AlkkagiGame.stoneRadius * scale, player: stone.owner, context: layer)
                let tint = model.game.canPlace(stoneID: id, at: preview) ? CheckTheme.accent : CheckTheme.danger
                let radius = AlkkagiGame.stoneRadius * scale + 3
                context.stroke(Path(ellipseIn: CGRect(x: preview.x * scale - radius, y: preview.y * scale - radius,
                                                     width: radius * 2, height: radius * 2)), with: .color(tint), lineWidth: 2)
            }
            AlkkagiDrawing.effects(model.hits, context: context, scale: scale, reduced: reduceMotion)
        }
        .frame(width: boardSide, height: boardSide)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 7)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .updating($dragIsActive) { _, active, _ in active = true }
            .onChanged { value in
                let scale = AlkkagiGame.boardSize / boardSide
                model.aim(start: AlkkagiVector(x: value.startLocation.x * scale, y: value.startLocation.y * scale),
                    translation: AlkkagiVector(x: value.translation.width * scale, y: value.translation.height * scale))
            }.onEnded { _ in model.release() })
        .accessibilityLabel("알까기 바둑판")
        .accessibilityValue(model.status)
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if model.game.phase == .finished && (onlineStore == nil || onlineStore?.state?.phase == .finished) {
            VStack(spacing: 12) {
                Image(systemName: "flag.checkered").font(.title2).foregroundStyle(CheckTheme.accent)
                Text(model.resultTitle).font(.title.weight(.bold))
                Text("총 \(model.game.shotCount)번의 한 수").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                Button(onlineStore == nil ? "다시 한 판" : "로비로") { model.restart() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(28).background(CheckTheme.panelElevated, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckTheme.border))
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            footer
            if model.game.phase == .placing {
                HStack(spacing: 12) {
                    ForEach(model.game.stones.filter { $0.owner == model.game.currentPlayer }) { stone in
                        Button { model.placementID = stone.id } label: {
                            AlkkagiStoneSymbol(player: stone.owner).frame(width: 28, height: 28)
                                .opacity(stone.isPlaced ? 0.4 : 1)
                                .padding(3)
                                .overlay(Circle().stroke(model.placementID == stone.id ? CheckTheme.accent : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).disabled(!model.canInteract)
                            .accessibilityLabel("\(stone.owner.title) \(stone.id % 5 + 1)번 돌 선택")
                    }
                    Spacer()
                    Button(onlineStore?.state?.myReady == true ? "준비 완료" : "배치 완료 (\(model.game.placedCount(model.game.currentPlayer))/5)") { model.confirmPlacement() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.game.placedCount(model.game.currentPlayer) < 5 || !model.canInteract)
                }
                Text(onlineStore == nil ? "내 영역에 돌 5개를 놓거나 옮겨 주세요. 시간이 끝나면 남은 돌은 자동 배치해요."
                     : "30초 동안 동시에 배치해요. 둘 다 준비하거나 시간이 끝날 때까지 상대 배치는 보이지 않아요.")
                    .font(.caption2).foregroundStyle(CheckTheme.secondaryText)
            }
        }
        .padding(12).background(CheckTheme.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckTheme.border))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(onlineStore?.notice ?? model.notice ?? model.status).font(.caption)
                .foregroundStyle(onlineStore?.notice == nil && model.notice == nil ? CheckTheme.secondaryText : CheckTheme.pending)
            Spacer()
            if model.selectedID != nil {
                Text("힘 \(Int(model.power * 100))%")
                    .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(CheckTheme.accent)
            } else {
                Text("\(model.game.shotCount)수").font(.caption.monospacedDigit()).foregroundStyle(CheckTheme.secondaryText)
            }
        }.frame(minHeight: 20)
    }

    @ViewBuilder
    private var onlineActions: some View {
        if let onlineStore {
            HStack(spacing: 10) {
                if onlineStore.state?.phase == .finished {
                    Button("로비로") { Task { await onlineStore.leaveFinishedMatch() } }
                        .buttonStyle(.borderedProminent)
                } else if confirmsResign {
                    Text("기권하면 상대가 승리해요").font(.caption).foregroundStyle(CheckTheme.pending)
                    Spacer()
                    Button("계속하기") { confirmsResign = false }.buttonStyle(.bordered)
                    Button("기권하기") { Task { await onlineStore.resign(); confirmsResign = false } }
                        .buttonStyle(.borderedProminent).tint(CheckTheme.danger).disabled(onlineStore.isBusy)
                } else {
                    Button("기권") { confirmsResign = true }.buttonStyle(.bordered).disabled(onlineStore.isBusy)
                    Spacer()
                    Text(onlineStore.isBusy ? "동기화 중" : "창을 닫아도 대전은 계속돼요")
                        .font(.caption).foregroundStyle(CheckTheme.secondaryText)
                }
            }.frame(minHeight: 32)
        }
    }
}

private struct AlkkagiStoneSymbol: View {
    let player: AlkkagiGame.Player
    var body: some View {
        Canvas { context, size in
            AlkkagiDrawing.disc(center: CGPoint(x: size.width / 2, y: size.height / 2),
                               radius: size.width * 0.43, player: player, context: context)
        }
    }
}

@MainActor
private struct AlkkagiChatPanel: View {
    @Bindable var model: AlkkagiLocalModel
    @State private var editorRenderedEmpty: Bool?

    var body: some View {
        BoardGameChatCard {
            HStack {
                Text("대화").font(.subheadline.weight(.bold))
                Spacer()
                Text(model.isOnline ? "대전 대화" : "로컬 대화").font(.caption2).foregroundStyle(CheckTheme.secondaryText)
                Button { model.toggleChatMute() } label: {
                    Image(systemName: model.chatMuted ? "bell.slash.fill" : "bell.fill")
                }.buttonStyle(.plain).help("상대 말 숨기기")
            }
            if !model.isOnline {
                Picker("지금 말하는 돌", selection: $model.chatSender) {
                    Text("흑돌").tag(AlkkagiGame.Player.black)
                    Text("백돌").tag(AlkkagiGame.Player.white)
                }.pickerStyle(.segmented)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if model.messages.isEmpty {
                            Text("아직 나눈 말이 없어요").font(.caption).foregroundStyle(CheckTheme.secondaryText).padding(.top, 20)
                        }
                        ForEach(model.messages) { message in
                            if let sender = message.sender {
                                if !model.chatMuted || sender == model.chatSender {
                                    BoardGameChatBubble(body: message.body, isMine: sender == model.chatSender,
                                        oppositeInset: 56, accent: CheckTheme.accent, primaryText: CheckTheme.primaryText)
                                        .id(message.id)
                                }
                            } else {
                                Text(message.body).font(.caption2).foregroundStyle(CheckTheme.secondaryText)
                                    .frame(maxWidth: .infinity).padding(.vertical, 4).id(message.id)
                            }
                        }
                    }.frame(maxWidth: .infinity)
                }
                .onChange(of: model.messages.last?.id) { _, _ in
                    if let id = model.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                ForEach(GomokuQuickPhrase.allCases, id: \.rawValue) { phrase in
                    Button { model.sendQuick(phrase) } label: {
                        Text(phrase.text).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                            .foregroundStyle(CheckTheme.primaryText).frame(maxWidth: .infinity).frame(height: 24)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CheckTheme.border))
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(CheckTheme.fieldFill)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CheckTheme.border))
                    if CheckEditorPlaceholder.isVisible(storeText: model.chatDraft, editorRenderedEmpty: editorRenderedEmpty) {
                        Text("메시지 입력 · ↩ 전송").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                            .padding(.horizontal, CheckEditorMetrics.inset.width).padding(.vertical, CheckEditorMetrics.inset.height)
                    }
                    CheckTextEditor(text: $model.chatDraft, sendsOnReturn: true,
                        canSendNow: { model.canSendChat }, onSend: send,
                        onRenderedEmptyChange: { editorRenderedEmpty = $0 })
                }.frame(height: 40)
                Button(action: send) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill").font(.system(size: 10, weight: .bold))
                        Text("보내기").font(.caption.weight(.bold))
                    }.foregroundStyle(.white).frame(width: 68, height: 32)
                }
                    .buttonStyle(.plain).background(CheckTheme.accent.opacity(model.canSendChat ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(!model.canSendChat).keyboardShortcut(.return, modifiers: .command).accessibilityLabel("보내기")
            }
            if model.chatLength >= 80 {
                Text("\(model.chatLength)/100").font(.caption2).foregroundStyle(model.chatLength > 100 ? CheckTheme.danger : CheckTheme.secondaryText)
            }
        }
    }
    private func send() { CheckEditorSend.commitThenSend { model.sendChat() } }
}

@MainActor
@Observable
final class AlkkagiLocalModel {
    var game = AlkkagiGame()
    var selectedID: Int?
    var pull = AlkkagiVector(x: 0, y: 0)
    var placementID: Int? = 0
    var dragPlacementID: Int?
    var placementPoint: AlkkagiVector?
    var notice: String?
    fileprivate var hits: [AlkkagiHit] = []
    fileprivate var falls: [AlkkagiFall] = []
    fileprivate var launch: AlkkagiLaunch?
    var time = 0.0
    var jolt = 0.0
    var soundEnabled = true
    var chatDraft = ""
    var chatSender: AlkkagiGame.Player = .black
    var chatMuted = false
    var onlineStore: AlkkagiOnlineStore?
    fileprivate var messages: [AlkkagiLocalMessage] = []
    @ObservationIgnored private var lastTime: TimeInterval?
    @ObservationIgnored private var clockTime = 0.0
    @ObservationIgnored private let feedback = AlkkagiFeedback()
    @ObservationIgnored private var powerBand = 0
    @ObservationIgnored private var messageSequence = 0
    @ObservationIgnored private var gestureIsActive = false
    @ObservationIgnored private var ignoresCurrentGesture = false
    @ObservationIgnored private var onlineRevision = -1
    @ObservationIgnored private var onlineMatchID: String?
    @ObservationIgnored private var onlineChatSeq = -1
    @ObservationIgnored private var onlineReplayElapsed = 0.0
    @ObservationIgnored private var predictedShotID: UUID?

    var isOnline: Bool { onlineStore != nil }
    var myColor: AlkkagiGame.Player { onlineStore?.state?.myColor ?? .black }
    var canInteract: Bool { onlineStore.map { $0.canPlace || $0.canShoot } ?? true }
    var selectedStone: AlkkagiGame.Stone? { game.stones.first { $0.id == selectedID && $0.isPlaced && !$0.isOut } }
    var power: Double { min(1, pull.length / AlkkagiGame.maxPull) }
    var remainingSeconds: Double {
        onlineStore?.remainingSeconds ?? (game.phase == .placing ? game.placementRemaining : game.turnRemaining)
    }
    var clockTint: Color { remainingSeconds <= 5 ? CheckTheme.danger : (remainingSeconds <= 10 ? CheckTheme.pending : CheckTheme.working) }
    var launchRecoil: AlkkagiVector {
        guard let launch else { return AlkkagiVector(x: 0, y: 0) }
        return launch.direction * (-sin(launch.age * 38) * exp(-launch.age * 17) * launch.power * 6)
    }
    var status: String {
        if let onlineStore, let state = onlineStore.state {
            if onlineStore.isBusy { return "서버와 동기화하고 있어요" }
            if state.phase == .finished { return resultTitle }
            if state.phase == .rolling { return "돌이 멈추면 차례가 바뀌어요" }
            if state.phase == .placing {
                return state.myReady ? "준비 완료 · 상대를 기다리고 있어요" : "\(state.myColor.title) 비공개 배치 중 · 내 영역을 눌러 주세요"
            }
            if !onlineStore.isMyTurn {
                let peer = state.currentPlayer == .black ? state.black : state.white
                return "\(peer.displayName)님 차례예요"
            }
        }
        return switch game.phase {
        case .placing: "\(game.currentPlayer.title) 배치 중 · 내 영역을 눌러 돌을 놓으세요"
        case .aiming: selectedID == nil ? "\(game.currentPlayer.title) 차례 — 돌을 뒤로 당겨 보세요" : "놓으면 발사해요 · Esc로 취소"
        case .rolling: "돌이 멈추면 차례가 바뀌어요"
        case .finished: resultTitle
        }
    }
    var resultTitle: String {
        switch game.result {
        case .winner(let player): "\(player.title) 승리!"
        case .draw: "멋진 한 판, 무승부!"
        case nil: "한 판 끝!"
        }
    }
    var canSendChat: Bool {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.unicodeScalars.count <= 100 && !(onlineStore?.isSendingChat ?? false)
    }
    var chatLength: Int { chatDraft.unicodeScalars.count }
    func sendChat() {
        guard canSendChat else { return }
        if let onlineStore {
            let draft = chatDraft
            let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let previous = onlineStore.chat.last?.seq ?? 0
            let myID = myColor == .black ? onlineStore.state?.black.id : onlineStore.state?.white.id
            Task { [weak self] in
                await onlineStore.sendChat(body: body)
                guard let self else { return }
                if self.chatDraft == draft,
                   onlineStore.chat.contains(where: { $0.seq > previous && $0.body == body && $0.senderID == myID }) {
                    self.chatDraft = ""
                }
                self.synchronizeOnline()
            }
            return
        }
        appendMessage(chatDraft.trimmingCharacters(in: .whitespacesAndNewlines), sender: chatSender)
        chatDraft = ""
    }
    func sendQuick(_ phrase: GomokuQuickPhrase) {
        if let onlineStore {
            Task { [weak self] in await onlineStore.sendChat(body: phrase.text); self?.synchronizeOnline() }
        } else {
            appendMessage(phrase.text, sender: chatSender)
        }
    }
    func toggleChatMute() {
        if let onlineStore {
            let muted = !chatMuted
            Task { [weak self] in await onlineStore.setMuted(muted); self?.synchronizeOnline() }
        } else { chatMuted.toggle() }
    }
    private func appendMessage(_ body: String, sender: AlkkagiGame.Player?) {
        messageSequence += 1
        messages.append(AlkkagiLocalMessage(id: messageSequence, sender: sender, body: body))
        if messages.count > 64 { messages.removeFirst(messages.count - 64) }
    }

    func aim(start: AlkkagiVector, translation: AlkkagiVector) {
        gestureIsActive = true
        guard !ignoresCurrentGesture, canInteract else { return }
        if game.phase == .placing {
            if dragPlacementID == nil {
                dragPlacementID = game.stones.first {
                    $0.owner == game.currentPlayer && $0.isPlaced && !$0.isOut && ($0.position - start).length < AlkkagiGame.stoneRadius * 1.4
                }?.id ?? placementID ?? game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
            }
            guard dragPlacementID != nil else { return }
            placementPoint = start + translation
            notice = nil
            return
        }
        guard game.phase == .aiming else { return }
        if selectedID == nil {
            selectedID = game.stones.first {
                $0.isPlaced && !$0.isOut && $0.owner == game.currentPlayer && ($0.position - start).length < AlkkagiGame.stoneRadius * 1.5
            }?.id
            if selectedID != nil { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        }
        guard selectedID != nil else { return }
        pull = translation.length > AlkkagiGame.maxPull ? translation * (AlkkagiGame.maxPull / translation.length) : translation
        let band = Int(power * 4)
        if band > powerBand { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        powerBand = band
    }
    func release() {
        defer { finishGesture() }
        guard !ignoresCurrentGesture, canInteract else { return }
        if game.phase == .placing {
            guard let id = dragPlacementID, let at = placementPoint else { return }
            if let onlineStore {
                guard game.canPlace(stoneID: id, at: at) else {
                    notice = "내 영역 안에서 돌이 겹치지 않게 놓아 주세요"
                    return
                }
                Task { [weak self] in await onlineStore.place(stoneID: id, at: at); self?.synchronizeOnline(force: true) }
                return
            }
            if game.placeStone(stoneID: id, at: at) {
                placementID = game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
                notice = nil
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            } else {
                notice = "내 영역 안에서 돌이 겹치지 않게 놓아 주세요"
            }
            return
        }
        guard let id = selectedID, let stone = selectedStone else { return }
        let shotPull = pull
        let actionID = UUID()
        if game.shoot(stoneID: id, pull: pull) {
            launch = AlkkagiLaunch(stoneID: id, direction: pull * (-1 / pull.length), power: power)
            if soundEnabled { feedback.play(strength: 0.3 + power * 0.6, ringOut: false, horizontal: stone.position.x) }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            if let onlineStore {
                predictedShotID = actionID
                onlineReplayElapsed = 0
                Task { [weak self] in
                    await onlineStore.shoot(stoneID: id, pull: shotPull, actionID: actionID)
                    self?.synchronizeOnline(force: true)
                    self?.predictedShotID = nil
                }
            }
        }
    }
    func cancelAim() {
        if gestureIsActive { ignoresCurrentGesture = true }
        selectedID = nil; pull = AlkkagiVector(x: 0, y: 0); powerBand = 0
        dragPlacementID = nil; placementPoint = nil
    }
    func finishGesture() {
        cancelAim()
        gestureIsActive = false
        ignoresCurrentGesture = false
    }
    func confirmPlacement() {
        if let onlineStore {
            Task { [weak self] in await onlineStore.confirmPlacement(); self?.synchronizeOnline(force: true) }
            return
        }
        let old = game
        if game.confirmPlacement() { changed(from: old) }
    }
    func restart() {
        if let onlineStore {
            Task { await onlineStore.leaveFinishedMatch() }
            return
        }
        game.reset(); cancelAim(); placementID = 0; notice = nil
        hits = []; falls = []; launch = nil; jolt = 0; lastTime = nil; clockTime = 0
        messages = []; chatDraft = ""; chatSender = .black; messageSequence = 0
    }
    private func changed(from old: AlkkagiGame) {
        guard onlineStore == nil else { return }
        guard old.phase != game.phase || old.currentPlayer != game.currentPlayer else { return }
        cancelAim(); notice = nil; clockTime = 0
        chatSender = game.currentPlayer
        if old.phase == .placing {
            placementID = game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
            if game.phase == .aiming {
                appendMessage("배치를 마쳤어요. 흑돌부터 시작해요!", sender: nil)
            } else {
                appendMessage("\(game.currentPlayer.title) 배치 차례예요", sender: nil)
            }
        } else if old.phase == .aiming && game.phase == .aiming && old.shotCount == game.shotCount {
            appendMessage("\(old.currentPlayer.title)의 시간이 끝나 차례를 넘겼어요", sender: nil)
        }
    }
    func tick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        defer { lastTime = now }
        guard let lastTime else { return }
        let elapsed = max(0, now - lastTime)
        let dt = min(1.0 / 20, elapsed)
        var impacts: [AlkkagiGame.Impact] = []
        let old = game
        if let onlineStore {
            synchronizeOnline()
            if onlineStore.state?.phase == .rolling, let shot = onlineStore.state?.shot {
                let target = min(shot.duration, max(0, (onlineStore.estimatedServerNowMs - shot.startedAtMs) / 1_000))
                var remaining = max(0, target - onlineReplayElapsed)
                while remaining > 1e-9 && game.phase == .rolling {
                    let slice = min(0.25, remaining)
                    impacts += game.advance(dt: slice)
                    remaining -= slice
                    onlineReplayElapsed += slice
                }
            } else if predictedShotID != nil && game.phase == .rolling {
                impacts = game.advance(dt: dt)
                onlineReplayElapsed += dt
            }
        } else if game.phase == .placing || game.phase == .aiming {
            // 초 단위 UI는 오목과 같이 5Hz로만 갱신한다. 창 밖을 눌러도 제한 시간은 흐른다.
            clockTime += elapsed
            if clockTime >= 0.2 {
                let deadlineExpired = clockTime + 1e-9 >= remainingSeconds
                impacts = game.advance(dt: clockTime)
                clockTime = 0
                if deadlineExpired { cancelAim() }
            }
        } else if game.phase == .rolling {
            impacts = game.advance(dt: dt)
        }
        changed(from: old)
        guard !hits.isEmpty || !falls.isEmpty || launch != nil || !impacts.isEmpty || jolt > 0 else { return }
        time += dt
        if var released = launch { released.age += dt; launch = released.age < 0.3 ? released : nil }
        hits = hits.compactMap { var h = $0; h.age += dt; return h.age < 0.32 ? h : nil }
        falls = falls.compactMap { var f = $0; f.age += dt; return f.age < 0.9 ? f : nil }
        jolt = max(0, jolt - dt * 9)
        for impact in impacts where impact.strength > 0.08 {
            hits.append(AlkkagiHit(position: impact.position, strength: impact.strength, ringOut: impact.isRingOut))
        }
        for stone in game.stones where stone.isOut && old.stones.first(where: { $0.id == stone.id })?.isOut == false {
            let p = stone.position
            let outward = AlkkagiVector(x: p.x < 0 ? -1 : (p.x > AlkkagiGame.boardSize ? 1 : 0),
                                        y: p.y < 0 ? -1 : (p.y > AlkkagiGame.boardSize ? 1 : 0))
            let edge = AlkkagiVector(x: min(AlkkagiGame.boardSize, max(0, p.x)), y: min(AlkkagiGame.boardSize, max(0, p.y)))
            falls.append(AlkkagiFall(position: edge, owner: stone.owner, outward: outward))
        }
        if let impact = impacts.max(by: { $0.strength < $1.strength }), impact.strength > 0.12 {
            jolt = max(jolt, pow(impact.strength, 1.3))
            if soundEnabled { feedback.play(strength: impact.strength, ringOut: impact.isRingOut, horizontal: impact.position.x) }
            if impact.strength > 0.35 { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        }
    }

    func attachOnline(_ store: AlkkagiOnlineStore?) {
        guard let store else { return }
        onlineStore = store
        synchronizeOnline(force: true)
    }

    private func synchronizeOnline(force: Bool = false) {
        guard let onlineStore, let state = onlineStore.state else { return }
        chatSender = state.myColor
        chatMuted = state.muted
        if onlineMatchID != state.id || onlineChatSeq != state.chatSeq {
            messages = onlineStore.chat.map { message in
                AlkkagiLocalMessage(id: message.seq, sender: message.senderID == state.black.id ? .black : .white, body: message.body)
            }
            onlineChatSeq = state.chatSeq
        }
        guard force || onlineMatchID != state.id || onlineRevision != state.revision else { return }
        // The other player's concealed placement must not interrupt my drag.
        if !force, onlineMatchID == state.id, state.phase == .placing, !state.myReady,
           game.phase == .placing, game.currentPlayer == state.myColor, game.stones == state.stones {
            onlineRevision = state.revision
            return
        }
        cancelAim()
        notice = nil
        let keepsPrediction = state.phase == .rolling
            && predictedShotID?.uuidString.caseInsensitiveCompare(state.shot?.id ?? "") == .orderedSame
            && game.shotCount == state.shotCount
        if state.phase == .rolling, !keepsPrediction, let replay = state.shotReplayGame {
            game = replay
            onlineReplayElapsed = 0
        } else if !keepsPrediction, let canonical = state.canonicalGame(serverNowMs: onlineStore.estimatedServerNowMs) {
            game = canonical
            onlineReplayElapsed = 0
        }
        onlineMatchID = state.id
        onlineRevision = state.revision
        placementID = game.stones.first { $0.owner == state.myColor && !$0.isPlaced }?.id
    }
}

private struct AlkkagiLocalMessage: Identifiable { let id: Int; let sender: AlkkagiGame.Player?; let body: String }
private struct AlkkagiHit { let position: AlkkagiVector; let strength: Double; let ringOut: Bool; var age = 0.0 }
private struct AlkkagiFall { let position: AlkkagiVector; let owner: AlkkagiGame.Player; let outward: AlkkagiVector; var age = 0.0 }
private struct AlkkagiLaunch { let stoneID: Int; let direction: AlkkagiVector; let power: Double; var age = 0.0 }

private enum AlkkagiDrawing {
    static func board(context: GraphicsContext, size: CGSize) {
        var layer = context
        let inset = size.width * 0.06
        let cell = (size.width - inset * 2) / 14
        let stars = [(3, 3), (11, 3), (7, 7), (3, 11), (11, 11)].map {
            CGPoint(x: inset + CGFloat($0.0) * cell, y: inset + CGFloat($0.1) * cell)
        }
        BoardGameDrawing.drawBoard(&layer, side: size.width, inset: inset, lines: 15, stars: stars)
    }

    static func stone(_ stone: AlkkagiGame.Stone, context: GraphicsContext, scale: Double,
                      selected: Bool, pull: AlkkagiVector, launch: AlkkagiLaunch?, hits: [AlkkagiHit], trails: Bool) {
        let point = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
        let radius = AlkkagiGame.stoneRadius * scale
        if trails, stone.velocity.length > 130 {
            for i in (1...3).reversed() {
                let lag = Double(i) * 0.009
                let p = CGPoint(x: point.x - stone.velocity.x * scale * lag, y: point.y - stone.velocity.y * scale * lag)
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(stone.owner.color.opacity(0.035 * Double(4 - i))))
            }
        }
        var squash = selected ? min(1, pull.length / AlkkagiGame.maxPull) * 0.09 : 0
        var angle = atan2(pull.y, pull.x)
        if let launch, launch.stoneID == stone.id {
            squash += sin(launch.age * 65) * exp(-launch.age * 22) * launch.power * 0.12
            angle = atan2(launch.direction.y, launch.direction.x)
        }
        if let hit = hits.last(where: { !$0.ringOut && $0.age < 0.1 && (stone.position - $0.position).length < 70 }) {
            squash += hit.strength * exp(-hit.age * 28) * 0.16
            angle = atan2(stone.position.y - hit.position.y, stone.position.x - hit.position.x)
        }
        var shaped = context
        if trails {
            squash = min(0.22, max(-0.12, squash))
            shaped.translateBy(x: point.x, y: point.y)
            shaped.rotate(by: .radians(angle))
            shaped.scaleBy(x: 1 - squash, y: 1 / (1 - squash))
            shaped.translateBy(x: -point.x, y: -point.y)
        }
        disc(center: point, radius: radius, player: stone.owner, context: shaped)
        if selected {
            context.stroke(Path(ellipseIn: CGRect(x: point.x - radius - 5, y: point.y - radius - 5, width: radius * 2 + 10, height: radius * 2 + 10)),
                           with: .color(.white.opacity(0.8)), lineWidth: 1.5)
        }
    }

    static func disc(center p: CGPoint, radius r: Double, player: AlkkagiGame.Player, context: GraphicsContext) {
        var layer = context
        BoardGameDrawing.drawStone(&layer, at: p, radius: r, color: player == .black ? .black : .white, opacity: context.opacity)
    }

    static func aim(stone: AlkkagiGame.Stone, pull: AlkkagiVector, context: GraphicsContext, scale: Double) {
        guard pull.length > 2 else { return }
        let center = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
        let grip = CGPoint(x: center.x + pull.x * scale, y: center.y + pull.y * scale)
        let direction = pull * (-1 / pull.length)
        let power = min(1, pull.length / AlkkagiGame.maxPull)
        let spread = AlkkagiGame.stoneRadius * scale * 0.8
        var band = Path()
        band.move(to: CGPoint(x: center.x - direction.y * spread, y: center.y + direction.x * spread))
        band.addLine(to: grip)
        band.addLine(to: CGPoint(x: center.x + direction.y * spread, y: center.y - direction.x * spread))
        context.stroke(band, with: .color(stone.owner.darkColor.opacity(0.15)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        context.stroke(band, with: .color(.white.opacity(0.65 + power * 0.35)), style: StrokeStyle(lineWidth: 1.5 + power, lineCap: .round, lineJoin: .round))
        let gripRadius = 5 + power * 2
        context.stroke(Path(ellipseIn: CGRect(x: grip.x - gripRadius, y: grip.y - gripRadius, width: gripRadius * 2, height: gripRadius * 2)), with: .color(.white), lineWidth: 1.5)
    }

    static func effects(_ hits: [AlkkagiHit], context: GraphicsContext, scale: Double, reduced: Bool) {
        for hit in hits {
            let t = hit.age / 0.32
            let radius = (8 + t * (18 + hit.strength * 24)) * scale
            let p = CGPoint(x: hit.position.x * scale, y: hit.position.y * scale)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(.white.opacity((1 - t) * 0.8)), lineWidth: (1 - t) * 2 + 0.5)
            if !reduced {
                for i in 0..<7 {
                    let a = Double(i) / 7 * .pi * 2
                    let d = radius * 1.3
                    context.fill(Path(ellipseIn: CGRect(x: p.x + cos(a) * d - 1.5, y: p.y + sin(a) * d - 1.5, width: 3, height: 3)),
                                 with: .color(.white.opacity((1 - t) * 0.7)))
                }
            }
        }
    }

    static func falling(_ falls: [AlkkagiFall], context: GraphicsContext, scale: Double, origin: CGPoint, reduced: Bool) {
        for fall in falls {
            let t = min(1, fall.age / 0.9)
            let outward = fall.outward.length > 0 ? fall.outward * (1 / fall.outward.length) : AlkkagiVector(x: 0, y: 1)
            // 판 경계를 넘어간 뒤 가속해 아래 층으로 낙하한다. 판 안에서 축소해 지우지 않는다.
            let distance = reduced ? 24 * t : 10 + 40 * t
            let p = CGPoint(x: origin.x + fall.position.x * scale + outward.x * distance,
                            y: origin.y + fall.position.y * scale + outward.y * distance + t * t * 100)
            let radius = AlkkagiGame.stoneRadius * scale * (1 - t * 0.25)
            var layer = context
            layer.opacity = reduced ? 1 - t : 1
            layer.fill(Path(ellipseIn: CGRect(x: p.x - radius * 0.9, y: p.y + 12 + t * 10,
                                             width: radius * 1.8, height: radius * 0.5)), with: .color(.black.opacity((1 - t) * 0.25)))
            if !reduced {
                layer.translateBy(x: p.x, y: p.y)
                layer.rotate(by: .radians(t * 0.7 * (outward.x < 0 ? -1 : 1)))
                layer.scaleBy(x: 1, y: 1 - t * 0.25)
                layer.translateBy(x: -p.x, y: -p.y)
            }
            disc(center: p, radius: radius, player: fall.owner, context: layer)
        }
    }

}

@MainActor
private final class AlkkagiFeedback {
    private var engine: AVAudioEngine?
    private var voices: [AVAudioPlayerNode] = []
    private var voice = 0
    private var lastSound = 0.0

    func play(strength: Double, ringOut: Bool, horizontal: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSound > 0.035 else { return }
        lastSound = now
        if engine == nil {
            let audio = AVAudioEngine()
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            for _ in 0..<4 {
                let node = AVAudioPlayerNode(); audio.attach(node)
                audio.connect(node, to: audio.mainMixerNode, format: format); voices.append(node)
            }
            do { try audio.start(); engine = audio } catch { voices = []; return }
        }
        guard !voices.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: ringOut ? 7_000 : 3_100),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) {
            let t = Double(i) / 44_100
            let tone = ringOut ? sin(2 * .pi * (500 * t - 900 * t * t)) * exp(-t * 23)
                              : (sin(2 * .pi * (820 + strength * 280) * t) + 0.5 * sin(2 * .pi * 240 * t)) * exp(-t * 70)
            samples[i] = Float(tone * min(1, max(0.1, strength)) * 0.19)
        }
        let node = voices[voice % voices.count]; voice += 1
        node.pan = Float((horizontal / AlkkagiGame.boardSize - 0.5) * 1.4)
        node.scheduleBuffer(buffer, at: nil, options: .interrupts); node.play()
    }
}

private extension AlkkagiGame.Player {
    var title: String { self == .black ? "흑돌" : "백돌" }
    var color: Color { self == .black ? Color(white: 0.15) : Color(white: 0.95) }
    var darkColor: Color { Color(red: 0.19, green: 0.17, blue: 0.14) }
}
