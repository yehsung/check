// 1:1 대기방 — 방에서 선 판을 **이 기기가 연 판**으로 받는다(게임 스토어마다 한 줄).
//
// 방 참가는 서버가 그 게임의 신청(방장) + 수락(참가자)을 한 트랜잭션으로 부르므로, 방장 기기는 신청 응답을 받은 적이 없다.
// 그래서 다섯 게임의 '이 기기가 연 판' 장부(GameDeviceLedger — 창 띄우기 · 주의 · 말풍선 문)에 판이 없다. 방 숨이 '시작됨 + 판 id' 를
// 돌려주면(방장) · 참가가 ok 면(참가자) 여기서 장부에 적고 그 판을 다시 읽는다 — 다음은 게임마다 원래 길(진행 중 판으로 처음
// 넘어가면 창을 띄우고 주의를 끈다)이 그대로 한다. 알까기는 장부가 없고 새 판이면 창을 판마다 한 번 띄운다(로비를 다시 읽는다).
import Foundation

extension GomokuStore {
    package func adoptRoomMatch(_ matchID: String) async {
        noteOwnsMatch(matchID.lowercased())
        await refreshMatch(id: matchID)
    }
}

extension ChessStore {
    package func adoptRoomMatch(_ matchID: String) async {
        noteOwnsMatch(matchID.lowercased())
        await refreshMatch(id: matchID)
    }
}

extension TetrisDuelStore {
    package func adoptRoomMatch(_ matchID: String) async {
        noteOwnsMatch(matchID.lowercased())
        await refreshMatch(id: matchID)
    }
}

extension ReversiStore {
    package func adoptRoomMatch(_ matchID: String) async {
        noteOwnsMatch(matchID.lowercased())
        await refreshMatch(id: matchID)
    }
}

extension CrossyDuelStore {
    package func adoptRoomMatch(_ matchID: String) async {
        noteOwnsMatch(matchID.lowercased())
        await refreshMatch(id: matchID)
    }
}

extension AlkkagiOnlineStore {
    package func adoptRoomMatch(_ matchID: String) async {
        await refreshLobby()
    }
}
