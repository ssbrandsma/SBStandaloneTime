[CmdletBinding()]
param(
    [string]$BaseUrl = "http://49.12.198.91/sbstandalone",
    [string]$OutputDirectory
)
$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
if ($version -ne "0.2.0") { throw "Expected release version 0.2.0, found $version" }
$BaseUrl = $BaseUrl.TrimEnd('/')
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root "dist" }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$stage = Join-Path ([IO.Path]::GetTempPath()) ("StandaloneTime-" + [guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $OutputDirectory "StandaloneTime-$version.zip"
$xmlPath = Join-Path $OutputDirectory "extensions.xml"
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
New-Item -ItemType Directory -Force $stage | Out-Null
try {
    Copy-Item (Join-Path $root "StandaloneTime\StandaloneTimeApplet.lua") $stage
    Copy-Item (Join-Path $root "StandaloneTime\StandaloneTimeMeta.lua") $stage
    Copy-Item (Join-Path $root "StandaloneTime\Resolver.lua") $stage
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Push-Location $stage
    try { Compress-Archive -Path * -DestinationPath $zipPath -CompressionLevel Optimal }
    finally { Pop-Location }
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try { $entries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName.Replace([char]92,'/') }) }
    finally { $archive.Dispose() }
    $expected = @("StandaloneTimeApplet.lua", "StandaloneTimeMeta.lua", "Resolver.lua")
    if (@($entries | Where-Object { $_ -notin $expected }).Count -gt 0 -or @($expected | Where-Object { $_ -notin $entries }).Count -gt 0) { throw "Unexpected ZIP layout: $($entries -join ', ')" }
    $sha = (Get-FileHash $zipPath -Algorithm SHA1).Hash.ToLowerInvariant()
    $zipUrl = "$BaseUrl/StandaloneTime-$version.zip"
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<extensions>
  <details><title lang="EN">SBStandalone Applet Repository</title></details>
  <applets>
    <applet name="StandaloneRadio" version="0.8.0" target="baby" minTarget="7.7" maxTarget="*"><title lang="EN">Standalone Radio</title><desc lang="EN">Standalone internet radio playback for Squeezebox Radio. LMS is only needed to install the applet.</desc><changes lang="EN">Add scalable Radio Browser catalogs, expanded codecs, Force HTTP, and HTTPS artwork support.</changes><creator>Sjoerd Brandsma</creator><url>http://49.12.198.91/sbstandalone/StandaloneRadio-0.8.0.zip</url><sha>2731936546b142669050720c98a88a014184ae0c</sha></applet>
    <applet name="StandaloneRadio" version="0.8.0" target="fab4" minTarget="7.7" maxTarget="*"><title lang="EN">Standalone Radio</title><desc lang="EN">Standalone internet radio playback for Squeezebox Touch. LMS is only needed to install the applet.</desc><changes lang="EN">Add scalable Radio Browser catalogs, expanded codecs, Force HTTP, and HTTPS artwork support.</changes><creator>Sjoerd Brandsma</creator><url>http://49.12.198.91/sbstandalone/StandaloneRadio-0.8.0.zip</url><sha>2731936546b142669050720c98a88a014184ae0c</sha></applet>
    <applet name="SpotifyConnect" version="0.5.4" target="baby" minTarget="7.7" maxTarget="*"><title lang="EN">Spotify Connect</title><desc lang="EN">Standalone Spotify Connect playback for Logitech Squeezebox Radio. LMS is only needed to install the applet.</desc><changes lang="EN">Fix playback across natural track boundaries and rapid Spotify track changes.</changes><creator>Sjoerd Brandsma</creator><url>http://49.12.198.91/sbspotifyconnect/SpotifyConnect-0.5.4.zip</url><sha>ae66fa2d86af4135e98a5b7e9d67cecd9540b9eb</sha></applet>
    <applet name="SpotifyConnect" version="0.5.4" target="fab4" minTarget="7.7" maxTarget="*"><title lang="EN">Spotify Connect</title><desc lang="EN">Standalone Spotify Connect playback for Logitech Squeezebox Touch. LMS is only needed to install the applet.</desc><changes lang="EN">Fix playback across natural track boundaries and rapid Spotify track changes.</changes><creator>Sjoerd Brandsma</creator><url>http://49.12.198.91/sbspotifyconnect/SpotifyConnect-0.5.4.zip</url><sha>ae66fa2d86af4135e98a5b7e9d67cecd9540b9eb</sha></applet>
    <applet name="DoomDemonstrator" version="0.1.0" target="baby" minTarget="7.7" maxTarget="*"><title lang="EN">Doom Demonstrator</title><desc lang="EN">Native DOOM Shareware Episode 1 demonstration for Squeezebox Radio. No sound.</desc><changes lang="EN">Applet Installer package release 0.1.0.</changes><creator>Sjoerd Brandsma</creator><url>http://49.12.198.91/sbdoom/DoomDemonstrator-0.1.0.zip</url><sha>4eab40c9cf3495f479504d3147248f1a26bcc395</sha></applet>
    <applet name="StandaloneTime" version="$version" target="baby" minTarget="7.7" maxTarget="*"><title lang="EN">Standalone Time</title><desc lang="EN">Keeps the Squeezebox Radio system clock and hardware RTC synchronized using internet time, without requiring LMS.</desc><changes lang="EN">Use the proven asynchronous nslookup resolver workaround for stock SqueezePlay firmware.</changes><creator>Sjoerd Brandsma</creator><url>$zipUrl</url><sha>$sha</sha></applet>
  </applets>
</extensions>
"@
    [IO.File]::WriteAllText($xmlPath, $xml, (New-Object Text.UTF8Encoding($false)))
    [xml]$null = Get-Content $xmlPath -Raw
    Write-Host "ZIP: $zipPath"
    Write-Host "SHA-1: $sha"
    Write-Host "URL: $zipUrl"
    Write-Host "Entries: $($entries -join ', ')"
}
finally { if (Test-Path $stage) { Remove-Item $stage -Recurse -Force } }
