# WinUtil

Windows utility with two switchable themes: **Omarchy White** (default, inspired by [Omarchy](https://omarchy.org)) and **VS Code Dark**. Uses the JetBrains Mono font. Install apps (winget), apply tweaks, enable Windows features, run fixes and set Windows Update behaviour.

## Run (no download needed)

PowerShell:

```powershell
irm https://raw.githubusercontent.com/Dalziel66/winutil/main/winutil.ps1 | iex
```

CMD:

```cmd
powershell -c "irm https://raw.githubusercontent.com/Dalziel66/winutil/main/winutil.ps1 | iex"
```

The script asks for administrator rights and relaunches itself. Press **Ctrl+T** (or the ☀ button) to switch theme. The choice is remembered.

## Project layout

```
winutil.ps1                 entry point: elevation, data, theme loader, layout, events
themes/
  omarchy-white.xaml        Omarchy White tokens (colors, gaps, borders, visibility)
  vscode-dark.xaml          VS Code Dark tokens
  README.md                 token contract + how to add a theme
```

`winutil.ps1` loads themes from `themes/` next to itself when run from a file. When run through `irm | iex`, it downloads them from this repo. See [themes/README.md](themes/README.md).

## Self-check

```powershell
$env:WINUTIL_TEST='1'; powershell -STA -File .\winutil.ps1
```

This builds the window without showing it and checks that every theme loads, has all tokens and does not clash with layout keys. It also checks that an incomplete theme is rejected.

## Fork

If you fork this repo, change `$ScriptUrl` (top of winutil.ps1) to your own raw URL. Themes are fetched relative to it.
