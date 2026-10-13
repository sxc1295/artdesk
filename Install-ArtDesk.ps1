param(
    [switch]$SkipRestart,
    [switch]$ValidateOnly,
    [string]$JbsExecutable
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ArtDesk.ps1') -LibraryOnly
$installRoot = $PSScriptRoot
$installStateRoot = Join-Path $installRoot 'local-state'
$installManifest = Join-Path $installStateRoot 'installation.json'
$installSettings = Join-Path $env:APPDATA 'johnsadventures.com\Background Switcher\Settings.xml'
$installDesktop = [Environment]::GetFolderPath('Desktop')
$installShortcut = Join-Path $installDesktop 'ArtDesk 名画介绍.lnk'
$installHost = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$installArguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $installRoot 'ArtDesk.ps1') + '"'

function Find-InstallJbs([string]$Requested) {
    if ($Requested) {
        if (-not [IO.File]::Exists($Requested)) { throw "找不到指定的 JBS 程序：$Requested" }
        return [IO.Path]::GetFullPath($Requested)
    }
    $locations = @()
    if ($env:LOCALAPPDATA) { $locations += Join-Path $env:LOCALAPPDATA "Programs\John's Background Switcher\BackgroundSwitcher.exe" }
    foreach ($folder in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($folder) { $locations += Join-Path $folder "John's Background Switcher\BackgroundSwitcher.exe" }
    }
    foreach ($path in $locations) { if ([IO.File]::Exists($path)) { return $path } }
    throw "未找到 John's Background Switcher。请先从官网 https://johnsad.ventures/software/backgroundswitcher/ 安装并运行一次；自定义安装位置可使用 -JbsExecutable 指定。"
}

function Read-InstallSettings {
    if (-not [IO.File]::Exists($installSettings)) {
        throw "没有找到 JBS 的 Settings.xml。请先运行 JBS，打开设置并保存一次，再安装名画桌面。预期位置：$installSettings"
    }
    $document = New-Object Xml.XmlDocument
    $document.XmlResolver = $null
    try { $document.Load($installSettings) } catch { throw "无法读取 JBS 配置，未作更改：$($_.Exception.Message)" }
    if ($document.DocumentElement.LocalName -ne 'backgroundswitchersettings' -or $document.DocumentElement.NamespaceURI) {
        throw 'JBS 配置格式不兼容，未作更改。请使用官网 Windows 版本，并先打开设置保存一次。'
    }
    foreach ($name in @('schema','watch_folders','run_command_after_switching','application_to_run_after_switching','arguments_for_run_after_switching','switching_interval','switch_on_startup','refresh_background_on_application_startup','display_mode','watch_traverse_subdirectories')) {
        if ($document.DocumentElement.SelectNodes($name).Count -ne 1) { throw "JBS 配置缺少或重复必要字段 $name，无法安全配置，未作更改。" }
    }
    if ($document.DocumentElement.SelectSingleNode('schema').InnerText -notmatch '^\d+$') {
        throw 'JBS 配置版本无法识别，未作更改。'
    }
    return ,$document
}

function Set-InstallOptions([xml]$Document) {
    $options = [ordered]@{
        run_command_after_switching = 'true'
        application_to_run_after_switching = $installHost
        arguments_for_run_after_switching = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $installRoot 'Queue-ArtDesk.ps1') + '"')
        switching_interval = 'Hours4'
        switch_on_startup = 'true'
        refresh_background_on_application_startup = 'true'
        display_mode = 'scaleblur'
        watch_traverse_subdirectories = 'true'
    }
    foreach ($option in $options.GetEnumerator()) {
        $Document.DocumentElement.SelectSingleNode([string]$option.Key).InnerText = [string]$option.Value
    }
    # Preserve run_on_startup, scheduled tasks, and any non-folder sources.
    $folders = $Document.DocumentElement.SelectSingleNode('watch_folders')
    $folders.RemoveAll()
    $node = $Document.CreateElement('folder')
    $node.SetAttribute('enabled', 'true')
    $node.InnerText = Join-Path $installRoot 'images'
    [void]$folders.AppendChild($node)
}

foreach ($name in @('ArtDesk.ps1','Queue-ArtDesk.ps1','Uninstall-ArtDesk.ps1','data\artworks.json','gallery-data.json','app-template.html')) {
    if (-not [IO.File]::Exists((Join-Path $installRoot $name))) { throw "缺少发行包文件：$name。请完整解压后重试。" }
}
if (-not $installDesktop -or -not [IO.Directory]::Exists($installDesktop)) { throw '无法找到当前用户桌面文件夹，未作更改。' }
if ([IO.File]::Exists($installManifest)) {
    $previous = Read-ArtJson $installManifest
    if ($previous.status -eq 'installed') { throw '该目录已有安装记录。请先运行 Uninstall-ArtDesk.cmd 恢复旧配置，再重新安装。' }
    if ($previous.status -ne 'uninstalled') { throw '本目录已有无法识别的安装记录。请先保留 local-state 中的备份并检查记录，未改动 JBS。' }
}
if (Test-Path -LiteralPath $installShortcut) {
    throw "桌面已有同名快捷方式，为避免覆盖请先重命名或移走它：$installShortcut"
}
$installExe = Find-InstallJbs $JbsExecutable
$installRecords = Read-ArtCatalog -VerifyImages
$installKnownPaths = @{}
foreach ($record in $installRecords) { $installKnownPaths[[string]$record.file] = $true }
foreach ($image in Get-ChildItem -LiteralPath (Join-Path $installRoot 'images') -Recurse -File) {
    if ($image.Extension -in '.jpg','.jpeg','.png','.bmp','.webp','.gif','.tif','.tiff' -and -not $installKnownPaths.ContainsKey($image.FullName)) {
        throw "images 文件夹存在没有资料的图片，请移出后重试：$($image.Name)"
    }
}
$installXml = Read-InstallSettings
Set-InstallOptions $installXml
if ($ValidateOnly) {
    Write-Output "PASS: $($installRecords.Count) 幅作品和图片校验通过，JBS 配置可用；未写入文件、未改动设置或停止程序。"
    return
}

$installBackup = Join-Path $installStateRoot ('backups\install-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($installBackup)
$installBackupSettings = Join-Path $installBackup 'Settings.xml'
# The first backup precedes stopping JBS. Re-read after it stops to catch a last settings save.
Copy-Item -LiteralPath $installSettings -Destination $installBackupSettings
$installSession = (Get-Process -Id $PID).SessionId
$installProcesses = @(Get-Process -Name BackgroundSwitcher -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $installSession -and $_.Path -ieq $installExe })
$installChanged = $false
$installShortcutCreated = $false
$installSucceeded = $false
try {
    foreach ($process in $installProcesses) { Stop-Process -Id $process.Id -Force }
    $installXml = Read-InstallSettings
    Copy-Item -LiteralPath $installSettings -Destination $installBackupSettings -Force
    $installOriginalHash = (Get-FileHash -LiteralPath $installBackupSettings -Algorithm SHA256).Hash
    Set-InstallOptions $installXml
    $installTemporary = $installSettings + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $installXml.Save($installTemporary)
        [IO.File]::Replace($installTemporary, $installSettings, [NullString]::Value)
        $installChanged = $true
    } finally { if ([IO.File]::Exists($installTemporary)) { [IO.File]::Delete($installTemporary) } }
    if (Test-Path -LiteralPath $installShortcut) { throw '创建快捷方式之前发现了同名文件，已停止安装并恢复配置。' }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($installShortcut)
    $shortcut.TargetPath = $installHost
    $shortcut.Arguments = $installArguments
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.Description = '桌边美术馆：当前名画介绍、中文画库与最近看过的作品。'
    $shortcut.IconLocation = $installExe + ',0'
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    $installShortcutCreated = $true
    $manifest = [ordered]@{
        version = 1
        status = 'installed'
        installedAt = (Get-Date).ToString('s')
        root = $installRoot
        settingsPath = $installSettings
        jbsExecutable = $installExe
        backupPath = $installBackupSettings
        backupSha256 = $installOriginalHash
        shortcutPath = $installShortcut
        shortcutSha256 = (Get-FileHash -LiteralPath $installShortcut -Algorithm SHA256).Hash
        total = $installRecords.Count
    }
    Write-ArtAtomic $installManifest (ConvertTo-Json -InputObject $manifest -Depth 5)
    $installSucceeded = $true
} catch {
    if ($installChanged) { Copy-Item -LiteralPath $installBackupSettings -Destination $installSettings -Force }
    if ($installShortcutCreated -and [IO.File]::Exists($installShortcut)) { Remove-Item -LiteralPath $installShortcut }
    throw
} finally {
    if (-not $SkipRestart -and ($installSucceeded -or $installProcesses.Count -gt 0)) {
        try { Start-Process -FilePath $installExe -WindowStyle Hidden }
        catch { Write-Warning '配置已处理，但 JBS 未能启动。请从开始菜单手动打开 JBS。' }
    }
}
Write-Output "安装完成：$($installRecords.Count) 幅画，每 4 小时换画。已保留原来的开机自启设置和其他图片来源。"
Write-Output "原 JBS 配置备份：$installBackupSettings"
Write-Output '请保留此程序文件夹的位置。运行 Open-ArtDesk.cmd 或桌面快捷方式查看作品；运行 Uninstall-ArtDesk.cmd 可恢复原配置。'
