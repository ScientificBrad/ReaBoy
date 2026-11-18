[CmdletBinding()]
param(
    [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\ReaBoy'),
    [switch]$NoLaunch,
    [switch]$NoShortcut,
    [string]$PackagePath,
    [string]$ExpectedSha256
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$work = Join-Path ([IO.Path]::GetTempPath()) ('ReaBoy-install-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    if (-not $PackagePath) {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/ScientificBrad/ReaBoy/releases/latest' -Headers @{'User-Agent'='ReaBoy-Installer'}
        $packages = @($release.assets | Where-Object { $_.name -match '^ReaBoy-v[0-9.]+-win-x64\.zip$' })
        if ($packages.Count -ne 1) { throw 'The latest release does not contain exactly one Windows x64 package.' }
        $asset = $packages[0]
        if (-not ([string]$asset.browser_download_url).StartsWith('https://github.com/ScientificBrad/ReaBoy/releases/download/')) { throw 'Unexpected package download location.' }
        Write-Host ('Downloading ReaBoy ' + $release.tag_name + '...')
        $PackagePath = Join-Path $work $asset.name
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $PackagePath
        $digest = ''
        if ($asset.PSObject.Properties['digest']) { $digest = [string]$asset.digest }
        if ($digest -match '^sha256:([0-9a-fA-F]{64})$') {
            $ExpectedSha256 = $Matches[1]
        } else {
            $manifest = @($release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' })
            if ($manifest.Count -ne 1) { throw 'No SHA-256 checksum is available for this release.' }
            $manifestPath = Join-Path $work 'SHA256SUMS.txt'
            Invoke-WebRequest -UseBasicParsing -Uri $manifest[0].browser_download_url -OutFile $manifestPath
            $pattern = '(?im)^([0-9a-f]{64})\s+\*?' + [Regex]::Escape($asset.name) + '\s*$'
            $match = [Regex]::Match((Get-Content -LiteralPath $manifestPath -Raw), $pattern)
            if (-not $match.Success) { throw 'The package is missing from the checksum manifest.' }
            $ExpectedSha256 = $match.Groups[1].Value
        }
    }
    if ($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'A valid expected SHA-256 checksum is required.' }
    $actual = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256) { throw 'The downloaded package failed SHA-256 verification.' }
    Write-Host 'Checksum verified.'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath).Path)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\','/')
            if ($name.StartsWith('/') -or $name.Contains(':') -or ($name.Split('/') -contains '..')) { throw 'Unsafe path in package.' }
        }
    } finally { $zip.Dispose() }
    $expanded = Join-Path $work 'expanded'
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $expanded
    $executables = @(Get-ChildItem -LiteralPath $expanded -Filter ReaBoy.exe -File -Recurse)
    if ($executables.Count -ne 1) { throw 'The package does not contain exactly one ReaBoy.exe.' }
    $source = $executables[0].DirectoryName
    foreach ($name in @('README.md','LICENSES.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) { throw ('Missing package file: ' + $name) }
    }
    $InstallDirectory = [IO.Path]::GetFullPath($InstallDirectory)
    $targetExe = Join-Path $InstallDirectory 'ReaBoy.exe'
    foreach ($process in @(Get-Process -Name ReaBoy -ErrorAction SilentlyContinue)) {
        if ($process.Path -eq $targetExe) {
            if (-not $process.CloseMainWindow() -or -not $process.WaitForExit(10000)) { throw 'Close ReaBoy and run the installer again.' }
        }
    }
    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    foreach ($name in @('ReaBoy.exe','README.md','LICENSES.txt')) {
        Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $InstallDirectory $name) -Force
    }
    $romTarget = Join-Path $InstallDirectory 'rom'
    New-Item -ItemType Directory -Path $romTarget -Force | Out-Null
    foreach ($name in @('dmg_boot.bin','README.txt','BOOTIX-LICENSE.txt','BOOTIX-SOURCE.txt')) {
        $inputFile = Join-Path (Join-Path $source 'rom') $name
        $targetFile = Join-Path $romTarget $name
        if ((Test-Path -LiteralPath $inputFile -PathType Leaf) -and -not ($name -eq 'dmg_boot.bin' -and (Test-Path -LiteralPath $targetFile))) {
            Copy-Item -LiteralPath $inputFile -Destination $targetFile -Force
        }
    }
    if (-not $NoShortcut) {
        $programs = [Environment]::GetFolderPath('Programs')
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path $programs 'ReaBoy.lnk'))
        $shortcut.TargetPath = $targetExe
        $shortcut.WorkingDirectory = $InstallDirectory
        $shortcut.Description = 'ReaBoy - Game Boy emulator by BJ Studios'
        $shortcut.Save()
    }
    Write-Host ('Installed ReaBoy to ' + $InstallDirectory)
    Write-Host 'Your settings, saves and existing boot firmware are preserved.'
    if (-not $NoLaunch) { Start-Process -FilePath $targetExe -WorkingDirectory $InstallDirectory }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
