# Themes

Mỗi theme là một file `ResourceDictionary` XAML chỉ chứa **design token**: màu, kích thước, và phần nào hiển thị. Layout nằm trong `winutil.ps1` và chỉ tham chiếu token qua `{DynamicResource <Key>}`. Vì vậy:

- Đổi theme lúc đang chạy (nút ☀ hoặc **Ctrl+T**) không phải dựng lại giao diện.
- Thêm theme mới không phải sửa layout.

## Cách theme được nạp

| Cách chạy | Nguồn theme |
|---|---|
| `.\winutil.ps1` (từ file) | `themes\<tên>.xaml` cạnh script, tiện để sửa và xem ngay |
| `irm ... \| iex` | `https://raw.githubusercontent.com/Dalziel66/winutil/main/themes/<tên>.xaml` |

Luồng xử lý: `Initialize-Theme` → `Get-Theme` (tải, parse, kiểm tra đủ key, cache) → `Set-Theme` (thay `Window.Resources.MergedDictionaries`, lưu lựa chọn vào `%LOCALAPPDATA%\winutil\theme.txt`).

Nếu theme đã lưu bị lỗi (mất mạng, file hỏng), script tự thử các theme còn lại trước khi báo lỗi.

## Thêm một theme mới

1. Copy `omarchy-white.xaml` thành `ten-theme.xaml`, rồi đổi giá trị các token.
2. Thêm `'ten-theme' = 'Tên hiển thị'` vào `$Themes` trong `winutil.ps1`. Đây là whitelist: tên không có trong danh sách sẽ không bao giờ được nạp.
3. Chạy self-check: `$env:WINUTIL_TEST='1'; powershell -STA -File .\winutil.ps1`. Lệnh này kiểm tra mọi theme nạp được, đủ key và không trùng key với layout.
4. Commit và push. Người dùng `irm | iex` sẽ nhận theme mới, có thể chậm vài phút do GitHub cache file raw.

## Hợp đồng token

Thiếu bất kỳ key nào thì theme bị từ chối, kèm thông báo liệt kê đủ các key thiếu. Danh sách nguồn nằm ở `$ThemeKeys` trong `winutil.ps1`.

> ⚠️ Không đặt tên token trùng với key Style trong layout (`Card`, `Comment`, `Desc`, `Head`, `Tile`, `Primary`, `Danger`, `Cap`, `CapClose`, `Act`, `Ws`). WPF tra `Window.Resources` **trước** theme, nên sẽ lấy nhầm Style thay vì Brush. Đó là lý do token màu comment tên là `CommentFg`.

### Màu (`SolidColorBrush`)

| Key | Dùng cho | Omarchy White | VS Code Dark |
|---|---|---|---|
| `Bg` | nền editor, terminal, cửa sổ | `#FFFFFF` | `#1E1E1E` |
| `BgSide` | sidebar | `#FFFFFF` | `#252526` |
| `BgTitle` | thanh tiêu đề / Waybar | `#FFFFFF` | `#3C3C3C` |
| `BgActivity` | activity bar | `#FFFFFF` | `#333333` |
| `BgInput` | ô tìm kiếm | `#FFFFFF` | `#3C3C3C` |
| `BgTabBar` / `BgTabActive` | dải tab / tab đang mở | `#FFFFFF` | `#252526` / `#1E1E1E` |
| `BgCard` | hộp nhóm | `#FFFFFF` | `#252526` |
| `Fg` | chữ chính | `#000000` | `#CCCCCC` |
| `FgMuted` | breadcrumb, hover workspace | `#6E6E6E` | `#A0A0A0` |
| `FgSubtle` | mô tả nhỏ | `#6E6E6E` | `#8B8B8B` |
| `FgStrong` | tên tab, "TERMINAL" | `#000000` | `#FFFFFF` |
| `FgHead` | tiêu đề sidebar | `#000000` | `#BBBBBB` |
| `CommentFg` | `// Browsers` | `#6E6E6E` | `#6A9955` |
| `Border` | viền hộp nhóm, tooltip | `#3A3A3A` | `#2B2B2B` |
| `TileBorderBrush` | viền ô tiling | `#C0C0C0` | `#2B2B2B` |
| `InputBorder` | viền ô nhập | `#3A3A3A` | `#3C3C3C` |
| `WindowBorder` | viền cửa sổ | `#C0C0C0` | `#2B2B2B` |
| `Accent` / `AccentFg` | checkbox đã chọn / dấu tick | `#1A1A1A` / `#FFFFFF` | `#007ACC` / `#FFFFFF` |
| `TabActiveBorder` | gạch trên tab đang mở | `#000000` | `#3794FF` |
| `TitleIconFg` / `TabIconFg` | icon tiêu đề / chữ "PS" | `#000000` | `#3794FF` / `#519ABA` |
| `ActFg` / `ActFgActive` | icon activity bar | `#6E6E6E` / `#000000` | `#858585` / `#FFFFFF` |
| `BtnBg` `BtnFg` `BtnBorder` | nút thường | trắng, chữ đen, viền `#3A3A3A` | `#3A3D41`, chữ trắng |
| `BtnPrimaryBg` `BtnPrimaryFg` | nút chính | `#1A1A1A` / `#FFFFFF` | `#0E639C` / `#FFFFFF` |
| `BtnDangerBg` `BtnDangerFg` | nút nguy hiểm | `#4A4A4A` / `#FFFFFF` | `#A1260D` / `#FFFFFF` |
| `CapFg` `CapHoverBg` | nút tiêu đề | `#000000` / `#E6E6E6` | `#CCCCCC` / `#505050` |
| `CloseHoverBg` `CloseHoverFg` | hover nút đóng | `#1A1A1A` / `#FFFFFF` | `#E81123` / `#FFFFFF` |
| `CheckBg` `CheckBorder` | ô checkbox | `#FFFFFF` / `#3A3A3A` | `#3C3C3C` / `#6B6B6B` |
| `ScrollThumb` | thanh cuộn | `#C0C0C0` | `#66797979` |
| `Selection` | bôi đen chữ | `#1A1A1A` | `#264F78` |
| `ToolTipBg` | tooltip | `#FFFFFF` | `#252526` |
| `StatusBg` / `StatusBusyBg` | nền thanh trạng thái (rảnh / bận) | `#FFFFFF` / `#FFFFFF` | `#007ACC` / `#CC6633` |
| `StatusFg` | chữ thanh trạng thái | `#000000` | `#FFFFFF` |
| `BadgeBg` / `BadgeBusyBg` / `BadgeFg` | khối "READY" | `#1A1A1A` / `#6E6E6E` / `#FFFFFF` | trong suốt / trong suốt / `#FFFFFF` |

### Hình học và hiển thị

| Key | Kiểu | Ý nghĩa | Omarchy White | VS Code Dark |
|---|---|---|---|---|
| `RootPad` | `Thickness` | lề quanh vùng làm việc | `5` | `0` |
| `TileGap` | `Thickness` | margin mỗi ô. Khe giữa 2 ô = 2×TileGap | `5` | `0` |
| `TileBorder` | `Thickness` | viền ô tiling | `2` | `0,0,1,1` |
| `BtnBorderThickness` | `Thickness` | viền nút | `1` | `0` |
| `Radius` | `CornerRadius` | bo góc nút, checkbox | `0` | `2` |
| `CardRadius` | `CornerRadius` | bo góc hộp nhóm | `0` | `4` |
| `ClassicChromeVis` | `Visibility` | activity bar + tiêu đề VS Code | `Collapsed` | `Visible` |
| `WaybarVis` | `Visibility` | workspace 1–4 + đồng hồ | `Visible` | `Collapsed` |

## Nguồn cảm hứng Omarchy White

Bảng màu lấy từ [`themes/white/colors.toml`](https://github.com/basecamp/omarchy/blob/master/themes/white/colors.toml) của Omarchy: `background #ffffff`, `foreground #000000`, `accent #6e6e6e`, thang xám `#1a1a1a → #c0c0c0`. Hình học (khe hở, viền 2px, góc vuông) mô phỏng bố cục Hyprland trong ảnh preview của theme.

## Bảo mật

XAML có thể khởi tạo object .NET tuỳ ý, nên **một file theme tương đương với code**. Script chỉ nạp theme từ cùng nguồn với chính nó (thư mục cạnh script hoặc cùng repo GitHub) và chỉ theo tên có trong whitelist `$Themes`. Đừng thêm cơ chế nạp theme từ URL tuỳ ý.
