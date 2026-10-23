$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Build.ps1')
. (Join-Path $PSScriptRoot 'tools\Find-Tool.ps1')
$studio = Find-RuleRoomStudio
$place = Join-Path $PSScriptRoot 'build\RuleRoom.rbxlx'
Start-Process -FilePath $studio -ArgumentList ('"' + $place + '"')
