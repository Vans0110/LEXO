param(
    [string]$RepositoryUrl = "https://github.com/Vans0110/LEXO-Private-Backup.git",
    [string]$Destination,
    [switch]$Update
)

$ErrorActionPreference = "Stop"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not found in PATH." }
if (-not $Destination) { $Destination = Join-Path (Split-Path (Resolve-Path (Join-Path $PSScriptRoot "..\.."))) "LEXO-Restored" }
$Destination = [System.IO.Path]::GetFullPath($Destination)

if (Test-Path $Destination) {
    if (-not $Update) { throw "Destination already exists. Use -Update for an existing restored repository." }
    if (-not (Test-Path (Join-Path $Destination ".git"))) { throw "Destination is not a Git repository." }
    & git -C $Destination status --porcelain
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect destination repository." }
    $dirty = & git -C $Destination status --porcelain
    if ($dirty) { throw "Destination has local changes. Commit or remove them before update." }
    & git -C $Destination pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "Update failed." }
} else {
    & git clone $RepositoryUrl $Destination
    if ($LASTEXITCODE -ne 0) { throw "Clone failed." }
}

$manifestPath = Join-Path $Destination "backup-manifest.json"
if (-not (Test-Path $manifestPath)) { throw "Backup manifest is missing." }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
Write-Host "LEXO source snapshot restored to: $Destination"
Write-Host ("Snapshot UTC: {0}; files: {1}; source size: {2:N1} MB" -f $manifest.created_utc, $manifest.file_count, ($manifest.total_bytes / 1MB))
Write-Host "Models, secrets, environments, builds and release packages are intentionally not restored."
