param(
    [string]$ObsidianExecutable = 'D:\obsidian\Obsidian.exe'
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$dashboard = Join-Path $repoRoot 'docs\obsidian-vault\00-Dashboard\Dashboard.md'
if (-not (Test-Path -LiteralPath $ObsidianExecutable -PathType Leaf)) {
    throw 'Obsidian executable not found. Pass -ObsidianExecutable with its installed path.'
}
if (-not (Test-Path -LiteralPath $dashboard -PathType Leaf)) {
    throw 'Project Dashboard does not exist.'
}
$uri = 'obsidian://open?path=' + [Uri]::EscapeDataString($dashboard)
# User requested this interactive project app. It must be registered as a vault first.
Start-Process -FilePath $ObsidianExecutable -ArgumentList $uri -WindowStyle Normal
Write-Output 'Requested the project Dashboard. This command does not prove UI opening or register a new vault.'
