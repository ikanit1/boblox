param([switch]$SkipChecks)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
. (Join-Path $PSScriptRoot 'tools\Find-Tool.ps1')
$rojo = Find-RuleRoomTool 'rojo'
$python = (Get-Command python -ErrorAction Stop).Source
& $python tools/candidate_manifest.py prepare
if ($LASTEXITCODE -ne 0) { throw 'Candidate authored-input snapshot failed.' }
& $python tools/build_assets.py
if ($LASTEXITCODE -ne 0) { throw 'Asset generation failed.' }
& $python tools/candidate_manifest.py begin
if ($LASTEXITCODE -ne 0) { throw 'Candidate input snapshot failed.' }
& $python tools/verify_world.py
if ($LASTEXITCODE -ne 0) { throw 'World geometry verification failed.' }
if (-not $SkipChecks) {
    & $python tools/check_sources.py
    if ($LASTEXITCODE -ne 0) { throw 'Source checks failed.' }
}
New-Item -ItemType Directory -Force -Path build | Out-Null
& $rojo build default.project.json -o build/RuleRoom.rbxlx
if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed.' }
& $rojo sourcemap default.project.json -o build/sourcemap.json
if ($LASTEXITCODE -ne 0) { throw 'Rojo sourcemap failed.' }
if (Test-Path -LiteralPath prototypes.project.json) {
    & $rojo build prototypes.project.json -o build/RuleRoomExperiments.rbxlx
    if ($LASTEXITCODE -ne 0) { throw 'Isolated prototype build failed.' }
}
& $python tools/verify_place.py
if ($LASTEXITCODE -ne 0) { throw 'Place structure verification failed.' }
foreach ($testFile in Get-ChildItem -LiteralPath tests -Filter '*.spec.luau' | Sort-Object Name) {
    & (Find-RuleRoomTool 'luau') $testFile.FullName
    if ($LASTEXITCODE -ne 0) { throw "Luau test failed: $($testFile.Name)" }
}
foreach ($integrationFile in Get-ChildItem -LiteralPath tests -Filter '*.integration.luau' | Sort-Object Name) {
    & (Find-RuleRoomTool 'lune') run $integrationFile.FullName
    if ($LASTEXITCODE -ne 0) { throw "Offline integration checks failed: $($integrationFile.Name)" }
}
& (Find-RuleRoomTool 'lune') run tools/verify_model.luau
if ($LASTEXITCODE -ne 0) { throw 'Offline model semantics failed.' }
& $python -m unittest discover -s tools/tests -p 'test_*.py'
if ($LASTEXITCODE -ne 0) { throw 'Build-tool regression checks failed.' }
& $python tools/candidate_manifest.py finish
if ($LASTEXITCODE -ne 0) { throw 'Candidate source/artifact identity check failed.' }
Write-Host "Built: $(Join-Path $PSScriptRoot 'build\RuleRoom.rbxlx')"
