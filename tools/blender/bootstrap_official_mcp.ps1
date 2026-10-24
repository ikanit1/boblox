param(
    [string]$RuntimeHome,
    [string]$BlenderPath = 'D:\Steam\steamapps\common\Blender\blender.exe',
    [switch]$SkipImageTools
)
$ErrorActionPreference = 'Stop'
$pin = 'dbbf836ad4b1025f14a2b3b504c43903f39e0b04'
if (-not $RuntimeHome) {
    $packaged = Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\RobloxDev\blender-mcp-official'
    $RuntimeHome = if (Test-Path -LiteralPath $packaged) { $packaged } else { Join-Path $env:LOCALAPPDATA 'RobloxDev\blender-mcp-official' }
}
if (-not (Test-Path -LiteralPath $BlenderPath -PathType Leaf)) { throw 'Pass -BlenderPath with the installed Blender 5.1+ executable.' }
$RuntimeHome = [System.IO.Path]::GetFullPath($RuntimeHome)
New-Item -ItemType Directory -Force -Path $RuntimeHome | Out-Null
$source = Join-Path $RuntimeHome 'source-dbbf836ad4b1'
if (-not (Test-Path -LiteralPath $source)) {
    & git -c credential.helper= -c credential.interactive=false clone --no-checkout https://projects.blender.org/lab/blender_mcp.git $source
    if ($LASTEXITCODE -ne 0) { throw 'Official source clone failed' }
    & git -C $source checkout --detach $pin
    if ($LASTEXITCODE -ne 0) { throw 'Pinned official revision is unavailable' }
}
$actual = (& git -C $source rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actual -ne $pin) { throw 'Existing runtime has a different upstream revision; review before updating.' }
$dirty = & git -C $source status --porcelain --untracked-files=no
if ($dirty) { throw 'Official runtime source has local edits; preserve and review them.' }
$python = Join-Path $RuntimeHome 'venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    & python -m venv (Join-Path $RuntimeHome 'venv')
    if ($LASTEXITCODE -ne 0) { throw 'MCP environment creation failed' }
}
& $python -m pip install --disable-pip-version-check -r (Join-Path $PSScriptRoot 'mcp-requirements.lock.txt')
if ($LASTEXITCODE -ne 0) { throw 'MCP dependencies failed' }
& $python -m pip install --disable-pip-version-check --no-deps (Join-Path $source 'mcp')
if ($LASTEXITCODE -ne 0) { throw 'Official MCP package installation failed' }
& $python -m pip check
if ($LASTEXITCODE -ne 0) { throw 'MCP dependency consistency check failed' }
$launcher = Join-Path $RuntimeHome 'launcher'
New-Item -ItemType Directory -Force -Path $launcher | Out-Null
$files = @{}
foreach ($name in 'run_mcp.py', 'start_bridge.py') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $launcher $name) -Force
    $files[$name] = (Get-FileHash -LiteralPath (Join-Path $launcher $name) -Algorithm SHA256).Hash.ToLowerInvariant()
}
if (-not $SkipImageTools) {
    $imagePython = Join-Path $RuntimeHome 'image-venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $imagePython)) {
        & python -m venv (Join-Path $RuntimeHome 'image-venv')
        if ($LASTEXITCODE -ne 0) { throw 'Image environment creation failed' }
    }
    & $imagePython -m pip install --disable-pip-version-check -r (Join-Path $PSScriptRoot 'image-requirements.lock.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Image dependencies failed' }
    & $imagePython -m pip check
    if ($LASTEXITCODE -ne 0) { throw 'Image dependency consistency check failed' }
}
$deployment = [ordered]@{
    upstream = 'https://projects.blender.org/lab/blender_mcp'
    upstreamCommit = $pin
    package = 'blender-mcp==1.0.2'
    blenderPath = $BlenderPath
    runtimeHome = $RuntimeHome
    launcherSha256 = $files
    command = $python
    args = @('-u', (Join-Path $launcher 'run_mcp.py'), '--blender', $BlenderPath, '--runtime-home', $RuntimeHome, '--port', '9877')
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
}
$deployment | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $RuntimeHome 'deployment.json') -Encoding utf8
Write-Host "Prepared official Blender MCP: $RuntimeHome"
Write-Host 'Codex registration is separate. Read deployment.json, then run the MCP handshake and read-only scene query.'
