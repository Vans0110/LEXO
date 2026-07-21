param(
    [string] $Repository = 'Vans0110/LEXO',
    [string] $Branch = 'main',
    [switch] $EnablePages,
    [switch] $UploadDirect
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'Virgil\App\assets\store\privacy_site\privacy-policy.html'
$publicDir = Join-Path $root 'public'
$publicFile = Join-Path $publicDir 'privacy-policy.html'
$remotePath = 'public/privacy-policy.html'
$pagesUrl = "https://vans0110.github.io/LEXO/$remotePath"

if (-not (Test-Path -LiteralPath $source)) {
    throw "Privacy policy source not found: $source"
}

New-Item -ItemType Directory -Force -Path $publicDir | Out-Null
Copy-Item -LiteralPath $source -Destination $publicFile -Force

Write-Host "[VIRGIL] Synced privacy policy:"
Write-Host "[VIRGIL]   $publicFile"

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    throw 'GitHub CLI was not found. Install gh or publish public/privacy-policy.html manually.'
}

& gh auth status | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI is not authenticated. Run: gh auth login'
}

function Invoke-GhJsonFile(
    [string] $Method,
    [string] $Endpoint,
    [object] $Body
) {
    $temp = New-TemporaryFile
    try {
        $Body | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
        & gh api --method $Method $Endpoint --input $temp
        if ($LASTEXITCODE -ne 0) {
            throw "gh api failed: $Method $Endpoint"
        }
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

if ($UploadDirect) {
    $bytes = [IO.File]::ReadAllBytes($publicFile)
    $content = [Convert]::ToBase64String($bytes)
    $endpoint = "repos/$Repository/contents/$remotePath"
    $sha = $null

    $existingJson = & gh api "$endpoint?ref=$Branch" 2>$null
    if ($LASTEXITCODE -eq 0 -and $existingJson) {
        $existing = $existingJson | ConvertFrom-Json
        $sha = $existing.sha
    }

    $body = @{
        message = 'Publish Virgil privacy policy'
        content = $content
        branch = $Branch
    }
    if ($sha) {
        $body.sha = $sha
    }

    Invoke-GhJsonFile -Method PUT -Endpoint $endpoint -Body $body | Out-Null
    Write-Host "[VIRGIL] Uploaded privacy policy to GitHub:"
    Write-Host "[VIRGIL]   $remotePath"
}

if ($EnablePages) {
    $sourceConfig = @{
        branch = $Branch
        path = '/'
    }
    $body = @{
        source = $sourceConfig
    }

    & gh api "repos/$Repository/pages" >$null 2>$null
    if ($LASTEXITCODE -eq 0) {
        Invoke-GhJsonFile -Method PUT -Endpoint "repos/$Repository/pages" -Body $body | Out-Null
        Write-Host '[VIRGIL] GitHub Pages settings updated.'
    } else {
        Invoke-GhJsonFile -Method POST -Endpoint "repos/$Repository/pages" -Body $body | Out-Null
        Write-Host '[VIRGIL] GitHub Pages enabled.'
    }
}

Write-Host ''
Write-Host '[VIRGIL] Privacy Policy URL:'
Write-Host "[VIRGIL]   $pagesUrl"
Write-Host ''
Write-Host '[VIRGIL] To upload directly and enable Pages:'
Write-Host '[VIRGIL]   .\PUBLISH_PRIVACY_POLICY.bat -UploadDirect -EnablePages'
