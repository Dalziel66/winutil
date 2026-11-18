# WinUtil - Windows utility (VS Code style UI)
# Run:  irm https://raw.githubusercontent.com/Dalziel66/winutil/main/winutil.ps1 | iex
$ScriptUrl = 'https://raw.githubusercontent.com/Dalziel66/winutil/main/winutil.ps1'

$IsTest = $env:WINUTIL_TEST -eq '1'   # self-check: build the window without showing it
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsTest -and (-not $isAdmin -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA')) {
    $arg = if ($PSCommandPath) { "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" }
           else { "-NoProfile -ExecutionPolicy Bypass -STA -Command `"irm '$ScriptUrl' | iex`"" }
    Write-Host 'WinUtil needs administrator rights, relaunching...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arg
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- data
$Apps = [ordered]@{
    'Browsers'      = 'Google Chrome|Google.Chrome', 'Firefox|Mozilla.Firefox', 'Brave|Brave.Brave', 'Opera|Opera.Opera', 'LibreWolf|LibreWolf.LibreWolf'
    'Communication' = 'Discord|Discord.Discord', 'Telegram|Telegram.TelegramDesktop', 'Zoom|Zoom.Zoom', 'Slack|SlackTechnologies.Slack', 'Microsoft Teams|Microsoft.Teams'
    'Development'   = 'VS Code|Microsoft.VisualStudioCode', 'Git|Git.Git', 'GitHub Desktop|GitHub.GitHubDesktop', 'Node.js LTS|OpenJS.NodeJS.LTS', 'Python 3.13|Python.Python.3.13', 'Windows Terminal|Microsoft.WindowsTerminal', 'PowerShell 7|Microsoft.PowerShell', 'Docker Desktop|Docker.DockerDesktop', 'JetBrains Toolbox|JetBrains.Toolbox', 'Postman|Postman.Postman', 'Neovim|Neovim.Neovim'
    'Utilities'     = '7-Zip|7zip.7zip', 'Everything|voidtools.Everything', 'PowerToys|Microsoft.PowerToys', 'Notepad++|Notepad++.Notepad++', 'ShareX|ShareX.ShareX', 'CPU-Z|CPUID.CPU-Z', 'GPU-Z|TechPowerUp.GPU-Z', 'CrystalDiskInfo|CrystalDewWorld.CrystalDiskInfo', 'Rufus|Rufus.Rufus', 'Bitwarden|Bitwarden.Bitwarden', 'UniGetUI|MartiCliment.UniGetUI'
    'Multimedia'    = 'VLC|VideoLAN.VLC', 'OBS Studio|OBSProject.OBSStudio', 'Spotify|Spotify.Spotify', 'Krita|KDE.Krita', 'Audacity|Audacity.Audacity', 'HandBrake|HandBrake.HandBrake'
    'Games'         = 'Steam|Valve.Steam', 'Epic Games|EpicGames.EpicGamesLauncher', 'GOG Galaxy|GOG.Galaxy', 'Ubisoft Connect|Ubisoft.Connect', 'EA App|ElectronicArts.EADesktop'
    'Documents'     = 'LibreOffice|TheDocumentFoundation.LibreOffice', 'Adobe Reader|Adobe.Acrobat.Reader.64-bit', 'SumatraPDF|SumatraPDF.SumatraPDF', 'Obsidian|Obsidian.Obsidian', 'Notion|Notion.Notion'
}

# Reg entries: @(path, name, value, undoValue)  -- undoValue $null = delete the value
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

$Features = 'NET Framework 3.5|NetFx3', 'Hyper-V|Microsoft-Hyper-V-All', 'WSL|Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform', 'Windows Sandbox|Containers-DisposableClientVM'

$Fixes = [ordered]@{
    'Reset network'           = 'Log (netsh winsock reset | Out-String); Log (netsh int ip reset | Out-String); Log (ipconfig /flushdns | Out-String)'
    'System repair (DISM+SFC)' = 'Log "DISM RestoreHealth..."; DISM /Online /Cleanup-Image /RestoreHealth | Out-Null; Log "  exit code: $LASTEXITCODE"; Log "SFC scan..."; sfc /scannow | Out-Null; Log "  exit code: $LASTEXITCODE"'
    'Reset Windows Update'    = '$s = "wuauserv","bits","cryptsvc"; Stop-Service $s -Force -ErrorAction SilentlyContinue; $t = Get-Date -Format yyyyMMddHHmmss; Rename-Item "$env:SystemRoot\SoftwareDistribution" "SoftwareDistribution.bak_$t" -ErrorAction SilentlyContinue; Rename-Item "$env:SystemRoot\System32\catroot2" "catroot2.bak_$t" -ErrorAction SilentlyContinue; Start-Service $s -ErrorAction SilentlyContinue; Log "Windows Update components reset (old folders kept as *.bak_$t)."'
}
$Panels = [ordered]@{ 'Control Panel' = 'control'; 'Network Connections' = 'ncpa.cpl'; 'Power Options' = 'powercfg.cpl'; 'Sound' = 'mmsys.cpl'; 'System Properties' = 'sysdm.cpl'; 'Device Manager' = 'devmgmt.msc'; 'Services' = 'services.msc'; 'Registry Editor' = 'regedit' }

$WU = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$UpdateCode = @{
    Default  = "Remove-Item '$WU' -Recurse -Force -ErrorAction SilentlyContinue; Set-Service wuauserv -StartupType Manual; Log 'Windows Update policies reset to default.'"
    Security = "Set-Reg '$WU' DeferFeatureUpdates 1; Set-Reg '$WU' DeferFeatureUpdatesPeriodInDays 365; Set-Reg '$WU' DeferQualityUpdates 1; Set-Reg '$WU' DeferQualityUpdatesPeriodInDays 4; Set-Reg '$WU\AU' NoAutoRebootWithLoggedOnUsers 1; Set-Service wuauserv -StartupType Manual; Log 'Feature updates delayed 365 days, security updates 4 days.'"
    Disable  = "Set-Reg '$WU\AU' NoAutoUpdate 1; Set-Reg '$WU\AU' AUOptions 1; Stop-Service wuauserv -Force -ErrorAction SilentlyContinue; Set-Service wuauserv -StartupType Disabled; Log 'Windows Update disabled. Remember to re-enable it later.'"
}

# ---------------------------------------------------------------- background tasks
$sync = [hashtable]::Synchronized(@{ Busy = $false; Q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]' })

$Prelude = @'
$ProgressPreference = 'SilentlyContinue'
function Log($m) { $sync.Q.Enqueue(('[{0}] {1}' -f (Get-Date -Format HH:mm:ss), $m)) }
function Set-Reg($Path, $Name, $Value) {
    if ($null -eq $Value) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue; return }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $type = if ($Value -is [string]) { 'String' } else { 'DWord' }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $type -Force
}
function Invoke-Winget([string[]]$WArgs) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget not found. Install "App Installer" from Microsoft Store.' }
    & winget @WArgs 2>&1 | ForEach-Object { $l = "$_".Trim(); if ($l -match '[A-Za-z]{3}') { Log "  $l" } }
    Log "  exit code: $LASTEXITCODE"
}
'@

function Write-Log($m) { $sync.Q.Enqueue(('[{0}] {1}' -f (Get-Date -Format HH:mm:ss), $m)) }

function Invoke-Task([string]$Title, [string]$Code, [hashtable]$Vars = @{}) {
    if ($sync.Busy) { Write-Log 'Another task is still running, please wait.'; return }
    $sync.Busy = $true; $sync.Task = $Title
    # shortcut: runspaces are not disposed after finishing, fine for an interactive tool
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    foreach ($k in $Vars.Keys) { $rs.SessionStateProxy.SetVariable($k, $Vars[$k]) }
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript("$Prelude`nLog '>> $Title'`ntry {`n$Code`n} catch { Log ('ERROR: ' + `$_) } finally { Log '>> done'; `$sync.Busy = `$false }")
    [void]$ps.BeginInvoke()
}

# ---------------------------------------------------------------- font (JetBrains Mono, loaded from %TEMP%, no install)
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

# ---------------------------------------------------------------- UI
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinUtil" Width="1180" Height="760" MinWidth="900" MinHeight="560"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="CanResize"
        Background="#1E1E1E" Foreground="#CCCCCC" FontSize="13" BorderBrush="#2B2B2B" BorderThickness="1">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="30" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#3A3D41"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="2" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.85"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.7"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#0E639C"/>
    </Style>
    <Style x:Key="Cap" TargetType="Button">
      <Setter Property="Width" Value="46"/><Setter Property="Height" Value="30"/>
      <Setter Property="Foreground" Value="#CCCCCC"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/><Setter Property="FontSize" Value="10"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border Background="{TemplateBinding Background}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        </ControlTemplate>
      </Setter.Value></Setter>
      <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#505050"/></Trigger></Style.Triggers>
    </Style>
    <Style x:Key="CapClose" TargetType="Button" BasedOn="{StaticResource Cap}">
      <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#E81123"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger></Style.Triggers>
    </Style>
    <Style x:Key="Act" TargetType="Button">
      <Setter Property="Width" Value="48"/><Setter Property="Height" Value="48"/>
      <Setter Property="Foreground" Value="#858585"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/><Setter Property="FontSize" Value="22"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Grid Background="Transparent">
            <Border x:Name="ind" Width="2" HorizontalAlignment="Left" Background="#FFFFFF" Visibility="Hidden"/>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
            <Trigger Property="Tag" Value="on"><Setter TargetName="ind" Property="Visibility" Value="Visible"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#CCCCCC"/>
      <Setter Property="Margin" Value="0,4,24,4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Border x:Name="box" Width="15" Height="15" CornerRadius="3" BorderThickness="1" BorderBrush="#6B6B6B" Background="#3C3C3C" VerticalAlignment="Center">
              <Path x:Name="tick" Data="M0,5 L3.5,8.5 L10,1" Stroke="#FFFFFF" StrokeThickness="1.8" Stretch="Uniform" Margin="2.5" Visibility="Collapsed"/>
            </Border>
            <ContentPresenter Margin="9,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="#007ACC"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
              <Setter TargetName="box" Property="Background" Value="#007ACC"/>
              <Setter TargetName="box" Property="BorderBrush" Value="#007ACC"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#3C3C3C"/><Setter Property="Foreground" Value="#CCCCCC"/>
      <Setter Property="BorderBrush" Value="#3C3C3C"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,5"/><Setter Property="CaretBrush" Value="#FFFFFF"/>
      <Setter Property="SelectionBrush" Value="#264F78"/>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="#252526"/><Setter Property="Foreground" Value="#CCCCCC"/><Setter Property="BorderBrush" Value="#454545"/>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/><Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Track x:Name="PART_Track" IsDirectionReversed="True" Orientation="{TemplateBinding Orientation}">
            <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="#66797979"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
          </Track>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#252526"/><Setter Property="BorderBrush" Value="#2B2B2B"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="4"/><Setter Property="Padding" Value="14,12"/><Setter Property="Margin" Value="0,0,12,12"/><Setter Property="Width" Value="250"/>
    </Style>
    <Style x:Key="Comment" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#6A9955"/><Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style x:Key="Desc" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#8B8B8B"/><Setter Property="FontSize" Value="11.5"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="Margin" Value="24,0,0,10"/>
    </Style>
    <Style x:Key="Head" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#BBBBBB"/><Setter Property="FontSize" Value="11"/><Setter Property="Margin" Value="0,0,0,14"/>
    </Style>
  </Window.Resources>

  <Grid Name="Root">
    <Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/><RowDefinition Height="22"/></Grid.RowDefinitions>

    <!-- title bar -->
    <Grid Grid.Row="0" Background="#3C3C3C">
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0">
        <TextBlock Text="&#xE756;" FontFamily="Segoe MDL2 Assets" Foreground="#3794FF" FontSize="14" VerticalAlignment="Center"/>
        <TextBlock Text="WinUtil" Margin="10,0,0,0" FontSize="12" VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock Name="TitleText" HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="12"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnMin" Style="{StaticResource Cap}" Content="&#xE921;"/>
        <Button Name="BtnMax" Style="{StaticResource Cap}" Content="&#xE922;"/>
        <Button Name="BtnClose" Style="{StaticResource CapClose}" Content="&#xE8BB;"/>
      </StackPanel>
    </Grid>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="48"/><ColumnDefinition Width="240"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

      <!-- activity bar -->
      <Border Grid.Column="0" Background="#333333">
        <StackPanel>
          <Button Name="ActInstall" Style="{StaticResource Act}" Content="&#xE896;" ToolTip="Install"/>
          <Button Name="ActTweaks" Style="{StaticResource Act}" Content="&#xE90F;" ToolTip="Tweaks"/>
          <Button Name="ActConfig" Style="{StaticResource Act}" Content="&#xE713;" ToolTip="Config"/>
          <Button Name="ActUpdates" Style="{StaticResource Act}" Content="&#xE895;" ToolTip="Updates"/>
        </StackPanel>
      </Border>

      <!-- side bar -->
      <Border Grid.Column="1" Background="#252526" BorderBrush="#2B2B2B" BorderThickness="0,0,1,0">
        <Grid>
          <StackPanel Name="SideInstall" Margin="16,12,8,12">
            <TextBlock Style="{StaticResource Head}" Text="INSTALL"/>
            <TextBlock Text="Search" FontSize="11" Foreground="#8B8B8B" Margin="0,0,0,4"/>
            <TextBox Name="Search" Margin="0,0,8,14"/>
            <Button Name="BtnInstall" Style="{StaticResource Primary}" Content="Install selected"/>
            <Button Name="BtnUninstall" Content="Uninstall selected"/>
            <Button Name="BtnUpgrade" Content="Upgrade all apps"/>
            <Button Name="BtnClearApps" Content="Clear selection"/>
            <TextBlock Name="SelCount" Text="0 selected" Foreground="#8B8B8B" FontSize="11" Margin="0,8,0,0"/>
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

      <!-- editor area -->
      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="35"/><RowDefinition Height="24"/><RowDefinition Height="*"/><RowDefinition Height="5"/><RowDefinition Height="200" MinHeight="60"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#252526">
          <Border HorizontalAlignment="Left" Background="#1E1E1E" BorderBrush="#3794FF" BorderThickness="0,1,0,0" Padding="14,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="PS" Foreground="#519ABA" FontWeight="Bold" FontSize="11" Margin="0,0,8,0" VerticalAlignment="Center"/>
              <TextBlock Name="TabTitle" Foreground="#FFFFFF" VerticalAlignment="Center"/>
              <TextBlock Text="&#xE8BB;" FontFamily="Segoe MDL2 Assets" FontSize="9" Margin="16,0,0,0" Foreground="#8B8B8B" VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
        </Border>
        <TextBlock Grid.Row="1" Name="Crumb" Margin="16,0" VerticalAlignment="Center" Foreground="#A0A0A0" FontSize="12"/>

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
                <Button Name="UpdDisable" Content="Disable updates" Background="#A1260D" HorizontalAlignment="Left" Margin="0,14,0,0"/>
              </StackPanel></Border>
            </WrapPanel>
          </ScrollViewer>
        </Grid>

        <GridSplitter Grid.Row="3" HorizontalAlignment="Stretch" Background="Transparent" ResizeDirection="Rows"/>

        <!-- terminal panel -->
        <Border Grid.Row="4" BorderBrush="#2B2B2B" BorderThickness="0,1,0,0">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="32"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Border BorderBrush="#E7E7E7" BorderThickness="0,0,0,1" HorizontalAlignment="Left" Margin="16,0,0,0" VerticalAlignment="Center" Padding="0,0,0,3">
              <TextBlock Text="TERMINAL" FontSize="11" Foreground="#E7E7E7"/>
            </Border>
            <Button Name="BtnClearLog" Style="{StaticResource Cap}" Content="&#xE74D;" ToolTip="Clear" HorizontalAlignment="Right" Width="32" FontSize="12"/>
            <TextBox Grid.Row="1" Name="Log" IsReadOnly="True" Background="#1E1E1E" BorderThickness="0" Padding="12,0"
                     TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Foreground="#CCCCCC" FontSize="12"/>
          </Grid>
        </Border>
      </Grid>
    </Grid>

    <!-- status bar -->
    <Border Grid.Row="2" Name="StatusBar" Background="#007ACC">
      <Border.Resources>
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#FFFFFF"/><Setter Property="FontSize" Value="12"/><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Margin" Value="10,0"/></Style>
      </Border.Resources>
      <DockPanel>
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
          <TextBlock Name="StWinget"/>
          <TextBlock Name="StPs"/>
          <TextBlock Text="Administrator"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="&#xE756;" FontFamily="Segoe MDL2 Assets" Margin="10,0,0,0"/>
          <TextBlock Name="StatusText" Text="Ready"/>
        </StackPanel>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@Name]') | ForEach-Object { $ui[$_.Name] = $win.FindName($_.Name) }
$win.FontFamily = Get-UiFont
$sep = ' ' + [char]0x203A + ' '

function New-Ui($type, $style) { $e = New-Object "Windows.Controls.$type"; if ($style) { $e.Style = $win.FindResource($style) }; $e }

# Install page: one card per category
$sync.AppBoxes = New-Object Collections.ArrayList
foreach ($cat in $Apps.Keys) {
    $card = New-Ui Border 'Card'; $sp = New-Object Windows.Controls.StackPanel; $card.Child = $sp
    $h = New-Ui TextBlock 'Comment'; $h.Text = "// $cat"; [void]$sp.Children.Add($h)
    foreach ($a in $Apps[$cat]) {
        $name, $id = $a -split '\|'
        $cb = New-Object Windows.Controls.CheckBox; $cb.Content = $name; $cb.Tag = $id; $cb.ToolTip = $id
        $cb.Add_Click({ $ui.SelCount.Text = "$(@($sync.AppBoxes | Where-Object IsChecked).Count) selected" })
        [void]$sp.Children.Add($cb); [void]$sync.AppBoxes.Add($cb)
    }
    [void]$ui.AppPanel.Children.Add($card)
}

# Tweaks page: one card per group
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

# Config page
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

# ---------------------------------------------------------------- events
$Pages = 'Install', 'Tweaks', 'Config', 'Updates'
function Show-Page($p) {
    foreach ($x in $Pages) {
        $v = if ($x -eq $p) { 'Visible' } else { 'Collapsed' }
        $ui["Page$x"].Visibility = $v; $ui["Side$x"].Visibility = $v
        $ui["Act$x"].Tag = if ($x -eq $p) { 'on' } else { '' }
    }
    $ui.TabTitle.Text = "$($p.ToLower()).ps1"
    $ui.Crumb.Text = "winutil$sep$($p.ToLower()).ps1"
    $ui.TitleText.Text = "$($p.ToLower()).ps1 - WinUtil"
}
foreach ($x in $Pages) { $ui["Act$x"].Add_Click({ Show-Page $this.Name.Substring(3) }) }

$ui.BtnMin.Add_Click({ $win.WindowState = 'Minimized' })
$ui.BtnMax.Add_Click({ $win.WindowState = if ($win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } })
$ui.BtnClose.Add_Click({ $win.Close() })
$win.Add_StateChanged({
    $max = $win.WindowState -eq 'Maximized'
    $ui.Root.Margin = if ($max) { 7 } else { 0 }   # WindowChrome overflows the screen by ~7px when maximized
    $ui.BtnMax.Content = if ($max) { [string][char]0xE923 } else { [string][char]0xE922 }
})

$ui.Search.Add_TextChanged({
    $q = $ui.Search.Text.Trim()
    foreach ($cb in $sync.AppBoxes) { $cb.Visibility = if (!$q -or $cb.Content -like "*$q*" -or $cb.Tag -like "*$q*") { 'Visible' } else { 'Collapsed' } }
})

$WingetArgs = '"-e","--silent","--accept-source-agreements"'
$ui.BtnInstall.Add_Click({
    $ids = @($sync.AppBoxes | Where-Object IsChecked | ForEach-Object Tag)
    if (!$ids) { Write-Log 'No apps selected.'; return }
    Invoke-Task 'Install apps' "foreach (`$id in `$ids) { Log `"Installing `$id`"; Invoke-Winget @('install','--id',`$id,$WingetArgs,'--accept-package-agreements') }" @{ ids = $ids }
})
$ui.BtnUninstall.Add_Click({
    $ids = @($sync.AppBoxes | Where-Object IsChecked | ForEach-Object Tag)
    if (!$ids) { Write-Log 'No apps selected.'; return }
    Invoke-Task 'Uninstall apps' "foreach (`$id in `$ids) { Log `"Uninstalling `$id`"; Invoke-Winget @('uninstall','--id',`$id,$WingetArgs) }" @{ ids = $ids }
})
$ui.BtnUpgrade.Add_Click({ Invoke-Task 'Upgrade all apps' "Invoke-Winget @('upgrade','--all','--silent','--accept-source-agreements','--accept-package-agreements')" })
$ui.BtnClearApps.Add_Click({ $sync.AppBoxes | ForEach-Object { $_.IsChecked = $false }; $ui.SelCount.Text = '0 selected' })

function Set-Preset($p) { foreach ($cb in $sync.TweakBoxes) { $cb.IsChecked = ($cb.Tag.Preset -split ',') -contains $p } }
$ui.PresetStd.Add_Click({ Set-Preset 'std' })
$ui.PresetMin.Add_Click({ Set-Preset 'min' })
$ui.PresetClear.Add_Click({ Set-Preset '-' })

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

$ui.BtnFeatures.Add_Click({
    $ids = @($sync.FeatureBoxes | Where-Object IsChecked | ForEach-Object { $_.Tag -split ',' })
    if (!$ids) { Write-Log 'No features selected.'; return }
    Invoke-Task 'Install features' 'foreach ($f in $ids) { Log "  enabling $f"; try { Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null } catch { Log "  ERROR: $_" } }; Log "  restart Windows to finish."' @{ ids = $ids }
})

$ui.UpdDefault.Add_Click({ Invoke-Task 'Updates: default' $UpdateCode.Default })
$ui.UpdSecurity.Add_Click({ Invoke-Task 'Updates: security' $UpdateCode.Security })
$ui.UpdDisable.Add_Click({
    if ([Windows.MessageBox]::Show('Disable Windows Update completely? Your PC will stop getting security patches.', 'WinUtil', 'YesNo', 'Warning') -eq 'Yes') {
        Invoke-Task 'Updates: disable' $UpdateCode.Disable
    }
})
$ui.BtnClearLog.Add_Click({ $ui.Log.Clear() })

# drain the log queue + status bar on the UI thread
$bc = New-Object Windows.Media.BrushConverter
$blue = $bc.ConvertFromString('#007ACC'); $orange = $bc.ConvertFromString('#CC6633')
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $m = $null; $any = $false
    while ($sync.Q.TryDequeue([ref]$m)) { $ui.Log.AppendText("$m`r`n"); $any = $true }
    if ($any) { $ui.Log.ScrollToEnd() }
    if ($sync.Busy) { $ui.StatusText.Text = "Running: $($sync.Task)..."; $ui.StatusBar.Background = $orange }
    else { $ui.StatusText.Text = 'Ready'; $ui.StatusBar.Background = $blue }
})
$win.Add_Closed({ $timer.Stop() })

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$ui.StWinget.Text = if ($hasWinget) { 'winget: ok' } else { 'winget: missing' }
$ui.StPs.Text = "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
Show-Page 'Install'
Write-Log "WinUtil ready. Font: $($win.FontFamily.Source). winget: $hasWinget"
$timer.Start()

if ($IsTest) {
    if ($ui.Values -contains $null) { throw 'Some named elements were not found' }
    Set-Preset 'std'
    if (@($sync.TweakBoxes | Where-Object IsChecked).Count -lt 5) { throw 'Preset failed' }
    "OK: $($sync.AppBoxes.Count) apps, $($sync.TweakBoxes.Count) tweaks, font=$($win.FontFamily.Source)"
    return
}
[void]$win.ShowDialog()
