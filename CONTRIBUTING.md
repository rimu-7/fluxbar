# Contributing to FluxBar

Thanks for helping out! Bug reports, ideas, docs fixes and code are all welcome.
New to the project? Look for issues labeled **good first issue**.

## Reporting bugs and ideas

Open an [issue](https://github.com/rimu-7/fluxbar/issues/new/choose) and pick a template.
For battery problems, please paste the output of `flux power status`.

Found a security problem (for example in the root battery helper)? Please don't open a public issue.
Use GitHub's [private vulnerability reporting](https://github.com/rimu-7/fluxbar/security/advisories/new) instead.

## Setting up

You need macOS 13+ and Xcode 15+ (or the Swift 5.9+ Command Line Tools).

```bash
git clone https://github.com/rimu-7/fluxbar.git
cd fluxbar
make build    # debug build
make test     # run the tests
make run      # start the menu bar app from the terminal (Ctrl+C to quit)
```

To try a change exactly as users get it:

```bash
make install  # builds FluxBar.app and installs it like the curl installer
```

## Where things live

| Folder | What it does |
| :-- | :-- |
| `Sources/FluxBar` | The menu bar app: status items (AppKit) and the popover (SwiftUI) |
| `Sources/flux`, `Sources/clip` | Command line tools |
| `Sources/ClipCore` | Clipboard database (SQLite via GRDB, FTS5 search) and the pasteboard watcher |
| `Sources/NetCore` | Network sampling and data usage |
| `Sources/PowerCore` | Battery readings, SMC access, charge limit logic, macOS charge limit bridge |
| `Sources/PowerDaemon` | `com.fluxbar.powerd`, the root helper that enforces the charge limit |
| `scripts/` | App build, installer, icon generator |

## Guidelines

- **Keep it light.** FluxBar runs all day. Avoid timers and polling where an event or notification exists,
  and stop work when nothing is on screen. Mention the impact in your PR if you touch anything that runs in the background.
- **Keep it native.** Prefer AppKit/SwiftUI and system frameworks over new dependencies.
- **Privacy.** The only network request is the daily update check to GitHub Releases (`Sources/ClipCore/Update`). Please keep it that way: no analytics, no telemetry.
- **Battery helper changes need extra care.** It runs as root. Keep it small, validate all input,
  and make sure it always restores normal charging when stopped or removed.
- **Add a test** for logic changes in `ClipCore`, `NetCore` or `PowerCore` (see `Tests/`).
- Match the surrounding code style. Small, focused PRs are easier to review than big ones.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Make your change, with tests where it makes sense.
3. Run `make test`.
4. Open a PR describing what changed and how you tested it.

CI builds and tests every PR.

## Releasing (maintainers)

1. Bump `version` in `Sources/ClipCore/FluxBarInfo.swift`.
2. Commit, then tag and push: `git tag v1.2.0 && git push origin v1.2.0`.
3. GitHub Actions builds the universal app and publishes `FluxBar.zip` and `FluxBar.dmg`.
   Installed copies pick it up within a day through the in-app updater.
   Keep the asset names `FluxBar.zip` and `FluxBar.zip.sha256`: the installer and the updater look for them.
   A tag with a suffix (`v1.3.0-beta.1`) is published as a pre-release, which the updater skips.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
