#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

gh_path="$(command -v gh)"
gh auth status --hostname github.com >/dev/null
swift test
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
"$bin_dir/CopilotCredits" --check

app="$HOME/Applications/CopilotCredits.app"
label="com.ljonka.copilot-credits"
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
launchctl bootout "$domain/$label" 2>/dev/null || true
mkdir -p "$app/Contents/MacOS" "$(dirname "$agent")"
cp "$bin_dir/CopilotCredits" "$app/Contents/MacOS/CopilotCredits"

/usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
for pair in "CFBundleIdentifier:$label" "CFBundleName:CopilotCredits" \
            "CFBundleExecutable:CopilotCredits" "CFBundlePackageType:APPL" \
            "CFBundleShortVersionString:1.0" "LSMinimumSystemVersion:13.0" "GHCliPath:$gh_path"; do
    /usr/bin/plutil -insert "${pair%%:*}" -string "${pair#*:}" "$app/Contents/Info.plist"
done
/usr/bin/plutil -insert LSUIElement -bool true "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"

/usr/bin/plutil -create xml1 "$agent"
/usr/bin/plutil -insert Label -string "$label" "$agent"
/usr/bin/plutil -insert ProgramArguments -json "[]" "$agent"
/usr/bin/plutil -insert ProgramArguments.0 -string "$app/Contents/MacOS/CopilotCredits" "$agent"
/usr/bin/plutil -insert RunAtLoad -bool true "$agent"
/usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$agent"
launchctl bootstrap "$domain" "$agent"
echo "Installiert und gestartet: $app (Autostart bei Anmeldung)"
