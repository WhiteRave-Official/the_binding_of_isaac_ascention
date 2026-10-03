param(
    [string]$GameDirectory = "D:\SteamLibrary\steamapps\common\The Binding of Isaac Rebirth",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo "build\native\bin\$Configuration\zhlAscention.dll"
$runtime = Join-Path $GameDirectory "repentogon"
$destination = Join-Path $runtime "zhlAscention.dll"

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Build the native module first: $source"
}
if (-not (Test-Path -LiteralPath (Join-Path $runtime "zhlREPENTOGON.dll") -PathType Leaf)) {
    throw "REPENTOGON runtime not found: $runtime"
}
if (Get-Process isaac-ng -ErrorAction SilentlyContinue) {
    throw "Close Isaac before replacing zhlAscention.dll."
}

Copy-Item -LiteralPath $source -Destination $destination -Force
$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
if ($sourceHash -ne $destinationHash) { throw "DLL copy verification failed." }
Write-Output "Installed $destination (SHA256 $destinationHash)"
