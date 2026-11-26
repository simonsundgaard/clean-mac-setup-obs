#!/bin/bash
# Clean Mac setup for OBS machine
# Run: chmod +x clean-mac-setup.sh && ./clean-mac-setup.sh
set -e

# ---------- Choose optional installs up front ----------
echo "Optional installs:"
echo "  1) Homebrew + OBS"
echo "  2) Blackmagic Desktop Video"
read -r -p "Enter numbers separated by spaces (e.g. '1 2'), or press Enter for none: " choices
INSTALL_OBS=false; INSTALL_DV=false
for c in $choices; do
  case "$c" in
    1) INSTALL_OBS=true ;;
    2) INSTALL_DV=true ;;
    *) echo "Ignoring unknown choice: $c" ;;
  esac
done

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

# Verify: on a fresh Mac the Dock can restore its old layout on restart
dock_count() { defaults read com.apple.dock persistent-apps 2>/dev/null | grep -c tile-type || true; }
sleep 3
if [ "$(dock_count)" -gt 0 ]; then
  echo "Dock not empty yet, trying again..."
  defaults write com.apple.dock persistent-apps -array
  killall Dock
  sleep 3
  if [ "$(dock_count)" -gt 0 ]; then
    echo "WARNING: Dock still has apps. Restart the Mac and run the script again."
  fi
fi

echo "== Desktop widgets: hide (Sonoma+) =="
defaults write com.apple.WindowManager StandardHideWidgets -bool true
defaults write com.apple.WindowManager StageManagerHideWidgets -bool true

echo "== Power: never sleep on charger (needs sudo) =="
sudo pmset -c sleep 0 displaysleep 0 disksleep 0

echo "== Screensaver + lock: off =="
defaults -currentHost write com.apple.screensaver idleTime -int 0
sysadminctl -screenLock off -password -   # prompts for your login password

# ---------- Optional: Homebrew + OBS ----------
if $INSTALL_OBS; then
  if ! command -v brew >/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  # brew refuses (and would stop the script) if OBS was installed by hand
  if [ -d "/Applications/OBS.app" ]; then
    echo "OBS is already installed, skipping."
  else
    brew install --cask obs
  fi
fi

# ---------- Optional: Blackmagic Desktop Video ----------
# Download via Blackmagic's (undocumented) download API. Request format adapted from
# https://github.com/pardeyke/homebrew-blackmagic (BSD-2-Clause, (c) Jonas Pardeyke).
# Pinned version: update BMD_DV_ID from that tap's Casks/blackmagic-desktop-video.rb.
BMD_DV_VERSION="16.3"
BMD_DV_ID="79712b31f62d4d449396231781252708"

# Every command checks its own exit code: set -e is ignored when called from "if"
install_desktop_video() (
  tmp="$(mktemp -d /private/tmp/bmd-dv.XXXXXX)" || exit 1
  trap 'hdiutil detach "$tmp/mnt" -force >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT

  url="$(curl -fsS -X POST -H 'Content-Type: application/json' \
    -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)' \
    -d '{"platform":"Mac OS X","policy":true,"country":"us","downloadOnly":true}' \
    "https://www.blackmagicdesign.com/api/register/us/download/$BMD_DV_ID")" || exit 1
  [[ "$url" == https://sw.blackmagicdesign.com/* ]] || { echo "Unexpected download URL: $url" >&2; exit 1; }

  echo "Downloading Desktop Video $BMD_DV_VERSION..."
  curl -fL --progress-bar -o "$tmp/dv.zip" "$url" || exit 1
  ditto -x -k "$tmp/dv.zip" "$tmp/unzipped" || exit 1

  pkg="$(find "$tmp/unzipped" -maxdepth 3 -iname '*.pkg' -print -quit)"
  if [ -z "$pkg" ]; then
    dmg="$(find "$tmp/unzipped" -maxdepth 3 -iname '*.dmg' -print -quit)"
    [ -n "$dmg" ] || { echo "No installer found in download" >&2; exit 1; }
    mkdir "$tmp/mnt" || exit 1
    printf 'Y\n' | hdiutil attach -nobrowse -readonly -mountpoint "$tmp/mnt" "$dmg" >/dev/null || exit 1
    pkg="$(find "$tmp/mnt" -maxdepth 3 -iname '*.pkg' -print -quit)"
    [ -n "$pkg" ] || { echo "No .pkg found inside $dmg" >&2; exit 1; }
  fi

  # Refuse anything not signed by Blackmagic and accepted by Gatekeeper
  pkgutil --check-signature "$pkg" | grep -q "Developer ID Installer: Blackmagic Design" \
    || { echo "Installer is not signed by Blackmagic Design, refusing to install" >&2; exit 1; }
  spctl --assess --type install "$pkg" \
    || { echo "Gatekeeper rejected the installer, refusing to install" >&2; exit 1; }

  sudo installer -pkg "$pkg" -target /
)

if $INSTALL_DV; then
  echo "== Blackmagic Desktop Video $BMD_DV_VERSION =="
  if install_desktop_video; then
    echo "Desktop Video installed. Approve the Blackmagic extension in"
    echo "System Settings > Privacy & Security, then restart."
  else
    echo "WARNING: Desktop Video install failed. Download it manually from"
    echo "https://www.blackmagicdesign.com/support/family/capture-and-playback"
  fi
fi

echo "Done. Log out/in or reboot to be sure everything applied."
