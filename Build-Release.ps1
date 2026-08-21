param([string]$OutputPath = "")
$ErrorActionPreference = 'Stop'
$baseDir = $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $baseDir 'ShadowKit-v8.0.2.zip' }
$staging = Join-Path $env:TEMP ('ShadowKitBuild_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
try {
    Get-ChildItem -Path $baseDir -Force | Where-Object { $_.Name -notin @('.git','state','logs','.gitignore') } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $staging -Recurse -Force
    }
    Remove-Item (Join-Path $staging 'state') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $staging 'logs') -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $staging -Recurse -Include '*.log','*.tmp' -File | Remove-Item -Force -ErrorAction SilentlyContinue
    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $OutputPath -Force
    $hash = (Get-FileHash $OutputPath -Algorithm SHA256).Hash
    "$OutputPath`nSHA256: $hash" | Set-Content ($OutputPath + '.sha256') -Encoding UTF8
    Write-Host "Release built: $OutputPath" -ForegroundColor Green
    Write-Host "SHA256: $hash" -ForegroundColor Cyan
} finally {
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
}
