param(
    [Parameter(Mandatory = $true)]
    [string]$GgufPath,

    [Parameter(Mandatory = $true)]
    [string]$ModelFilePath
)

$content = @(
    "FROM $GgufPath",
    "",
    'TEMPLATE """{{ if .System }}<BOS_TOKEN><|START_OF_TURN_TOKEN|><|SYSTEM_TOKEN|>{{ .System }}<|END_OF_TURN_TOKEN|>{{ end }}<|START_OF_TURN_TOKEN|><|USER_TOKEN|>{{ .Prompt }}<|END_OF_TURN_TOKEN|><|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>"""',
    "",
    'PARAMETER stop <|END_OF_TURN_TOKEN|>',
    'PARAMETER stop <|START_OF_TURN_TOKEN|>',
    'PARAMETER stop <EOS_TOKEN>'
)

Set-Content -LiteralPath $ModelFilePath -Value $content -Encoding UTF8
