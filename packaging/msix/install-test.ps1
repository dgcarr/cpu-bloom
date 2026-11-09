[CmdletBinding()]
param([Parameter(Mandatory)][string]$BuildResult)
$ErrorActionPreference = 'Stop'
$result = Get-Content -LiteralPath $BuildResult -Raw | ConvertFrom-Json
$log = Join-Path (Split-Path $BuildResult) 'install-test.log'
try {
    if ($result.mode -ne 'Test' -or $result.identity -ne 'CpuBloom.LocalTest') { throw 'Only a local test package may be installed by this script.' }
    if ((Get-FileHash -LiteralPath $result.package).Hash -ne $result.sha256) { throw 'Package checksum does not match build result.' }
    # This opt-in is restricted to this unsigned test identity. It does not
    # modify Developer Mode, Smart App Control, or certificate trust stores.
    Add-AppxPackage -Path $result.package -AllowUnsigned -ErrorAction Stop
    Get-AppxPackage -Name CpuBloom.LocalTest | Select-Object Name,PackageFullName,PackageFamilyName,InstallLocation | ConvertTo-Json | Set-Content -LiteralPath $log
} catch {
    $_ | Out-String | Set-Content -LiteralPath $log
    exit 1
}
