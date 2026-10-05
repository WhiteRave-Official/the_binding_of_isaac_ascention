param([string]$OutputRoot = "D:\IsaacModding\workshop_staging")

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stage = Join-Path (Join-Path $OutputRoot $stamp) "the_binding_of_isaac_ascention"
New-Item -ItemType Directory -Path $stage -Force | Out-Null

foreach ($file in @("main.lua", "metadata.xml", "README.md")) {
    $source = Join-Path $repo $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing release file: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stage $file)
}
foreach ($folder in @("content", "content-repentogon", "resources")) {
    Copy-Item -LiteralPath (Join-Path $repo $folder) -Destination $stage -Recurse
}
$scriptRoot = Join-Path $repo "scripts"
Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.lua" | ForEach-Object {
    $relative = $_.FullName.Substring($scriptRoot.Length).TrimStart('\')
    $destination = Join-Path (Join-Path $stage "scripts") $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $destination
}

$blocked = Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object {
    $_.Extension -in @(".exe", ".dll", ".bat", ".cmd", ".ps1")
}
if ($blocked) { throw "Workshop package contains blocked files: $($blocked.FullName -join ', ')" }

Write-Output "Workshop package: $stage"
Write-Output "Select its metadata.xml in ModUploader. Suggested thumbnail: resources\gfx\ui\boss\playerportrait_geburah.png"
