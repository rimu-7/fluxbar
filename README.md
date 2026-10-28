<div align="center">

<img src="Resources/AppIcon.png" width="112" alt="FluxBar icon">

# FluxBar

**Clipboard history, a live network speed meter and a battery charge limiter, in one tiny native menu bar app.**

[![CI](https://github.com/rimu-7/fluxbar/actions/workflows/ci.yml/badge.svg)](https://github.com/rimu-7/fluxbar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/rimu-7/fluxbar?sort=semver)](https://github.com/rimu-7/fluxbar/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Apple Silicon & Intel](https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-supported-555)

</div>

## Features

### 📋 Clipboard history

- Instant full-text search across everything you've copied
- Keeps rich text, images and files, not just plain text
- Pin the clips you reuse; pinned clips are never deleted automatically
- Skips passwords and one-time codes from password managers like 1Password, Bitwarden and KeePassXC
- Keyboard first: arrow keys, `Return` to copy, `⌘1`–`⌘9` for quick picks

### 📶 Network speed meter

- Live upload and download speed in the menu bar
- Today's, this month's and this session's data usage

### 🔋 Battery charge limiter

- Holds your battery at a level you choose (e.g. 80%) to slow battery wear
- Uses the macOS charge limit on macOS 27, so there's nothing extra to install
- Keeps working when FluxBar is closed, during sleep and after restarts

### ⌨️ `flux` command line

- Everything above from the terminal, with `--json` output for scripts

## Light and private

### Light on your Mac

About **20 MB of memory** and **well under 1% CPU** when idle. FluxBar avoids constant polling, pauses during sleep, and frees the popover's memory when you close it.
More detail in [How it stays light](#how-it-stays-light).

### Private by design

FluxBar has **no analytics or telemetry**. Its only network request is a once-a-day update check to GitHub's public API, which sends nothing about you or your data, and you can turn it off in Settings. Your clipboard history never leaves your Mac, and large items are stored encrypted with a key kept in your Keychain.

## Install

Requires macOS 13 Ventura or newer.

### Terminal (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/rimu-7/fluxbar/main/scripts/install.sh | bash
```

This installs `FluxBar.app` into `/Applications`, adds the `flux` and `clip` commands to your PATH, and opens the app.

### Updating

FluxBar checks for new versions once a day and asks before installing anything. Updates are downloaded from GitHub Releases, checked against their published checksum and code signature, and installed in place. Your clipboard history and settings are kept.

You can also update any time with **Settings › Check Now**, with `flux update`, or by running the install command again.

<details>
<summary>Installer options</summary>

Pass options after `bash -s --`, for example:

```bash
curl -fsSL https://raw.githubusercontent.com/rimu-7/fluxbar/main/scripts/install.sh | bash -s -- --version 1.2.0
```

| Option | Description |
| :-- | :-- |
| `--version X.Y.Z` | Install a specific release (default: latest) |
| `--dir PATH` | Where to put FluxBar.app (default: `/Applications`, or `~/Applications`) |
| `--bin-dir PATH` | Where to put the `flux` and `clip` commands |
| `--no-launch` | Don't open FluxBar after installing |
| `--uninstall` | Remove FluxBar (keeps your clipboard history) |
| `--purge` | With `--uninstall`, also delete history and settings |

</details>

### Disk image

Download **FluxBar.dmg** from [Releases](https://github.com/rimu-7/fluxbar/releases), open it and drag FluxBar to Applications.

> [!NOTE]
> Until releases are notarized by Apple, macOS blocks the first launch of an app downloaded in a browser.
> Open **System Settings › Privacy & Security** and click **Open Anyway**. The terminal installer doesn't have this step.

### Turn on the battery limit

```bash
flux power limit 80
```

Or use the slider in the **Battery** tab. What happens next depends on your macOS version:

| macOS | How the limit works | Limits |
| :-- | :-- | :-- |
| **27**, or 26.7 / 15.8 and later | FluxBar sets the macOS charge limit (the same one in **System Settings › Battery › Charge Limit**). No helper, no password. | 80, 85, 90, 95 or 100% |
| Older versions | FluxBar installs a small background helper (`com.fluxbar.powerd`) once, which asks for your password. It only wakes up when your battery level, charger or settings change. | 50–100% |

Apple locked the low-level charging controls in macOS 27, so on that version **every** charge-limit app is limited to what macOS allows.

## Command line

```bash
flux power                 # battery, charger and limit status
flux power limit 85        # hold at 85% (80–100 on macOS 27, 50–100 before)
flux power limit off       # charge normally to 100%
flux power uninstall       # remove the helper (older macOS) and restore normal charging

flux clip list             # recent clips (-s "query" to search, --pinned, --json)
flux clip get 42           # print clip #42
flux clip copy 42          # put clip #42 back on the clipboard
flux clip paste            # print the most recent clip

flux net                   # current speed, today's and this month's usage
flux net live              # stream the speed every second

flux update                # install the latest version (--check to only check)
```

`clip` is a shorter command just for history: `clip list`, `clip add "text"` (or `some-command | clip add`), `clip pin 1`, `clip delete 1`, `clip clear --force`, `clip stats`.

Add `--help` to any command for all options.

## Keyboard shortcuts

In the clipboard tab:

| Key | Action |
| :-- | :-- |
| `↑` `↓` | Move selection |
| `Return` | Copy the selected clip |
| `⌘P` | Pin or unpin |
| `Delete` | Delete the selected clip |
| `⌘1` … `⌘9` | Copy one of the first nine clips |
| `Esc` | Clear the search, then close |

## Troubleshooting

<details>
<summary><b>The battery doesn't stop at my limit</b></summary>

1. Run `flux power status` and check the **Charge limit** line.
   - On macOS 27 it should say `80% · macOS charge limit`. If it says `off`, run `flux power limit 80`.
   - On older macOS the **Helper** line should say `running`. If the helper isn't installed, run `flux power limit 80`.
2. On macOS 27, close System Settings before changing the limit from FluxBar. An open Battery settings window can save its old value back when you click **Done**.
3. Quit other charge-limit apps (AlDente, Battery Toolkit, `battery`, WattBit, …). Two tools controlling charging at the same time will fight each other.
4. macOS may let the battery go a few percent above or below the limit. That's normal.

</details>

<details>
<summary><b><code>flux: command not found</code></b></summary>

The installer prints which folder it linked the commands into. If that folder isn't in your PATH (usually `~/.local/bin`), add it to `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

</details>

<details>
<summary><b>An update won't install</b></summary>

FluxBar replaces itself in the folder it's running from, so that folder must be writable by you. If FluxBar is somewhere else (or was opened straight from the disk image), move it to **Applications** first. You can always update with the install command instead:

```bash
curl -fsSL https://raw.githubusercontent.com/rimu-7/fluxbar/main/scripts/install.sh | bash
```

</details>

<details>
<summary><b>A copied item doesn't show up</b></summary>

Check that recording isn't paused: the record button at the top of the clipboard tab turns orange when paused. Items marked as passwords or one-time codes by password managers are skipped on purpose.

</details>

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/rimu-7/fluxbar/main/scripts/install.sh | bash -s -- --uninstall
```

This also removes the battery helper and restores normal charging. Add `--purge` to delete your clipboard history too.

## How it stays light

- The popover's interface is created when you open it and thrown away when you close it.
- The speed meter samples once a second only while it's visible (every 2 s in Low Power Mode, every 30 s in the background just to keep usage totals). It stops during sleep, and the menu bar is only redrawn when the number changes.
- The clipboard check reads a single counter twice a second. Content is read only when something new was copied, and only in the formats FluxBar keeps.
- Battery readings are driven by macOS power notifications, never polled. On macOS 27 the charge limit runs entirely inside macOS, so FluxBar has no background helper at all.
- Images and large rich text are stored as encrypted files outside the database, and cleaned up when their clip is deleted.

## Data locations

| What | Where |
| :-- | :-- |
| Clipboard history | `~/Library/Application Support/ClipSuite/clips.db` |
| Images, attachments, data usage | `~/Library/Application Support/FluxBar/` |
| Battery limit (macOS 27) | Stored by macOS, shown in **System Settings › Battery** |
| Battery limit settings (older macOS) | `/Library/Application Support/FluxBar/charge-limit.json` |
| Battery helper (older macOS) | `/Library/PrivilegedHelperTools/com.fluxbar.powerd` and `/Library/LaunchDaemons/com.fluxbar.powerd.plist` |

## Contributing

Contributions are welcome, from bug reports and ideas to docs and code. 🙌

- Found a bug or have an idea? [Open an issue](https://github.com/rimu-7/fluxbar/issues/new/choose).
- Want to write code? Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, project layout and guidelines.
  Issues labeled [good first issue](https://github.com/rimu-7/fluxbar/labels/good%20first%20issue) are a nice place to start.

Quick start:

```bash
git clone https://github.com/rimu-7/fluxbar.git && cd fluxbar
make test     # run the tests
make run      # run the app from the terminal
make app      # build dist/FluxBar.app, FluxBar.zip and FluxBar.dmg
```

If FluxBar is useful to you, a ⭐ on GitHub helps others find it.

## License

[MIT](LICENSE)
