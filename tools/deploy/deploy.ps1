<#
.SYNOPSIS
  Deploys PalStorageManager to a Palworld Game Pass (WinGDK) install.

.DESCRIPTION
  Copies src/PalStorageManager -> <PALWORLD_ROOT>/Pal/Binaries/<BINARIES_DIR>/<MODS_SUBDIR>/PalStorageManager

  Configuration (first hit wins):
    1) -PalworldRoot parameter
    2) PALWORLD_ROOT environment variable
    3) .env file in the repo root (PALWORLD_ROOT=..., PALWORLD_BINARIES_DIR=...)

  Game Pass notes:
    * Binary dir is WinGDK (NOT Steam's Win64).
    * Depending on the UE4SS build, mods live under "ue4ss\Mods" or "Mods";
      the script auto-detects which one exists (prefers ue4ss\Mods).
    * If copying fails with access denied, the MS Store sandbox is blocking
      writes — see README "Troubleshooting".

.EXAMPLE
  ./deploy.ps1 -PalworldRoot "C:\XboxGames\Palworld\Content"
  ./deploy.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$PalworldRoot = $env:PALWORLD_ROOT,
    [string]$BinariesDir = $env:PALWORLD_BINARIES_DIR,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Source = Join-Path $RepoRoot "src\PalStorageManager"

# .env fallback
$DotEnv = Join-Path $RepoRoot ".env"
if ((-not $PalworldRoot -or -not $BinariesDir) -and (Test-Path $DotEnv)) {
    Get-Content $DotEnv | ForEach-Object {
        if ($_ -match '^\s*PALWORLD_ROOT\s*=\s*(.+)\s*$' -and -not $PalworldRoot) {
            $script:PalworldRoot = $Matches[1].Trim()
        }
        if ($_ -match '^\s*PALWORLD_BINARIES_DIR\s*=\s*(.+)\s*$' -and -not $BinariesDir) {
            $script:BinariesDir = $Matches[1].Trim()
        }
    }
}
if (-not $BinariesDir) { $BinariesDir = "WinGDK" }  # Game Pass default (Steam would be Win64)

if (-not $PalworldRoot) {
    Write-Error "PALWORLD_ROOT not set. Pass -PalworldRoot, set the env var, or create .env (see .env.example). Typical Game Pass root: C:\XboxGames\Palworld\Content"
}
if (-not (Test-Path $Source)) {
    Write-Error "Mod source not found: $Source"
}

$Binaries = Join-Path (Join-Path (Join-Path $PalworldRoot "Pal") "Binaries") $BinariesDir
if (-not (Test-Path $Binaries)) {
    Write-Error "Binaries dir not found: $Binaries  (Game Pass install should contain Pal\Binaries\WinGDK). Check PALWORLD_ROOT."
}

# UE4SS layout auto-detection: prefer <bin>\ue4ss\Mods, fall back to <bin>\Mods.
$ModsDir = $null
foreach ($candidate in @("ue4ss\Mods", "Mods")) {
    $p = Join-Path $Binaries $candidate
    if (Test-Path $p) { $ModsDir = $p; break }
}
if (-not $ModsDir) {
    Write-Error "No UE4SS Mods folder found under $Binaries (looked for ue4ss\Mods and Mods). Install UE4SS (Palworld-compatible build) first — see README."
}

$Target = Join-Path $ModsDir "PalStorageManager"
Write-Host "Source : $Source"
Write-Host "Target : $Target"

if ($DryRun) {
    Write-Host "[dry-run] Would copy the mod (Scripts, config, enabled.txt, mod.json). No changes made."
    exit 0
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null
# Never deploy local dev overrides.
$Exclude = @("user.lua")
Copy-Item -Path (Join-Path $Source "*") -Destination $Target -Recurse -Force -Exclude $Exclude

Write-Host "Deployed. Start Palworld and check UE4SS.log for '[PalStorageManager]' lines."
Write-Host "Reminder: Game Pass updates can wipe UE4SS/mods — redeploy after game updates."
