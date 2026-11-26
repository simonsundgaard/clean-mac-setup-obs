#!/bin/bash
# Clean Mac setup for OBS machine
# Run: chmod +x clean-mac-setup.sh && ./clean-mac-setup.sh
set -e

# ---------- Choose optional installs up front ----------
echo "Optional installs:"
echo "  1) Homebrew + OBS"
echo "  2) Blackmagic Desktop Video"
echo "  3) OBS profile 'vip-engine' (1080p50 settings)"
echo "  4) AnyDesk (via Homebrew)"
echo "  5) TeamViewer (via Homebrew)"
read -r -p "Enter numbers separated by spaces (e.g. '1 2 3'), or press Enter for none: " choices
INSTALL_OBS=false; INSTALL_DV=false; INSTALL_OBS_PROFILE=false; INSTALL_ANYDESK=false; INSTALL_TEAMVIEWER=false
for c in $choices; do
  case "$c" in
    1) INSTALL_OBS=true ;;
    2) INSTALL_DV=true ;;
    3) INSTALL_OBS_PROFILE=true ;;
    4) INSTALL_ANYDESK=true ;;
    5) INSTALL_TEAMVIEWER=true ;;
    *) echo "Ignoring unknown choice: $c" ;;
  esac
done

echo "== Dock: remove all apps (Finder + Trash stay), auto-hide =="
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock persistent-others -array
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock autohide -bool true

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

# ---------- Optional: Homebrew apps (OBS, AnyDesk, TeamViewer) ----------
ensure_brew() {
  if ! command -v brew >/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

# brew refuses (and would stop the script) if the app was installed by hand
brew_cask_install() {  # <cask> <App name in /Applications>
  if [ -d "/Applications/$2.app" ]; then
    echo "$2 is already installed, skipping."
  else
    ensure_brew
    brew install --cask "$1"
  fi
}

if $INSTALL_OBS; then
  echo "== OBS =="
  ensure_brew
  brew_cask_install obs OBS
fi
if $INSTALL_ANYDESK; then
  echo "== AnyDesk =="
  brew_cask_install anydesk AnyDesk
fi
if $INSTALL_TEAMVIEWER; then
  echo "== TeamViewer =="
  brew_cask_install teamviewer TeamViewer
fi

# ---------- Optional: OBS profile ----------
# Fetched from GitHub so it also works when the script is run via curl
OBS_PROFILE_URL="https://raw.githubusercontent.com/simonsundgaard/clean-mac-setup-obs/main/clean-mac-setup/obs/vipengine/basic.ini"
OBS_PROFILE_NAME="vip-engine"
OBS_PROFILE_DIR="vipengine"
OBS_CONFIG="$HOME/Library/Application Support/obs-studio"

install_obs_profile() (
  if pgrep -xiq obs; then   # OBS overwrites its config when it quits
    echo "OBS is running. Quit OBS and run the script again." >&2; exit 1
  fi
  dest="$OBS_CONFIG/basic/profiles/$OBS_PROFILE_DIR"
  mkdir -p "$dest" || exit 1
  [ -f "$dest/basic.ini" ] && { cp "$dest/basic.ini" "$dest/basic.ini.bak.$(date +%Y%m%d-%H%M%S)" || exit 1; }

  # Point recording paths at this user's home folder, and drop the
  # browser-dock cookie id, which belongs to the Mac the profile was exported from
  curl -fsSL "$OBS_PROFILE_URL" \
    | sed -E -e "s#^((Rec|FF)?FilePath)=/Users/[^/]+#\1=$HOME#" -e '/^CookieId=/d' \
    > "$dest/basic.ini.new" || exit 1
  grep -q "^Name=$OBS_PROFILE_NAME\$" "$dest/basic.ini.new" || { echo "Downloaded profile looks wrong" >&2; exit 1; }
  mv "$dest/basic.ini.new" "$dest/basic.ini" || exit 1

  # Make it the active profile (user.ini only exists once OBS has been opened)
  user_ini="$OBS_CONFIG/user.ini"
  if [ -f "$user_ini" ] && grep -q '^ProfileDir=' "$user_ini"; then
    cp "$user_ini" "$user_ini.bak" || exit 1
    sed -i '' -e "s#^Profile=.*#Profile=$OBS_PROFILE_NAME#" -e "s#^ProfileDir=.*#ProfileDir=$OBS_PROFILE_DIR#" "$user_ini" || exit 1
  else
    echo "OBS hasn't been opened yet: choose Profile > $OBS_PROFILE_NAME in OBS once."
  fi
)

if $INSTALL_OBS_PROFILE; then
  echo "== OBS profile: $OBS_PROFILE_NAME =="
  if install_obs_profile; then
    echo "OBS profile '$OBS_PROFILE_NAME' installed."
  else
    echo "WARNING: OBS profile not installed. Import it in OBS via Profile > Import."
  fi
fi

# ---------- Optional: Blackmagic Desktop Video ----------
# Download via Blackmagic's (undocumented) download API. Request format adapted from
# https://github.com/pardeyke/homebrew-blackmagic (BSD-2-Clause, (c) Jonas Pardeyke).
# Pinned version. To update, find the "downloadId" of the newest "Desktop Video" Mac entry in
# https://www.blackmagicdesign.com/api/support/us/downloads.json
BMD_DV_VERSION="16.5"
BMD_DV_ID="2a7b96a4684847b8874a9704a66a0221"

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
