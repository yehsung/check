#if DEBUG
import Foundation

/// 메시지 탭 데모 장면 고리(**DEBUG 전용** — Release 에서 컴파일되지 않는다). 데모 라우트(`-AingCheckDemoRoute`)로는 닿지 않는
/// 화면을 스크린샷으로 확인하려고 둔다. 데모 모드(`context.isDemo`)가 아니면 아무것도 안 한다.
///
///     -AingCheckDemoMessages new        메시지 목록 위에 사람 찾기 시트를 띄운다(라우트 messages 와 함께).
///     -AingCheckDemoMessages composer   그 대화 입력칸에 185자를 넣고 한 번 보낸다 — 장면 픽스처가 target_focused 로 답해
///                                       카운터 · 되돌아온 글 · 실패 문구가 한 화면에 선다(라우트 messages/<peer> 와 함께).
package enum MessagesDemoLaunch {
    package static let argument = "-AingCheckDemoMessages"

    static func value(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1].lowercased()
    }

    static func opensNewConversation(isDemo: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        isDemo && value(arguments: arguments) == "new"
    }

    /// 데모 입력칸 글(185자 — 카운터가 선다).
    static let composerDraft: String = {
        let sentence = "내일 오전 회의 자료는 공유 폴더에 올려 두었어요. 확인하고 의견 남겨 주세요. "
        var text = ""
        while text.unicodeScalars.count < 185 { text += sentence }
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(185))).trimmingCharacters(in: .whitespaces)
    }()

    @MainActor
    static func seedComposerIfRequested(store: MessagesStore, peerID: String, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard store.context.isDemo, value(arguments: arguments) == "composer", store.draft(for: peerID).isEmpty,
              store.sendNotices[peerID] == nil, !store.isSending
        else { return }
        store.setDraft(composerDraft, for: peerID)
        store.sendDraft(to: peerID, isComposing: false)
    }
}
#endif
