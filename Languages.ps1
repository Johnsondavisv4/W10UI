if ($PSVersionTable.PSVersion.Major -le 5) {
    Write-Host "Detectado PowerShell antiguo. Reiniciando en PowerShell 7..." -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList "-File `"$PSCommandPath`""
    exit
}

$BaseDir = $PSScriptRoot
$ConfigPath = Join-Path $BaseDir "data.ini"
$BinDir = Join-Path $BaseDir "bin"
$AriaPath = Join-Path $BinDir "aria2c.exe"

if (Test-Path (Join-Path $BaseDir "W10MUI")) {
    $WorkDir = Join-Path $BaseDir "W10MUI"
} else {
    $WorkDir = $BaseDir
}

$DirLangs = Join-Path $WorkDir "Langs"
$DirFODs = Join-Path (Join-Path $WorkDir "OnDemand") "x64"

function GetID {
    param ([string]$IniPath)

    if (-not (Test-Path $IniPath)) {
        Write-Error "No se encontro data.ini."
        exit 1
    }

    $version = (Get-Content $IniPath | Where-Object { $_ -match '^Version=' } | Select-Object -First 1) -replace '^Version=', ''
    $arch = (Get-Content $IniPath | Where-Object { $_ -match '^Arch=' } | Select-Object -First 1) -replace '^Arch=', ''
    $rev = (Get-Content $IniPath | Where-Object { $_ -match '^Rev=' } | Select-Object -First 1) -replace '^Rev=', ''

    if (-not $version -or -not $arch) {
        Write-Error "data.ini debe contener Version y Arch."
        exit 1
    }

    if (-not $rev) {
        $rev = "latest"
    }

    $isLatest = $rev -ieq "latest"
    if (-not $isLatest -and $rev -notmatch '^\d+$') {
        Write-Error "Rev debe ser 'latest' o un numero."
        exit 1
    }

    $searchTerms = if ($isLatest) { "$version $arch" } else { "$version $rev $arch" }
    $query = [uri]::EscapeDataString($searchTerms)
    $url = "https://api.uupdump.net/listid.php?search=$query"
    $resp = Invoke-RestMethod -Uri $url

    $items = $resp.response.builds.PSObject.Properties | ForEach-Object { $_.Value }
    $match = $items |
        Where-Object {
            $_.arch -eq $arch -and
            $_.title -match [regex]::Escape($version) -and
            ($isLatest -or $_.title -match [regex]::Escape($rev))
        } |
        Select-Object -First 1

    if (-not $match) {
        Write-Error "No se encontro UpdateID para Version=$version, Rev=$rev y Arch=$arch."
        exit 1
    }

    return $match.uuid
}

function Get-Aria {
    param ([string]$TargetPath)

    $ariaUrl = "https://uupdump.net/misc/aria2c.exe"
    $ariaDir = Split-Path -Parent $TargetPath

    if (-not (Test-Path $ariaDir)) {
        New-Item -ItemType Directory -Path $ariaDir | Out-Null
    }

    Write-Host "Descargando aria2c.exe..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $ariaUrl -OutFile $TargetPath
}

function Main {
    param (
        [string]$AriaExe,
        [string]$LangsDir,
        [string]$FodsDir,
        [string]$IniPath
    )

    $id = GetID -IniPath $IniPath
    $ApiUrl = "https://uupdump.net/get.php?id=$id&aria2=2"

    if (-not (Test-Path $AriaExe)) {
        Get-Aria -TargetPath $AriaExe
    }

    Write-Host "Conectando a UUP Dump..." -ForegroundColor Cyan
    $raw = Invoke-WebRequest -Uri $ApiUrl -UseBasicParsing

    $texto = $raw.Content

    if (!(Test-Path $LangsDir)) { New-Item -ItemType Directory -Path $LangsDir | Out-Null }
    if (!(Test-Path $FodsDir)) { New-Item -ItemType Directory -Path $FodsDir | Out-Null }

    Write-Host "Buscando archivos objetivos en la respuesta..." -ForegroundColor Cyan

    $RegexPack = '(?mi)^http[^\n]+\n\s*out=.*(?:LanguagePack).*es-mx.*$'
    $RegexFOD  = '(?mi)^http[^\n]+\n\s*out=.*(?:LanguageFeatures).*es-mx.*$'

    $MatchesPack = [regex]::Matches($texto, $RegexPack)
    $MatchesFOD  = [regex]::Matches($texto, $RegexFOD)

    if ($MatchesPack.Count -eq 0 -and $MatchesFOD.Count -eq 0) {
        Write-Error "No se encontraron descargas coincidentes en la respuesta."
        exit 1
    }

    $BinDir = Split-Path -Parent $AriaExe
    $LangTxt = Join-Path $BinDir "Lang.txt"
    $OnDemandTxt = Join-Path $BinDir "OnDemand.txt"

    if ($MatchesPack.Count -gt 0) {
        $packContent = ($MatchesPack | ForEach-Object { $_.Value }) -join "`n"
        $packContent | Set-Content -Path $LangTxt -Encoding UTF8
    }

    if ($MatchesFOD.Count -gt 0) {
        $fodContent = ($MatchesFOD | ForEach-Object { $_.Value }) -join "`n"
        $fodContent | Set-Content -Path $OnDemandTxt -Encoding UTF8
    }

    Write-Host "Se encontraron $($MatchesPack.Count) LanguagePacks y $($MatchesFOD.Count) FeaturesOnDemand. Iniciando descarga..." -ForegroundColor Green

    if (Test-Path $LangTxt) {
        Write-Host "-> Bajando: Language Packs"
        & $AriaExe --no-conf --allow-overwrite=true --auto-file-renaming=false -x 16 -s 16 -j 16 -d $LangsDir -i $LangTxt
    }

    if (Test-Path $OnDemandTxt) {
        Write-Host "-> Bajando: Features On Demand"
        & $AriaExe --no-conf --allow-overwrite=true --auto-file-renaming=false -x 16 -s 16 -j 16 -d $FodsDir -i $OnDemandTxt
    }

    Write-Host "¡Clasificación y descarga completadas! Archivos listos en \Langs y \OnDemand\x64" -ForegroundColor Cyan

    if (Test-Path $BinDir) {
        Remove-Item -Path $BinDir -Recurse -Force
    }
}

Main -AriaExe $AriaPath -LangsDir $DirLangs -FodsDir $DirFODs -IniPath $ConfigPath