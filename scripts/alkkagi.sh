#!/bin/sh
set -eu
task_repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_package="$task_repo_root/playgrounds/alkkagi"

case "${1:-run}" in
    run)
        exec swift run --package-path "$task_package" AlkkagiPlayground
        ;;
    test)
        shift
        exec swift test --package-path "$task_package" "$@"
        ;;
    build)
        exec swift build --package-path "$task_package"
        ;;
    app)
        swift build --package-path "$task_package"
        task_bin=$(swift build --package-path "$task_package" --show-bin-path)
        task_app="$task_package/.build/Alkkagi Playground.app"
        mkdir -p "$task_app/Contents/MacOS"
        cp "$task_bin/AlkkagiPlayground" "$task_app/Contents/MacOS/AlkkagiPlayground"
        cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.aingcheck.alkkagi.playground</string>
<key>CFBundleName</key><string>Alkkagi Playground</string>
<key>CFBundleExecutable</key><string>AlkkagiPlayground</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
        printf '%s\n' "$task_app"
        ;;
    *)
        printf '%s\n' '사용법: ./scripts/alkkagi.sh [run|test [--filter 이름]|build|app]' >&2
        exit 2
        ;;
esac
