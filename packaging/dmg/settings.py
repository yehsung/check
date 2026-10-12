# dmgbuild 설정 — scripts/package-dmg.sh 가 부른다. 직접 돌릴 일은 없다.
#
# dmgbuild 는 이 파일을 옵션 사전 안에서 exec 한다: __file__ 이 없어서 경로는 전부 -D 로 받고,
# 여기서 만드는 최상위 이름은 전부 옵션이 된다 — 옵션 이름(size, icon, files, background …)과 겹치는
# 임시 변수를 만들지 말 것(내부용은 대문자/밑줄로).
#
#   -D app=<스테이플된 .app>   -D dmg_dir=<packaging/dmg>   -D volume_icon=<AppIcon.icns>
#
# ★ 좌표는 background.html 과 짝이다. 한쪽만 바꾸면 아이콘이 그림의 카드 밖으로 빠진다 —
#   둘 다 고치고 `node packaging/dmg/render-background.mjs` 로 다시 구워라.
import os.path

APP_PATH = defines["app"]  # noqa: F821 — dmgbuild 가 넣어 준다
DMG_DIR = defines["dmg_dir"]  # noqa: F821
APP_NAME = os.path.basename(APP_PATH.rstrip("/"))

# Finder 의 WindowBounds 는 제목 막대까지 포함한 창 전체다(2026-10-12 macOS 27 실측: 프레임 = WindowBounds,
# y 는 화면 아래에서 잰다). 그래서 창을 내용 640x400 + 제목 막대 28 로 잡고, 배경은 아래로 20 더 길게 굽는다 —
# 제목 막대가 더 얇은 macOS 에서도 그림 밖 빈 띠가 드러나지 않게. 보이는 내용 기준 좌표는 아래 그대로다.
CONTENT_W, CONTENT_H = 640, 400
TITLEBAR_H = 28
BACKGROUND_W, BACKGROUND_H = 640, 420  # 배경 1x 크기(2x 는 1280x840) — package-dmg.sh 가 이 줄로 PNG 크기를 검사한다
ICON_Y = 228
APP_X = 160
APPS_X = 480

# 내용물
format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [APP_PATH]
symlinks = {"Applications": "/Applications"}
# hide_extensions 는 쓰지 않는다: SetFile -a E 가 .app 번들에 com.apple.FinderInfo xattr 를 붙여
# `codesign --verify --strict` 가 "Finder information ... detritus not allowed" 로 거절하고, 끌어다 놓은 설치본에도
# 그대로 따라간다(2026-10-12 실측). .app 확장자는 Finder 가 기본으로 숨긴다.

# 볼륨 아이콘 · 배경
icon = defines["volume_icon"]  # noqa: F821
# 같은 폴더의 background@2x.png 를 dmgbuild 가 찾아 tiffutil -cathidpicheck 로 한 장의 HiDPI TIFF 로 묶는다
# (.background.tiff). 2x 가 정확히 두 배가 아니면 tiffutil 이 거절한다.
background = os.path.join(DMG_DIR, "background.png")

# 창 — 도구막대·사이드바·경로막대·상태막대 없이 그림만
window_rect = ((200, 360), (CONTENT_W, CONTENT_H + TITLEBAR_H))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False
arrange_by = None
grid_offset = (0, 0)
icon_size = 128
text_size = 13
label_pos = "bottom"

# Iloc 은 아이콘 그림의 중심이다
icon_locations = {
    APP_NAME: (APP_X, ICON_Y),
    "Applications": (APPS_X, ICON_Y),
}
