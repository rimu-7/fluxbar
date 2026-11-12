<div align="center">

<img src="Resources/AppIcon.png" width="112" alt="FluxBar icon">

# FluxBar

**Clipboard history, network speed, battery charge limits and Caffeine in one native macOS menu bar app.**

[![CI](https://github.com/rimu-7/fluxbar/actions/workflows/ci.yml/badge.svg)](https://github.com/rimu-7/fluxbar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/rimu-7/fluxbar?sort=semver)](https://github.com/rimu-7/fluxbar/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Apple Silicon & Intel](https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-supported-555)

[**Download FluxBar.dmg**](https://github.com/rimu-7/fluxbar/releases/latest/download/FluxBar.dmg)

</div>

## Install with Finder

Requires macOS 13 Ventura or newer. Release DMGs support Apple Silicon and Intel Macs.

1. Download **FluxBar.dmg** from [Releases](https://github.com/rimu-7/fluxbar/releases).
2. Open the disk image and drag **FluxBar.app** onto **Applications**.
3. Eject the disk image, then open **FluxBar** from Applications.
4. Look for the clipboard and speed icons in your menu bar. FluxBar opens its popover on first launch; it has no main window or Dock icon.

**The DMG includes everything needed for graphical use. No Terminal, curl installer, Homebrew or separate helper download is required.**

If macOS blocks the first launch of an unnotarized release, open **System Settings → Privacy & Security → Open Anyway** for FluxBar, then confirm. Releases built without the project's Apple signing credentials require this graphical approval.

## Finish setup inside FluxBar

### Battery charge limit

Open the **Battery** tab or **Settings**. Battery setup is shown near the top of both.

- If **Enable** appears, choose it and approve the macOS administrator dialog. The battery controls are already included in the app.
- If **Update** appears after replacing FluxBar, choose it to update the installed battery controls too.
- Choose your charge limit using the slider or presets, then turn on the charge limit toggle.
- **Repair** reinstalls battery controls if charging stops following your limit. **Remove Battery Helper** restores normal charging and removes the helper.

On Macs that support the built-in macOS charge limit, FluxBar uses that setting directly and needs no helper setup. Available limits depend on your hardware and macOS: supported native limits are generally 80–100%; helper-based limits support 50–100%. The app shows when charging control is unavailable instead of claiming a limit is active.

A battery charge limit continues working when FluxBar is closed. Caffeine ends when you turn it off or quit FluxBar.

### Start at login

Open **Settings → Start at Login**. If macOS asks for approval, enable FluxBar in **System Settings → General → Login Items**.

## Features

### Clipboard

- Search your clipboard history instantly.
- Keep text, rich text, images and files.
- Pin frequently used clips; pinned clips survive automatic cleanup.
- Skip items marked as concealed by password managers, including passwords and one-time codes.
- Set retention and history limits, pause recording, and clear history in Settings.

### Battery

- View battery, charger, health and power information.
- Choose a supported charge limit to reduce time spent at a full charge.
- Set up, update, repair and remove battery controls through the app.

### Speed

- See live upload and download rates in the menu bar.
- View today's, this month's and the current session's data usage.
- Manage bandwidth history from Settings.

### Caffeine

- Find **Caffeine** immediately after **Speed**.
- Turn on **Keep awake** to prevent idle display sleep while reading, presenting or focusing.
- Follow the large elapsed-session timer.
- Close the popover while Caffeine keeps running. Turn it off to restore normal display sleep.

## Update graphically

FluxBar checks GitHub Releases once a day and asks before installing an update. Open **Settings → Check Now** whenever you want to check manually.

Downloads are checked against the published checksum and app signature before replacement. Your clipboard history and settings are kept.

You can also download a newer DMG, quit FluxBar, and drag the new copy into Applications, choosing **Replace** in Finder. Reopen FluxBar and choose **Update** in Battery or Settings if battery controls need updating. If in-app updating is blocked by a read-only location or folder permissions, use this same Finder replacement flow.

## Keyboard shortcuts

In the Clipboard tab:

| Key | Action |
| :-- | :-- |
| `↑` `↓` | Move selection |
| `Return` | Copy the selected clip |
| `⌘P` | Pin or unpin |
| `Delete` | Delete the selected clip |
| `⌘1` … `⌘9` | Copy one of the first nine clips |
| `Esc` | Clear search, then close the popover |

## Troubleshooting

<details>
<summary><b>I opened FluxBar but cannot find it</b></summary>

FluxBar lives in the menu bar. Click its clipboard or speed icon. Opening FluxBar again from Applications also opens its popover. It does not create a main window or Dock icon.

</details>

<details>
<summary><b>The battery limit is not working</b></summary>

1. Open **Battery** and check the setup message near the top. Choose **Enable**, **Update** or **Repair** if offered, and approve macOS authorization.
2. Check that the charge limit toggle is on and the selected limit is supported. A cancelled approval does not enable the limit.
3. If FluxBar uses the macOS charge limit, close System Settings before changing it in FluxBar; an open Battery settings window can save its old value back.
4. Quit other charge-limit apps so they do not compete for charging control.
5. A battery may settle a few percent above or below the selected limit. Unsupported hardware or macOS charging controls cannot be enabled by installing a different way.

</details>

<details>
<summary><b>An update will not install</b></summary>

Quit FluxBar and replace it from the latest DMG using Finder. Keep it in Applications, eject the disk image and reopen the installed copy. Your history and settings are stored separately from the app.

</details>

<details>
<summary><b>A copied item does not appear</b></summary>

Check that recording is not paused. The record button in Clipboard turns orange when paused. Concealed items from password managers are intentionally skipped.

</details>

## Remove FluxBar with Finder

1. Turn off the battery charge limit in **Battery**.
2. In **Battery** or **Settings**, choose **Remove Battery Helper** if shown and approve the macOS dialog. If **Remove Old Battery Helper** appears, remove that too.
3. Turn off **Start at Login** in Settings.
4. Choose **Quit FluxBar** in Settings, then move FluxBar from Applications to Trash.

Clipboard history and preferences are kept separately. To erase history, use **Settings → Delete All Clips** before quitting.

## Privacy and efficiency

FluxBar has no analytics or telemetry. Clipboard history stays on your Mac; images and large attachments are stored encrypted using a key in Keychain. Update checks go to GitHub Releases and can be turned off in Settings.

The popover's interface is released when closed. Network sampling slows down in the background and stops during sleep; battery readings use macOS power notifications. Caffeine uses a macOS power assertion, which is released when FluxBar exits.

## Data locations

| Data | Location |
| :-- | :-- |
| Clipboard history | `~/Library/Application Support/ClipSuite/clips.db` |
| Images, attachments, network usage | `~/Library/Application Support/FluxBar/` |
| Native charge limit | Managed by macOS; visible in System Settings → Battery |
| Helper-based charge settings | `/Library/Application Support/FluxBar/charge-limit.json` |
| Battery helper | `/Library/PrivilegedHelperTools/com.fluxbar.powerd` |

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for source builds, tests and release packaging. Bug reports and ideas are welcome in [Issues](https://github.com/rimu-7/fluxbar/issues).

Optional scripting tools remain bundled for advanced use; see [command-line documentation](docs/COMMAND_LINE.md). They are not needed for installation, setup or everyday use.

## License

[MIT](LICENSE)
