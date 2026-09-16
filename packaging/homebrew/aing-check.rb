# Homebrew Cask 템플릿.
# scripts/release-brew.sh 가 version/sha256/owner 자리표시자를 릴리즈 값으로 치환해
# tap 저장소(<owner>/homebrew-check)의 Casks/aing-check.rb 로 복사합니다.
# 직접 수정할 필요는 없습니다. 배포 흐름은 docs/release.md 참고.
cask "aing-check" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/__GH_OWNER__/check/releases/download/v#{version}/aing-check.zip"
  name "aing-check"
  desc "Menu bar work-status and timer utility for small Mac teams"
  homepage "https://github.com/__GH_OWNER__/check"

  depends_on macos: :sonoma

  # 배포 zip 은 aing-check/ 폴더 아래에 aing-check.app 을 담는다 (설치하기.command 동봉).
  app "aing-check/aing-check.app"

  # 앱은 Developer ID 서명 + 공증 + 스테이플되어 있으므로 quarantine 조치 불필요.

  # quit 훅과 짝: 설치/업그레이드가 끝나면 앱을 백그라운드로 재실행한다.
  # 이게 없으면 업그레이드가 앱을 종료만 하고 방치해, 사용자가 눈치채기 전까지 근무가 기록되지 않는다.
  # brew 7: 블록형 postflight 은 낡음 경고 → postflight_steps. 경로는 Ruby 보간이 아니라 {{appdir}} 토큰이어야 한다
  # (보간을 두면 cask 가 통째로 안 읽힌다). must_succeed: false — 재실행은 덤이다. 새 맥에선 옮긴 직후
  # LaunchServices 등록이 늦어 open 이 kLSNoExecutableErr(-10827)로 실패할 수 있고, run 의 기본값(true)은
  # 그 실패로 설치 전체를 되돌린다(2026-09-17 신규 설치 실패 신고).
  postflight_steps do
    run "/usr/bin/open", args: ["-g", "{{appdir}}/aing-check.app"], must_succeed: false
  end

  # 삭제/업그레이드 시 실행 중인 앱을 먼저 종료한다(앱의 종료 훅이 근무중이면 퇴근 동기화 후 종료).
  uninstall quit: "kingcheck"

  # 삭제 시 정리: Bundle ID 는 kingcheck.
  zap trash: [
    "~/Library/Preferences/kingcheck.plist",
    "~/Library/Caches/kingcheck",
    "~/Library/HTTPStorages/kingcheck",
    "~/Library/Saved Application State/kingcheck.savedState",
  ]
end
