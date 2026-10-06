$ErrorActionPreference = 'Stop'
$engineDir = Join-Path $PSScriptRoot '.engine'
$engine = Join-Path $engineDir 'Godot_v4.5.1-stable_win64.exe'
$archiveName = 'Godot_v4.5.1-stable_win64.exe.zip'
$checksum = 'ab84df90ead5a888530faaabe744a27678ef7635068883900174fae37f7fc6178d033b551d88963c7dc2466580915a582bbc79aca97c19085900655761f56a27'

if (-not (Test-Path $engine)) {
    Write-Host 'Downloading the official Godot runtime (first launch only)...'
    New-Item -ItemType Directory -Force -Path $engineDir | Out-Null
    $archive = Join-Path $engineDir $archiveName
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/godotengine/godot/releases/download/4.5.1-stable/$archiveName" -OutFile $archive
    $actual = (Get-FileHash -Algorithm SHA512 -Path $archive).Hash.ToLowerInvariant()
    if ($actual -ne $checksum) {
        Remove-Item $archive -Force
        throw 'Runtime checksum mismatch. Download was discarded.'
    }
    Expand-Archive -Force -Path $archive -DestinationPath $engineDir
    Remove-Item $archive -Force
}

& $engine --path $PSScriptRoot
exit $LASTEXITCODE

