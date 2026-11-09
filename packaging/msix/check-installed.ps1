param([Parameter(Mandatory)][string]$Installed, [Parameter(Mandatory)][string]$CheckClasses, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
try {
    $context = @{}
    & "$Installed/store-bridge.exe" context | ForEach-Object {
        $split=$_.IndexOf('='); if ($split -gt 0) { $context[$_.Substring(0,$split)]=$_.Substring($split+1) }
    }
    if ($context.packaged -ne 'true') { throw 'Run this script inside package context.' }
    $env:CPU_BLOOM_PACKAGED='1'
    $env:CPU_BLOOM_CONFIG_DIR=$context.settings
    $env:CPU_BLOOM_CACHE_DIR=$context.cache
    $env:CPU_BLOOM_PICTURES=$context.pictures
    $env:CPU_BLOOM_APP_DIR=$Installed
    $test = Start-Process "$Installed/java/bin/java.exe" -ArgumentList @('-Xmx320m','-cp',"`"$CheckClasses;$Installed/lib/*`"",'InstalledRuntimeCheck') -WindowStyle Hidden -RedirectStandardOutput "$OutputDirectory/installed-runtime.log" -RedirectStandardError "$OutputDirectory/installed-runtime.stderr.log" -Wait -PassThru
    @{ exitCode=$test.ExitCode } | ConvertTo-Json | Set-Content "$OutputDirectory/installed-runtime-state.json"
} catch { $_ | Out-String | Set-Content "$OutputDirectory/installed-runtime-error.txt" }
