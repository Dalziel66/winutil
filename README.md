# WinUtil

Windows utility with a VS Code-style UI and the JetBrains Mono font. Install apps (winget), apply tweaks, enable Windows features, run fixes and set Windows Update behaviour.

## Run (no download needed)

Open PowerShell or CMD and run:

```powershell
irm https://raw.githubusercontent.com/YOUR_USER/winutil/main/winutil.ps1 | iex
```

From CMD:

```cmd
powershell -c "irm https://raw.githubusercontent.com/YOUR_USER/winutil/main/winutil.ps1 | iex"
```

The script asks for administrator rights and relaunches itself.

## Publish

1. Create a public GitHub repo named `winutil` and push `winutil.ps1`.
2. Replace `YOUR_USER` in `$ScriptUrl` (line 3 of winutil.ps1) and in this README.

## Self-check

```powershell
$env:WINUTIL_TEST='1'; powershell -STA -File .\winutil.ps1
```
