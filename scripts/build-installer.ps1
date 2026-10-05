param([string]$Configuration = "Release")

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo "AscentionNativeSetup.cs"
$payload = Join-Path $repo "build\native\bin\$Configuration\zhlAscention.dll"
$output = Join-Path $repo "Ascention Native Setup.exe"
$compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path -LiteralPath $payload -PathType Leaf)) { throw "Build the native DLL first: $payload" }
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "C# compiler not found: $compiler" }

& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /out:"$output" `
    /reference:System.dll /reference:System.Core.dll /reference:System.Windows.Forms.dll `
    /resource:"$payload",Ascention.Native "$source"
if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed." }
Write-Output "Built: $output"
Write-Output "SHA-256: $((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash)"
