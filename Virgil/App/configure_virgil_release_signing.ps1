$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$keystorePath = Join-Path $projectRoot 'keys\virgil-upload.jks'
$propertiesPath = Join-Path $projectRoot 'android\key.properties'
$keytoolPath = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'

if (-not (Test-Path -LiteralPath $keystorePath)) {
    throw "Upload key not found: $keystorePath"
}

if (-not (Test-Path -LiteralPath $keytoolPath)) {
    throw "keytool not found: $keytoolPath"
}

$password = Read-Host 'Enter the virgil-upload keystore password' -AsSecureString
$confirmation = Read-Host 'Re-enter the password' -AsSecureString

$passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
$confirmationPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
    $confirmation
)

try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        $passwordPtr
    )
    $plainConfirmation = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        $confirmationPtr
    )

    if ([string]::IsNullOrWhiteSpace($plainPassword)) {
        throw 'Password cannot be empty.'
    }
    if ($plainPassword -cne $plainConfirmation) {
        throw 'Passwords do not match.'
    }

    $env:VIRGIL_KEYSTORE_PASSWORD = $plainPassword
    & $keytoolPath `
        -list `
        -keystore $keystorePath `
        -alias virgil-upload `
        -storepass:env VIRGIL_KEYSTORE_PASSWORD | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'The password does not open virgil-upload.jks.'
    }

    function ConvertTo-JavaPropertyValue([string] $value) {
        $escaped = $value.Replace('\', '\\')
        foreach ($character in @('=', ':', '#', '!')) {
            $escaped = $escaped.Replace($character, "\$character")
        }
        return $escaped
    }

    $propertyPassword = ConvertTo-JavaPropertyValue $plainPassword
    $content = @(
        "storePassword=$propertyPassword"
        "keyPassword=$propertyPassword"
        'keyAlias=virgil-upload'
        'storeFile=../keys/virgil-upload.jks'
    )
    [IO.File]::WriteAllLines(
        $propertiesPath,
        $content,
        [Text.UTF8Encoding]::new($false)
    )
} finally {
    if ($passwordPtr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
    }
    if ($confirmationPtr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmationPtr)
    }
    $plainPassword = $null
    $plainConfirmation = $null
    $propertyPassword = $null
    Remove-Item Env:\VIRGIL_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '[VIRGIL] Release signing configuration created:'
Write-Host $propertiesPath
Write-Host '[VIRGIL] This file is excluded from Git.'
