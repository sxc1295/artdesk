param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$VerifyBundledImages
)

# No wallpaper, registry, real JBS settings or desktop shortcut is changed.
# Tests run against a disposable installation under the system temp directory.
$ErrorActionPreference = 'Stop'
$testProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$testCount = 0
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ArtDesk-test-' + [Guid]::NewGuid().ToString('N'))
$testInstallRoot = Join-Path $testRoot 'portable copy with spaces'
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
$savedLocation = Get-Location
$testEncoding = New-Object Text.UTF8Encoding($false)

function Assert-ArtTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:testCount++
}
function Assert-ArtThrows([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-ArtTest $failed $Message
}
function Write-TestJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 20), $testEncoding)
}
function Write-TestImage([string]$Path, [Drawing.Color]$Color) {
    $bitmap = New-Object Drawing.Bitmap(48, 72)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear($Color)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Bmp)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
function Get-TestSnapshot([string]$Path) {
    $rows = @(Get-ChildItem -LiteralPath $Path -File -Recurse | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($Path.Length) + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    return ($rows -join "`n")
}
function Write-TestStatus([string[]]$Files) {
    $pictures = @($Files | ForEach-Object {
        '<BackgroundSwitcherSettingsPicture><Identifier>' + [Security.SecurityElement]::Escape($_) + '</Identifier></BackgroundSwitcherSettingsPicture>'
    }) -join ''
    [IO.File]::WriteAllText($testStatusPath, ('<backgroundswitchersettings><last_switch>fixture</last_switch><current_pictures>' + $pictures + '</current_pictures></backgroundswitchersettings>'), $testEncoding)
}

try {
    Add-Type -AssemblyName System.Drawing
    foreach ($path in @($testInstallRoot, (Join-Path $testInstallRoot 'images'), (Join-Path $testInstallRoot 'data'), (Join-Path $testInstallRoot 'local-state'), (Join-Path $testRoot 'other'), (Join-Path $testRoot 'roaming'), (Join-Path $testRoot 'local'))) {
        [void][IO.Directory]::CreateDirectory($path)
    }
    $env:APPDATA = Join-Path $testRoot 'roaming'
    $env:LOCALAPPDATA = Join-Path $testRoot 'local'
    foreach ($name in @('ArtDesk.ps1', 'Queue-ArtDesk.ps1', 'Install-ArtDesk.ps1', 'Uninstall-ArtDesk.ps1', 'app-template.html')) {
        $source = Join-Path $testProjectRoot $name
        if ([IO.File]::Exists($source)) { Copy-Item -LiteralPath $source -Destination (Join-Path $testInstallRoot $name) }
    }
    foreach ($scriptFile in @(Get-ChildItem -LiteralPath $testProjectRoot -Filter '*.ps1' -Recurse -File)) {
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors)
        Assert-ArtTest (@($parseErrors).Count -eq 0) ('PowerShell parse error: ' + $scriptFile.Name)
    }
    $testImageA = Join-Path $testInstallRoot 'images\sample-a.bmp'
    $testImageB = Join-Path $testInstallRoot 'images\sample-b.bmp'
    Write-TestImage $testImageA ([Drawing.Color]::Crimson)
    Write-TestImage $testImageB ([Drawing.Color]::RoyalBlue)
    $testRows = @(
        [pscustomobject]@{id='fixture:a';file='images/sample-a.bmp';sha256=(Get-FileHash -LiteralPath $testImageA -Algorithm SHA256).Hash;titleZh='Fixture A'},
        [pscustomobject]@{id='fixture:b';file='images/sample-b.bmp';sha256=(Get-FileHash -LiteralPath $testImageB -Algorithm SHA256).Hash;titleZh='Fixture B'}
    )
    $testDataPath = Join-Path $testInstallRoot 'data\artworks.json'
    Write-TestJson $testDataPath $testRows
    Write-TestJson (Join-Path $testInstallRoot 'gallery-data.json') ([ordered]@{artworks=$testRows;stats=@{total=2}})
    $initialSnapshot = Get-TestSnapshot $testInstallRoot
    . (Join-Path $testInstallRoot 'ArtDesk.ps1') -LibraryOnly
    Assert-ArtTest ((Get-TestSnapshot $testInstallRoot) -ceq $initialSnapshot) 'LibraryOnly wrote files.'

    Set-Location -LiteralPath (Join-Path $testRoot 'other')
    $catalog = Read-ArtCatalog -VerifyImages
    Assert-ArtTest ($catalog.Count -eq 2 -and $catalog[0].file -ieq $testImageA) 'Relative catalogue paths did not resolve from installation root.'
    Assert-ArtTest ((Read-ArtJson $testDataPath)[0].file -eq 'images/sample-a.bmp') 'Catalogue load rewrote the distributable relative paths.'
    Assert-ArtThrows { Resolve-ArtCatalogPath 'images/../../outside.bmp' } 'Parent traversal escaped the images directory.'
    Assert-ArtThrows { Resolve-ArtCatalogPath $testImageA } 'An absolute catalogue path was accepted.'
    Assert-ArtThrows { Resolve-ArtCatalogPath 'images-other/sample.bmp' } 'A sibling directory passed the images boundary check.'
    Assert-ArtTest ((Resolve-Artwork $testImageA $catalog).id -eq 'fixture:a') 'Known artwork was not identified.'
    Assert-ArtTest ((Resolve-Artwork $testImageB $catalog).id -eq 'fixture:b') 'Changing images kept the previous artwork identity.'
    Assert-ArtTest ((Resolve-Artwork '' $catalog).status -eq 'unknown') 'Empty wallpaper was attributed.'
    $outsideImage = Join-Path $testRoot 'other\sample-a.bmp'
    Copy-Item -LiteralPath $testImageA -Destination $outsideImage
    Assert-ArtTest ((Resolve-Artwork $outsideImage $catalog).status -eq 'unknown') 'An external file with the same name and bytes was wrongly attributed.'
    Write-TestImage $testImageA ([Drawing.Color]::Green)
    Assert-ArtTest ((Resolve-Artwork $testImageA $catalog).status -eq 'unknown') 'A changed image was trusted.'
    Assert-ArtThrows { Read-ArtCatalog -VerifyImages } 'Catalogue validation accepted a changed image.'
    Copy-Item -LiteralPath $outsideImage -Destination $testImageA -Force
    Write-TestJson $testDataPath @($testRows[0], $testRows[0])
    Assert-ArtThrows { Read-ArtCatalog } 'Duplicate artwork IDs were accepted.'
    $duplicatePath = [pscustomobject]@{id='fixture:c';file=$testRows[0].file;sha256=$testRows[0].sha256}
    Write-TestJson $testDataPath @($testRows[0], $duplicatePath)
    Assert-ArtThrows { Read-ArtCatalog } 'Duplicate artwork paths were accepted.'
    Write-TestJson $testDataPath $testRows

    # JBS identification must agree across source, status, cache and Windows image.
    foreach ($path in @($artJbsRoot, (Split-Path -Parent $artJbsCache), (Split-Path -Parent $artWindowsCache))) {
        [void][IO.Directory]::CreateDirectory($path)
    }
    $testStatusPath = Join-Path $artJbsRoot 'Status.xml'
    $testActivePath = Join-Path $artJbsRoot 'ActiveBackground.jpg'
    foreach ($destination in @($artJbsCache, $testActivePath, $artWindowsCache)) { Copy-Item -LiteralPath $testImageA -Destination $destination -Force }
    Assert-ArtTest ((Resolve-Artwork $testActivePath $catalog).status -eq 'unknown') 'Missing JBS status was attributed.'
    Write-TestStatus @($testImageA)
    Assert-ArtTest ((Resolve-Artwork $testActivePath $catalog).id -eq 'fixture:a') 'Consistent JBS state failed identification.'
    Copy-Item -LiteralPath $testImageB -Destination $artJbsCache -Force
    Assert-ArtTest ((Resolve-Artwork $testActivePath $catalog).status -eq 'unknown') 'Stale JBS cache was attributed.'
    Copy-Item -LiteralPath $testImageA -Destination $artJbsCache -Force
    Copy-Item -LiteralPath $testImageB -Destination $artWindowsCache -Force
    Assert-ArtTest ((Resolve-Artwork $testActivePath $catalog).status -eq 'unknown') 'A different Windows image was attributed.'
    Copy-Item -LiteralPath $testImageB -Destination $testActivePath -Force
    Assert-ArtTest ((Resolve-Artwork $testActivePath $catalog).status -eq 'unknown') 'Consistent rendered images from the wrong artwork were attributed.'
    foreach ($destination in @($testActivePath, $artWindowsCache)) { Copy-Item -LiteralPath $testImageA -Destination $destination -Force }
    Write-TestStatus @($testImageA, $testImageB)
    Assert-ArtTest ((Resolve-Artwork $testActivePath $catalog).status -eq 'unknown') 'Multiple JBS pictures were attributed to one artwork.'
    Write-TestStatus @($outsideImage)
    Assert-ArtTest ((Resolve-Artwork $testActivePath $catalog).status -eq 'unknown') 'An external JBS source was attributed.'

    # Unknown states must not create history; consecutive duplicate entries are collapsed.
    $unknown = New-ArtUnknown 'fixture'
    [void](Save-ArtHistory $unknown)
    Assert-ArtTest (-not [IO.File]::Exists((Join-Path $artStateRoot 'history.json'))) 'An unknown state created viewing history.'
    $known = Resolve-Artwork $testImageA $catalog
    [void](Save-ArtHistory $known)
    $history = Save-ArtHistory $known
    Assert-ArtTest ($history.Count -eq 1 -and $history[0].id -eq 'fixture:a') 'Consecutive history entries were duplicated.'

    # Dangerous process actions are forbidden even if a validation branch regresses.
    function Start-Process { throw 'Validation attempted to start a process.' }
    function Stop-Process { throw 'Validation attempted to stop a process.' }
    function Get-Process { throw 'Validation attempted to inspect a process for mutation.' }
    $testSettingsPath = Join-Path $artJbsRoot 'Settings.xml'
    $testSettingsXml = '<backgroundswitchersettings><schema>53</schema><watch_folders><folder enabled="true">original</folder></watch_folders><run_command_after_switching>false</run_command_after_switching><application_to_run_after_switching /><arguments_for_run_after_switching /><switching_interval>Hours1</switching_interval><switch_on_startup>false</switch_on_startup><refresh_background_on_application_startup>false</refresh_background_on_application_startup><display_mode>original</display_mode><watch_traverse_subdirectories>false</watch_traverse_subdirectories><run_on_startup>false</run_on_startup></backgroundswitchersettings>'
    [IO.File]::WriteAllText($testSettingsPath, $testSettingsXml, $testEncoding)
    $testFakeExe = Join-Path $testRoot 'BackgroundSwitcher.exe'
    [IO.File]::WriteAllText($testFakeExe, 'Non-executable test fixture.', $testEncoding)
    $testInstallScript = Join-Path $testInstallRoot 'Install-ArtDesk.ps1'
    $testUninstallScript = Join-Path $testInstallRoot 'Uninstall-ArtDesk.ps1'
    Assert-ArtTest ([IO.File]::Exists($testInstallScript) -and [IO.File]::Exists($testUninstallScript)) 'Install/uninstall scripts are missing.'
    $beforeValidation = Get-TestSnapshot $testRoot
    $validationOutput = & $testInstallScript -ValidateOnly -JbsExecutable $testFakeExe
    Assert-ArtTest ([string]$validationOutput -match '^PASS:') 'Installer validation did not report success.'
    Assert-ArtTest ((Get-TestSnapshot $testRoot) -ceq $beforeValidation) 'Install ValidateOnly changed fixture files.'
    [IO.File]::WriteAllText($testSettingsPath, $testSettingsXml.Replace('<schema>53</schema>', ''), $testEncoding)
    $beforeValidation = Get-TestSnapshot $testRoot
    Assert-ArtThrows { & $testInstallScript -ValidateOnly -JbsExecutable $testFakeExe } 'Unsupported JBS settings were accepted.'
    Assert-ArtTest ((Get-TestSnapshot $testRoot) -ceq $beforeValidation) 'Rejected installation changed fixture files.'
    [IO.File]::WriteAllText($testSettingsPath, $testSettingsXml, $testEncoding)
    Copy-Item -LiteralPath $testImageA -Destination (Join-Path $testInstallRoot 'images\uncatalogued.bmp')
    Assert-ArtThrows { & $testInstallScript -ValidateOnly -JbsExecutable $testFakeExe } 'An uncatalogued wallpaper image was accepted.'
    Remove-Item -LiteralPath (Join-Path $testInstallRoot 'images\uncatalogued.bmp')

    # Validate recovery boundaries using a synthetic install record, never install.
    $testBackupDirectory = Join-Path $testInstallRoot 'local-state\backups\fixture'
    [void][IO.Directory]::CreateDirectory($testBackupDirectory)
    $testBackup = Join-Path $testBackupDirectory 'Settings.xml'
    Copy-Item -LiteralPath $testSettingsPath -Destination $testBackup
    $testManifestPath = Join-Path $testInstallRoot 'local-state\installation.json'
    $testManifest = [ordered]@{
        version=1;status='installed';root=$testInstallRoot;settingsPath=$testSettingsPath;
        jbsExecutable=$testFakeExe;backupPath=$testBackup;
        backupSha256=(Get-FileHash -LiteralPath $testBackup -Algorithm SHA256).Hash;
        shortcutPath=(Join-Path $testRoot 'never-created.lnk');shortcutSha256='none'
    }
    Write-TestJson $testManifestPath $testManifest
    $beforeValidation = Get-TestSnapshot $testRoot
    $validationOutput = & $testUninstallScript -ValidateOnly
    Assert-ArtTest ([string]$validationOutput -match '^PASS:') 'Uninstaller validation did not report success.'
    Assert-ArtTest ((Get-TestSnapshot $testRoot) -ceq $beforeValidation) 'Uninstall ValidateOnly changed fixture files.'
    $testManifest.root = Join-Path $testRoot 'another-installation'
    Write-TestJson $testManifestPath $testManifest
    Assert-ArtThrows { & $testUninstallScript -ValidateOnly } 'An installation record from another directory was accepted.'
    $testManifest.root = $testInstallRoot
    $testManifest.settingsPath = Join-Path $testRoot 'another-user\Settings.xml'
    Write-TestJson $testManifestPath $testManifest
    Assert-ArtThrows { & $testUninstallScript -ValidateOnly } 'An installation record from another user was accepted.'
    $testManifest.settingsPath = $testSettingsPath
    $testManifest.backupPath = $testSettingsPath
    Write-TestJson $testManifestPath $testManifest
    Assert-ArtThrows { & $testUninstallScript -ValidateOnly } 'A backup outside the local backup folder was accepted.'
    $testManifest.backupPath = $testBackup
    $testManifest.backupSha256 = '0' * 64
    Write-TestJson $testManifestPath $testManifest
    $beforeValidation = Get-TestSnapshot $testRoot
    Assert-ArtThrows { & $testUninstallScript -ValidateOnly } 'A changed original-settings backup was accepted.'
    Assert-ArtTest ((Get-TestSnapshot $testRoot) -ceq $beforeValidation) 'Rejected uninstallation changed fixture files.'

    # A source checkout needs no downloaded artwork to run the fixture tests above.
    $sourceCatalog = @(Read-ArtJson (Join-Path $testProjectRoot 'data\artworks.json'))
    Assert-ArtTest ($sourceCatalog.Count -eq 395) 'Expected the 395-work release catalogue.'
    Assert-ArtTest (@($sourceCatalog.id | Sort-Object -Unique).Count -eq $sourceCatalog.Count) 'Release artwork IDs are duplicated.'
    foreach ($record in $sourceCatalog) {
        foreach ($field in @('titleZh','artistZh','museumZh','descriptionZh','lookForZh','sourceUrl','license','sha256')) {
            Assert-ArtTest (-not [string]::IsNullOrWhiteSpace([string]$record.$field)) ('Missing ' + $field + ' for ' + $record.id)
        }
        Assert-ArtTest ([string]$record.file -match '^images/[^/\\]+\.(jpg|jpeg|png|bmp)$') ('Non-portable path for ' + $record.id)
        Assert-ArtTest ((ConvertTo-Json -InputObject $record -Compress) -notmatch '(?i)[A-Z]:\\\\Users\\\\|wallpaperPath|checkedAt|installation\.json') ('Personal state in catalogue: ' + $record.id)
        if ($VerifyBundledImages) {
            $path = Join-Path $testProjectRoot $record.file
            Assert-ArtTest ([IO.File]::Exists($path)) ('Missing bundled image: ' + $record.file)
            Assert-ArtTest ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ieq $record.sha256) ('Bundled image hash mismatch: ' + $record.file)
        }
    }
    Write-Output ('PASS: ' + $testCount + ' assertions; isolated identity, portability, history, install/uninstall validation and catalogue checks; PowerShell ' + $PSVersionTable.PSVersion + '; bundled image hashes checked: ' + [bool]$VerifyBundledImages)
} finally {
    Set-Location -LiteralPath $savedLocation.Path
    $env:APPDATA = $savedAppData
    $env:LOCALAPPDATA = $savedLocalAppData
    # Remove only the exact generated test folder under the OS temporary directory.
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedTest = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTest) -match '^ArtDesk-test-[0-9a-f]{32}$' -and [IO.Directory]::Exists($resolvedTest)) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
