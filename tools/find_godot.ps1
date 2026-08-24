$localGodot = Join-Path $PSScriptRoot "..\.tools\godot\Godot_v4.7.2-stable_win64.exe"

if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) {
    $env:GODOT_BIN
    exit 0
}

if (Test-Path -LiteralPath $localGodot -PathType Leaf) {
    $localGodot
    exit 0
}

$programFilesCandidates = @(
    Get-ChildItem -Path "C:\Program Files\Godot\Godot*.exe" -File -ErrorAction SilentlyContinue,
    Get-ChildItem -Path "C:\Program Files\Godot Engine\Godot*.exe" -File -ErrorAction SilentlyContinue
)

if ($programFilesCandidates.Count -gt 0) {
    $programFilesCandidates[0].FullName
    exit 0
}

throw "Godot executable not found. Set GODOT_BIN or install the portable runtime in .tools\\godot."
