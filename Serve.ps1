$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
. (Join-Path $PSScriptRoot 'tools\Find-Tool.ps1')
& (Find-RuleRoomTool 'rojo') serve default.project.json --address 127.0.0.1 --port 34872
