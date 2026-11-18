# =============================================================================
#  WinUtil - công cụ tiện ích Windows (giao diện kiểu VS Code / Omarchy)
# =============================================================================
#  Chạy:  irm https://raw.githubusercontent.com/Dalziel66/winutil/main/winutil.ps1 | iex
#
#  Cấu trúc dự án:
#    winutil.ps1              <- file này: logic, layout, sự kiện
#    themes/omarchy-white.xaml   theme trắng (cảm hứng Omarchy White)
#    themes/vscode-dark.xaml     theme tối (cảm hứng VS Code)
#    themes/README.md            "hợp đồng" token mà mọi theme phải có
#
#  Luồng chạy:
#    1. Tự nâng quyền Admin (+ STA, bắt buộc cho WPF).
#    2. Dựng cửa sổ từ XAML. Mọi màu/kích thước dùng {DynamicResource Key}.
#    3. Nạp theme: từ thư mục themes/ cạnh file (khi chạy local) hoặc tải từ
#       cùng repo GitHub (khi chạy qua irm | iex). Theme được merge vào
#       Window.Resources nên DynamicResource tự cập nhật khi đổi theme.
#    4. Tác vụ nặng (winget, registry...) chạy trong runspace nền; log được
#       đẩy về UI qua ConcurrentQueue + DispatcherTimer (không treo giao diện).
#
#  Lưu ý mã hoá: mọi chuỗi trong code chỉ dùng ASCII. Tiếng Việt chỉ nằm
#  trong comment, vì PowerShell 5.1 đọc file .ps1 không BOM theo ANSI.
# =============================================================================

$ScriptUrl = 'https://raw.githubusercontent.com/Dalziel66/winutil/main/winutil.ps1'
# Thư mục gốc raw của repo, dùng để tải theme khi chạy qua irm | iex
$RepoRaw   = $ScriptUrl -replace '/[^/]+$', ''

# WINUTIL_TEST=1: chế độ tự kiểm tra, dựng cửa sổ nhưng không hiện, không nâng quyền
$IsTest = $env:WINUTIL_TEST -eq '1'

# ----------------------------------------------------------------------------
#  1. Nâng quyền
# ----------------------------------------------------------------------------
# Khi chạy qua iex thì không có $PSCommandPath, nên relaunch bằng chính lệnh irm.
# Dùng 'return' thay vì 'exit' để không đóng cửa sổ PowerShell của người dùng.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsTest -and (-not $isAdmin -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA')) {
    $arg = if ($PSCommandPath) { "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" }
           else { "-NoProfile -ExecutionPolicy Bypass -STA -Command `"irm '$ScriptUrl' | iex`"" }
    Write-Host 'WinUtil needs administrator rights, relaunching...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arg
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest trên PS 5.1 chậm hẳn nếu hiện progress bar

# ----------------------------------------------------------------------------
#  2. Dữ liệu (thêm/bớt app, tweak... chỉ cần sửa ở đây)
# ----------------------------------------------------------------------------
# Định dạng app: 'Tên hiển thị|WingetId'. Kiểm tra Id bằng: winget search <tên>
$Apps = [ordered]@{
    'Browsers'      = 'Google Chrome|Google.Chrome', 'Firefox|Mozilla.Firefox', 'Brave|Brave.Brave', 'Opera|Opera.Opera', 'LibreWolf|LibreWolf.LibreWolf'
    'Communication' = 'Discord|Discord.Discord', 'Telegram|Telegram.TelegramDesktop', 'Zoom|Zoom.Zoom', 'Slack|SlackTechnologies.Slack', 'Microsoft Teams|Microsoft.Teams'
    'Development'   = 'VS Code|Microsoft.VisualStudioCode', 'Git|Git.Git', 'GitHub Desktop|GitHub.GitHubDesktop', 'Node.js LTS|OpenJS.NodeJS.LTS', 'Python 3.13|Python.Python.3.13', 'Windows Terminal|Microsoft.WindowsTerminal', 'PowerShell 7|Microsoft.PowerShell', 'Docker Desktop|Docker.DockerDesktop', 'JetBrains Toolbox|JetBrains.Toolbox', 'Postman|Postman.Postman', 'Neovim|Neovim.Neovim'
    'Utilities'     = '7-Zip|7zip.7zip', 'Everything|voidtools.Everything', 'PowerToys|Microsoft.PowerToys', 'Notepad++|Notepad++.Notepad++', 'ShareX|ShareX.ShareX', 'CPU-Z|CPUID.CPU-Z', 'GPU-Z|TechPowerUp.GPU-Z', 'CrystalDiskInfo|CrystalDewWorld.CrystalDiskInfo', 'Rufus|Rufus.Rufus', 'Bitwarden|Bitwarden.Bitwarden', 'UniGetUI|MartiCliment.UniGetUI'
    'Multimedia'    = 'VLC|VideoLAN.VLC', 'OBS Studio|OBSProject.OBSStudio', 'Spotify|Spotify.Spotify', 'Krita|KDE.Krita', 'Audacity|Audacity.Audacity', 'HandBrake|HandBrake.HandBrake'
    'Games'         = 'Steam|Valve.Steam', 'Epic Games|EpicGames.EpicGamesLauncher', 'GOG Galaxy|GOG.Galaxy', 'Ubisoft Connect|Ubisoft.Connect', 'EA App|ElectronicArts.EADesktop'
    'Documents'     = 'LibreOffice|TheDocumentFoundation.LibreOffice', 'Adobe Reader|Adobe.Acrobat.Reader.64-bit', 'SumatraPDF|SumatraPDF.SumatraPDF', 'Obsidian|Obsidian.Obsidian', 'Notion|Notion.Notion'
}

# Mỗi tweak là một hashtable:
#   Group    nhóm hiển thị (mỗi nhóm một hộp)
#   Preset   'std', 'min' hoặc rỗng: tweak thuộc preset nào
#   Reg      danh sách @(path, name, value, undoValue). undoValue = $null nghĩa là xoá value khi Undo.
#            Kiểu value tự suy ra: chuỗi -> REG_SZ, số -> REG_DWORD (xem Set-Reg trong $Prelude).
#   Run/Undo đoạn code dạng CHUỖI (không phải scriptblock), vì scriptblock bị gắn với runspace
#            nơi nó được tạo và không chạy an toàn ở runspace nền.
#   Explorer $true nếu cần khởi động lại explorer.exe để thấy thay đổi.
$Tweaks = @(
    @{ Group = 'Essential'; Name = 'Create restore point'; Preset = 'std,min'; Desc = 'Creates a System Restore point before applying changes.'
       Reg = @(, @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore', 'SystemRestorePointCreationFrequency', 0, $null))
       Run = 'Enable-ComputerRestore -Drive "$env:SystemDrive\"; Checkpoint-Computer -Description "WinUtil" -RestorePointType MODIFY_SETTINGS' }
    @{ Group = 'Essential'; Name = 'Delete temporary files'; Preset = 'std,min'; Desc = 'Clears %TEMP% and C:\Windows\Temp.'
       Run = 'Get-ChildItem $env:TEMP, "$env:SystemRoot\Temp" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue' }
    @{ Group = 'Essential'; Name = 'Disable hibernation'; Preset = 'std'; Desc = 'Frees disk space used by hiberfil.sys (disables Fast Startup).'
       Run = 'powercfg /hibernate off'; Undo = 'powercfg /hibernate on' }
    @{ Group = 'Privacy'; Name = 'Disable telemetry'; Preset = 'std,min'; Desc = 'Turns off diagnostic data, advertising ID and suggested apps.'
       Reg = @(
           @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry', 0, $null),
           @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 0, 1),
           @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SilentInstalledAppsEnabled', 0, 1),
           @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SystemPaneSuggestionsEnabled', 0, 1))
       Run = 'Stop-Service DiagTrack -Force -ErrorAction SilentlyContinue; Set-Service DiagTrack -StartupType Disabled'
       Undo = 'Set-Service DiagTrack -StartupType Automatic; Start-Service DiagTrack -ErrorAction SilentlyContinue' }
    @{ Group = 'Privacy'; Name = 'Disable activity history'; Preset = 'std,min'; Desc = 'Stops Windows from recording your activity timeline.'
       Reg = @(
           @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableActivityFeed', 0, $null),
           @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'PublishUserActivities', 0, $null),
           @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'UploadUserActivities', 0, $null)) }
    @{ Group = 'Privacy'; Name = 'Disable location tracking'; Preset = 'std'; Desc = 'Denies location access for apps.'
       Reg = @(, @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location', 'Value', 'Deny', 'Allow')) }
    @{ Group = 'Privacy'; Name = 'Disable Bing in Start search'; Preset = 'std'; Desc = 'Start menu search stays local.'
       Reg = @(, @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search', 'BingSearchEnabled', 0, 1)) }
    @{ Group = 'Privacy'; Name = 'Disable Copilot'; Preset = ''; Desc = 'Turns off Windows Copilot via policy.'
       Reg = @(
           @('HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1, $null),
           @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1, $null)) }
    @{ Group = 'Privacy'; Name = 'Disable Recall'; Preset = ''; Desc = 'Disables AI snapshot analysis (Copilot+ PCs).'
       Reg = @(, @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableAIDataAnalysis', 1, $null)) }
    @{ Group = 'Interface'; Name = 'Dark mode'; Preset = ''; Desc = 'Dark theme for apps and system.'
       Reg = @(
           @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme', 0, 1),
           @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'SystemUsesLightTheme', 0, 1)) }
    @{ Group = 'Interface'; Name = 'Show file extensions'; Preset = 'std'; Desc = 'Explorer shows .exe, .txt ...'; Explorer = $true
       Reg = @(, @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'HideFileExt', 0, 1)) }
    @{ Group = 'Interface'; Name = 'Show hidden files'; Preset = ''; Desc = 'Explorer shows hidden files and folders.'; Explorer = $true
       Reg = @(, @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Hidden', 1, 2)) }
    @{ Group = 'Interface'; Name = 'Classic right-click menu'; Preset = ''; Desc = 'Windows 10 style context menu on Windows 11.'; Explorer = $true
       Run = 'New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Value "" -Force | Out-Null'
       Undo = 'Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue' }
    @{ Group = 'Interface'; Name = 'Align taskbar left'; Preset = ''; Desc = 'Moves Start and taskbar icons to the left.'
       Reg = @(, @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarAl', 0, 1)) }
    @{ Group = 'Interface'; Name = 'Enable "End task" on taskbar'; Preset = 'std'; Desc = 'Right-click a taskbar app to kill it.'
       Reg = @(, @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings', 'TaskbarEndTask', 1, 0)) }
    @{ Group = 'Interface'; Name = 'Disable widgets'; Preset = ''; Desc = 'Removes News and Interests / Widgets.'
       Reg = @(, @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests', 0, $null)) }
    @{ Group = 'Performance'; Name = 'Disable GameDVR'; Preset = 'std'; Desc = 'Turns off background game recording.'
       Reg = @(
           @('HKCU:\System\GameConfigStore', 'GameDVR_Enabled', 0, 1),
           @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR', 'AllowGameDVR', 0, $null)) }
    @{ Group = 'Performance'; Name = 'Disable mouse acceleration'; Preset = ''; Desc = 'Raw 1:1 mouse movement.'
       Reg = @(
           @('HKCU:\Control Panel\Mouse', 'MouseSpeed', '0', '1'),
           @('HKCU:\Control Panel\Mouse', 'MouseThreshold1', '0', '6'),
           @('HKCU:\Control Panel\Mouse', 'MouseThreshold2', '0', '10')) }
    @{ Group = 'Performance'; Name = 'Prefer IPv4 over IPv6'; Preset = ''; Desc = 'Keeps IPv6 but prioritizes IPv4.'
       Reg = @(, @('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters', 'DisabledComponents', 32, $null)) }
    @{ Group = 'Performance'; Name = 'Add Ultimate Performance plan'; Preset = ''; Desc = 'Adds the hidden power plan (select it in Power Options).'
       Run = 'Log (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-String)' }
)

# 'Tên|FeatureName[,FeatureName...]' cho Enable-WindowsOptionalFeature
$Features = 'NET Framework 3.5|NetFx3', 'Hyper-V|Microsoft-Hyper-V-All', 'WSL|Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform', 'Windows Sandbox|Containers-DisposableClientVM'

# Các nút sửa lỗi: tên nút -> code chạy nền. Reset Windows Update ĐỔI TÊN thư mục cũ
# (*.bak_<thời gian>) thay vì xoá, để có thể khôi phục nếu cần.
$Fixes = [ordered]@{
    'Reset network'            = 'Log (netsh winsock reset | Out-String); Log (netsh int ip reset | Out-String); Log (ipconfig /flushdns | Out-String)'
    'System repair (DISM+SFC)' = 'Log "DISM RestoreHealth..."; DISM /Online /Cleanup-Image /RestoreHealth | Out-Null; Log "  exit code: $LASTEXITCODE"; Log "SFC scan..."; sfc /scannow | Out-Null; Log "  exit code: $LASTEXITCODE"'
    'Reset Windows Update'     = '$s = "wuauserv","bits","cryptsvc"; Stop-Service $s -Force -ErrorAction SilentlyContinue; $t = Get-Date -Format yyyyMMddHHmmss; Rename-Item "$env:SystemRoot\SoftwareDistribution" "SoftwareDistribution.bak_$t" -ErrorAction SilentlyContinue; Rename-Item "$env:SystemRoot\System32\catroot2" "catroot2.bak_$t" -ErrorAction SilentlyContinue; Start-Service $s -ErrorAction SilentlyContinue; Log "Windows Update components reset (old folders kept as *.bak_$t)."'
}
# Các bảng điều khiển cũ: mở trực tiếp trên luồng UI (không cần chạy nền)
$Panels = [ordered]@{ 'Control Panel' = 'control'; 'Network Connections' = 'ncpa.cpl'; 'Power Options' = 'powercfg.cpl'; 'Sound' = 'mmsys.cpl'; 'System Properties' = 'sysdm.cpl'; 'Device Manager' = 'devmgmt.msc'; 'Services' = 'services.msc'; 'Registry Editor' = 'regedit' }

$WU = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$UpdateCode = @{
    Default  = "Remove-Item '$WU' -Recurse -Force -ErrorAction SilentlyContinue; Set-Service wuauserv -StartupType Manual; Log 'Windows Update policies reset to default.'"
    Security = "Set-Reg '$WU' DeferFeatureUpdates 1; Set-Reg '$WU' DeferFeatureUpdatesPeriodInDays 365; Set-Reg '$WU' DeferQualityUpdates 1; Set-Reg '$WU' DeferQualityUpdatesPeriodInDays 4; Set-Reg '$WU\AU' NoAutoRebootWithLoggedOnUsers 1; Set-Service wuauserv -StartupType Manual; Log 'Feature updates delayed 365 days, security updates 4 days.'"
    Disable  = "Set-Reg '$WU\AU' NoAutoUpdate 1; Set-Reg '$WU\AU' AUOptions 1; Stop-Service wuauserv -Force -ErrorAction SilentlyContinue; Set-Service wuauserv -StartupType Disabled; Log 'Windows Update disabled. Remember to re-enable it later.'"
}

# ----------------------------------------------------------------------------
#  3. Theme: danh sách, hợp đồng token, bộ nạp
# ----------------------------------------------------------------------------
# Whitelist tên theme. Tên đọc từ file cấu hình CHỈ được dùng nếu có trong danh sách
# này, tránh path traversal (vd "..\..\x") khi ghép đường dẫn/URL.
# Theme đầu tiên là mặc định. Ctrl+T đổi vòng theo thứ tự này.
$Themes = [ordered]@{
    'omarchy-white' = 'Omarchy White'
    'vscode-dark'   = 'VS Code Dark'
}

# Hợp đồng token: theme nào thiếu key nào sẽ bị từ chối với thông báo rõ ràng,
# thay vì để WPF âm thầm vẽ màu trong suốt. Giữ đồng bộ với themes/README.md.
# QUAN TRỌNG: tên token không được trùng key Style trong Window.Resources (Card,
# Comment, Desc...). WPF tra Window.Resources TRƯỚC MergedDictionaries, nên sẽ lấy
# nhầm Style thay vì Brush và lỗi "cannot cast Style to Brush". Self-test có kiểm tra.
$ThemeKeys = @(
    'Bg', 'BgSide', 'BgTitle', 'BgActivity', 'BgInput', 'BgTabBar', 'BgTabActive', 'BgCard',
    'Fg', 'FgMuted', 'FgSubtle', 'FgStrong', 'FgHead', 'CommentFg',
    'Border', 'TileBorderBrush', 'InputBorder', 'WindowBorder',
    'Accent', 'AccentFg', 'TabActiveBorder', 'TitleIconFg', 'TabIconFg', 'ActFg', 'ActFgActive',
    'BtnBg', 'BtnFg', 'BtnBorder', 'BtnPrimaryBg', 'BtnPrimaryFg', 'BtnDangerBg', 'BtnDangerFg',
    'CapFg', 'CapHoverBg', 'CloseHoverBg', 'CloseHoverFg',
    'CheckBg', 'CheckBorder', 'ScrollThumb', 'Selection', 'ToolTipBg',
    'StatusBg', 'StatusBusyBg', 'StatusFg', 'BadgeBg', 'BadgeBusyBg', 'BadgeFg',
    'RootPad', 'TileGap', 'TileBorder', 'BtnBorderThickness', 'Radius', 'CardRadius',
    'ClassicChromeVis', 'WaybarVis'
)

# Theme được chọn lưu ở %LOCALAPPDATA%\winutil\theme.txt (một dòng: tên theme)
$SettingsDir = Join-Path $env:LOCALAPPDATA 'winutil'
$ThemeFile   = Join-Path $SettingsDir 'theme.txt'
$ThemeCache  = @{}   # tên -> ResourceDictionary đã parse, để đổi qua lại không tải lại mạng

# Đọc nội dung XAML của theme.
#  - Chạy từ file (.\winutil.ps1): đọc themes\<tên>.xaml cạnh script, tiện cho việc sửa theme.
#  - Chạy qua irm | iex: $PSScriptRoot rỗng nên tải từ $RepoRaw/themes/<tên>.xaml.
# Bảo mật: XAML có thể khởi tạo object .NET tuỳ ý, tức là tương đương code. Vì vậy chỉ
# nạp từ cùng nguồn với script (thư mục cạnh script hoặc cùng repo), không nhận URL tuỳ ý.
function Get-ThemeXaml([string]$Name) {
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot "themes\$Name.xaml" }
    if ($local -and (Test-Path $local)) { return [IO.File]::ReadAllText($local, [Text.Encoding]::UTF8) }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    return (Invoke-WebRequest "$RepoRaw/themes/$Name.xaml" -UseBasicParsing).Content
}

# Parse + kiểm tra hợp đồng token, có cache.
function Get-Theme([string]$Name) {
    if (-not $Themes.Contains($Name)) { throw "Unknown theme '$Name'" }
    if (-not $ThemeCache[$Name]) {
        $dict = [Windows.Markup.XamlReader]::Parse((Get-ThemeXaml $Name))
        $missing = @($ThemeKeys | Where-Object { -not $dict.Contains($_) })
        if ($missing) { throw "Theme '$Name' is missing keys: $($missing -join ', ')" }
        $ThemeCache[$Name] = $dict
    }
    $ThemeCache[$Name]
}

# Áp dụng theme: thay MergedDictionaries của cửa sổ. Mọi chỗ dùng {DynamicResource}
# (kể cả trong style/template và SetResourceReference) tự vẽ lại, không cần dựng lại UI.
function Set-Theme([string]$Name, [switch]$Save) {
    $dict = Get-Theme $Name
    $win.Resources.MergedDictionaries.Clear()
    $win.Resources.MergedDictionaries.Add($dict)
    $sync.Theme = $Name
    if ($Save) {
        try { New-Item $SettingsDir -ItemType Directory -Force | Out-Null; Set-Content $ThemeFile $Name -Encoding ASCII }
        catch { Write-Log "Could not save theme choice: $_" }
    }
}

# Theme lúc khởi động: theme đã lưu (nếu hợp lệ), không thì theme mặc định.
# Nếu theme đó lỗi (mạng, file hỏng) thì thử lần lượt các theme còn lại.
function Initialize-Theme {
    $saved = if (Test-Path $ThemeFile) { (Get-Content $ThemeFile -TotalCount 1).Trim() }
    $order = @($saved) + @($Themes.Keys) | Where-Object { $_ -and $Themes.Contains($_) } | Select-Object -Unique
    foreach ($n in $order) {
        try { Set-Theme $n; return } catch { Write-Log "Theme '$n' failed: $_" }
    }
    throw 'No theme could be loaded. Check your internet connection or the themes folder.'
}

# Ctrl+T / nút đổi theme: sang theme kế tiếp trong $Themes
function Switch-Theme {
    $names = @($Themes.Keys)
    $next = $names[([array]::IndexOf($names, $sync.Theme) + 1) % $names.Count]
    try { Set-Theme $next -Save; Write-Log "Theme: $($Themes[$next])" } catch { Write-Log "ERROR: $_" }
}

# ----------------------------------------------------------------------------
#  4. Tác vụ nền
# ----------------------------------------------------------------------------
# $sync là hashtable dùng chung giữa luồng UI và các runspace nền.
#   Q     hàng đợi log thread-safe. Runspace nền chỉ Enqueue, UI timer Dequeue.
#         Cách này tránh hẳn việc gọi Dispatcher từ luồng khác.
#   Busy  true khi đang có tác vụ chạy. Mỗi lần chỉ cho chạy một tác vụ, vì
#         winget và registry không nên chạy song song.
#   Prog      tiến trình cài/gỡ app hiện tại (luồng nền ghi, UI timer đọc và vẽ):
#               Active  đã có lượt chạy nào chưa (để hiện panel PROGRESS)
#               Total / Index   tổng số app / app thứ mấy đang xử lý (đếm từ 1)
#               Name    tên app đang xử lý, hoặc dòng tổng kết khi xong
#               Phase   giai đoạn hiện tại (downloading, installing...)
#               Detail  chi tiết (vd "12.0 MB / 48.0 MB")
#               Pct     % tổng của cả lượt (0-100)
#   AppState  winget id -> trạng thái ngắn hiển thị cạnh checkbox ("queued", "45%", "done"...).
#             Dùng ConcurrentDictionary vì UI duyệt (enumerate) nó trong khi luồng nền đang ghi.
#             Hashtable thường sẽ ném lỗi "collection was modified".
$sync = [hashtable]::Synchronized(@{
    Busy = $false; LastBusy = $null
    Q        = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    Prog     = [hashtable]::Synchronized(@{ Active = $false; Total = 0; Index = 0; Name = ''; Phase = ''; Detail = ''; Pct = 0 })
    AppState = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string,string]'
})

# Code được chèn vào đầu MỌI tác vụ nền: các hàm tiện ích có sẵn trong runspace.
#
# Theo dõi tiến trình winget:
#  - Invoke-Winget chạy winget.exe bằng System.Diagnostics.Process, đọc stdout bất đồng bộ
#    (ReadLineAsync + Wait 400ms) để trong lúc winget im lặng vẫn cập nhật được tiến trình.
#  - % TẢI: đã kiểm chứng (winget 1.x) là khi stdout bị chuyển hướng, winget KHÔNG in thanh
#    tải. Đo kích thước file cũng không được, vì winget tải qua Delivery Optimization (DO)
#    vào cache riêng rồi mới copy sang. Cách đúng là hỏi chính DO:
#      Get-DeliveryOptimizationStatus  -> mỗi lượt tải có SourceURL, FileSize, TotalBytesDownloaded
#      (PredefinedCallerApplication = "Windows Package Manager").
#      Dòng "Downloading <url>" của winget cho biết URL -> lọc đúng lượt tải đó -> % + MB + tốc độ.
#    Nếu không có DO (cmdlet thiếu, hoặc winget cấu hình downloader = wininet) thì hiện số
#    giây đã tải. Nếu một phiên bản winget nào đó CÓ in "12.0 MB / 48.0 MB" ra stdout thì
#    Read-WingetLine vẫn đọc được (mỗi dòng được cắt thêm ở '\r').
#  - Giai đoạn chạy installer (có thể vài phút, không có output): hiện số giây đã trôi qua,
#    để người dùng biết tool không bị treo.
#  - Read-WingetLine phân loại từng dòng:
#      "12.0 MB / 48.0 MB"           -> % tải (không ghi log, tránh spam)
#      "Found ..." / "Downloading ..." / "Successfully verified installer hash" /
#      "Starting package install..." -> chuyển giai đoạn + ghi log
#      dòng không có chữ (spinner, thanh bar) -> bỏ qua
#    Các mẫu này là output tiếng Anh của winget. Nếu winget hiển thị ngôn ngữ khác thì vẫn
#    cài bình thường, chỉ là panel ít chi tiết hơn (vẫn có app thứ mấy và kết quả cuối).
#  - Set-Phase quy đổi giai đoạn ra % tổng bằng trọng số $PhaseWeight. Giai đoạn tải chiếm
#    khoảng 10% -> 70% của mỗi app, theo đúng % tải thật.
#  - Mã thoát winget (int32 có dấu):
#      0            thành công
#      -1978335189  0x8A15002B  đã cài và không có bản mới hơn  -> "up to date"
#      -1978334967  0x8A150109  cài xong nhưng cần khởi động lại  -> "done (reboot)"
#      khác         lỗi (xem dòng log ngay trên exit code trong TERMINAL)
$Prelude = @'
$ProgressPreference = 'SilentlyContinue'
function Log($m) { $sync.Q.Enqueue(('[{0}] {1}' -f (Get-Date -Format HH:mm:ss), $m)) }
function Set-Reg($Path, $Name, $Value) {
    if ($null -eq $Value) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue; return }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $type = if ($Value -is [string]) { 'String' } else { 'DWord' }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $type -Force
}

$PhaseText   = @{ start = 'starting'; found = 'found'; dl = 'downloading'; verify = 'verifying'; install = 'installing'; uninstall = 'removing'; ok = 'done'; latest = 'up to date'; reboot = 'done (reboot)'; fail = 'failed' }
$PhaseWeight = @{ start = 2; found = 10; dl = 10; verify = 70; install = 80; uninstall = 50; ok = 100; latest = 100; reboot = 100; fail = 100 }

# On: đang theo dõi một lượt tải. Url: URL winget báo. Start: lúc bắt đầu tải.
# LastPoll: lần hỏi DO gần nhất (giới hạn ~1 lần/giây vì cmdlet tốn ~100ms).
# PhaseStart: lúc vào giai đoạn hiện tại (để đếm giây khi chạy installer).
$DlState = @{
    On = $false; Url = ''; Start = Get-Date; LastPoll = [datetime]::MinValue; PhaseStart = Get-Date
    HasDO = [bool](Get-Command Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue)
}

function Format-Size([double]$b) { if ($b -ge 1GB) { '{0:N2} GB' -f ($b / 1GB) } else { '{0:N1} MB' -f ($b / 1MB) } }

function Start-DownloadWatch([string]$Url) { $DlState.On = $true; $DlState.Url = $Url; $DlState.Start = Get-Date }

function Update-DownloadWatch([string]$Id) {
    if (((Get-Date) - $DlState.LastPoll).TotalMilliseconds -lt 900) { return }
    $DlState.LastPoll = Get-Date
    $sec = [math]::Max(1, [int]((Get-Date) - $DlState.Start).TotalSeconds)
    $job = if ($DlState.HasDO) {
        Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue | Where-Object SourceURL -eq $DlState.Url | Select-Object -Last 1
    }
    if ($job -and $job.FileSize -gt 0) {
        $got = [double]$job.TotalBytesDownloaded; $all = [double]$job.FileSize
        $pct = [math]::Min(99, [int](100 * $got / $all))   # 100% chỉ khi winget báo xong
        Set-Phase $Id 'dl' $pct ('{0} / {1}  {2}/s' -f (Format-Size $got), (Format-Size $all), (Format-Size ($got / $sec)))
    } else {
        $sync.Prog.Detail = "downloading... ${sec}s"
    }
}

function Set-Phase([string]$Id, [string]$Phase, [int]$Pct = 0, [string]$Detail = '') {
    if ($Phase -ne 'dl') { $DlState.On = $false }
    if ($Phase -ne $sync.Prog.LastPhase) { $DlState.PhaseStart = Get-Date; $sync.Prog.LastPhase = $Phase }
    $w = if ($Phase -eq 'dl') { 10 + [int](0.6 * $Pct) } else { $PhaseWeight[$Phase] }
    if ($Id) { $sync.AppState[$Id] = if ($Phase -eq 'dl' -and $Pct -gt 0) { "$Pct%" } else { $PhaseText[$Phase] } }
    $sync.Prog.Phase  = $PhaseText[$Phase]
    $sync.Prog.Detail = $Detail
    $sync.Prog.Pct    = [int]((([math]::Max(1, $sync.Prog.Index) - 1) * 100 + $w) / [math]::Max(1, $sync.Prog.Total))
}

function Read-WingetLine([string]$Line, [string]$Id) {
    $l = ($Line -replace '\x1b\[[0-9;?]*[A-Za-z]', '').Trim()
    if (-not $l) { return }
    $m = [regex]::Match($l, '(?i)([\d.]+)\s*(KB|MB|GB)\s*/\s*([\d.]+)\s*(KB|MB|GB)')
    if ($m.Success) {
        $unit = @{ KB = 1KB; MB = 1MB; GB = 1GB }
        $got = [double]$m.Groups[1].Value * $unit[$m.Groups[2].Value]
        $all = [double]$m.Groups[3].Value * $unit[$m.Groups[4].Value]
        $pct = if ($all -gt 0) { [math]::Min(100, [int](100 * $got / $all)) } else { 0 }
        Set-Phase $Id 'dl' $pct ('{0} {1} / {2} {3}' -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value, $m.Groups[4].Value)
        return
    }
    if ($l -notmatch '[A-Za-z]{3}') {
        $m = [regex]::Match($l, '(\d{1,3})\s*%\s*$')
        if ($m.Success) { $sync.Prog.Detail = "$($m.Groups[1].Value)%" }
        return
    }
    Log "  $l"
    switch -Regex ($l) {
        '^Found '                            { Set-Phase $Id 'found' 0 ($l -replace '^Found ', '') }
        '^Downloading (\S+)'                 { Set-Phase $Id 'dl' 0 'connecting...'; Start-DownloadWatch $Matches[1] }
        'verified installer hash'            { Set-Phase $Id 'verify' 0 'installer hash verified' }
        'Starting package install'           { Set-Phase $Id 'install' 0 'running installer, please wait...' }
        'Starting package uninstall'         { Set-Phase $Id 'uninstall' 0 'running uninstaller...' }
        'existing package already installed' { Set-Phase $Id 'found' 0 'already installed, checking for upgrade' }
    }
}

function Invoke-Winget([string[]]$WArgs, [string]$Id = '') {
    $exe = (Get-Command winget -ErrorAction SilentlyContinue).Source
    if (-not $exe) { throw 'winget not found. Install "App Installer" from Microsoft Store.' }
    $psi = New-Object Diagnostics.ProcessStartInfo $exe, ($WArgs -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $task = $p.StandardOutput.ReadLineAsync()
    while ($true) {
        if ($task.Wait(400)) {
            $line = $task.Result
            if ($null -eq $line) { break }   # winget đã đóng stdout
            foreach ($part in $line -split "`r") { $null = Read-WingetLine $part $Id }
            $task = $p.StandardOutput.ReadLineAsync()
        } elseif ($DlState.On) {
            Update-DownloadWatch $Id
        } elseif ($sync.Prog.LastPhase -in 'install', 'uninstall') {
            $base = if ($sync.Prog.LastPhase -eq 'install') { 'running installer' } else { 'running uninstaller' }
            $sync.Prog.Detail = '{0}... {1}s' -f $base, [int]((Get-Date) - $DlState.PhaseStart).TotalSeconds
        }
    }
    $p.WaitForExit()
    Log ('  exit code: {0} (0x{0:X8})' -f $p.ExitCode)
    return $p.ExitCode
}

function Invoke-WingetBatch([string]$Verb, [object[]]$Apps) {
    $n = $Apps.Count; $ok = 0; $fail = 0
    $sync.Prog.Total = $n; $sync.Prog.Index = 0; $sync.Prog.Active = $true
    foreach ($a in $Apps) { $sync.AppState[$a[0]] = 'queued' }
    for ($i = 0; $i -lt $n; $i++) {
        $id = $Apps[$i][0]; $name = $Apps[$i][1]
        $sync.Prog.Index = $i + 1; $sync.Prog.Name = $name
        Set-Phase $id 'start' 0 "$Verb $id"
        Log "[$($i + 1)/$n] $Verb $name ($id)"
        $wa = if ($Verb -eq 'install') { 'install', '--id', $id, '-e', '--silent', '--accept-source-agreements', '--accept-package-agreements' }
              else { 'uninstall', '--id', $id, '-e', '--silent', '--accept-source-agreements' }
        try { $code = [int]@(Invoke-Winget $wa $id)[-1] } catch { Log "  ERROR: $_"; $code = -1 }
        $phase = if ($code -eq 0) { 'ok' } elseif ($code -eq -1978335189) { 'latest' } elseif ($code -eq -1978334967) { 'reboot' } else { 'fail' }
        Set-Phase $id $phase 0 "exit code $code"
        if ($phase -eq 'fail') { $fail++ } else { $ok++ }
    }
    $sync.Prog.Name = "Finished: $ok ok, $fail failed"
    $sync.Prog.Phase = 'finished'; $sync.Prog.Detail = 'details in TERMINAL'; $sync.Prog.Pct = 100
    Log "Summary: $ok ok, $fail failed"
}
'@

function Write-Log($m) { $sync.Q.Enqueue(('[{0}] {1}' -f (Get-Date -Format HH:mm:ss), $m)) }

# Chạy $Code (chuỗi) trong runspace mới. $Vars được bơm vào thành biến trong runspace đó.
function Invoke-Task([string]$Title, [string]$Code, [hashtable]$Vars = @{}) {
    if ($sync.Busy) { Write-Log 'Another task is still running, please wait.'; return }
    $sync.Busy = $true; $sync.Task = $Title
    # shortcut: runspaces are not disposed after finishing, fine for an interactive tool
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    foreach ($k in $Vars.Keys) { $rs.SessionStateProxy.SetVariable($k, $Vars[$k]) }
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    # finally luôn hạ cờ Busy, kể cả khi tác vụ lỗi, để UI không bị khoá vĩnh viễn
    [void]$ps.AddScript("$Prelude`nLog '>> $Title'`ntry {`n$Code`n} catch { Log ('ERROR: ' + `$_) } finally { Log '>> done'; `$sync.Busy = `$false }")
    [void]$ps.BeginInvoke()
}

# ----------------------------------------------------------------------------
#  5. Font JetBrains Mono (nạp từ %TEMP%, không cần cài vào Windows)
# ----------------------------------------------------------------------------
# WPF nạp font trực tiếp từ thư mục qua cú pháp "<thư mục>/#<Tên family>".
# Có sẵn font trong hệ thống thì dùng luôn. Tải lỗi thì dùng Consolas.
function Get-UiFont {
    if ([Windows.Media.Fonts]::SystemFontFamilies | Where-Object Source -eq 'JetBrains Mono') { return New-Object Windows.Media.FontFamily 'JetBrains Mono' }
    $dir = Join-Path $env:TEMP 'winutil-font'
    try {
        New-Item $dir -ItemType Directory -Force | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        foreach ($w in 'Regular', 'Bold') {
            $f = Join-Path $dir "JetBrainsMono-$w.ttf"
            if (-not (Test-Path $f)) { Invoke-WebRequest "https://github.com/JetBrains/JetBrainsMono/raw/master/fonts/ttf/JetBrainsMono-$w.ttf" -OutFile $f -UseBasicParsing }
        }
        return New-Object Windows.Media.FontFamily ((New-Object Uri "$dir\"), './#JetBrains Mono')
    } catch { return New-Object Windows.Media.FontFamily 'Consolas' }
}

# ----------------------------------------------------------------------------
#  6. Layout (XAML)
# ----------------------------------------------------------------------------
# Quy ước:
#  - KHÔNG viết mã màu cứng trong layout: luôn dùng {DynamicResource <Token>}.
#    (StaticResource sẽ không cập nhật khi đổi theme, và cũng lỗi vì lúc parse
#    layout thì theme chưa được merge.)
#  - Các phần tử code cần truy cập dùng thuộc tính Name (không phải x:Name),
#    để vòng lặp SelectNodes('//*[@Name]') ở dưới tìm được.
#  - Một layout duy nhất cho mọi theme. Khác biệt cấu trúc (activity bar hay
#    waybar, có khe hở hay không) được điều khiển bằng token *Vis / Thickness.
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinUtil" Width="1180" Height="760" MinWidth="900" MinHeight="560"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="CanResize"
        Background="{DynamicResource Bg}" Foreground="{DynamicResource Fg}" FontSize="13"
        BorderBrush="{DynamicResource WindowBorder}" BorderThickness="1">
  <!-- Tự vẽ thanh tiêu đề nhưng vẫn giữ kéo/resize/snap của Windows -->
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="30" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <!-- Nút mặc định (nút thường) -->
    <Style TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource BtnBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource BtnFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BtnBorder}"/>
      <Setter Property="BorderThickness" Value="{DynamicResource BtnBorderThickness}"/>
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="{DynamicResource Radius}" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.8"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.65"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{DynamicResource BtnPrimaryBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource BtnPrimaryFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BtnPrimaryBg}"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{DynamicResource BtnDangerBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource BtnDangerFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BtnDangerBg}"/>
    </Style>
    <!-- Nút trên thanh tiêu đề. IsHitTestVisibleInChrome để bấm được trong vùng caption. -->
    <Style x:Key="Cap" TargetType="Button">
      <Setter Property="Width" Value="46"/><Setter Property="Height" Value="30"/>
      <Setter Property="Foreground" Value="{DynamicResource CapFg}"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/><Setter Property="FontSize" Value="10"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border Background="{TemplateBinding Background}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        </ControlTemplate>
      </Setter.Value></Setter>
      <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource CapHoverBg}"/></Trigger></Style.Triggers>
    </Style>
    <Style x:Key="CapClose" TargetType="Button" BasedOn="{StaticResource Cap}">
      <Style.Triggers><Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="{DynamicResource CloseHoverBg}"/><Setter Property="Foreground" Value="{DynamicResource CloseHoverFg}"/>
      </Trigger></Style.Triggers>
    </Style>
    <!-- Activity bar (VS Code). Tag="on" = trang đang mở. -->
    <Style x:Key="Act" TargetType="Button">
      <Setter Property="Width" Value="48"/><Setter Property="Height" Value="48"/>
      <Setter Property="Foreground" Value="{DynamicResource ActFg}"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/><Setter Property="FontSize" Value="22"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Grid Background="Transparent">
            <Border x:Name="ind" Width="2" HorizontalAlignment="Left" Background="{DynamicResource ActFgActive}" Visibility="Hidden"/>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{DynamicResource ActFgActive}"/></Trigger>
            <Trigger Property="Tag" Value="on"><Setter TargetName="ind" Property="Visibility" Value="Visible"/><Setter Property="Foreground" Value="{DynamicResource ActFgActive}"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <!-- Workspace kiểu Waybar (Omarchy): hiện số, trang đang mở thành ô vuông đặc. -->
    <Style x:Key="Ws" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Width" Value="22"/><Setter Property="Height" Value="30"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Grid Background="Transparent">
            <ContentPresenter x:Name="num" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Border x:Name="dot" Width="9" Height="9" Background="{TemplateBinding Foreground}" Visibility="Collapsed"
                    HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{DynamicResource FgMuted}"/></Trigger>
            <Trigger Property="Tag" Value="on"><Setter TargetName="num" Property="Visibility" Value="Collapsed"/><Setter TargetName="dot" Property="Visibility" Value="Visible"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="Margin" Value="0,4,24,4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Border x:Name="box" Width="15" Height="15" CornerRadius="{DynamicResource Radius}" BorderThickness="1"
                    BorderBrush="{DynamicResource CheckBorder}" Background="{DynamicResource CheckBg}" VerticalAlignment="Center">
              <Path x:Name="tick" Data="M0,5 L3.5,8.5 L10,1" Stroke="{DynamicResource AccentFg}" StrokeThickness="1.8" Stretch="Uniform" Margin="2.5" Visibility="Collapsed"/>
            </Border>
            <ContentPresenter Margin="9,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
              <Setter TargetName="box" Property="Background" Value="{DynamicResource Accent}"/>
              <Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource BgInput}"/><Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,5"/><Setter Property="CaretBrush" Value="{DynamicResource Fg}"/>
      <Setter Property="SelectionBrush" Value="{DynamicResource Selection}"/>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{DynamicResource ToolTipBg}"/><Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
    </Style>
    <!-- Scrollbar mảnh, chỉ có thumb. Các ScrollViewer đều tắt cuộn ngang. -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/><Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Track x:Name="PART_Track" IsDirectionReversed="True" Orientation="{TemplateBinding Orientation}">
            <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="{DynamicResource ScrollThumb}"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
          </Track>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <!-- Thanh tiến trình: track = màu ô nhập, phần đã chạy = Accent (đen ở White, xanh ở Dark) -->
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="6"/>
      <Setter Property="Maximum" Value="100"/>
      <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
      <Setter Property="Background" Value="{DynamicResource BgInput}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ProgressBar">
          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="{DynamicResource Radius}">
            <!-- ProgressBar tự đặt Width của PART_Indicator theo Value/Maximum -->
            <Grid x:Name="PART_Track" ClipToBounds="True">
              <Rectangle x:Name="PART_Indicator" HorizontalAlignment="Left" Fill="{TemplateBinding Foreground}"/>
            </Grid>
          </Border>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <!-- Ô cửa sổ (tile): sidebar, editor, terminal. Khe hở + viền lấy từ theme. -->
    <Style x:Key="Tile" TargetType="Border">
      <Setter Property="Margin" Value="{DynamicResource TileGap}"/>
      <Setter Property="BorderThickness" Value="{DynamicResource TileBorder}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource TileBorderBrush}"/>
      <Setter Property="Background" Value="{DynamicResource Bg}"/>
    </Style>
    <!-- Hộp nhóm (danh mục app, nhóm tweak, lựa chọn update) -->
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource BgCard}"/><Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
      <Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="{DynamicResource CardRadius}"/>
      <Setter Property="Padding" Value="14,12"/><Setter Property="Margin" Value="0,0,12,12"/><Setter Property="Width" Value="250"/>
    </Style>
    <Style x:Key="Comment" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource CommentFg}"/><Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style x:Key="Desc" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FgSubtle}"/><Setter Property="FontSize" Value="11.5"/>
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="Margin" Value="24,0,0,10"/>
    </Style>
    <Style x:Key="Head" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FgHead}"/><Setter Property="FontSize" Value="11"/><Setter Property="Margin" Value="0,0,0,14"/>
    </Style>
  </Window.Resources>

  <Grid Name="Root">
    <Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/><RowDefinition Height="22"/></Grid.RowDefinitions>

    <!-- ═══ Thanh tiêu đề: VS Code (ClassicChromeVis) hoặc Waybar (WaybarVis) ═══ -->
    <Grid Grid.Row="0" Background="{DynamicResource BgTitle}">
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0">
        <TextBlock Text="&#xE756;" FontFamily="Segoe MDL2 Assets" Foreground="{DynamicResource TitleIconFg}" FontSize="14" VerticalAlignment="Center"/>
        <TextBlock Text="WinUtil" Margin="10,0,0,0" FontSize="12" VerticalAlignment="Center" Visibility="{DynamicResource ClassicChromeVis}"/>
        <StackPanel Orientation="Horizontal" Margin="8,0,0,0" Visibility="{DynamicResource WaybarVis}">
          <Button Name="WsInstall" Style="{StaticResource Ws}" Content="1" ToolTip="Install"/>
          <Button Name="WsTweaks" Style="{StaticResource Ws}" Content="2" ToolTip="Tweaks"/>
          <Button Name="WsConfig" Style="{StaticResource Ws}" Content="3" ToolTip="Config"/>
          <Button Name="WsUpdates" Style="{StaticResource Ws}" Content="4" ToolTip="Updates"/>
        </StackPanel>
      </StackPanel>
      <TextBlock Name="TitleText" HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="12" Visibility="{DynamicResource ClassicChromeVis}"/>
      <TextBlock Name="Clock" HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="12" Visibility="{DynamicResource WaybarVis}"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnTheme" Style="{StaticResource Cap}" Content="&#xE706;" FontSize="13" ToolTip="Switch theme (Ctrl+T)"/>
        <Button Name="BtnMin" Style="{StaticResource Cap}" Content="&#xE921;"/>
        <Button Name="BtnMax" Style="{StaticResource Cap}" Content="&#xE922;"/>
        <Button Name="BtnClose" Style="{StaticResource CapClose}" Content="&#xE8BB;"/>
      </StackPanel>
    </Grid>

    <!-- ═══ Vùng làm việc: activity bar | sidebar tile | (editor tile / terminal tile) ═══ -->
    <Grid Grid.Row="1" Margin="{DynamicResource RootPad}">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="240"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

      <Border Grid.Column="0" Width="48" Background="{DynamicResource BgActivity}" Visibility="{DynamicResource ClassicChromeVis}">
        <StackPanel>
          <Button Name="ActInstall" Style="{StaticResource Act}" Content="&#xE896;" ToolTip="Install"/>
          <Button Name="ActTweaks" Style="{StaticResource Act}" Content="&#xE90F;" ToolTip="Tweaks"/>
          <Button Name="ActConfig" Style="{StaticResource Act}" Content="&#xE713;" ToolTip="Config"/>
          <Button Name="ActUpdates" Style="{StaticResource Act}" Content="&#xE895;" ToolTip="Updates"/>
        </StackPanel>
      </Border>

      <!-- Sidebar: mỗi trang có một StackPanel riêng, Show-Page bật/tắt theo trang -->
      <Border Grid.Column="1" Style="{StaticResource Tile}" Background="{DynamicResource BgSide}">
        <Grid>
          <StackPanel Name="SideInstall" Margin="16,12,8,12">
            <TextBlock Style="{StaticResource Head}" Text="INSTALL"/>
            <TextBlock Text="Search" FontSize="11" Foreground="{DynamicResource FgSubtle}" Margin="0,0,0,4"/>
            <TextBox Name="Search" Margin="0,0,8,14"/>
            <Button Name="BtnInstall" Style="{StaticResource Primary}" Content="Install selected"/>
            <Button Name="BtnUninstall" Content="Uninstall selected"/>
            <Button Name="BtnUpgrade" Content="Upgrade all apps"/>
            <Button Name="BtnClearApps" Content="Clear selection"/>
            <TextBlock Name="SelCount" Text="0 selected" Foreground="{DynamicResource FgSubtle}" FontSize="11" Margin="0,8,0,0"/>
            <!-- Panel tiến trình: ẩn cho tới lượt cài/gỡ đầu tiên, sau đó giữ lại kết quả lượt gần nhất -->
            <StackPanel Name="ProgPanel" Margin="0,22,8,0" Visibility="Collapsed">
              <TextBlock Style="{StaticResource Head}" Text="PROGRESS" Margin="0,0,0,8"/>
              <TextBlock Name="ProgApp" FontWeight="Bold" TextTrimming="CharacterEllipsis"/>
              <TextBlock Name="ProgPhase" Foreground="{DynamicResource FgSubtle}" FontSize="11.5" TextWrapping="Wrap" Margin="0,3,0,8"/>
              <ProgressBar Name="ProgBar"/>
              <TextBlock Name="ProgCount" Foreground="{DynamicResource FgSubtle}" FontSize="11" Margin="0,6,0,0"/>
            </StackPanel>
          </StackPanel>
          <StackPanel Name="SideTweaks" Margin="16,12,8,12" Visibility="Collapsed">
            <TextBlock Style="{StaticResource Head}" Text="TWEAKS"/>
            <Button Name="PresetStd" Content="Preset: Standard"/>
            <Button Name="PresetMin" Content="Preset: Minimal"/>
            <Button Name="PresetClear" Content="Clear selection" Margin="0,0,8,18"/>
            <Button Name="BtnRunTweaks" Style="{StaticResource Primary}" Content="Run tweaks"/>
            <Button Name="BtnUndoTweaks" Content="Undo selected"/>
          </StackPanel>
          <StackPanel Name="SideConfig" Margin="16,12,8,12" Visibility="Collapsed">
            <TextBlock Style="{StaticResource Head}" Text="CONFIG"/>
            <Button Name="BtnFeatures" Style="{StaticResource Primary}" Content="Install features"/>
            <TextBlock Style="{StaticResource Desc}" Margin="0,8,8,0" Text="Some features need a restart to finish."/>
          </StackPanel>
          <StackPanel Name="SideUpdates" Margin="16,12,8,12" Visibility="Collapsed">
            <TextBlock Style="{StaticResource Head}" Text="UPDATES"/>
            <TextBlock Style="{StaticResource Desc}" Margin="0,0,8,0" Text="Choose how Windows Update behaves. 'Security' is recommended for most users."/>
          </StackPanel>
        </Grid>
      </Border>

      <Grid Grid.Column="2">
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="5"/><RowDefinition Height="210" MinHeight="70"/></Grid.RowDefinitions>

        <!-- Editor tile: tab + breadcrumb + nội dung trang -->
        <Border Grid.Row="0" Style="{StaticResource Tile}">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="35"/><RowDefinition Height="24"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Border Grid.Row="0" Background="{DynamicResource BgTabBar}">
              <Border HorizontalAlignment="Left" Background="{DynamicResource BgTabActive}" BorderBrush="{DynamicResource TabActiveBorder}" BorderThickness="0,1,0,0" Padding="14,0">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock Text="PS" Foreground="{DynamicResource TabIconFg}" FontWeight="Bold" FontSize="11" Margin="0,0,8,0" VerticalAlignment="Center"/>
                  <TextBlock Name="TabTitle" Foreground="{DynamicResource FgStrong}" VerticalAlignment="Center"/>
                  <TextBlock Text="&#xE8BB;" FontFamily="Segoe MDL2 Assets" FontSize="9" Margin="16,0,0,0" Foreground="{DynamicResource FgSubtle}" VerticalAlignment="Center"/>
                </StackPanel>
              </Border>
            </Border>
            <TextBlock Grid.Row="1" Name="Crumb" Margin="16,0" VerticalAlignment="Center" Foreground="{DynamicResource FgMuted}" FontSize="12"/>

            <Grid Grid.Row="2" Margin="16,8,6,0">
              <ScrollViewer Name="PageInstall" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <WrapPanel Name="AppPanel"/>
              </ScrollViewer>
              <ScrollViewer Name="PageTweaks" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <WrapPanel Name="TweakPanel"/>
              </ScrollViewer>
              <ScrollViewer Name="PageConfig" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel>
                  <TextBlock Style="{StaticResource Comment}" Text="// Windows features"/>
                  <WrapPanel Name="FeaturePanel" Margin="0,0,0,18"/>
                  <TextBlock Style="{StaticResource Comment}" Text="// Fixes"/>
                  <WrapPanel Name="FixPanel" Margin="0,0,0,18"/>
                  <TextBlock Style="{StaticResource Comment}" Text="// Legacy Windows panels"/>
                  <WrapPanel Name="PanelPanel"/>
                </StackPanel>
              </ScrollViewer>
              <ScrollViewer Name="PageUpdates" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <WrapPanel>
                  <Border Style="{StaticResource Card}" Width="290"><StackPanel>
                    <TextBlock Style="{StaticResource Comment}" Text="// Default"/>
                    <TextBlock Style="{StaticResource Desc}" Margin="0" Text="Windows default behaviour. Removes every update policy set by this tool."/>
                    <Button Name="UpdDefault" Content="Set default" HorizontalAlignment="Left" Margin="0,14,0,0"/>
                  </StackPanel></Border>
                  <Border Style="{StaticResource Card}" Width="290"><StackPanel>
                    <TextBlock Style="{StaticResource Comment}" Text="// Security (recommended)"/>
                    <TextBlock Style="{StaticResource Desc}" Margin="0" Text="Delays feature updates by 365 days and security updates by 4 days. No forced reboot while signed in."/>
                    <Button Name="UpdSecurity" Style="{StaticResource Primary}" Content="Set security" HorizontalAlignment="Left" Margin="0,14,0,0"/>
                  </StackPanel></Border>
                  <Border Style="{StaticResource Card}" Width="290"><StackPanel>
                    <TextBlock Style="{StaticResource Comment}" Text="// Disable all updates"/>
                    <TextBlock Style="{StaticResource Desc}" Margin="0" Text="Not recommended. Your PC stops receiving security patches."/>
                    <Button Name="UpdDisable" Style="{StaticResource Danger}" Content="Disable updates" HorizontalAlignment="Left" Margin="0,14,0,0"/>
                  </StackPanel></Border>
                </WrapPanel>
              </ScrollViewer>
            </Grid>
          </Grid>
        </Border>

        <GridSplitter Grid.Row="1" HorizontalAlignment="Stretch" Background="Transparent" ResizeDirection="Rows"/>

        <!-- Terminal tile: log của mọi tác vụ -->
        <Border Grid.Row="2" Style="{StaticResource Tile}">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="32"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Border BorderBrush="{DynamicResource FgStrong}" BorderThickness="0,0,0,1" HorizontalAlignment="Left" Margin="16,0,0,0" VerticalAlignment="Center" Padding="0,0,0,3">
              <TextBlock Text="TERMINAL" FontSize="11" Foreground="{DynamicResource FgStrong}"/>
            </Border>
            <Button Name="BtnClearLog" Style="{StaticResource Cap}" Content="&#xE74D;" ToolTip="Clear" HorizontalAlignment="Right" Width="32" FontSize="12"/>
            <TextBox Grid.Row="1" Name="Log" IsReadOnly="True" Background="{DynamicResource Bg}" BorderThickness="0" Padding="12,0"
                     TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontSize="12"/>
          </Grid>
        </Border>
      </Grid>
    </Grid>

    <!-- ═══ Thanh trạng thái. Nền bar và nền badge do code đổi theo Busy (xem timer) ═══ -->
    <Border Grid.Row="2" Name="StatusBar" Background="{DynamicResource StatusBg}">
      <Border.Resources>
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{DynamicResource StatusFg}"/><Setter Property="FontSize" Value="12"/><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Margin" Value="10,0"/></Style>
      </Border.Resources>
      <DockPanel>
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
          <TextBlock Name="StTheme"/>
          <TextBlock Name="StWinget"/>
          <TextBlock Name="StPs"/>
          <TextBlock Text="Administrator"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal">
          <Border Name="StatusBadge" Background="{DynamicResource BadgeBg}" Padding="0,0,2,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE756;" FontFamily="Segoe MDL2 Assets" Foreground="{DynamicResource BadgeFg}"/>
              <TextBlock Name="StatusText" Text="Ready" Margin="0,0,10,0" Foreground="{DynamicResource BadgeFg}"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
# $ui['Ten'] -> phần tử có Name="Ten" trong XAML
$ui = @{}
$xaml.SelectNodes('//*[@Name]') | ForEach-Object { $ui[$_.Name] = $win.FindName($_.Name) }
$win.FontFamily = Get-UiFont
Initialize-Theme    # phải chạy trước khi cửa sổ hiện, để frame đầu tiên đã đúng màu
$sep = ' ' + [char]0x203A + ' '

# Tạo control WPF trong code. $style là key trong Window.Resources (Card, Comment, Desc...)
function New-Ui($type, $style) { $e = New-Object "Windows.Controls.$type"; if ($style) { $e.Style = $win.FindResource($style) }; $e }

# ----------------------------------------------------------------------------
#  7. Sinh nội dung động từ dữ liệu ở mục 2
# ----------------------------------------------------------------------------
# Trang Install: mỗi danh mục một hộp. Mỗi app là một hàng (DockPanel) gồm:
#   checkbox (Tag = winget id) | nhãn trạng thái bên phải ($AppLabels[id], timer cập nhật)
# Ô tìm kiếm ẩn/hiện cả hàng (= $cb.Parent).
$sync.AppBoxes = New-Object Collections.ArrayList
$AppLabels = @{}
foreach ($cat in $Apps.Keys) {
    $card = New-Ui Border 'Card'; $sp = New-Object Windows.Controls.StackPanel; $card.Child = $sp
    $h = New-Ui TextBlock 'Comment'; $h.Text = "// $cat"; [void]$sp.Children.Add($h)
    foreach ($a in $Apps[$cat]) {
        $name, $id = $a -split '\|'
        $row = New-Object Windows.Controls.DockPanel
        $st = New-Ui TextBlock 'Desc'; $st.Margin = '8,0,0,0'; $st.TextWrapping = 'NoWrap'; $st.VerticalAlignment = 'Center'
        [Windows.Controls.DockPanel]::SetDock($st, 'Right')
        $cb = New-Object Windows.Controls.CheckBox; $cb.Content = $name; $cb.Tag = $id; $cb.ToolTip = $id; $cb.Margin = '0,4,0,4'
        $cb.Add_Click({ $ui.SelCount.Text = "$(@($sync.AppBoxes | Where-Object IsChecked).Count) selected" })
        [void]$row.Children.Add($st); [void]$row.Children.Add($cb)
        [void]$sp.Children.Add($row); [void]$sync.AppBoxes.Add($cb); $AppLabels[$id] = $st
    }
    [void]$ui.AppPanel.Children.Add($card)
}

# Trang Tweaks: mỗi Group một hộp. Tag của checkbox = chính hashtable tweak
$sync.TweakBoxes = New-Object Collections.ArrayList
foreach ($g in ($Tweaks | ForEach-Object { $_.Group } | Select-Object -Unique)) {
    $card = New-Ui Border 'Card'; $card.Width = 360; $sp = New-Object Windows.Controls.StackPanel; $card.Child = $sp
    $h = New-Ui TextBlock 'Comment'; $h.Text = "// $g"; [void]$sp.Children.Add($h)
    foreach ($t in ($Tweaks | Where-Object Group -eq $g)) {
        $cb = New-Object Windows.Controls.CheckBox; $cb.Content = $t.Name; $cb.Tag = $t; $cb.Margin = '0,4,0,2'
        $d = New-Ui TextBlock 'Desc'; $d.Text = $t.Desc
        [void]$sp.Children.Add($cb); [void]$sp.Children.Add($d); [void]$sync.TweakBoxes.Add($cb)
    }
    [void]$ui.TweakPanel.Children.Add($card)
}

# Trang Config
$sync.FeatureBoxes = New-Object Collections.ArrayList
foreach ($f in $Features) {
    $name, $id = $f -split '\|'
    $cb = New-Object Windows.Controls.CheckBox; $cb.Content = $name; $cb.Tag = $id
    [void]$ui.FeaturePanel.Children.Add($cb); [void]$sync.FeatureBoxes.Add($cb)
}
foreach ($k in $Fixes.Keys) {
    $b = New-Object Windows.Controls.Button; $b.Content = $k; $b.Tag = $Fixes[$k]
    $b.Add_Click({ Invoke-Task $this.Content $this.Tag }); [void]$ui.FixPanel.Children.Add($b)
}
foreach ($k in $Panels.Keys) {
    $b = New-Object Windows.Controls.Button; $b.Content = $k; $b.Tag = $Panels[$k]
    $b.Add_Click({ Start-Process $this.Tag }); [void]$ui.PanelPanel.Children.Add($b)
}

# ----------------------------------------------------------------------------
#  8. Sự kiện
# ----------------------------------------------------------------------------
# Chuyển trang: bật trang + sidebar tương ứng, đánh dấu cả activity bar lẫn workspace.
# Tên control theo quy ước Page<X>, Side<X>, Act<X>, Ws<X>.
$Pages = 'Install', 'Tweaks', 'Config', 'Updates'
function Show-Page($p) {
    foreach ($x in $Pages) {
        $on = $x -eq $p
        $v = if ($on) { 'Visible' } else { 'Collapsed' }
        $ui["Page$x"].Visibility = $v; $ui["Side$x"].Visibility = $v
        $tag = if ($on) { 'on' } else { '' }
        $ui["Act$x"].Tag = $tag; $ui["Ws$x"].Tag = $tag
    }
    $ui.TabTitle.Text = "$($p.ToLower()).ps1"
    $ui.Crumb.Text = "winutil$sep$($p.ToLower()).ps1"
    $ui.TitleText.Text = "$($p.ToLower()).ps1 - WinUtil"
}
# Lấy tên trang từ tên control: "ActTweaks" -> "Tweaks", "WsTweaks" -> "Tweaks"
foreach ($x in $Pages) {
    $ui["Act$x"].Add_Click({ Show-Page ($this.Name -replace '^(Act|Ws)', '') })
    $ui["Ws$x"].Add_Click({ Show-Page ($this.Name -replace '^(Act|Ws)', '') })
}

$ui.BtnTheme.Add_Click({ Switch-Theme })
$win.Add_KeyDown({
    if ($_.Key -eq 'T' -and [Windows.Input.Keyboard]::Modifiers -eq 'Control') { Switch-Theme; $_.Handled = $true }
})

$ui.BtnMin.Add_Click({ $win.WindowState = 'Minimized' })
$ui.BtnMax.Add_Click({ $win.WindowState = if ($win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } })
$ui.BtnClose.Add_Click({ $win.Close() })
$win.Add_StateChanged({
    $max = $win.WindowState -eq 'Maximized'
    $ui.Root.Margin = if ($max) { 7 } else { 0 }   # WindowChrome tràn ra ngoài màn hình ~7px khi maximize
    $ui.BtnMax.Content = if ($max) { [string][char]0xE923 } else { [string][char]0xE922 }
})

# Tìm kiếm theo tên hoặc winget id
$ui.Search.Add_TextChanged({
    $q = $ui.Search.Text.Trim()
    foreach ($cb in $sync.AppBoxes) { $cb.Parent.Visibility = if (!$q -or $cb.Content -like "*$q*" -or $cb.Tag -like "*$q*") { 'Visible' } else { 'Collapsed' } }
})

# ---- Install / Uninstall / Upgrade
# Gửi sang luồng nền danh sách @(id, tên) để panel PROGRESS hiện tên thân thiện.
function Start-AppBatch([string]$Verb) {
    $sel = @($sync.AppBoxes | Where-Object IsChecked | ForEach-Object { , @($_.Tag, $_.Content) })
    if (!$sel) { Write-Log 'No apps selected.'; return }
    Invoke-Task "$Verb $($sel.Count) app(s)" 'Invoke-WingetBatch $verb $apps' @{ verb = $Verb; apps = $sel }
}
$ui.BtnInstall.Add_Click({ Start-AppBatch 'install' })
$ui.BtnUninstall.Add_Click({ Start-AppBatch 'uninstall' })
# Upgrade all: winget tự liệt kê gói cần nâng cấp, nên coi cả lượt là 1 "app"
$ui.BtnUpgrade.Add_Click({
    Invoke-Task 'Upgrade all apps' @'
$sync.Prog.Active = $true; $sync.Prog.Total = 1; $sync.Prog.Index = 1; $sync.Prog.Name = 'Upgrading all apps'
$code = [int]@(Invoke-Winget @('upgrade', '--all', '--silent', '--accept-source-agreements', '--accept-package-agreements'))[-1]
Set-Phase '' $(if ($code -eq 0) { 'ok' } else { 'fail' }) 0 "exit code $code"
$sync.Prog.Name = 'Upgrade finished'
'@
})
$ui.BtnClearApps.Add_Click({ $sync.AppBoxes | ForEach-Object { $_.IsChecked = $false }; $ui.SelCount.Text = '0 selected' })

# ---- Tweaks
function Set-Preset($p) { foreach ($cb in $sync.TweakBoxes) { $cb.IsChecked = ($cb.Tag.Preset -split ',') -contains $p } }
$ui.PresetStd.Add_Click({ Set-Preset 'std' })
$ui.PresetMin.Add_Click({ Set-Preset 'min' })
$ui.PresetClear.Add_Click({ Set-Preset '-' })

# Chạy trong runspace nền, với $items (các tweak đã chọn) và $undo được bơm vào.
# Mỗi tweak có try/catch riêng: một tweak lỗi không chặn các tweak còn lại.
$TweakCode = @'
foreach ($t in $items) {
    Log "  $(if ($undo) { 'undo' } else { 'apply' }): $($t.Name)"
    try {
        foreach ($r in $t.Reg) { Set-Reg $r[0] $r[1] $(if ($undo) { $r[3] } else { $r[2] }) }
        $c = if ($undo) { $t.Undo } else { $t.Run }
        if ($c) { & ([scriptblock]::Create($c)) }
    } catch { Log "  ERROR: $_" }
}
if ($items | Where-Object { $_.Explorer }) { Log '  restarting Explorer'; Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }
'@
function Start-Tweaks([bool]$undo) {
    $items = @($sync.TweakBoxes | Where-Object IsChecked | ForEach-Object Tag)
    if (!$items) { Write-Log 'No tweaks selected.'; return }
    Invoke-Task $(if ($undo) { 'Undo tweaks' } else { 'Run tweaks' }) $TweakCode @{ items = $items; undo = $undo }
}
$ui.BtnRunTweaks.Add_Click({ Start-Tweaks $false })
$ui.BtnUndoTweaks.Add_Click({ Start-Tweaks $true })

# ---- Config
$ui.BtnFeatures.Add_Click({
    $ids = @($sync.FeatureBoxes | Where-Object IsChecked | ForEach-Object { $_.Tag -split ',' })
    if (!$ids) { Write-Log 'No features selected.'; return }
    Invoke-Task 'Install features' 'foreach ($f in $ids) { Log "  enabling $f"; try { Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null } catch { Log "  ERROR: $_" } }; Log "  restart Windows to finish."' @{ ids = $ids }
})

# ---- Updates (Disable có hộp thoại xác nhận vì ảnh hưởng bảo mật)
$ui.UpdDefault.Add_Click({ Invoke-Task 'Updates: default' $UpdateCode.Default })
$ui.UpdSecurity.Add_Click({ Invoke-Task 'Updates: security' $UpdateCode.Security })
$ui.UpdDisable.Add_Click({
    if ([Windows.MessageBox]::Show('Disable Windows Update completely? Your PC will stop getting security patches.', 'WinUtil', 'YesNo', 'Warning') -eq 'Yes') {
        Invoke-Task 'Updates: disable' $UpdateCode.Disable
    }
})
$ui.BtnClearLog.Add_Click({ $ui.Log.Clear() })

# ----------------------------------------------------------------------------
#  9. Vòng lặp UI (150ms): đổ log, đồng hồ, trạng thái
# ----------------------------------------------------------------------------
# Khi Busy đổi: trỏ nền bar/badge sang token khác bằng SetResourceReference
# (không gán brush cứng), nên đổi theme giữa chừng vẫn đúng màu.
# Trạng thái trong AppState (chữ ASCII từ luồng nền) -> nhãn hiển thị, thêm dấu ✓ / ✗
$Tick = [string][char]0x2713; $Cross = [string][char]0x2717
function Format-AppState([string]$s) {
    switch ($s) {
        'done'          { "$Tick done" }
        'up to date'    { "$Tick latest" }
        'done (reboot)' { "$Tick reboot" }
        'failed'        { "$Cross failed" }
        default         { $s }
    }
}

# Đồng bộ nhãn cạnh từng app với $sync.AppState.
# PHẢI dùng .GetEnumerator(): `foreach ($x in <dictionary>)` của PowerShell coi cả dictionary
# là MỘT phần tử, không duyệt từng cặp key/value. ConcurrentDictionary cho phép duyệt an toàn
# trong khi luồng nền đang ghi.
function Update-AppLabels {
    foreach ($kv in $sync.AppState.GetEnumerator()) {
        $lbl = $AppLabels[$kv.Key]
        if ($lbl) { $t = Format-AppState $kv.Value; if ($lbl.Text -ne $t) { $lbl.Text = $t } }
    }
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $m = $null; $any = $false
    while ($sync.Q.TryDequeue([ref]$m)) { $ui.Log.AppendText("$m`r`n"); $any = $true }
    if ($any) { $ui.Log.ScrollToEnd() }

    $ui.Clock.Text = (Get-Date).ToString('dddd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    $ui.StTheme.Text = $Themes[$sync.Theme]

    if ($sync.Busy -ne $sync.LastBusy) {
        $sync.LastBusy = $sync.Busy
        $k = if ($sync.Busy) { 'Busy' } else { '' }
        $ui.StatusBar.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, "Status${k}Bg")
        $ui.StatusBadge.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, "Badge${k}Bg")
    }

    # Tiến trình cài/gỡ app: panel PROGRESS + nhãn cạnh từng app + thanh trạng thái
    $p = $sync.Prog
    $batch = $p.Active -and $p.Phase -ne 'finished'
    $ui.StatusText.Text = if (-not $sync.Busy) { 'READY' }
                          elseif ($batch) { "RUNNING: $($p.Name) [$($p.Index)/$($p.Total)] $($p.Pct)%" }
                          else { "RUNNING: $($sync.Task)" }
    if ($p.Active) {
        $ui.ProgPanel.Visibility = 'Visible'
        $ui.ProgApp.Text   = $p.Name
        $ui.ProgPhase.Text = if ($p.Detail) { "$($p.Phase)`n$($p.Detail)" } else { $p.Phase }
        $ui.ProgBar.Value  = $p.Pct
        $ui.ProgCount.Text = "$($p.Index) / $($p.Total)   $($p.Pct)%"
    }
    Update-AppLabels
})
$win.Add_Closed({ $timer.Stop() })

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$ui.StWinget.Text = if ($hasWinget) { 'winget: ok' } else { 'winget: missing' }
$ui.StPs.Text = "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
Show-Page 'Install'
Write-Log "WinUtil ready. Theme: $($Themes[$sync.Theme]) (Ctrl+T to switch). Font: $($win.FontFamily.Source). winget: $hasWinget"
$timer.Start()

# ----------------------------------------------------------------------------
#  10. Tự kiểm tra (WINUTIL_TEST=1) hoặc hiện cửa sổ
# ----------------------------------------------------------------------------
if ($IsTest) {
    if ($ui.Values -contains $null) { throw 'Some named elements were not found' }
    Set-Preset 'std'
    if (@($sync.TweakBoxes | Where-Object IsChecked).Count -lt 5) { throw 'Preset failed' }
    # .Keys chỉ gồm key của chính Window.Resources (.Contains thì tìm cả MergedDictionaries)
    $ownKeys = @($win.Resources.Keys)
    $clash = @($ThemeKeys | Where-Object { $ownKeys -contains $_ })
    if ($clash) { throw "Theme tokens clash with Window.Resources keys: $($clash -join ', ')" }
    # Mọi theme phải nạp được, đủ token, và áp dụng được lên cửa sổ
    foreach ($n in $Themes.Keys) {
        Set-Theme $n
        $bg = $win.FindResource('Bg').Color
        $vis = $win.FindResource('WaybarVis')
        "theme ok: $n (Bg=$bg, Waybar=$vis)"
    }
    # Hợp đồng token phải từ chối theme thiếu key: giả lập một theme rỗng
    $ThemeCache.Remove('omarchy-white')
    $origGet = ${function:Get-ThemeXaml}
    ${function:Get-ThemeXaml} = { '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"/>' }
    try { Get-Theme 'omarchy-white' | Out-Null; throw 'contract check did not reject an empty theme' }
    catch { if ("$_" -notlike '*missing keys*') { throw } ; 'contract ok: empty theme rejected' }
    ${function:Get-ThemeXaml} = $origGet

    # Bộ phân tích output winget: nạp $Prelude vào phiên hiện tại rồi đưa vào các dòng mẫu.
    # App 1/2, tải 12/48 MB = 25% -> trọng số 10 + 0.6*25 = 25 -> tổng (0*100 + 25)/2 = 12%
    . ([scriptblock]::Create($Prelude))
    $sync.Prog.Total = 2; $sync.Prog.Index = 1
    Read-WingetLine ("  " + [string][char]0x2588 * 8 + "  12.0 MB / 48.0 MB") 'Test.App'
    if ($sync.AppState['Test.App'] -ne '25%' -or $sync.Prog.Pct -ne 12 -or $sync.Prog.Detail -ne '12.0 MB / 48.0 MB') {
        throw "download parse failed: state=$($sync.AppState['Test.App']) pct=$($sync.Prog.Pct) detail=$($sync.Prog.Detail)"
    }
    Read-WingetLine 'Successfully verified installer hash' 'Test.App'
    if ($sync.AppState['Test.App'] -ne 'verifying') { throw 'phase parse failed' }
    Read-WingetLine ([string][char]0x2588 * 5 + '  |') 'Test.App'   # spinner: phải bị bỏ qua
    if ($sync.AppState['Test.App'] -ne 'verifying') { throw 'spinner line changed state' }
    if ((Format-AppState 'failed') -ne "$Cross failed") { throw 'label format failed' }
    # Nhãn cạnh app phải được cập nhật từ AppState
    $sync.AppState['Google.Chrome'] = 'done'; $sync.AppState['Brave.Brave'] = '45%'
    Update-AppLabels
    if ($AppLabels['Google.Chrome'].Text -ne "$Tick done" -or $AppLabels['Brave.Brave'].Text -ne '45%') {
        throw "app labels not updated: '$($AppLabels['Google.Chrome'].Text)' '$($AppLabels['Brave.Brave'].Text)'"
    }
    'parser ok: download %, phases, spinner filter, app labels'
    "OK: $($sync.AppBoxes.Count) apps, $($sync.TweakBoxes.Count) tweaks, font=$($win.FontFamily.Source)"
    return
}
[void]$win.ShowDialog()
