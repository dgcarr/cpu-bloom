$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('cpu-bloom-gates-' + [guid]::NewGuid().ToString('N') + '.json')
function Expect-Rejection([hashtable]$Configuration, [string]$Message) {
    $Configuration | ConvertTo-Json | Set-Content -LiteralPath $fixture
    try {
        & "$PSScriptRoot/build-msix.ps1" -Mode Store -ConfigFile $fixture
        throw 'Invalid release configuration was accepted'
    } catch {
        if ($_.Exception.Message -notlike $Message) { throw }
        Write-Output "PASS: $($_.Exception.Message)"
    }
}
try {
    Expect-Rejection @{} 'Missing Store configuration*'
    $validShape = @{IdentityName='CpuBloom.LocalTest';Publisher='CN=NotAnAssignedIdentity';PublisherDisplayName='Test';DisplayName='CPU Bloom';Version='0.3.0.0';PrivacyUrl='https://example.com/privacy';SupportUrl='https://example.com/support';AssetRightsReviewed=$true;ThirdPartyNoticesReviewed=$true}
    Expect-Rejection $validShape 'Test identities cannot*'
    $validShape.IdentityName='GateValidationOnly'
    Expect-Rejection $validShape 'Invalid public HTTPS URL*'
    $validShape.PrivacyUrl='https://unpublished.invalid/privacy'; $validShape.SupportUrl='https://unpublished.invalid/support'
    $validShape.ThirdPartyNoticesReviewed=$false
    Expect-Rejection $validShape 'Asset rights and third-party*'
    $validShape.ThirdPartyNoticesReviewed='false'
    Expect-Rejection $validShape 'Asset rights and third-party*'
} finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture } }
