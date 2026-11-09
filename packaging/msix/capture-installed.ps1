param([Parameter(Mandatory)][string]$Installed, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
try {
    foreach ($theme in @('bloom','orchid','poppy','ridge')) {
        $capture = Join-Path $OutputDirectory "$theme.png"
        if (Test-Path -LiteralPath $capture) { throw "Use a fresh capture directory: $capture" }
        $env:CPU_BLOOM_SNAPSHOT = $capture
        Start-Process -FilePath "$Installed/cpu_bloom.exe" -ArgumentList "--theme=$theme" -WorkingDirectory $Installed
        $deadline = (Get-Date).AddSeconds(45)
        while (!(Test-Path -LiteralPath $capture) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        if (!(Test-Path -LiteralPath $capture)) { throw "Theme did not produce a snapshot: $theme" }
        Start-Sleep -Seconds 2
    }
    'PASS: all four installed themes rendered snapshots' | Set-Content "$OutputDirectory/capture-result.txt"
} catch {
    $_ | Out-String | Set-Content "$OutputDirectory/capture-error.txt"
} finally { Remove-Item Env:CPU_BLOOM_SNAPSHOT -ErrorAction SilentlyContinue }
