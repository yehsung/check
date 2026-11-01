import Foundation

/// 사진 삭제 자리의 문구 한 벌(맥 설정 행 · 폰 프로필 화면). **순수 값이라 테스트가 글자 그대로 되묻는다** — 스토어가 세우는 네 문구
/// (성공·파일 남음·실패·로그인 전)도 여기서 가져간다. 문구가 뷰와 스토어 두 곳에 흩어지면 한쪽만 고쳐도
/// 아무 테스트가 안 빨개진다.
package enum AvatarRemovalText {
    package static let title = "프로필 사진"
    /// 평소 설명. **"사진이 있으면"이라고 말하지 않는다** — 이 행은 사진 유무와 무관하게 늘 같은 자리에 있다.
    package static let detail = "지우면 내 자리에 착용한 캐릭터가 대신 보여요."
    /// 확인 단계의 설명. 되돌릴 수 없다는 사실만 말한다(겁주는 문장이 아니라 사실 한 줄).
    package static let confirmDetail = "지운 사진은 되돌릴 수 없어요. 다시 쓰려면 새로 올려야 해요."
    package static let action = "기본 캐릭터로 되돌리기"
    package static let confirm = "되돌리기"
    package static let cancel = "취소"
    package static let inFlight = "지우는 중…"
    package static let successMessage = "기본 캐릭터로 되돌렸어요"
    /// 표는 비웠는데 **파일이 남은** 경우. "되돌렸어요"라고 말하면 거짓말이다 — 공개 버킷의 얼굴은 URL 만 알면 보인다.
    /// 문구 근거: 앞부분은 일어난 사실(표는 비었다)을, 뒷부분은 이 저장소가 이미 쓰는 재시도 안내 문장
    /// ("잠시 후 다시 시도해 주세요" — 별명 행의 연결 실패 안내)을 그대로 쓴다.
    package static let fileLeftMessage = "사진 파일이 아직 남아 있어요. 잠시 후 다시 시도해 주세요"

    /// 팝오버 푸터(한 줄)용 짧은 쪽. 설정 행은 전문을 쓰고, 푸터만 이 값을 쓴다 — 긴 문장은 푸터에서 뒤가 잘리는데
    /// 하필 잘리는 부분이 사용자가 할 일("다시 시도해 주세요")이다. 매핑을 여기 한 곳에 둬야 문구가 갈리지 않는다.
    package static func shortForFooter(_ message: String) -> String {
        message == fileLeftMessage ? "사진 파일이 아직 남아 있어요" : message
    }
    package static let failureMessage = "사진을 지우지 못했어요"
    /// 로그인 전. 위젯의 "로그인하면 지금 근무 중인 사람이 떠요" 와 같은 어법이다.
    package static let signedOutMessage = "로그인하면 사진을 지울 수 있어요"
}
