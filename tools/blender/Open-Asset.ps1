param([string]$BlenderPath = 'D:\Steam\steamapps\common\Blender\blender.exe')
$ErrorActionPreference = 'Stop'
$asset = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\assets\source\reactor_beacon\reactor_beacon.blend'))
if (-not (Test-Path -LiteralPath $BlenderPath -PathType Leaf)) { throw 'Pass the installed Blender executable with -BlenderPath.' }
if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) { throw 'The source asset has not been generated.' }
# Explicit interactive entry point for the user; the Codex MCP bridge is a separate scratch scene.
Start-Process -FilePath $BlenderPath -ArgumentList ('"' + $asset + '"')
