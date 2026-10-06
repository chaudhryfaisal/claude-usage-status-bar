# ClaudeBar

A native macOS menu bar app that shows your Claude usage limits: session (5-hour), weekly, and weekly Opus. The same numbers you see on the claude.ai dashboard and in Claude Code's `/usage` command.

![ClaudeBar popover](docs/screenshot.png)

- Lives in your menu bar: `✳ 14/10%` shows your primary account's session (5h) and weekly usage side by side
- Multiple accounts: add as many Claude accounts as you like, give each an alias, and star one as primary (shown in the menu bar)
- Click the menu bar icon to see usage for all connected accounts at a glance
- Dashboard window (footer button) shows a card per account with progress bars, reset times, and time remaining
- Per account: alias editing, set primary, web dashboard link, reconnect on token expiry, and disconnect
- Mac-native design, adapts to light and dark mode
- Refreshes every 5 minutes and whenever you open it
- Launch at login toggle
- Zero third-party dependencies, pure SwiftUI

## Install

```bash
make install && make open
```

Or without make:

```bash
git clone https://github.com/ousid/claudebar
cd claudebar
./scripts/build-app.sh
cp -r ClaudeBar.app /Applications/
open /Applications/ClaudeBar.app
```

Requires macOS 13+ and the Swift toolchain. Running `xcode-select --install` is enough, no Xcode needed.

### Make targets

| Target | What it does |
| --- | --- |
| `make` / `make all` | build, install, open |
| `make build` | compile `ClaudeBar.app` in this directory |
| `make install` | build and copy the app to `INSTALL_DIR` (default `/Applications`) |
| `make open` | launch the installed app |
| `make uninstall` | quit and remove the app; leaves your Keychain token behind |

Override the install location with `make install INSTALL_DIR=~/Applications`.

## Connect your account

Click the ✳ icon, then **Connect Claude Account**. Your browser opens claude.ai. Approve access, copy the code shown, and paste it into the popover. That's it. Repeat with **+ Add account** to add more accounts, then set an alias and star a primary.

## Security and privacy

- ClaudeBar signs in with its own OAuth token requesting only the read-only `user:profile` scope. It can see your usage numbers and nothing else. It cannot send messages or spend your quota, even if the token were stolen.
- Each account's token is stored in your macOS Keychain (`com.claudebar.oauth.<account-id>`, this device only) and never leaves your machine.
- The app talks only to Anthropic endpoints (`claude.ai`, `api.anthropic.com`, `console.anthropic.com`). No analytics, no third-party servers.
- The OAuth flow uses PKCE (S256) with state verification.

Found a security issue? See [SECURITY.md](SECURITY.md).

## Uninstall

```bash
make uninstall
security delete-generic-password -s com.claudebar.oauth.<account-id>  # one per account
```

## Disclaimer

ClaudeBar is an independent open-source project, not affiliated with or endorsed by Anthropic. It uses the same public OAuth endpoints the official Claude Code CLI uses. These are undocumented and may change.

## License

[MIT](LICENSE)
