param([switch]$SkipChecks)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
. (Join-Path $PSScriptRoot 'tools\Find-Tool.ps1')
$rojo = Find-RuleRoomTool 'rojo'
$python = (Get-Command python -ErrorAction Stop).Source
& $python tools/build_assets.py
if ($LASTEXITCODE -ne 0) { throw 'Asset generation failed.' }
if (-not $SkipChecks) {
    & $python tools/check_sources.py
    if ($LASTEXITCODE -ne 0) { throw 'Source checks failed.' }
}
New-Item -ItemType Directory -Force -Path build | Out-Null
& $rojo build default.project.json -o build/RuleRoom.rbxlx
if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed.' }
& $rojo sourcemap default.project.json -o build/sourcemap.json
if ($LASTEXITCODE -ne 0) { throw 'Rojo sourcemap failed.' }
& $python tools/verify_place.py
if ($LASTEXITCODE -ne 0) { throw 'Place structure verification failed.' }
foreach ($testFile in Get-ChildItem -LiteralPath tests -Filter '*.spec.luau' | Sort-Object Name) {
    & (Find-RuleRoomTool 'luau') $testFile.FullName
    if ($LASTEXITCODE -ne 0) { throw "Luau test failed: $($testFile.Name)" }
}
& (Find-RuleRoomTool 'lune') run tests/ProfileService.integration.luau
if ($LASTEXITCODE -ne 0) { throw 'ProfileService integration checks failed.' }
& (Find-RuleRoomTool 'lune') run tools/verify_model.luau
if ($LASTEXITCODE -ne 0) { throw 'Offline model semantics failed.' }
Write-Host "Built: $(Join-Path $PSScriptRoot 'build\RuleRoom.rbxlx')"
