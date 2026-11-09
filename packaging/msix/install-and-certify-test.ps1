param([Parameter(Mandatory)][string]$BuildResult, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$build = Get-Content -LiteralPath $BuildResult -Raw | ConvertFrom-Json
if ($build.mode -ne 'Test' -or $build.identity -ne 'CpuBloom.LocalTest') { throw 'Only the local test identity is accepted.' }
$installation = Start-Process "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -ArgumentList @('-NoProfile','-File',"`"$PSScriptRoot/install-test.ps1`"",'-BuildResult',"`"$BuildResult`"") -WindowStyle Hidden -Wait -PassThru
if ($installation.ExitCode -ne 0) { throw 'Test package installation failed; certification not started.' }
$package = Get-AppxPackage -Name $build.identity
if (!$package -or $package.Version.ToString() -ne $build.version) { throw 'Installed version does not match the requested build.' }
& "$PSScriptRoot/run-wack.ps1" -PackageFullName $package.PackageFullName -OutputDirectory $OutputDirectory
