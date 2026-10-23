function Find-RuleRoomTool([string]$Name) {
    $candidate = Join-Path $env:LOCALAPPDATA "RobloxDev\bin\$Name.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "Missing tool '$Name'. See docs/toolchain.json."
}

function Find-RuleRoomStudio {
    $roots = @(
        (Join-Path $env:ProgramFiles 'Roblox\Versions'),
        (Join-Path ${env:ProgramFiles(x86)} 'Roblox\Versions'),
        (Join-Path $env:LOCALAPPDATA 'Roblox\Versions')
    )
    $studios = foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -Path (Join-Path $root '*\RobloxStudioBeta.exe') -ErrorAction SilentlyContinue
        }
    }
    $studio = $studios | Sort-Object { $_.VersionInfo.FileMinorPart }, LastWriteTime -Descending | Select-Object -First 1
    if (-not $studio) { throw 'Roblox Studio is not installed.' }
    return $studio.FullName
}
