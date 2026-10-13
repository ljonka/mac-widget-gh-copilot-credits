#!/bin/bash
set -euo pipefail
label="com.ljonka.copilot-credits"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$HOME/Applications/CopilotCredits.app"
echo "CopilotCredits deinstalliert. Tageswerte bleiben in ~/Library/Application Support/CopilotCredits."
