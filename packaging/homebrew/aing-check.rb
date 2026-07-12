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
