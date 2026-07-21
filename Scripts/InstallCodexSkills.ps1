param(
    [string[]]$SkillName = @(),
    [string]$DestinationRoot = (Join-Path $env:USERPROFILE '.codex\skills')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'Skills'
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Repository skills directory not found: $sourceRoot"
}

$skills = Get-ChildItem -LiteralPath $sourceRoot -Directory
if ($SkillName.Count -gt 0) {
    $wanted = [Collections.Generic.HashSet[string]]::new(
        [string[]]$SkillName,
        [StringComparer]::OrdinalIgnoreCase
    )
    $skills = @($skills | Where-Object { $wanted.Contains($_.Name) })
    $missing = @($SkillName | Where-Object {
        -not ($skills.Name -contains $_)
    })
    if ($missing.Count -gt 0) {
        throw "Unknown repository skill(s): $($missing -join ', ')"
    }
}
if ($skills.Count -eq 0) {
    throw 'No repository skills selected.'
}

New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
foreach ($skill in $skills) {
    $manifest = Join-Path $skill.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw "SKILL.md not found: $($skill.FullName)"
    }
    $destination = Join-Path $DestinationRoot $skill.Name
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath $skill.FullName -Force |
        Copy-Item -Destination $destination -Recurse -Force
    Write-Output "Installed $($skill.Name) -> $destination"
}