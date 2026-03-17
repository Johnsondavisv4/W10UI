if ($PSVersionTable.PSVersion.Major -le 5) {
    Write-Host "Detectado PowerShell antiguo. Reiniciando en PowerShell 7..." -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList "-File `"$PSCommandPath`""
    exit
}

$BaseDir = $PSScriptRoot
$ConfigPath = Join-Path $BaseDir "data.ini"
$BinDir = Join-Path $BaseDir "bin"
$AriaPath = Join-Path $BinDir "aria2c.exe"

if (Test-Path (Join-Path $BaseDir "uup-converter-wimlib")) {
    $WorkDir = Join-Path $BaseDir "uup-converter-wimlib"
} else {
    $WorkDir = $BaseDir
}

$DirUUPs = Join-Path $WorkDir "UUPs"

function GetID {
    param ([string]$IniPath)

    if (-not (Test-Path $IniPath)) {
        Write-Error "No se encontro data.ini."
        exit 1
    }

    $version = (Get-Content $IniPath | Where-Object { $_ -match '^Version=' } | Select-Object -First 1) -replace '^Version=', ''
    $arch = (Get-Content $IniPath | Where-Object { $_ -match '^Arch=' } | Select-Object -First 1) -replace '^Arch=', ''
    $rev = (Get-Content $IniPath | Where-Object { $_ -match '^Rev=' } | Select-Object -First 1) -replace '^Rev=', ''
    $lang = (Get-Content $IniPath | Where-Object { $_ -match '^Lang=' } | Select-Object -First 1) -replace '^Lang=', ''

    if (-not $version -or -not $arch -or -not $lang) {
        Write-Error "data.ini debe contener Version, Arch y Lang."
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

    return @{ uuid = $match.uuid; lang = $lang }
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
        [string]$IniPath,
        [string]$TargetDir
    )

    $idData = GetID -IniPath $IniPath
    $id = $idData.uuid
    $Lang = $idData.lang
    
    $ApiUrlApps = "https://uupdump.net/get.php?id=$id&pack=neutral&edition=app&aria2=2"
    $ApiUrlOS   = "https://uupdump.net/get.php?id=$id&pack=$Lang&edition=professional&aria2=2"

    if (-not (Test-Path $AriaExe)) {
        Get-Aria -TargetPath $AriaExe
    }
    
    $BinDir = Split-Path -Parent $AriaExe

    Write-Host "Conectando a UUP Dump..." -ForegroundColor Cyan
    $rawApps = Invoke-WebRequest -Uri $ApiUrlApps -UseBasicParsing
    
    Write-Host "Buscando archivos objetivos en la respuesta..." -ForegroundColor Cyan
    $textoApps = $rawApps.Content
    
    if (!(Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir | Out-Null }

    $RegexFiltroApps = '(?mi)http[^\n]+\n\s*out=[^\n]+language-(?!es)[^\n]+\n\s*checksum=[^\n]+\n*'
    $textoAppsFiltrado = $textoApps -replace $RegexFiltroApps, ''

    $AppsTxt = Join-Path $BinDir "Apps.txt"
    $textoAppsFiltrado | Set-Content -Path $AppsTxt -Encoding UTF8

    Write-Host "Obteniendo lista de descarga total..." -ForegroundColor Cyan
    $rawOS = Invoke-WebRequest -Uri $ApiUrlOS -UseBasicParsing
    $textoOS = $rawOS.Content

    $OsTxt = Join-Path $BinDir "Os.txt"
    $textoOS | Set-Content -Path $OsTxt -Encoding UTF8

    Write-Host "Iniciando descarga..." -ForegroundColor Green

    if (Test-Path $AppsTxt) {
        Write-Host "-> Bajando: Store Apps"
        & $AriaExe --no-conf --allow-overwrite=true --auto-file-renaming=false -x 16 -s 16 -d $TargetDir -i $AppsTxt
    }
    
    if (Test-Path $OsTxt) {
        Write-Host "-> Bajando: Archivos Base"
        & $AriaExe --no-conf --allow-overwrite=true --auto-file-renaming=false -x 16 -s 16 -d $TargetDir -i $OsTxt
    }

    Write-Host "Descarga completada." -ForegroundColor Cyan

    if (Test-Path $BinDir) {
        Remove-Item -Path $BinDir -Recurse -Force
    }
}

Main -AriaExe $AriaPath -IniPath $ConfigPath -TargetDir $DirUUPs
