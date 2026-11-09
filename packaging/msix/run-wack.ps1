[CmdletBinding(DefaultParameterSetName='Installed')]
param(
    [Parameter(Mandatory,ParameterSetName='Installed')][string]$PackageFullName,
    [Parameter(Mandatory,ParameterSetName='Archive')][string]$PackagePath,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$tool = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/App Certification Kit/appcert.exe'
try {
    $reset = Start-Process $tool -ArgumentList 'reset' -WindowStyle Hidden -Wait -PassThru
    $target = @('-packagefullname',$PackageFullName)
    if ($PSCmdlet.ParameterSetName -eq 'Archive') { $target = @('-appxpackagepath',"`"$PackagePath`"") }
    $test = Start-Process $tool -ArgumentList (@('test') + $target + @('-reportoutputpath',"`"$OutputDirectory\wack.xml`"")) -WindowStyle Hidden -RedirectStandardOutput "$OutputDirectory/wack.stdout.log" -RedirectStandardError "$OutputDirectory/wack.stderr.log" -Wait -PassThru
    [ordered]@{ exitCode=$test.ExitCode; reportExists=(Test-Path "$OutputDirectory/wack.xml"); package=$PackageFullName; packagePath=$PackagePath } | ConvertTo-Json | Set-Content "$OutputDirectory/wack-state.json"
} catch {
    $_ | Out-String | Set-Content "$OutputDirectory/wack-error.log"
    exit 1
}
