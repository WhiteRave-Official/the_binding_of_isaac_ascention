param(
    [string]$RepentogonSource = "D:\IsaacModding\tools\REPENTOGON-SDK",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$sdkBuild = Join-Path $repo "build\repentogon-sdk"
$nativeBuild = Join-Path $repo "build\native"

function Invoke-Checked([scriptblock]$Command, [string]$Step) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE." }
}

Invoke-Checked { cmake -S $RepentogonSource -B $sdkBuild -A Win32 } "SDK configure"
Invoke-Checked { cmake --build $sdkBuild --config $Configuration --target libzhl Lua5.3.3r } "SDK build"
Invoke-Checked {
    cmake -S (Join-Path $repo "native") -B $nativeBuild -A Win32 `
        "-DREPENTOGON_SOURCE=$RepentogonSource" `
        "-DREPENTOGON_BUILD=$sdkBuild"
} "Ascention configure"
Invoke-Checked { cmake --build $nativeBuild --config $Configuration --target zhlAscention } "Ascention build"

$dll = Join-Path $nativeBuild "bin\$Configuration\zhlAscention.dll"
if (-not (Test-Path -LiteralPath $dll)) { throw "Missing native output: $dll" }
Write-Output $dll
