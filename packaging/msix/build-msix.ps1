[CmdletBinding()]
param(
    [ValidateSet('Test','Store')][string]$Mode = 'Test',
    [string]$ConfigFile,
    [string]$ProcessingRoot = "$env:LOCALAPPDATA\CPU-Bloom-Build\Processing",
    [string]$JreArchive,
    [string]$Version = '0.3.0.0'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lock = Get-Content (Join-Path $PSScriptRoot 'inputs.lock.json') -Raw | ConvertFrom-Json
if (!$JreArchive) { $JreArchive = Join-Path $repo 'dist/windows-jre.zip' }
if ($Mode -eq 'Store') {
    if (!$ConfigFile) { throw 'Store builds require assigned Partner Center identity and reviewed release configuration.' }
    $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
    foreach ($key in @('IdentityName','Publisher','PublisherDisplayName','DisplayName','Version','PrivacyUrl','SupportUrl')) {
        if ([string]::IsNullOrWhiteSpace($config.$key)) { throw "Missing Store configuration: $key" }
    }
    if ($config.IdentityName -match '(?i)^CpuBloom\.LocalTest$|placeholder|example' -or $config.Publisher -match '(?i)Local Test|OID\.2\.25\.311729368913984317654407730594956997722') { throw 'Test identities cannot be submitted to the Store.' }
    foreach ($key in @('PrivacyUrl','SupportUrl')) {
        $uri = [uri]$config.$key
        if (!$uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -match '^(localhost|example\.)') { throw "Invalid public HTTPS URL: $key" }
    }
    if ($config.AssetRightsReviewed -isnot [bool] -or $config.ThirdPartyNoticesReviewed -isnot [bool] -or !$config.AssetRightsReviewed -or !$config.ThirdPartyNoticesReviewed) { throw 'Asset rights and third-party license obligations must be reviewed before a Store build.' }
    $Version = $config.Version
} else {
    # Deliberately isolated unsigned namespace for LOCAL testing only. This is
    # never represented as an assigned Partner Center identity.
    $config = [pscustomobject]@{
        IdentityName='CpuBloom.LocalTest'
        Publisher='CN=CPU Bloom Local Test, OID.2.25.311729368913984317654407730594956997722=1'
        PublisherDisplayName='CPU Bloom Local Test'
        DisplayName='CPU Bloom (Local Test)'
        Version=$Version
    }
}
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$' -or ($Version.Split('.') | Where-Object { [int]$_ -gt 65535 })) { throw 'Use a four-part package version ending in .0, with components <= 65535.' }
& python (Join-Path $PSScriptRoot 'verify-inputs.py') $ProcessingRoot $JreArchive
if ($LASTEXITCODE) { throw 'Input verification failed' }
$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10'
$sdkBin = Join-Path $sdkRoot "bin/$($lock.windowsSdk)/x64"
$sdkInclude = Join-Path $sdkRoot "Include/$($lock.windowsSdk)"
$sdkLib = Join-Path $sdkRoot "Lib/$($lock.windowsSdk)"
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Install Visual Studio C++ Build Tools.' }
$msvc = Join-Path $vs "VC/Tools/MSVC/$($lock.msvc)"
$cl = Join-Path $msvc 'bin/Hostx64/x64/cl.exe'
foreach ($required in @($cl, (Join-Path $sdkBin 'makeappx.exe'))) { if (!(Test-Path $required)) { throw "Pinned tool missing: $required" } }
$build = Join-Path $repo ('dist/msix/' + $Mode.ToLower() + '-' + $Version + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$stage = Join-Path $build 'package'
$export = Join-Path $build 'export'
New-Item -ItemType Directory -Force $stage | Out-Null
$tool = Start-Process -FilePath (Join-Path $ProcessingRoot 'Processing.exe') -ArgumentList @('cli', "--sketch=`"$repo\cpu_bloom`"", "--output=`"$export`"", '--variant=windows-amd64', '--no-java', '--export') -WindowStyle Hidden -RedirectStandardOutput (Join-Path $build 'processing.log') -RedirectStandardError (Join-Path $build 'processing.err') -Wait -PassThru
if ($tool.ExitCode -ne 0 -or !(Test-Path "$export/lib/cpu_bloom.jar")) { throw "Processing failed; inspect $build" }
New-Item -ItemType Directory "$stage/lib" | Out-Null
Get-ChildItem "$export/lib/*.jar" | Where-Object { $_.Name -notlike '*-natives-*' -or $_.Name -like '*-natives-windows-amd64.jar' } | Copy-Item -Destination "$stage/lib"
Copy-Item "$export/data" "$stage/data" -Recurse
Expand-Archive -LiteralPath $JreArchive -DestinationPath "$build/runtime"
$runtime = @(Get-ChildItem "$build/runtime" -Directory)
if ($runtime.Count -ne 1) { throw 'Unexpected Java archive layout' }
Copy-Item -LiteralPath $runtime[0].FullName -Destination "$stage/java" -Recurse
Copy-Item "$PSScriptRoot/Assets" "$stage/Assets" -Recurse
Copy-Item "$repo/LICENSE" "$stage/LICENSE.txt"
Copy-Item "$PSScriptRoot/THIRD-PARTY-NOTICES.md" "$stage/THIRD-PARTY-NOTICES.md"
Copy-Item "$PSScriptRoot/ASSET-PROVENANCE.md" "$stage/ASSET-PROVENANCE.md"
Copy-Item "$PSScriptRoot/privacy-policy.draft.md" "$stage/privacy-policy.draft.md"
$previousInclude = $env:INCLUDE; $previousLib = $env:LIB
try {
    $env:INCLUDE = "$msvc/include;$sdkInclude/ucrt;$sdkInclude/shared;$sdkInclude/um;$sdkInclude/winrt;$sdkInclude/cppwinrt"
    $env:LIB = "$msvc/lib/x64;$sdkLib/ucrt/x64;$sdkLib/um/x64"
    $common = @('/nologo','/std:c++17','/EHsc','/O2','/MT','/W4','/guard:cf','/Brepro','/DUNICODE','/D_UNICODE')
    & $cl @common "$PSScriptRoot/native/launcher.cpp" "/Fo$build/launcher.obj" "/Fe$stage/cpu_bloom.exe" /link /SUBSYSTEM:WINDOWS /DYNAMICBASE /NXCOMPAT windowsapp.lib shell32.lib ole32.lib user32.lib
    if ($LASTEXITCODE) { throw 'Launcher compilation failed' }
    & $cl @common /DCPU_BLOOM_STARTUP "$PSScriptRoot/native/launcher.cpp" "/Fo$build/startup.obj" "/Fe$stage/cpu_bloom_startup.exe" /link /SUBSYSTEM:WINDOWS /DYNAMICBASE /NXCOMPAT windowsapp.lib shell32.lib ole32.lib user32.lib
    if ($LASTEXITCODE) { throw 'Startup launcher compilation failed' }
    & $cl @common "$PSScriptRoot/native/store-bridge.cpp" "/Fo$build/bridge.obj" "/Fe$stage/store-bridge.exe" /link /SUBSYSTEM:CONSOLE /DYNAMICBASE /NXCOMPAT windowsapp.lib shell32.lib ole32.lib
    if ($LASTEXITCODE) { throw 'Store bridge compilation failed' }
} finally { $env:INCLUDE = $previousInclude; $env:LIB = $previousLib }
$manifest = Get-Content "$PSScriptRoot/AppxManifest.xml" -Raw
foreach ($key in @('IdentityName','Publisher','PublisherDisplayName','DisplayName','Version')) {
    $manifest = $manifest.Replace("@@$key@@", [System.Security.SecurityElement]::Escape([string]$config.$key))
}
[xml]$null = $manifest
[IO.File]::WriteAllText("$stage/AppxManifest.xml", $manifest, [Text.UTF8Encoding]::new($false))
& python "$PSScriptRoot/inventory.py" $stage
if ($LASTEXITCODE) { throw 'Dependency inventory failed' }
$package = Join-Path $build "cpu-bloom-$Version-x64.msix"
& "$sdkBin/makeappx.exe" pack /d $stage /p $package /o *> "$build/makeappx.log"
if ($LASTEXITCODE) { throw 'MSIX packaging or manifest validation failed' }
$metadata = [ordered]@{mode=$Mode; package=$package; stage=$stage; version=$Version; identity=$config.IdentityName; sha256=(Get-FileHash $package).Hash; sdk=$lock.windowsSdk; msvc=$lock.msvc; inputLock=(Get-FileHash "$PSScriptRoot/inputs.lock.json").Hash}
$metadata | ConvertTo-Json | Set-Content "$build/build-result.json"
$metadata | ConvertTo-Json | Set-Content "$repo/dist/msix/latest-$($Mode.ToLower()).json"
Write-Output "Built $package"
