param(
    [switch]$RecordOnly,
    [switch]$InspectOnly,
    [switch]$NoOpen,
    [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
$artRoot = $PSScriptRoot
$artCatalogPath = Join-Path $artRoot 'data\artworks.json'
$artStateRoot = Join-Path $artRoot 'local-state'
$artJbsRoot = Join-Path $env:APPDATA 'johnsadventures.com\Background Switcher'
$artJbsCache = Join-Path $env:LOCALAPPDATA 'johnsadventures.com\Background Switcher\Current\0.bmp'
$artWindowsCache = Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
$artEncoding = New-Object Text.UTF8Encoding($false)

function Read-ArtJson([string]$Path) {
    return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Resolve-ArtCatalogPath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -notmatch '^images[\\/]') {
        throw "图片必须使用 images/ 开头的相对路径：$RelativePath"
    }
    $imageRoot = [IO.Path]::GetFullPath((Join-Path $artRoot 'images')) + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath((Join-Path $artRoot $RelativePath))
    if (-not $resolved.StartsWith($imageRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "图片路径超出了 images 文件夹：$RelativePath"
    }
    return $resolved
}

function Read-ArtCatalog([switch]$VerifyImages) {
    $records = @(Read-ArtJson $artCatalogPath)
    if ($records.Count -eq 0) { throw '画库为空，请重新解压完整发行包。' }
    $ids = @{}
    $paths = @{}
    foreach ($record in $records) {
        $id = [string]$record.id
        if ([string]::IsNullOrWhiteSpace($id) -or $ids.ContainsKey($id)) { throw "画库作品编号为空或重复：$id" }
        $ids[$id] = $true
        if ([string]$record.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "作品缺少有效的图片校验值：$id" }
        $path = Resolve-ArtCatalogPath ([string]$record.file)
        if ($paths.ContainsKey($path)) { throw "画库图片路径重复：$($record.file)" }
        $paths[$path] = $true
        if ($VerifyImages) {
            if (-not [IO.File]::Exists($path)) { throw "缺少图片，请先取得完整图片包：$($record.file)" }
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $record.sha256) {
                throw "图片校验失败，请重新取得该图片：$($record.file)"
            }
        }
        # Resolve only in memory: the distributable catalogue always keeps relative paths.
        $record.file = $path
    }
    return ,$records
}

function Get-ArtEdge {
    $candidates = @()
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
        if ($base) { $candidates += Join-Path $base 'Microsoft\Edge\Application\msedge.exe' }
    }
    foreach ($candidate in $candidates) { if ([IO.File]::Exists($candidate)) { return $candidate } }
    $command = Get-Command msedge.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw '没有找到 Microsoft Edge。请安装 Edge 后再打开画库。'
}

function Write-ArtAtomic([string]$Path, [string]$Text) {
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $Text, $artEncoding)
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temporary, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Get-ArtImageSample([string]$Path, [double]$CropToAspect = 0) {
    Add-Type -AssemblyName System.Drawing
    $inputImage = $null
    $sample = $null
    $graphics = $null
    try {
        $inputImage = [Drawing.Image]::FromFile($Path)
        $sample = New-Object Drawing.Bitmap(24, 24)
        $graphics = [Drawing.Graphics]::FromImage($sample)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        if ($CropToAspect -gt 0) {
            # JBS scaleblur places the complete artwork in a centred contain rectangle.
            # Sample that painting rectangle, excluding the blurred side/top background.
            $cropWidth = [double]$inputImage.Width
            $cropHeight = $cropWidth / $CropToAspect
            if ($cropHeight -gt $inputImage.Height) {
                $cropHeight = [double]$inputImage.Height
                $cropWidth = $cropHeight * $CropToAspect
            }
            $cropX = ($inputImage.Width - $cropWidth) / 2
            $cropY = ($inputImage.Height - $cropHeight) / 2
            $dest = New-Object Drawing.Rectangle(0, 0, 24, 24)
            $graphics.DrawImage($inputImage, $dest, [single]$cropX, [single]$cropY, [single]$cropWidth, [single]$cropHeight, [Drawing.GraphicsUnit]::Pixel)
        } else {
            $graphics.DrawImage($inputImage, 0, 0, 24, 24)
        }
        $values = New-Object 'System.Collections.Generic.List[double]'
        for ($y = 0; $y -lt 24; $y++) {
            for ($x = 0; $x -lt 24; $x++) {
                $pixel = $sample.GetPixel($x, $y)
                $values.Add($pixel.R); $values.Add($pixel.G); $values.Add($pixel.B)
            }
        }
        return [pscustomobject]@{Width=$inputImage.Width; Height=$inputImage.Height; Values=$values.ToArray()}
    } finally {
        if ($graphics) { $graphics.Dispose() }
        if ($sample) { $sample.Dispose() }
        if ($inputImage) { $inputImage.Dispose() }
    }
}

function Test-ArtImagePair([string]$First, [string]$Second, [double]$Tolerance = 3) {
    if (-not [IO.File]::Exists($First) -or -not [IO.File]::Exists($Second)) { return $false }
    $a = Get-ArtImageSample $First
    $b = Get-ArtImageSample $Second
    if ($a.Width -ne $b.Width -or $a.Height -ne $b.Height) { return $false }
    $difference = 0.0
    for ($i=0; $i -lt $a.Values.Count; $i++) { $difference += [Math]::Abs($a.Values[$i] - $b.Values[$i]) }
    return (($difference / $a.Values.Count) -le $Tolerance)
}

function Test-ArtRenderedSource([string]$Source, [string]$Rendered, [double]$Tolerance = 5) {
    $sourceSample = Get-ArtImageSample $Source
    $renderedSample = Get-ArtImageSample $Rendered ($sourceSample.Width / [double]$sourceSample.Height)
    $difference = 0.0
    for ($i=0; $i -lt $sourceSample.Values.Count; $i++) {
        $difference += [Math]::Abs($sourceSample.Values[$i] - $renderedSample.Values[$i])
    }
    return (($difference / $sourceSample.Values.Count) -le $Tolerance)
}

function New-ArtUnknown([string]$Message, [string]$Path = '') {
    return [pscustomobject]@{status='unknown'; id=$null; message=$Message; wallpaperPath=$Path; checkedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')}
}

function Resolve-Artwork([string]$WallpaperPath, [object[]]$Catalog) {
    if ([string]::IsNullOrWhiteSpace($WallpaperPath)) { return New-ArtUnknown 'Windows 尚未提供当前壁纸路径。画库仍可正常浏览。' }
    $actualPath = [IO.Path]::GetFullPath($WallpaperPath)
    $entry = @($Catalog | Where-Object { $_.file -ieq $actualPath })
    if ($entry.Count -eq 1) {
        if (-not [IO.File]::Exists($actualPath)) { return New-ArtUnknown '当前壁纸的原文件已找不到。请从画库查看已保存的作品。' $actualPath }
        if ((Get-FileHash -LiteralPath $actualPath -Algorithm SHA256).Hash -ine $entry[0].sha256) {
            return New-ArtUnknown '这张图片文件已经变化，需要重新核实图片与资料的对应关系。' $actualPath
        }
        return [pscustomobject]@{status='matched'; id=$entry[0].id; message='已按 Windows 当前壁纸文件核对。'; wallpaperPath=$actualPath; checkedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')}
    }
    $activePath = Join-Path $artJbsRoot 'ActiveBackground.jpg'
    if ($actualPath -ine $activePath) {
        return New-ArtUnknown 'Windows 当前使用的图片不在已核对画库中，可能由其他程序或手动设置。为避免介绍错配，本页暂不指定当前作品；你仍可浏览画库和最近看过的画。' $actualPath
    }
    $statusPath = Join-Path $artJbsRoot 'Status.xml'
    if (-not [IO.File]::Exists($statusPath)) { return New-ArtUnknown '换画程序尚未保存作品记录。稍后重新打开介绍即可。' $actualPath }
    $statusBefore = [IO.File]::ReadAllText($statusPath)
    [xml]$status = $statusBefore
    $pictures = @($status.backgroundswitchersettings.current_pictures.BackgroundSwitcherSettingsPicture)
    if ($pictures.Count -ne 1) { return New-ArtUnknown '当前存在多张壁纸记录，暂时无法唯一确认作品。' $actualPath }
    $sourcePath = [string]$pictures[0].Identifier
    $entry = @($Catalog | Where-Object { $_.file -ieq $sourcePath })
    if ($entry.Count -ne 1) { return New-ArtUnknown '当前作品尚未加入资料库，先显示画库，避免匹配到其他作品。' $actualPath }
    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ine $entry[0].sha256) {
        return New-ArtUnknown '当前作品文件已经变化，需要重新核实资料。' $actualPath
    }
    if (-not (Test-ArtImagePair $sourcePath $artJbsCache 3)) {
        return New-ArtUnknown '正在换画，图片缓存和作品记录尚未同步。稍后重新打开介绍即可。' $actualPath
    }
    if (-not (Test-ArtImagePair $activePath $artWindowsCache 5)) {
        return New-ArtUnknown 'Windows 桌面图片与换画程序的输出尚未一致。稍后重新打开介绍即可。' $actualPath
    }
    if (-not (Test-ArtRenderedSource $sourcePath $activePath 5)) {
        return New-ArtUnknown '桌面画面与记录中的作品未能对应。为避免错配，暂不显示当前作品介绍。' $actualPath
    }
    Start-Sleep -Milliseconds 150
    if ([IO.File]::ReadAllText($statusPath) -cne $statusBefore) { return New-ArtUnknown '检查期间壁纸发生了切换，请重新打开介绍。' $actualPath }
    return [pscustomobject]@{status='matched'; id=$entry[0].id; message='已核对 Windows 壁纸、图片缓存及作品记录。'; wallpaperPath=$actualPath; checkedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); shownAt=[string]$status.backgroundswitchersettings.last_switch}
}

function Get-ArtCurrent([object[]]$Catalog) {
    $resolved = $null
    $maximumAttempts = 6
    if ($RecordOnly) { $maximumAttempts = 24; Start-Sleep -Milliseconds 2000 }
    for ($attempt=0; $attempt -lt $maximumAttempts; $attempt++) {
        try {
            $wallpaper = [string](Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
            $resolved = Resolve-Artwork $wallpaper $Catalog
            $wallpaperAfter = [string](Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
            if ($wallpaper -ine $wallpaperAfter) { $resolved = New-ArtUnknown '检查期间桌面已变化，请重新打开介绍。' }
            if ($resolved.status -eq 'matched') { break }
        } catch {
            $resolved = New-ArtUnknown '暂时无法确认当前画作。可能正在切换壁纸；你仍可查看画库和历史记录。'
            $resolved | Add-Member -NotePropertyName diagnostic -NotePropertyValue $_.Exception.Message
        }
        if ($attempt -lt ($maximumAttempts - 1)) { Start-Sleep -Milliseconds 600 }
    }
    return $resolved
}

function Save-ArtHistory($Current) {
    $path = Join-Path $artStateRoot 'history.json'
    $history = @()
    if ([IO.File]::Exists($path)) { $history = @(Read-ArtJson $path) }
    if ($Current.status -eq 'matched') {
        if ($history.Count -eq 0 -or $history[0].id -ne $Current.id) {
            $shown = $Current.checkedAt
            if ($Current.shownAt) { $shown = $Current.shownAt }
            $new = [pscustomobject]@{id=$Current.id; shownAt=$shown}
            $history = @($new) + @($history | Select-Object -First 199)
            Write-ArtAtomic $path (ConvertTo-Json -InputObject @($history) -Depth 5)
        }
    }
    return ,@($history)
}

function Write-ArtViewer($Current, [object[]]$History) {
    # Large embedded images do not need to be parsed and re-serialized on every open.
    $baseJson = [IO.File]::ReadAllText((Join-Path $artRoot 'gallery-data.json'), [Text.Encoding]::UTF8).Trim()
    if (-not $baseJson.StartsWith('{') -or -not $baseJson.EndsWith('}')) { throw 'Invalid gallery data.' }
    $snapshot = [ordered]@{generatedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');currentId=$Current.id;currentStatus=$Current.status;currentMessage=$Current.message;history=@($History)}
    $headerJson = ConvertTo-Json -InputObject $snapshot -Depth 8 -Compress
    $json = $headerJson.Substring(0,$headerJson.Length-1) + ',' + $baseJson.Substring(1)
    # JSON appears inside a script block. Escape HTML metacharacters to prevent catalogue text closing it.
    $json = $json.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
    $template = [IO.File]::ReadAllText((Join-Path $artRoot 'app-template.html'), [Text.Encoding]::UTF8)
    if (-not $template.Contains('__ARTDESK_DATA__')) { throw 'The viewer template is missing its data placeholder.' }
    $path = Join-Path $artRoot 'ArtDesk.html'
    Write-ArtAtomic $path $template.Replace('__ARTDESK_DATA__', $json)
    return $path
}

if ($LibraryOnly) { return }
$artHasher = [Security.Cryptography.SHA256]::Create()
try { $artInstance = [BitConverter]::ToString($artHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($artRoot.ToLowerInvariant()))).Replace('-', '').Substring(0, 16) }
finally { $artHasher.Dispose() }
$artMutex = New-Object Threading.Mutex($false, ('Local\ArtDesk-' + $artInstance))
$artHasLock = $false
try {
    $artHasLock = $artMutex.WaitOne(45000)
    if (-not $artHasLock) { throw 'Another artwork update is in progress. Please retry in a moment.' }
    $artCatalog = Read-ArtCatalog
    $artCurrent = Get-ArtCurrent $artCatalog
    if ($InspectOnly) { $artCurrent | ConvertTo-Json -Depth 4; return }
    [void][IO.Directory]::CreateDirectory($artStateRoot)
    $artHistory = Save-ArtHistory $artCurrent
    Write-ArtAtomic (Join-Path $artStateRoot 'current.json') (ConvertTo-Json -InputObject $artCurrent -Depth 4)
    if ($RecordOnly) { return }
    $artViewer = Write-ArtViewer $artCurrent $artHistory
    if (-not $NoOpen) {
        $artEdge = Get-ArtEdge
        # This is the result window the user explicitly requested, rather than a background helper.
        Start-Process -FilePath $artEdge -ArgumentList @('--new-window', '--start-maximized', ('"' + $artViewer + '"'))
    }
} catch {
    $artError = (Get-Date).ToString('s') + ' ' + $_.Exception.Message
    if (-not $InspectOnly) {
        try {
            [void][IO.Directory]::CreateDirectory($artStateRoot)
            Add-Content -LiteralPath (Join-Path $artStateRoot 'errors.log') -Value $artError -Encoding UTF8
        } catch { Write-Warning '无法写入错误记录，请确认程序文件夹可写。' }
    }
    if (-not $RecordOnly) {
        if (-not $NoOpen -and -not $InspectOnly) {
            Add-Type -AssemblyName System.Windows.Forms
            [void][Windows.Forms.MessageBox]::Show('名画介绍暂时未能更新，请稍后重试。错误记录已保存在名画桌面文件夹中。', '名画介绍', 'OK', 'Information')
        }
        throw
    }
} finally {
    if ($artHasLock) { $artMutex.ReleaseMutex() }
    $artMutex.Dispose()
}
