# Dot-source this file to scope the selected toolchain to the current process.
$ErrorActionPreference = 'Stop'
$ruleRoomRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ruleRoomLock = Get-Content -Raw -LiteralPath (Join-Path $ruleRoomRoot 'docs/environment/tooling-lock.json') | ConvertFrom-Json
$ruleRoomToolPaths = @((Join-Path $env:LOCALAPPDATA 'RobloxDev/bin'))
foreach ($ruleRoomName in @('Node.js', 'Visual Studio Code')) {
    $ruleRoomEntry = $ruleRoomLock.assets | Where-Object tool -eq $ruleRoomName
    if (-not $ruleRoomEntry -or -not (Test-Path -LiteralPath $ruleRoomEntry.path)) { throw "Missing configured $ruleRoomName; run the environment bootstrap." }
    $ruleRoomFolder = Split-Path $ruleRoomEntry.path -Parent
    $ruleRoomToolPaths += if ($ruleRoomName -eq 'Visual Studio Code') { Join-Path $ruleRoomFolder 'bin' } else { $ruleRoomFolder }
}
$env:PATH = (($ruleRoomToolPaths + ($env:PATH -split ';')) | Select-Object -Unique) -join ';'
Write-Host 'RuleRoom toolchain active for this PowerShell process.'
