param(
    [string]$RepositoryUrl = "https://github.com/Vans0110/LEXO-Private-Backup.git",
    [switch]$Push,
    [switch]$SkipPrivacyCheck
)

$ErrorActionPreference = "Stop"
$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$snapshot = Join-Path $workspace ".private_backup_repo"

$excludedDirs = @(
    ".git", ".private_backup_repo", ".agents", ".dart_tool", ".gradle", ".idea", ".vscode",
    "__pycache__", "build", "ephemeral", "node_modules", "tmp", "Runtime", "CloudLibrary",
    ".venv_backend", ".venv_kokoro", "models", "hf_home", "stanza_resources", "Release", "Archive",
    "Private", "keys"
)
$excludedFiles = @(
    ".env", "credentials.env", "key.properties", "*.jks", "*.keystore", "*.p12", "*.pfx", "*.pem",
    "*.key", "*.aab", "*.apk", "*.ipa", "*.exe", "*.dll", "*.pdb", "*.pyc", "*.log"
)

function Invoke-Git([string[]]$Arguments, [string]$Directory = $snapshot) {
    & git -C $Directory @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git failed: git $($Arguments -join ' ')" }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not found in PATH." }
New-Item -ItemType Directory -Force -Path $snapshot | Out-Null

Write-Host "[1/6] Creating an independent snapshot..."
$copyArgs = @($workspace, $snapshot, "/MIR", "/R:1", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/XJ")
$copyArgs += "/XD"; $copyArgs += $excludedDirs
$copyArgs += "/XF"; $copyArgs += $excludedFiles
& robocopy @copyArgs
if ($LASTEXITCODE -ge 8) { throw "Robocopy failed with code $LASTEXITCODE." }

Write-Host "[2/6] Writing backup metadata..."
$meta = @"
# LEXO private snapshot

This repository is an independent private backup of the LEXO workspace.
Generated builds, release packages, caches, virtual environments, local ML models and secrets are intentionally excluded.

Restore with `RESTORE_LEXO_PRIVATE.bat` or `Scripts/PrivateBackup/Restore-LexoPrivate.ps1`.
"@
Set-Content -LiteralPath (Join-Path $snapshot "PRIVATE_BACKUP.md") -Value $meta -Encoding UTF8
$manifest = Get-ChildItem $snapshot -Recurse -File -Force | Where-Object { $_.FullName -notlike "$snapshot\.git\*" } |
    ForEach-Object { [pscustomobject]@{ path=$_.FullName.Substring($snapshot.Length + 1).Replace('\','/'); size=$_.Length } }
$summary = [pscustomobject]@{
    created_utc = (Get-Date).ToUniversalTime().ToString("o")
    source = $workspace
    file_count = @($manifest).Count
    total_bytes = ($manifest | Measure-Object size -Sum).Sum
    excluded_directories = $excludedDirs
    excluded_files = $excludedFiles
}
$summary | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $snapshot "backup-manifest.json") -Encoding UTF8

Write-Host "[3/6] Checking file sizes and possible secrets..."
$large = Get-ChildItem $snapshot -Recurse -File -Force | Where-Object { $_.FullName -notlike "$snapshot\.git\*" -and $_.Length -ge 95MB }
if ($large) { $large | Select-Object FullName,Length | Format-Table; throw "Snapshot contains files of 95 MB or larger." }
$dangerNames = Get-ChildItem $snapshot -Recurse -File -Force | Where-Object {
    $_.Name -match '(?i)(^\.env$|credential|secret|token|password|key\.properties$|\.jks$|\.keystore$|\.p12$|\.pfx$|\.pem$)'
}
if ($dangerNames) { $dangerNames | Select-Object FullName | Format-Table; throw "Possible secret files found." }
$secretPattern = '(?i)(api[_-]?key|access[_-]?token|secret[_-]?key|password)\s*[:=]\s*["''][^"'']{8,}'
$secretHits = Get-ChildItem $snapshot -Recurse -File -Include *.env,*.json,*.yaml,*.yml,*.toml,*.ini,*.properties,*.py,*.dart,*.ps1,*.bat |
    Select-String -Pattern $secretPattern -ErrorAction SilentlyContinue
if ($secretHits) { $secretHits | Select-Object Path,LineNumber | Format-Table; throw "Possible embedded secrets found." }

Write-Host "[4/6] Preparing the independent Git repository..."
if (-not (Test-Path (Join-Path $snapshot ".git"))) { Invoke-Git @("init", "-b", "main") }
$remote = (& git -C $snapshot remote get-url origin 2>$null)
if ($LASTEXITCODE -ne 0) { Invoke-Git @("remote", "add", "origin", $RepositoryUrl) }
elseif ($remote -ne $RepositoryUrl) { throw "Snapshot origin is '$remote', expected '$RepositoryUrl'." }
Invoke-Git @("add", "--all")
& git -C $snapshot diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host "No snapshot changes to commit." }
else { Invoke-Git @("commit", "-m", "LEXO private backup $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") }

Write-Host "[5/6] Snapshot ready: $snapshot"
Write-Host ("Files: {0}; size: {1:N1} MB" -f $summary.file_count, ($summary.total_bytes / 1MB))
if (-not $Push) { Write-Host "Dry run complete. Use -Push only after the private repository exists."; exit 0 }

if (-not $SkipPrivacyCheck) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is required to verify repository privacy before push." }
    $repoInfo = & gh repo view $RepositoryUrl --json isPrivate --jq .isPrivate
    if ($LASTEXITCODE -ne 0 -or $repoInfo.Trim() -ne "true") { throw "Remote repository is absent or not private." }
}
Write-Host "[6/6] Pushing to the private repository..."
Invoke-Git @("push", "-u", "origin", "main")
Write-Host "Private backup completed."
