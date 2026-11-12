# Optional scripting tools

All app features are available graphically after installing the DMG. These tools are optional.
The DMG bundles `flux` and `clip` inside `FluxBar.app/Contents/MacOS`; it does not modify your shell or PATH.
For example, use `"/Applications/FluxBar.app/Contents/MacOS/flux" --help` if you want to script FluxBar.

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

