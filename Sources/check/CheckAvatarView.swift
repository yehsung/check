import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import CheckCore

// MARK: - 기본 아바타 = 착용 캐릭터 (2026-09-20 사용자 요청 — 맥, 작업 M)
//
// "유저들 프로필 기본값으로 장착중인 캐릭터로 뜨게 해줘. 지금은 별명의 첫글자가 들어가 있잖아. 그거 말고.
//  프로필 사진 직접 업로드한 사람은 업로드한 사진으로 뜨는거 유지하고."
//
// 사람 아바타의 우선순위(정본은 코어 `AppUserCharacterDirectory.avatar(for:photoURL:)` — 폰과 한 규칙):
//   ① 올린 사진 → ② 그 사람의 착용 캐릭터(neutral 초상 · 원형) → ③ 캐릭터를 **모를 때만** 이니셜(첫 조회 전 · 표에 없는 사람 ·
//   이 빌드가 모르는 새 캐릭터). 착용값 null 은 아잉이다. 사진을 불러오는 중이거나 실패하면 이니셜이 아니라 캐릭터로 떨어진다.
//
// 표(`AppUserCharacterDirectory`)는 스토어가 받고(`WorkTimerStoreAvatars.swift`), **창 루트 넷**(팝오버 · 설정 · 미니게임 · 오목)이
// `appUserAvatarCharacters(from:)` 로 이 환경값에 건다 — 호출부는 **사용자 id** 만 넘긴다. 환경값이 없는 자리(렌더 테스트가 부품만
// 그릴 때 · 미리보기)는 빈 표 = 지금처럼 이니셜이다.
//
// ★ 초상은 `CheckMascotAssets.image(for:characterID:)` 로 얻지 **않는다** — 그 함수는 모르는 id·깨진 PNG 를 아잉으로 폴백한다(내 캐릭터용
//   규칙). 여기는 **남의 사실**을 그리는 자리라, 그리지 못하면 아잉이 아니라 이니셜이다(`AppUserAvatarArt.portrait(characterID:)`).
//
// ★ 그림은 **`portrait-neutral.png` 한 장**이다(알파 상자로 조인 뒤 캐릭터당 한 번만 디코드·캐시).
//   2026-09-21 사용자 지시 "카드에 나오는 기본 그림으로 해달라"는 **크롭만 고쳐도 충족된다** — 카드 그림(아틀라스 `frontIdle` 셀)과
//   이 PNG 는 **같은 그림의 해상도 차이**다(조인 실루엣 가로/세로 실측: 여우 0.870 대 0.867 · 유령 0.984 대 0.984 ·
//   해파리 0.870 대 0.867 · 시바 0.786 대 0.785 · 다람쥐 0.729 대 0.729 — 같은 자세·같은 비, 192² 대 512 높이).
//   한때 출처를 `CharacterCardArt.image` 로 바꿨다가 **되돌렸다**(2026-09-21). 이유 셋 — 앞의 둘은 다시 쟀다
//   (`V0336AvatarArtBakeProbe.cost`, 테스트 빌드 · 3회 · 캐시 비우고 여섯 캐릭터):
//     · 첫 페인트의 메인스레드 시간 **203ms 대 23ms**(카드 그림 대 초상 — 8.7배). 아바타는 팝오버가 열리자마자 여러 개 뜬다.
//     · 상주 메모리 **아틀라스 21.5MB**(높이 516px 아틀라스 다섯 장 — 폭 1768~2444)가 새로 들어오고, 조인 그림도 4.3MB 대 0.7MB 다.
//     · 초상 디코드가 실패하면 그 함수가 **아잉으로 접어** 남의 얼굴에 아잉이 선다(이 파일의 첫 ★ 이 막는 바로 그 일).

private struct AppUserCharactersKey: EnvironmentKey {
    /// 빈 표(전원 이니셜). 창 루트가 스토어의 표를 걸기 전의 자리 · 부품만 그리는 렌더 테스트가 이 값을 본다.
    static let defaultValue = AppUserCharacterDirectory(knownIDs: [CharacterCatalog.builtInAingID])
}

extension EnvironmentValues {
    /// 사람 아바타가 찾는 캐릭터 한 표. 창 루트가 `appUserAvatarCharacters(from:)` 로 스토어의 표를 건다.
    var appUserCharacters: AppUserCharacterDirectory {
        get { self[AppUserCharactersKey.self] }
        set { self[AppUserCharactersKey.self] = newValue }
    }
}

extension View {
    /// **창 루트 한 곳에서** 부른다(팝오버 `CheckMenuView` · 설정 `CheckSettingsView` · 미니게임 `CheckMiniGameWindowView` ·
    /// 오목 `GomokuPanel`). 이 아래 모든 사람 아바타가 이 스토어의 캐릭터 한 표에서 착용 캐릭터를 찾는다.
    ///
    /// 표를 읽는 것은 작은 감싸개 뷰의 body 다 — 루트 뷰의 body 가 읽으면 표가 바뀔 때마다 팝오버 전체가 다시 평가된다.
    /// 감싸개만 다시 평가되고, 환경값이 바뀐 것을 읽는 쪽(아바타)만 다시 그려진다. `store` 가 nil 이면(스토어 없이 그리는
    /// 오목 렌더 테스트) 빈 표 = 이니셜.
    func appUserAvatarCharacters(from store: WorkTimerStore?) -> some View {
        AppUserAvatarCharactersScope(store: store, content: self)
    }
}

private struct AppUserAvatarCharactersScope<Content: View>: View {
    let store: WorkTimerStore?
    let content: Content

    var body: some View {
        content.environment(\.appUserCharacters, store?.appUserCharacters ?? AppUserCharactersKey.defaultValue)
    }
}

extension AppUserCharacterDirectory {
    /// 맥의 판정 한 곳: 표의 규칙(`avatar(for:photoURL:)`) 그대로에, **표가 이 사람을 모를 때만** 호출부가 이미 받은 착용값
    /// (`characterHint` — 오목 로비·신청 행의 `GomokuUser.characterID`)을 쓴다.
    ///
    /// 힌트는 **이 빌드가 초상을 그릴 수 있는 id 일 때만** 쓴다. nil 은 아잉으로 접지 않는다 — 오목 행의 nil 은 '안 골랐다(아잉)'와
    /// '그 응답이 칸을 안 실었다(신청 행 · 옛 서버)'를 가르지 못한다. 모르는 것을 아잉으로 단정하면 틀린 사실을 그린다.
    /// 표가 아는 사람은 표가 이긴다(팝오버·오목 창이 같은 사람을 다른 캐릭터로 그리지 않게).
    func avatar(for userID: String?, photoURL: URL?, characterHint: String?) -> AppUserAvatar {
        let resolved = avatar(for: userID, photoURL: photoURL)
        guard characterID(for: userID) == nil,
              let hint = CharacterSyncDecision.normalized(characterHint),
              knownIDs.contains(hint)
        else { return resolved }
        if case .photo(let url, _) = resolved { return .photo(url, fallbackCharacterID: hint) }
        return .character(hint)
    }
}

// MARK: - Avatar view

/// 원형 아바타. 사진 → 착용 캐릭터 → 이니셜 순으로 그린다(위 머리 주석). 사진은 비동기 원격 이미지를 원형으로 그리고,
/// 불러오는 중·실패면 그 사람의 캐릭터(모르면 이니셜 + 해시색)로 떨어진다.
/// 행 아바타 기준 크기는 26pt. 레티나 선명도를 위해 원본 비트맵을 그대로 고해상 보간한다.
struct CheckAvatarView: View {
    let name: String
    /// 이 사람의 사용자 id — 캐릭터 한 표에서 착용 캐릭터를 찾는 열쇠. **기본값이 없다**: 빠뜨린 호출부는 컴파일이 막는다
    /// (기본값을 두면 그 자리만 조용히 이니셜로 남는다). 사람이 아닌 자리(팀 리그 줄)와 id 를 모르는 자리만 nil 을 **명시**한다 —
    /// 어느 자리가 nil 인지는 `V0335AvatarCharacterTests` 의 소스 계약이 센다.
    let userID: String?
    var avatarURL: URL? = nil
    var size: CGFloat = 26
    /// 소속 센터("서울"/"부산"). nil 이면 배지를 안 그린다 — 기존 호출부는 기본값으로 무영향이다.
    var center: String? = nil
    /// 호출부가 이미 받은 착용값(서버 원문 — 오목 행). 표가 이 사람을 모를 때만 쓴다(`avatar(for:photoURL:characterHint:)`).
    var characterHint: String? = nil

    @Environment(\.appUserCharacters) private var characters

    var body: some View {
        AppUserAvatarFace(
            avatar: characters.avatar(for: userID, photoURL: avatarURL, characterHint: characterHint),
            name: name,
            size: size
        )
            // overlay 라서 **레이아웃 폭을 1pt 도 안 쓴다.** 이름 몫(콕찌르기 81.05pt)이 그대로인 이유가 이것이다.
            .overlay(alignment: .bottomTrailing) {
                if let center { CenterCornerBadge(label: center, avatarSize: size) }
            }
    }
}

/// 판정 결과 → 그림(얼굴 한 벌). 원형 자르기 · 테두리는 얼굴마다 같다(사진 · 캐릭터 · 이니셜이 한 목록에 섞여도 같은 원).
/// **이니셜 원은 이 뷰(와 사진 실패 폴백)에서만** 그린다 — 호출부가 `InitialAvatar` 를 직접 그리면 표를 건너뛴다.
struct AppUserAvatarFace: View {
    let avatar: AppUserAvatar
    let name: String
    let size: CGFloat

    var body: some View {
        if case .photo(let url, _) = avatar {
            RemoteAvatarView(name: name, url: url, size: size, fallback: avatar.afterPhotoFailure)
        } else {
            AppUserAvatarStill(avatar: avatar, name: name, size: size)
        }
    }
}

/// 사진이 아닌 얼굴(캐릭터 · 이니셜). 사진 로딩 중·실패의 폴백도 이것을 그린다.
private struct AppUserAvatarStill: View {
    let avatar: AppUserAvatar
    let name: String
    let size: CGFloat

    var body: some View {
        if case .character(let id) = avatar, let portrait = AppUserAvatarArt.portrait(characterID: id) {
            CharacterAvatarFace(portrait: portrait, size: size)
        } else {
            // 모르는 사람 · 초상을 그릴 수 없는 캐릭터(에셋 결손) — 아잉으로 단정하지 않고 이니셜.
            InitialAvatar(name: name, size: size)
        }
    }
}

/// 다른 사람의 착용 캐릭터 얼굴 — neutral 초상을 받침 원 안에. 링·표정 변화는 없다(남의 근무 상태는 이 자리가 말하지 않는다).
///
/// ★ 캐릭터마다 여백이 다르므로(아잉 실루엣은 192² 캔버스의 세로 80%) 원본을 그대로 줄이면 크기가 들쭉날쭉하다. 그래서
///   **알파 상자로 조인 초상**(`AppUserAvatarArt.portrait`)을 `portraitBox(diameter:artSize:)` 가 준 상자에 넣는다 —
///   높이를 지름에 맞추고 폭은 원본 비대로 따라간다(가로형은 상한에 걸려 줄어든다).
/// ★ **정사각 상자 + `scaledToFit` 이 아니다.** 그러면 가로가 세로보다 넓은 아잉만 폭 기준으로 맞춰져 혼자 작아진다 —
///   폭·높이를 직접 준다(상자가 이미 원본 비라 `scaledToFit` 은 할 일이 없다).
/// ★ `Image(nsImage:)` 는 `.interpolation` 을 무시한다(`CharacterPortrait` 주석 — 2026-09-13 실측). 그래서 CGImage 로 그린다.
///   보간은 `.high` 다: 여기는 192px 짜리 조인 초상을 16~34pt(@2x 로 33~70px)에 앉히는 자리라 2.7~5.8배 축소다 —
///   이웃 보간은 픽셀을 너무 많이 버린다(메뉴바 18pt 와 같은 이유 — `CheckMascotAssets.currentCharacterIsPixelArt()` 주석).
private struct CharacterAvatarFace: View {
    let portrait: CGImage
    let size: CGFloat

    var body: some View {
        let box = AppUserAvatarArt.portraitBox(
            diameter: size,
            artSize: CGSize(width: portrait.width, height: portrait.height)
        )
        ZStack {
            Circle().fill(AppUserAvatarArt.backdrop)
            Image(decorative: portrait, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: box.width, height: box.height)
                .offset(y: box.offsetY)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// 사람 아바타에 그릴 캐릭터 초상(맥). 초상은 **이미 `check_check.bundle` 에 있다** — `Characters/<id>/portrait-neutral.png` 와
/// 아잉 `aing-neutral.png`(`CheckMascotAssets.portraitURL(for: .neutral, characterID:)` 가 둘 다 찾는다). 새 자원 번들을 만들지 않으므로
/// 배포 스크립트(`scripts/build-local.sh` — `check_check.bundle` 하나만 복사한다)는 고칠 것이 없다(코어 `AppUserCharacters.swift` 머리 결정).
enum AppUserAvatarArt {
    /// 원 안에 놓을 그림 상자(pt). 지름과 **원본 그림의 비**만으로 정해지는 순수 계산이다 —
    /// `portraitBox(diameter:artSize:)` 만 만든다.
    struct PortraitBox: Equatable {
        var width: CGFloat
        var height: CGFloat
        /// 위로 올리는 양(음수 = 위). **아래 끝을 원 아래 끝에 맞춘다** — 레퍼런스가 그 자리라서다.
        /// 그래도 발 가장자리는 잘린다(아래 15% 행 실측 0~38.7% · 레퍼런스 20.9%). 통째로 없어지지 않을 뿐이다.
        var offsetY: CGFloat
    }

    /// **높이 기준**: 조인 그림의 높이를 지름의 이 배로 맞춘다. 폭은 원본 비대로 따라간다.
    ///
    /// ### 레퍼런스 1.018 / 0.800 이 어디서 나왔나
    /// 기준은 조영서 님이 **프로필 사진으로 올린 그림**이다(110×130 JPG — 2026-09-21). 사진 아바타는
    /// `scaledToFill` + 원형 자르기라, 그 사진 좌표로 되짚으면 원은 **지름 110px(=사진 폭) · 중심 (55, 65)** 이다.
    /// 그 원을 기준으로 배경색과 28 이상 다른 픽셀의 상자를 재면 x 14~101 · y 8~119 —
    /// **높이 112px = 1.018 지름 · 폭 88px = 0.800 지름**, 상자 중심은 원 중심에서 0.009 지름만 위,
    /// 위 끝 −0.518 · **아래 끝 +0.500(원 아래 끝에 정확히 닿는다)**.
    ///
    /// ### 레퍼런스도 잘린다
    /// 그 원에서 실루엣의 **5.4%** 가 원 밖이다 — 위 15% 행 28.5% · **아래 15% 행 20.9%**.
    /// 그러니 "발끝이 남는다"가 아니라 **발 가장자리도 잘리되 통째로 사라지지는 않는다**가 맞다.
    /// 여섯 캐릭터 × 열한 후보를 나란히 구워 골랐다(@26pt 실측):
    /// - 옛 값(정사각 1.20 · 아래로 +0.15)은 **아래 15% 행이 여섯 다 100% 잘렸다**(전체 잘림 19.9~33.3%) — 발이 통째로 없어졌다.
    /// - 이 값(높이 1.03 · 위로 0.015)은 전체 잘림 2.2~8.7%(레퍼런스 5.4%), 아래 15% 행 0~38.7%(레퍼런스 20.9%).
    /// 1.018 이 아니라 1.03 인 이유는 26pt 에서 얼굴이 읽히려면 작은 쪽으로 기울면 안 되기 때문이다(+1.2%).
    static let artHeightFraction: CGFloat = 1.03
    /// **가로 상한**: 폭이 지름의 이 배를 넘으면 폭을 여기에 맞추고 높이를 비율대로 줄인다.
    /// 여섯 중 가로가 세로보다 넓은 **아잉(조인 164×154 — 비 1.065)만** 걸린다: 높이 1.03 이면 폭이 1.097 이 돼 팔이 좌우로 잘린다.
    /// 유령(비 0.984)은 폭 1.014 로 아슬하게 안 걸린다 — 상한을 1.01 로 낮추면 유령도 걸려 혼자 작아진다.
    static let artMaxWidthFraction: CGFloat = 1.02
    /// 그림을 **위로** 올리는 양(지름 대비). 레퍼런스처럼 **아래 끝을 원 아래 끝(+0.500)에 맞춘** 값이다 —
    /// 중심 = 0.500 − 1.03/2 = **−0.015**. (레퍼런스 자신의 중심은 −0.009 다. 높이가 1.018 이라 그만큼만 올라간다.)
    /// 옛 값은 +0.15(아래로)였고, 그것이 아래 15% 행을 통째로 잘라 먹은 범인이다.
    static let artOffsetFraction: CGFloat = -0.015
    /// 받침 원. 어두운 행 위에서 캐릭터 윤곽이 묻히지 않을 만큼만 밝다.
    static let backdrop = Color.white.opacity(0.14)

    /// 지름과 원본 비로 그림 상자를 정한다. **순수 함수** — 뷰 없이 값으로 검증한다(`V0336AvatarArtTests`).
    /// 원본 비를 모를 때(0·음수 크기)는 정사각으로 접는다 — 그림이 사라지는 것보다 낫다.
    nonisolated static func portraitBox(diameter: CGFloat, artSize: CGSize) -> PortraitBox {
        let offsetY = diameter * artOffsetFraction
        guard diameter > 0, artSize.width > 0, artSize.height > 0 else {
            let side = max(0, diameter) * artHeightFraction
            return PortraitBox(width: side, height: side, offsetY: offsetY)
        }
        var height = diameter * artHeightFraction
        var width = height * (artSize.width / artSize.height)
        let maxWidth = diameter * artMaxWidthFraction
        if width > maxWidth {
            width = maxWidth
            height = width * (artSize.height / artSize.width)
        }
        return PortraitBox(width: width, height: height, offsetY: offsetY)
    }

    /// 이 빌드가 **초상을 그릴 수 있는** 캐릭터 id(아잉 포함). 캐릭터 한 표의 '아는 캐릭터'다 — 목록에 있어도 초상이 없는 id 를
    /// '안다'고 하면 빈 그림이 선다(코어 접기 규칙). 번들 카탈로그를 한 번 훑는다.
    static let knownIDs: [String] = CheckMascotAssets.catalog.allIDs.filter { id in
        guard let url = CheckMascotAssets.portraitURL(for: .neutral, characterID: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 알파 상자로 조인 neutral 초상. 캐릭터당 한 번만 디코드·조인한다(행은 hover·갱신마다 다시 그려진다).
    /// 초상이 없거나 깨졌으면 nil — **아잉으로 폴백하지 않는다**(호출부가 이니셜을 그린다).
    ///
    /// ★ 모르는 id 를 끊는 가드가 **따로 없는 이유**: `portraitURL(for:characterID:)` 자체가 카탈로그에 없는 id 에 nil 을 준다.
    ///   폴백이 있는 함수(`CheckMascotAssets.image(for:characterID:)` · `CharacterCardArt.image`)를 여기에 끼우면 그 순간
    ///   **남의 얼굴에 아잉이 선다** — 2026-09-21 에 한 번 그렇게 바꿨다가 되돌렸다(머리 주석 ★).
    @MainActor
    static func portrait(characterID: String) -> CGImage? {
        if let hit = cache[characterID] { return hit }
        guard let url = CheckMascotAssets.portraitURL(for: .neutral, characterID: characterID),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let tight = CharacterCardArt.tightened(raw)
        cache[characterID] = tight
        return tight
    }

    @MainActor private static var cache: [String: CGImage] = [:]
}

/// 아바타 모서리에 얹는 소속 센터 배지. 두 글자를 그대로 적는다.
/// 캡슐 폭이 아바타 지름을 넘지 않게 잡아 이웃(이름 텍스트)과 겹치지 않는다 —
/// overlay 는 폭을 안 쓰지만 **그림은 이웃 위에 그려지므로** 넘치면 이름 첫 글자를 덮는다.
struct CenterCornerBadge: View {
    let label: String
    let avatarSize: CGFloat

    /// 글자 크기는 아바타에 비례시킨다(26pt 아바타 → 7pt). 화면마다 아바타가 22~30pt 로 달라서
    /// 고정값을 쓰면 미니게임(22pt)에서만 배지가 아바타를 잡아먹는다.
    private var fontSize: CGFloat { max(6, (avatarSize * 0.24).rounded()) }

    var body: some View {
        Text(label)
            // .rounded 는 작은 한글에서 획을 굵게 유지해 1× 에서 덜 뭉갠다.
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            // 어두운 알약 + 흰 글자. 아바타 해시색이 무엇이든 대비가 유지된다(아바타 색은 사람마다 다르다).
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.5))
            // x 를 더 주면 캡슐이 아바타 오른쪽으로 나가지만, 아바타와 이름 사이 간격이 10pt 라
            // 이름 글자를 덮지는 않는다(콕찌르기 행 기준 넘침 4pt).
            .offset(x: 4, y: 2)
    }
}

// MARK: - Initial (fallback) avatar

/// 이름 이니셜 + 해시색 원형 아바타. **캐릭터를 모를 때만** 쓰는 마지막 폴백이다(사진 실패는 먼저 캐릭터로 떨어진다).
/// `AppUserAvatarStill` 이 판정 결과가 이니셜일 때 그린다 — 호출부가 직접 그리지 않는다.
struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 30

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    var body: some View {
        let color = CheckTheme.avatarColor(for: name)
        Text(initial)
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Remote avatar

/// URL 기반 원형 이미지 아바타.
/// - file URL 또는 캐시 hit은 동기 로드해 스냅샷/첫 프레임에서도 즉시 표시된다.
/// - http(s) URL은 `URLSession`으로 비동기 로드하고 성공 시 `NSCache`에 저장한다.
/// - 로딩 중/실패 시에는 `fallback`(= `AppUserAvatar.afterPhotoFailure` — 그 사람의 캐릭터, 모르면 이니셜)을 그린다.
private struct RemoteAvatarView: View {
    let name: String
    let url: URL
    let size: CGFloat
    /// 불러오는 중·실패 때 그릴 얼굴. 사진이 아닌 판정(캐릭터 · 이니셜)만 온다.
    let fallback: AppUserAvatar

    @State private var loaded: NSImage?

    var body: some View {
        Group {
            if let image = loaded ?? AvatarImageCache.shared.synchronousImage(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            } else {
                AppUserAvatarStill(avatar: fallback, name: name, size: size)
            }
        }
        .task(id: url) {
            loaded = await AvatarImageCache.shared.image(for: url)
        }
    }
}

/// URL별 아바타 이미지 캐시. 동기 경로(file URL·캐시 hit)와 비동기 네트워크 로드를 함께 제공한다.
/// 내부 저장소는 `NSCache`로 스레드 세이프하다.
final class AvatarImageCache: @unchecked Sendable {
    static let shared = AvatarImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {}

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// 캐시 hit 또는 file URL은 즉시 이미지를 돌려준다(스냅샷/첫 프레임 대응). 그 외엔 nil.
    func synchronousImage(for url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard url.isFileURL, let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// 캐시 → file URL 동기 로드 → http(s) 비동기 로드 순으로 이미지를 얻는다. 실패 시 nil.
    func image(for url: URL) async -> NSImage? {
        if let image = synchronousImage(for: url) {
            return image
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: - Editable avatar (own row)

/// 내 행 전용 아바타. hover 시 카메라 배지를 덧씌우고, 클릭하면 이미지 파일 선택 패널을 연다.
/// 선택된 이미지는 최장변 256px JPEG로 다운스케일해 `onPick(Data)`로 전달한다.
/// 얼굴은 남의 아바타와 같은 규칙이다(사진 → 내 착용 캐릭터 → 이니셜) — 사진을 안 올렸으면 내 캐릭터가 선다.
struct EditableAvatarView: View {
    let name: String
    /// 내 사용자 id(`CheckAvatarView.userID` 와 같은 규약 — 기본값 없음).
    let userID: String?
    var avatarURL: URL? = nil
    var size: CGFloat = 26
    let onPick: (Data) -> Void

    @State private var hovering = false

    var body: some View {
        CheckAvatarView(name: name, userID: userID, avatarURL: avatarURL, size: size)
            .overlay {
                if hovering {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.48))
                        Image(systemName: "camera.fill")
                            .font(.system(size: size * 0.36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size, height: size)
                }
            }
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .onTapGesture { presentPicker() }
            .checkTooltip("아바타 변경")
    }

    // 공개 이미지 타입(png/jpeg/heic)만 허용하는 열기 패널. 취소·비이미지·로드 실패는 조용히 무시.
    private func presentPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "선택"
        panel.message = "아바타로 사용할 이미지를 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // 원본 디코드+다운스케일은 무거워 메인 액터를 순간 멈출 수 있으므로 백그라운드에서 처리하고 결과만 메인에서 전달한다.
        Task { @MainActor in
            guard let data = await CheckAvatarView.decodeDownscaledJPEGData(from: url) else { return }
            onPick(data)
        }
    }
}

// MARK: - Downscale (pure)

extension CheckAvatarView {
    /// 원본 픽셀 크기를 최장변이 `maxDimension`을 넘지 않도록 종횡비를 유지해 축소한다.
    /// 최장변이 이미 `maxDimension` 이하면 원본 크기를 그대로 돌려준다(확대하지 않음).
    /// 순수 함수 — 그래픽 컨텍스트 없이 크기 계산만 하므로 단위 테스트 대상이다.
    nonisolated static func downscaledPixelSize(for source: CGSize, maxDimension: CGFloat = 256) -> CGSize {
        let longest = max(source.width, source.height)
        guard longest > maxDimension, longest > 0 else {
            return source
        }
        let scale = maxDimension / longest
        return CGSize(
            width: max(1, (source.width * scale).rounded()),
            height: max(1, (source.height * scale).rounded())
        )
    }

    /// 이미지를 최장변 256px 로 줄인 JPEG(압축 0.85) Data 로. 실패 시 nil.
    ///
    /// ── 왜 ImageIO 썸네일인가 (2026-09-21, 다른 세션의 램 스윕이 넘긴 실측) ──
    /// 옛 구현은 `NSImage.tiffRepresentation`(원본 해상도 **무압축** TIFF)을 만들고 그 Data 로 `NSBitmapImageRep` 를 하나 더 떠서
    /// **둘을 동시에** 들고 있었다. 256px 축소는 그 뒤였으므로 **피크가 원본 픽셀 수에 비례**했다 — 8064×6048 JPEG(20.7MB) 하나로
    /// 피크 307.9MB(측정), 게다가 TIFF 가 autorelease 라 함수가 돌아온 뒤에도 바로 안 내려왔다. 사진 앱에서 고른 요즘 사진 한 장이
    /// 메뉴바 앱의 메모리를 통째로 끌어올린다("앱이 램 1기가 먹는다" 제보의 두 번째 원인).
    ///
    /// ImageIO 는 축소본을 **직접** 만든다(JPEG 은 DCT 단계에서 서브샘플 디코드). 같은 입력에서 피크가 한 자릿수 MB 대로 떨어지고
    /// 결과 바이트는 사실상 같다. 폰이 이미 같은 방식이다(`MeAvatarImage.jpegData` — 규칙·옵션까지 같은 한 벌).
    ///
    /// ── 규칙(옛 구현과 같다) ──
    /// 최장변 `maxDimension` 으로 비율 유지 축소 · 원본이 더 작으면 **키우지 않는다**(`ThumbnailMaxPixelSize` 는 확대하지 않는다) ·
    /// JPEG 품질 `compression`. 크기 계산의 정본은 여전히 `downscaledPixelSize` 이고, 이 경로의 결과가 그 계산과 일치하는지는
    /// 테스트가 실제 픽셀로 되묻는다.
    ///
    /// ── EXIF 회전: 적용한다(`kCGImageSourceCreateThumbnailWithTransform: true`) ──
    /// 옛 경로도 결과적으로 적용했다 — `NSImage` 는 EXIF 방향을 반영해 그리고 `tiffRepresentation` 은 그려진 결과를 뜬다.
    /// 끄면 아이폰으로 세로로 찍은 사진이 **옆으로 누운 채** 올라간다. 폰도 같은 옵션이다.
    ///
    /// ── 투명 PNG: 흰 바탕을 **명시해서** 깐다 ──
    /// JPEG 에는 알파가 없다. 옛 `NSBitmapImageRep` 경로도 투명 자리를 흰색으로 구웠고(벤치 실측: 완전 투명·반투명 PNG 둘 다
    /// `rgb(255,255,255)`), 새 경로도 같은 결과를 내야 한다 — 그런데 `CGImageDestination` 은 알파를 어떻게 버릴지 보장하지 않으므로
    /// **우리가 흰 바탕에 한 번 그려서 고정한다**. 폰도 같은 처방이다(`MeAvatarImage.flattenedOnWhite`) — 같은 사진이 맥과 폰에서
    /// 다르게 올라가지 않게 규칙을 한 벌로 둔다.
    nonisolated static func downscaledJPEGData(from data: Data, maxDimension: CGFloat = 256, compression: CGFloat = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downscaledJPEGData(from: source, maxDimension: maxDimension, compression: compression)
    }

    /// 파일 URL 이미지를 백그라운드(detached)에서 줄여 JPEG Data 로. 실패 시 nil.
    /// **파일을 Data 로 먼저 읽지 않는다** — `CGImageSourceCreateWithURL` 은 필요한 만큼만 읽으므로 20MB 사진의 바이트가
    /// 통째로 메모리에 올라오지 않는다(이 경로가 실제 업로드 경로다 — `EditableAvatarView` 의 파일 선택).
    nonisolated static func decodeDownscaledJPEGData(from url: URL, maxDimension: CGFloat = 256, compression: CGFloat = 0.85) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return downscaledJPEGData(from: source, maxDimension: maxDimension, compression: compression)
        }.value
    }

    /// 두 진입로의 공통 몸통. 이미지가 없는 파일(비이미지·깨진 바이트)이면 nil.
    private nonisolated static func downscaledJPEGData(
        from source: CGImageSource, maxDimension: CGFloat, compression: CGFloat
    ) -> Data? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            // 박혀 있는 EXIF 썸네일(작고 거칠다)을 쓰지 않고 본 이미지에서 만든다.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension.rounded()),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let flattened = flattenedOnWhite(thumbnail) ?? thumbnail
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(
            destination, flattened, [kCGImageDestinationLossyCompressionQuality: compression] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 투명 PNG 가 검게 올라가지 않게 흰 바탕에 한 번 그린다(폰 `MeAvatarImage.flattenedOnWhite` 와 같은 처방).
    /// 썸네일 크기(≤ maxDimension)에서만 도는 그리기라 비용이 작다.
    private nonisolated static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
