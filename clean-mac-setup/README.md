# clean-mac-setup

Run directly from GitHub (copy/paste into Terminal):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/simonsundgaard/clean-mac-setup-obs/main/clean-mac-setup/clean-mac-setup.sh)
```

Or run from a local clone, in this folder:

```bash
chmod +x clean-mac-setup.sh
./clean-mac-setup.sh
```

At the start you pick optional installs (Homebrew + OBS, Blackmagic Desktop Video, the OBS profile in `obs/`), e.g. `1 2 3` for all. You'll be asked for your password (sudo and screen-lock settings). Log out/in or reboot afterwards.
