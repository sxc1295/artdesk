param([switch]$SkipRestart, [switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ArtDesk.ps1') -LibraryOnly
$uninstallRoot = $PSScriptRoot
$uninstallStateRoot = Join-Path $uninstallRoot 'local-state'
$uninstallManifest = Join-Path $uninstallStateRoot 'installation.json'
if (-not [IO.File]::Exists($uninstallManifest)) { throw '本目录没有安装记录，无需卸载。画库与图片可以继续使用。' }
$uninstallRecord = Read-ArtJson $uninstallManifest
if ($uninstallRecord.status -eq 'uninstalled') { Write-Output '已恢复过原 JBS 配置，无需重复卸载。'; return }
if ($uninstallRecord.status -ne 'installed' -or $uninstallRecord.version -ne 1) { throw '安装记录格式无法识别，未改动任何配置。' }
if ([IO.Path]::GetFullPath([string]$uninstallRecord.root).TrimEnd('\') -ine [IO.Path]::GetFullPath($uninstallRoot).TrimEnd('\')) {
    throw '程序文件夹已移动，或此安装记录来自另一台电脑。请将文件夹放回原位置后卸载；未改动任何配置。'
}
$uninstallSettings = Join-Path $env:APPDATA 'johnsadventures.com\Background Switcher\Settings.xml'
if ([IO.Path]::GetFullPath([string]$uninstallRecord.settingsPath) -ine [IO.Path]::GetFullPath($uninstallSettings)) {
    throw '安装记录不属于当前 Windows 用户，未改动任何配置。'
}
$uninstallBackup = [IO.Path]::GetFullPath([string]$uninstallRecord.backupPath)
$uninstallAllowedBackupRoot = [IO.Path]::GetFullPath((Join-Path $uninstallStateRoot 'backups')) + [IO.Path]::DirectorySeparatorChar
if (-not $uninstallBackup.StartsWith($uninstallAllowedBackupRoot, [StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($uninstallBackup)) {
    throw '没有找到本次安装的原配置备份，未改动 JBS。请保留 local-state 文件夹并检查备份。'
}
if ((Get-FileHash -LiteralPath $uninstallBackup -Algorithm SHA256).Hash -ine $uninstallRecord.backupSha256) {
    throw '原配置备份的内容已改变，自动恢复已停止。请检查备份文件，避免覆盖为错误配置。'
}
if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($uninstallSettings))) { throw '当前用户的 JBS 配置文件夹已不存在，未创建或改动任何目录。' }
$uninstallShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ArtDesk 名画介绍.lnk'
$uninstallCanRemoveShortcut = $false
if ([string]$uninstallRecord.shortcutPath -ieq $uninstallShortcut -and [IO.File]::Exists($uninstallShortcut)) {
    $uninstallCanRemoveShortcut = ((Get-FileHash -LiteralPath $uninstallShortcut -Algorithm SHA256).Hash -ieq $uninstallRecord.shortcutSha256)
}
if ($ValidateOnly) { Write-Output 'PASS: 原配置备份和当前用户身份检查通过；未写入文件、未改动设置或停止程序。'; return }

$uninstallExe = [string]$uninstallRecord.jbsExecutable
$uninstallSession = (Get-Process -Id $PID).SessionId
$uninstallProcesses = @(Get-Process -Name BackgroundSwitcher -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $uninstallSession -and $_.Path -ieq $uninstallExe })
$uninstallSnapshot = Join-Path $uninstallStateRoot ('backups\before-uninstall-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.xml')
$uninstallSucceeded = $false
try {
    foreach ($process in $uninstallProcesses) { Stop-Process -Id $process.Id -Force }
    if ([IO.File]::Exists($uninstallSettings)) { Copy-Item -LiteralPath $uninstallSettings -Destination $uninstallSnapshot }
    $temporary = $uninstallSettings + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        Copy-Item -LiteralPath $uninstallBackup -Destination $temporary
        if ([IO.File]::Exists($uninstallSettings)) { [IO.File]::Replace($temporary, $uninstallSettings, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $uninstallSettings) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    # Never remove an unrelated or subsequently edited shortcut.
    if ($uninstallCanRemoveShortcut -and [IO.File]::Exists($uninstallShortcut)) {
        if ((Get-FileHash -LiteralPath $uninstallShortcut -Algorithm SHA256).Hash -ieq $uninstallRecord.shortcutSha256) {
            Remove-Item -LiteralPath $uninstallShortcut
        }
    } elseif ([IO.File]::Exists($uninstallShortcut)) {
        Write-Warning '桌面同名快捷方式已变化，已保留它，请自行检查。'
    }
    $uninstallRecord.status = 'uninstalled'
    $uninstallRecord | Add-Member -NotePropertyName uninstalledAt -NotePropertyValue (Get-Date).ToString('s') -Force
    $uninstallRecord | Add-Member -NotePropertyName beforeUninstallBackup -NotePropertyValue $uninstallSnapshot -Force
    Write-ArtAtomic $uninstallManifest (ConvertTo-Json -InputObject $uninstallRecord -Depth 5)
    $uninstallSucceeded = $true
} finally {
    if (-not $SkipRestart -and $uninstallProcesses.Count -gt 0 -and [IO.File]::Exists($uninstallExe)) {
        try { Start-Process -FilePath $uninstallExe -WindowStyle Hidden }
        catch { Write-Warning 'JBS 未能重新启动，请从开始菜单手动打开。' }
    }
}
if ($uninstallSucceeded) {
    Write-Output '已恢复安装前的 JBS 配置。图片、画库、历史记录和全部备份均已保留。'
    if ([IO.File]::Exists($uninstallSnapshot)) { Write-Output "卸载前的配置也已保存：$uninstallSnapshot" }
}
