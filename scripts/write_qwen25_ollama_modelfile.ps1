param(
    [Parameter(Mandatory = $true)]
    [string]$GgufPath,

    [Parameter(Mandatory = $true)]
    [string]$ModelFilePath
)

$content = @(
    "FROM $GgufPath",
    "",
    "PARAMETER num_ctx 8192"
)

Set-Content -LiteralPath $ModelFilePath -Value $content -Encoding UTF8
