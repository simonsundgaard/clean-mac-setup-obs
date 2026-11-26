#!/bin/bash
# Clean Mac setup for OBS machine
# Run: chmod +x mac-setup.sh && ./mac-setup.sh
set -e

echo "== Dock: remove all apps (Finder + Trash stay) =="
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock persistent-others -array
defaults write com.apple.dock show-recents -bool false

echo "== Hot corners: disable all =="
for c in tl tr bl br; do
  defaults write com.apple.dock "wvous-$c-corner" -int 1
  defaults write com.apple.dock "wvous-$c-modifier" -int 0
done

killall Dock

echo "== Desktop widgets: hide (Sonoma+) =="
defaults write com.apple.WindowManager StandardHideWidgets -bool true
defaults write com.apple.WindowManager StageManagerHideWidgets -bool true

echo "== Power: never sleep on charger (needs sudo) =="
sudo pmset -c sleep 0 displaysleep 0 disksleep 0

echo "== Screensaver + lock: off =="
defaults -currentHost write com.apple.screensaver idleTime -int 0
sysadminctl -screenLock off -password -   # prompts for your login password

# ---------- Optional: Homebrew + OBS ----------
read -r -p "Install Homebrew + OBS? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  if ! command -v brew >/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  brew install --cask obs
fi

echo "Done. Log out/in or reboot to be sure everything applied."
