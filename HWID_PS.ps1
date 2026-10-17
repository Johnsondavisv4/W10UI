[CmdletBinding()]
param (
    [switch]$Unattended,
    [switch]$NoEditionChange,
    [switch]$DebugMode
)

$script:WindowsAppId = "55c92734-d682-4d71-983e-d6ec3f16059f"
$script:TicketDirectory = "$env:ProgramData\Microsoft\Windows\ClipSVC\GenuineTicket"
$script:RequiredServices = @("ClipSVC", "sppsvc", "wlidsvc", "KeyIso", "LicenseManager", "Winmgmt")

function Get-EditionCatalog {
    [CmdletBinding()]
    param()
    $Catalog = [System.Collections.Generic.List[PSCustomObject]]::new()
    $RawData = @(
        "8b351c9c-f398-4515-9900-09df49427262_XGVPP-NMH47-7TTHJ-W3FW7-8HV2C_4_X19-99683_Enterprise",
        "c83cef07-6b72-4bbc-a28f-a00386872839_3V6Q6-NQXCX-V8YXR-9QCYV-QPFCT_27_X19-98746_EnterpriseN",
        "4de7cb65-cdf1-4de9-8ae8-e3cce27b9f2c_VK7JG-NPHTM-C97JM-9MPGT-3V66T_48_X19-98841_Professional",
        "9fbaf5d6-4d83-4422-870d-fdda6e5858aa_2B87N-8KFHP-DKV6R-Y2C8J-PKCKT_49_X19-98859_ProfessionalN",
        "f742e4ff-909d-4fe9-aacb-3231d24a0c58_4CPRK-NM3K3-X6XXQ-RXX86-WXCHW_98_X19-98877_CoreN",
        "1d1bac85-7365-4fea-949a-96978ec91ae0_N2434-X9D7W-8PF6X-8DV9T-8TYMD_99_X19-99652_CoreCountrySpecific",
        "3ae2cc14-ab2d-41f4-972f-5e20142771dc_BT79Q-G7N6G-PGBYW-4YWX6-6F4BT_100_X19-99661_CoreSingleLanguage",
        "2b1f36bb-c1cd-4306-bf5c-a0367c2d97d8_YTMG3-N6DKC-DKB77-7M9GH-8HVX7_101_X19-98868_Core",
        "2a6137f3-75c0-4f26-8e3e-d83d802865a4_XKCNC-J26Q9-KFHD2-FKTHY-KD72Y_119_X19-99606_PPIPro",
        "e558417a-5123-4f6f-91e7-385c1c7ca9d4_YNMGQ-8RYV3-4PGQ3-C8XTP-7CCBY_121_X19-98886_Education",
        "c5198a66-e435-4432-89cf-ec777c9d0352_84NGF-MHBT6-FXBX8-QWJK7-DRR8H_122_X19-98892_EducationN",
        "d06934ee-5448-4fd1-964a-cd077618aa06_43TBQ-NH92J-XKTM7-KT3KK-P39PB_125_X21-83233_EnterpriseS_RS5",
        "706e0cfd-23f4-43bb-a9af-1a492b9f1302_NK96Y-D9CD8-W44CQ-R8YTK-DYJWX_125_X21-05035_EnterpriseS_RS1",
        "faa57748-75c8-40a2-b851-71ce92aa8b45_FWN7H-PF93Q-4GGP8-M8RF3-MDWWW_125_X19-99617_EnterpriseS_TH",
        "3d1022d8-969f-4222-b54b-327f5a5af4c9_2DBW3-N2PJG-MVHW3-G7TDK-9HKR4_126_X21-04921_EnterpriseSN_RS1",
        "60c243e1-f90b-4a1b-ba89-387294948fb6_NTX6B-BRYC2-K6786-F6MVQ-M7V2X_126_X19-98770_EnterpriseSN_TH",
        "eb6d346f-1c60-4643-b960-40ec31596c45_DXG7C-N36C4-C4HTG-X4T3X-2YV77_161_X21-43626_ProfessionalWorkstation",
        "89e87510-ba92-45f6-8329-3afa905e3e83_WYPNQ-8C467-V2W6J-TX4WX-WT2RQ_162_X21-43644_ProfessionalWorkstationN",
        "62f0c100-9c53-4e02-b886-a3528ddfe7f6_8PTT6-RNW4C-6V7J2-C2D3X-MHBPB_164_X21-04955_ProfessionalEducation",
        "13a38698-4a49-4b9e-8e83-98fe51110953_GJTYN-HDMQY-FRR76-HVGC7-QPF8P_165_X21-04956_ProfessionalEducationN",
        "df96023b-dcd9-4be2-afa0-c6c871159ebe_NJCF7-PW8QT-3324D-688JX-2YV66_175_X21-41295_ServerRdsh",
        "d4ef7282-3d2c-4cf0-9976-8854e64a8d1e_V3WVW-N2PV2-CGWC3-34QGF-VMJ2C_178_X21-32983_Cloud",
        "af5c9381-9240-417d-8d35-eb40cd03e484_NH9J3-68WK7-6FB93-4K3DF-DJ4F6_179_X21-32987_CloudN",
        "8ab9bdd1-1f67-4997-82d9-8878520837d9_XQQYW-NFFMW-XJPBH-K8732-CKFFD_188_X21-99378_IoTEnterprise",
        "ed655016-a9e8-4434-95d9-4345352c2552_QPM6N-7J2WJ-P88HH-P3YRH-YY74H_191_X21-99682_IoTEnterpriseS_VB",
        "6c4de1b8-24bb-4c17-9a77-7b939414c298_CGK42-GYN6Y-VD22B-BX98W-J8JXD_191_X23-12617_IoTEnterpriseS_Ge",
        "d4bdc678-0a4b-4a32-a5b3-aaa24c3b0f24_K9VKN-3BGWV-Y624W-MCRMQ-BHDCD_202_X22-53884_CloudEditionN",
        "92fb8726-92a8-4ffc-94ce-f82e07444653_KY7PN-VR6RX-83W6Y-6DDYQ-T6R4W_203_X22-53847_CloudEdition",
        "5a85300a-bfce-474f-ac07-a30983e3fb90_N979K-XWD77-YW3GB-HBGH6-D32MH_205_X23-15042_IoTEnterpriseSK",
        "80083eae-7031-4394-9e88-4901973d56fe_P8Q7T-WNK7X-PMFXY-VXHBG-RRK69_206_X23-62084_IoTEnterpriseK",
        "1bc2140b-285b-4351-b99c-26a126104b29_TMP2N-KGFHJ-PWM6F-68KCQ-3PJBP_210_X23-60513_WNC"
    )

    foreach ($Item in $RawData) {
        $Split = $Item -split '_'
        $Catalog.Add([PSCustomObject]@{
                ActivationId = $Split[0]
                ProductKey   = $Split[1]
                SkuId        = [int]$Split[2]
                ProductId    = $Split[3]
                EditionName  = ($Split[4..($Split.Count - 1)] -join '_')
            })
    }

    return $Catalog
}

function Get-EditionFallbackCatalog {
    [CmdletBinding()]
    param()

    $FallbackCatalog = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $RawData = @(
        "125_EnterpriseS-2021_cce9d2de-98ee-4ce2-8113-222620c64a27_ed655016-a9e8-4434-95d9-4345352c2552_QPM6N-7J2WJ-P88HH-P3YRH-YY74H_191_X21-99682_IoTEnterpriseS-2021",
        "125_EnterpriseS-2024_f6e29426-a256-4316-88bf-cc5b0f95ec0c_6c4de1b8-24bb-4c17-9a77-7b939414c298_CGK42-GYN6Y-VD22B-BX98W-J8JXD_191_X23-12617_IoTEnterpriseS-2024",
        "138_ProfessionalSingleLanguage_a48938aa-62fa-4966-9d44-9f04da3f72f2_4de7cb65-cdf1-4de9-8ae8-e3cce27b9f2c_VK7JG-NPHTM-C97JM-9MPGT-3V66T_48_X19-98841_Professional",
        "139_ProfessionalCountrySpecific_f7af7d09-40e4-419c-a49b-eae366689ebd_4de7cb65-cdf1-4de9-8ae8-e3cce27b9f2c_VK7JG-NPHTM-C97JM-9MPGT-3V66T_48_X19-98841_Professional",
        "139_ProfessionalCountrySpecific-Zn_01eb852c-424d-4060-94b8-c10d799d7364_4de7cb65-cdf1-4de9-8ae8-e3cce27b9f2c_VK7JG-NPHTM-C97JM-9MPGT-3V66T_48_X19-98841_Professional"
    )

    foreach ($Item in $RawData) {
        $Split = $Item -split '_'
        $FallbackCatalog.Add([PSCustomObject]@{
                SourceSkuId       = [int]$Split[0]
                SourceEditionName = $Split[1]
                SourceActId       = $Split[2]
                TargetActId       = $Split[3]
                TargetProductKey  = $Split[4]
                TargetSkuId       = [int]$Split[5]
                TargetProductId   = $Split[6]
                TargetEditionName = $Split[7]
            })
    }
    
    return $FallbackCatalog
}

function Resolve-EditionFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$CurrentSkuId,
        [string[]]$CurrentActivationId
    )

    $FallbackCatalog = Get-EditionFallbackCatalog

    $Match = $FallbackCatalog | Where-Object { $_.SourceSkuId -eq $CurrentSkuId -and $_.SourceActId -in $CurrentActivationId }

    if ($Match) {
        return $Match
    }
    
    return $null
}

function Test-IsAdministrator {
    [CmdletBinding()]
    param()

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-ArchitecturePaths {
    [CmdletBinding()]
    param()

    $SysNativePath = "$env:SystemRoot\Sysnative"
    if (Test-Path $SysNativePath) {
        return $SysNativePath
    }
    
    return "$env:SystemRoot\System32"
}

function Test-OperatingSystemBuild {
    [CmdletBinding()]
    param()

    $Build = [System.Environment]::OSVersion.Version.Build
    
    if (Test-Path "$env:Systemdrive\Users\WDAGUtilityAccount") {
        throw "Entorno Windows Sandbox detectado. El proceso de licencias no está soportado en este espacio aislado."
    }

    if ($Build -lt 10240) {
        throw "Versión de sistema operativo no soportada [$Build]. Se requiere como mínimo Windows 10 o Windows 11."
    }

    $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($OSInfo.Caption -match "Server") {
        throw "HWID no es soportado en plataformas Windows Server. Use canales de activación alternativos."
    }

    if ($OSInfo.Caption -match "Eval" -or (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name EditionID -ErrorAction SilentlyContinue).EditionID -match "Eval") {
        throw "Las ediciones de evaluación no admiten el canal de licencias digitales permanentes (HWID)."
    }

    return $Build
}

function Test-IsPermanentlyActivated {
    [CmdletBinding()]
    param()

    $Filter = "LicenseStatus=1 AND GracePeriodRemaining=0 AND PartialProductKey IS NOT NULL AND LicenseDependsOn IS NULL"
    $Products = Get-CimInstance -ClassName "SoftwareLicensingProduct" -Filter $Filter -ErrorAction SilentlyContinue

    foreach ($Product in $Products) {
        if ($Product.Name -match "Windows") {
            return $true
        }
    }
    return $false
}

function Test-LicensingServicesStatus {
    [CmdletBinding()]
    param()

    foreach ($Service in $script:RequiredServices) {
        $Status = Get-Service -Name $Service -ErrorAction SilentlyContinue
        
        if (-not $Status) {
            return $false
        }

        if ($Status.StartType -eq 'Disabled') {
            Set-Service -Name $Service -StartupType Manual -ErrorAction SilentlyContinue
        }

        if ($Status.Status -ne 'Running') {
            Start-Service -Name $Service -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
    return $true
}

function Get-InstalledWindowsSku {
    [CmdletBinding()]
    param()

    try {
        $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [int]$OSInfo.OperatingSystemSKU
    }
    catch {
        $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions"
        $RegValue = Get-ItemProperty -Path $RegPath -Name "OSProductPfn" -ErrorAction SilentlyContinue

        if ($null -ne $RegValue -and $RegValue.OSProductPfn -match "Microsoft\.Windows\.([^.]+)\.") {
            $SkuToken = $Matches[1]
            if ($SkuToken -match "^\d+$") {
                return [int]$SkuToken
            }
        }

        throw "Fallo al recuperar el identificador SKU de Windows a bajo nivel."
    }
}

function Get-SystemActivationIds {
    [CmdletBinding()]
    param()

    $DetectedIds = [System.Collections.Generic.List[string]]::new()
    $WindowsAppId = "55c92734-d682-4d71-983e-d6ec3f16059f"

    try {
        $Products = Get-CimInstance -ClassName "SoftwareLicensingProduct" -Filter "ApplicationID='$WindowsAppId'" -ErrorAction Stop
        foreach ($Product in $Products) {
            if (-not [string]::IsNullOrWhiteSpace($Product.ID)) {
                $CleanId = $Product.ID.Trim().ToLower()
                if (-not $DetectedIds.Contains($CleanId)) {
                    $DetectedIds.Add($CleanId)
                }
            }
        }
    }
    catch {
    }

    $TokensPath = "$env:SystemRoot\System32\spp\tokens\skus"
    if (Test-Path $TokensPath) {
        try {
            $LicenseFiles = Get-ChildItem -Path $TokensPath -Recurse -Filter "*.xrm-ms" -ErrorAction SilentlyContinue
            foreach ($File in $LicenseFiles) {
                $Content = [IO.File]::ReadAllText($File.FullName)
                
                $Regex = [regex]'name="productSkuId">\{([0-9a-fA-F\-]+)\}'
                $RegexMatches = $Regex.Matches($Content)
                
                foreach ($Match in $RegexMatches) {
                    $CleanGuid = $Match.Groups[1].Value.Trim().ToLower()
                    if (-not $DetectedIds.Contains($CleanGuid)) {
                        $DetectedIds.Add($CleanGuid)
                    }
                }
            }
        }
        catch {
        }
    }

    return $DetectedIds
}

function Get-InstalledWindowsEditionName {
    [CmdletBinding()]
    param()

    $WinOSName = $null

    try {
        $SignatureLines = @(
            "[DllImport(""winbrand.dll"", CharSet = CharSet.Unicode)]"
            "public static extern string BrandingFormatString(string format);"
        )
        $Signature = $SignatureLines -join [Environment]::NewLine
        $WinBrandType = Add-Type -MemberDefinition $Signature -Name "WinBrandApi" -Namespace "WinBrand" -PassThru -ErrorAction Stop
        
        $RawBrand = $WinBrandType::BrandingFormatString('%WINDOWS_LONG%')

        if (-not [string]::IsNullOrWhiteSpace($RawBrand)) {
            $WinOSName = $RawBrand -replace [string][char]0xa9, '' -replace [string][char]0xae, '' -replace [string][char]0x2122, ''
            $WinOSName = $WinOSName.Trim()
        }
    }
    catch {
    }

    if ([string]::IsNullOrWhiteSpace($WinOSName)) {
        try {
            $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
            $ProductName = (Get-ItemProperty -Path $RegPath -Name "ProductName" -ErrorAction SilentlyContinue).ProductName
            
            if ($ProductName) {
                $WinOSName = $ProductName
                
                if ([System.Environment]::OSVersion.Version.Build -ge 22000) {
                    $WinOSName = $WinOSName -replace "Windows 10", "Windows 11"
                }
            }
        }
        catch {
            $WinOSName = "Windows (Edición Desconocida)"
        }
    }

    return $WinOSName
}

function Set-ProductKeyViaWmi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProductKey
    )

    try {
        $LicensingService = Get-CimInstance -ClassName "SoftwareLicensingService" -ErrorAction Stop

        $KeyResult = Invoke-CimMethod -InputObject $LicensingService -MethodName "InstallProductKey" -Arguments @{ ProductKey = $ProductKey } -ErrorAction Stop

        if ($null -eq $KeyResult -or $null -eq $KeyResult.ReturnValue -or $KeyResult.ReturnValue -eq 0 -or $KeyResult.ReturnValue -eq 131073) {
            $null = Invoke-CimMethod -InputObject $LicensingService -MethodName "RefreshLicenseStatus" -ErrorAction SilentlyContinue
            return $true
        }
        
        return $false
    }
    catch {
        return $true
    }
}

function Invoke-SppServiceReevaluation {
    [CmdletBinding()]
    param()

    $RegPath = "Registry::HKU\S-1-5-20\Software\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\PersistedSystemState"

    if (Test-Path $RegPath) {
        Remove-ItemProperty -Path $RegPath -Name "State" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RegPath -Name "SuppressRulesEngine" -ErrorAction SilentlyContinue
    }

    Stop-Service -Name "sppsvc" -Force -ErrorAction SilentlyContinue

    Start-Service -Name "sppsvc" -ErrorAction SilentlyContinue
}

function Assert-ExecutionEnvironment {
    [CmdletBinding()]
    param()

    $IsAdmin = Test-IsAdministrator
    $script:SysPathNativa = Initialize-ArchitecturePaths

    if (-not $IsAdmin) {
        if ($script:DebugMode) {
            Write-Host "[-] Token de administrador no detectado. Solicitando elevación UAC..." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }

        $Arguments = @("-NoExit", "-File", """$PSCommandPath""")
        foreach ($Key in $PSBoundParameters.Keys) {
            if ($PSBoundParameters[$Key] -is [switch]) {
                if ($PSBoundParameters[$Key].ToBool()) { $Arguments += "-$Key" }
            }
            else {
                $Arguments += "-$Key"
                $Arguments += """$($PSBoundParameters[$Key])"""
            }
        }

        Start-Process -FilePath "powershell.exe" -ArgumentList $Arguments -Verb RunAs
        Exit
    }
}

function Assert-SystemHealth {
    [CmdletBinding()]
    param()

    $null = Test-OperatingSystemBuild

    if (-not (Test-LicensingServicesStatus)) {
        throw "Error de salud: Uno o más servicios críticos del motor de protección de software están ausentes o corruptos."
    }
}

function Get-EditionActivationConfig {
    [CmdletBinding()]
    param()

    $CurrentSku = Get-InstalledWindowsSku

    $Catalog = Get-EditionCatalog

    $SystemActivationIds = Get-SystemActivationIds

    $DirectMatch = $Catalog | Where-Object { $_.SkuId -eq $CurrentSku -and $_.ActivationId -in $SystemActivationIds }

    $SO_name = Get-InstalledWindowsEditionName

    if ($DirectMatch) {
        $ActivationConfig = [PSCustomObject]@{
            SkuId       = $DirectMatch.SkuId
            ProductID   = $DirectMatch.ProductId
            ProductKey  = $DirectMatch.ProductKey
            EditionName = $DirectMatch.EditionName
        }
    }
    else {
        $FallbackMatch = Resolve-EditionFallback -CurrentSkuId $CurrentSku -CurrentActivationId $SystemActivationIds

        if ($FallbackMatch) {
            if ($NoEditionChange) {
                throw "Error: La edición actual requiere cambio de SKU, pero se ha pasado la bandera de bloqueo -NoEditionChange."
            }

            $ActivationConfig = [PSCustomObject]@{
                SkuId       = $FallbackMatch.TargetSkuId
                ProductID   = $FallbackMatch.TargetProductId
                ProductKey  = $FallbackMatch.TargetProductKey                
                EditionName = $FallbackMatch.TargetEditionName
            }
        }
        else {
            throw "Error de catálogo: El SKU detectado [$CurrentSku] no es compatible con la activación digital HWID."
        }
    }

    if (@($DirectMatch).Count -gt 1) {
        $ActiveProduct = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"
        $ActiveIds = @($ActiveProduct | ForEach-Object { $_.ID.ToString().ToLower() })
        $SelectedMatch = $DirectMatch | Where-Object { $_.ActivationId -in $ActiveIds } | Select-Object -First 1
        if ($SelectedMatch) {
            $ActivationConfig.SkuId = $SelectedMatch.SkuId
            $ActivationConfig.ProductID = $SelectedMatch.ProductId
            $ActivationConfig.ProductKey = $SelectedMatch.ProductKey            
            $ActivationConfig.EditionName = $SelectedMatch.EditionName
        }
    }
    
    $ActivationConfig | Add-Member -NotePropertyName 'Name' -NotePropertyValue $SO_name
    return $ActivationConfig
}

function Set-GenericProductKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProductKey
    )

    $Result = Set-ProductKeyViaWmi -ProductKey $ProductKey

    if (-not $Result) {
        throw "Fallo crítico en la instalación de la clave de producto a través del subsistema de licencias WMI. Verifique la compatibilidad de los tokens."
    }
}

function Register-DigitalLicenseTicket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$SkuId,

        [Parameter(Mandatory = $true)]
        [string]$ProductID,

        [Parameter(Mandatory = $true)]
        [string]$ProductKey
    )

    if (-not (Test-Path $TicketDirectory)) {
        $null = New-Item -Path $TicketDirectory -ItemType Directory -Force
    }
    Get-ChildItem -Path $TicketDirectory -Include *.* -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue

    $SessionIdStr = "OSMajorVersion=5;OSMinorVersion=1;OSPlatformId=2;PP=0;Pfn=Microsoft.Windows.$SkuId.$ProductID`_8wekyb3d8bbwe;PKeyIID=221306452340115677963964261259250411589493550039199940431586886;"
    $SessionIdBase64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($SessionIdStr + [char]0))
    $PropertiesStr = "OA3xOriginalProductId=;OA3xOriginalProductKey=;SessionId=$SessionIdBase64;TimeStampClient=2022-10-11T12:00:00Z"

    [byte[]]$RsaKeyBlob = @(
        0x07, 0x02, 0x00, 0x00, 0x00, 0xA4, 0x00, 0x00, 0x52, 0x53, 0x41, 0x32, 0x00, 0x04, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x29, 0x87, 0xBA, 0x3F, 0x52, 0x90, 0x57, 0xD8, 0x12, 0x26, 0x6B, 0x38,
        0xB2, 0x3B, 0xF9, 0x67, 0x08, 0x4F, 0xDD, 0x8B, 0xF5, 0xE3, 0x11, 0xB8, 0x61, 0x3A, 0x33, 0x42,
        0x51, 0x65, 0x05, 0x86, 0x1E, 0x00, 0x41, 0xDE, 0xC5, 0xDD, 0x44, 0x60, 0x56, 0x3D, 0x14, 0x39,
        0xB7, 0x43, 0x65, 0xE9, 0xF7, 0x2B, 0xA5, 0xF0, 0xA3, 0x65, 0x68, 0xE9, 0xE4, 0x8B, 0x5C, 0x03,
        0x2D, 0x36, 0xFE, 0x28, 0x4C, 0xD1, 0x3C, 0x3D, 0xC1, 0x90, 0x75, 0xF9, 0x6E, 0x02, 0xE0, 0x58,
        0x97, 0x6A, 0xCA, 0x80, 0x02, 0x42, 0x3F, 0x6C, 0x15, 0x85, 0x4D, 0x83, 0x23, 0x6A, 0x95, 0x9E,
        0x38, 0x52, 0x59, 0x38, 0x6A, 0x99, 0xF0, 0xB5, 0xCD, 0x53, 0x7E, 0x08, 0x7C, 0xB5, 0x51, 0xD3,
        0x8F, 0xA3, 0x0D, 0xA0, 0xFA, 0x8D, 0x87, 0x3C, 0xFC, 0x59, 0x21, 0xD8, 0x2E, 0xD9, 0x97, 0x8B,
        0x40, 0x60, 0xB1, 0xD7, 0x2B, 0x0A, 0x6E, 0x60, 0xB5, 0x50, 0xCC, 0x3C, 0xB1, 0x57, 0xE4, 0xB7,
        0xDC, 0x5A, 0x4D, 0xE1, 0x5C, 0xE0, 0x94, 0x4C, 0x5E, 0x28, 0xFF, 0xFA, 0x80, 0x6A, 0x13, 0x53,
        0x52, 0xDB, 0xF3, 0x04, 0x92, 0x43, 0x38, 0xB9, 0x1B, 0xD9, 0x85, 0x54, 0x7B, 0x14, 0xC7, 0x89,
        0x16, 0x8A, 0x4B, 0x82, 0xA1, 0x08, 0x02, 0x99, 0x23, 0x48, 0xDD, 0x75, 0x9C, 0xC8, 0xC1, 0xCE,
        0xB0, 0xD7, 0x1B, 0xD8, 0xFB, 0x2D, 0xA7, 0x2E, 0x47, 0xA7, 0x18, 0x4B, 0xF6, 0x29, 0x69, 0x44,
        0x30, 0x33, 0xBA, 0xA7, 0x1F, 0xCE, 0x96, 0x9E, 0x40, 0xE1, 0x43, 0xF0, 0xE0, 0x0D, 0x0A, 0x32,
        0xB4, 0xEE, 0xA1, 0xC3, 0x5E, 0x9B, 0xC7, 0x7F, 0xF5, 0x9D, 0xD8, 0xF2, 0x0F, 0xD9, 0x8F, 0xAD,
        0x75, 0x0A, 0x00, 0xD5, 0x25, 0x43, 0xF7, 0xAE, 0x51, 0x7F, 0xB7, 0xDE, 0xB7, 0xAD, 0xFB, 0xCE,
        0x83, 0xE1, 0x81, 0xFF, 0xDD, 0xA2, 0x77, 0xFE, 0xEB, 0x27, 0x1F, 0x10, 0xFA, 0x82, 0x37, 0xF4,
        0x7E, 0xCC, 0xE2, 0xA1, 0x58, 0xC8, 0xAF, 0x1D, 0x1A, 0x81, 0x31, 0x6E, 0xF4, 0x8B, 0x63, 0x34,
        0xF3, 0x05, 0x0F, 0xE1, 0xCC, 0x15, 0xDC, 0xA4, 0x28, 0x7A, 0x9E, 0xEB, 0x62, 0xD8, 0xD8, 0x8C,
        0x85, 0xD7, 0x07, 0x87, 0x90, 0x2F, 0xF7, 0x1C, 0x56, 0x85, 0x2F, 0xEF, 0x32, 0x37, 0x07, 0xAB,
        0xB0, 0xE6, 0xB5, 0x02, 0x19, 0x35, 0xAF, 0xDB, 0xD4, 0xA2, 0x9C, 0x36, 0x80, 0xC6, 0xDC, 0x82,
        0x08, 0xE0, 0xC0, 0x5F, 0x3C, 0x59, 0xAA, 0x4E, 0x26, 0x03, 0x29, 0xB3, 0x62, 0x58, 0x41, 0x59,
        0x3A, 0x37, 0x43, 0x35, 0xE3, 0x9F, 0x34, 0xE2, 0xA1, 0x04, 0x97, 0x12, 0x9D, 0x8C, 0xAD, 0xF7,
        0xFB, 0x8C, 0xA1, 0xA2, 0xE9, 0xE4, 0xEF, 0xD9, 0xC5, 0xE5, 0xDF, 0x0E, 0xBF, 0x4A, 0xE0, 0x7A,
        0x1E, 0x10, 0x50, 0x58, 0x63, 0x51, 0xE1, 0xD4, 0xFE, 0x57, 0xB0, 0x9E, 0xD7, 0xDA, 0x8C, 0xED,
        0x7D, 0x82, 0xAC, 0x2F, 0x25, 0x58, 0x0A, 0x58, 0xE6, 0xA4, 0xF4, 0x57, 0x4B, 0xA4, 0x1B, 0x65,
        0xB9, 0x4A, 0x87, 0x46, 0xEB, 0x8C, 0x0F, 0x9A, 0x48, 0x90, 0xF9, 0x9F, 0x76, 0x69, 0x03, 0x72,
        0x77, 0xEC, 0xC1, 0x42, 0x4C, 0x87, 0xDB, 0x0B, 0x3C, 0xD4, 0x74, 0xEF, 0xE5, 0x34, 0xE0, 0x32,
        0x45, 0xB0, 0xF8, 0xAB, 0xD5, 0x26, 0x21, 0xD7, 0xD2, 0x98, 0x54, 0x8F, 0x64, 0x88, 0x20, 0x2B,
        0x14, 0xE3, 0x82, 0xD5, 0x2A, 0x4B, 0x8F, 0x4E, 0x35, 0x20, 0x82, 0x7E, 0x1B, 0xFE, 0xFA, 0x2C,
        0x79, 0x6C, 0x6E, 0x66, 0x94, 0xBB, 0x0A, 0xEB, 0xBA, 0xD9, 0x70, 0x61, 0xE9, 0x47, 0xB5, 0x82,
        0xFC, 0x18, 0x3C, 0x66, 0x3A, 0x09, 0x2E, 0x1F, 0x61, 0x74, 0xCA, 0xCB, 0xF6, 0x7A, 0x52, 0x37,
        0x1D, 0xAC, 0x8D, 0x63, 0x69, 0x84, 0x8E, 0xC7, 0x70, 0x59, 0xDD, 0x2D, 0x91, 0x1E, 0xF7, 0xB1,
        0x56, 0xED, 0x7A, 0x06, 0x9D, 0x5B, 0x33, 0x15, 0xDD, 0x31, 0xD0, 0xE6, 0x16, 0x07, 0x9B, 0xA5,
        0x94, 0x06, 0x7D, 0xC1, 0xE9, 0xD6, 0xC8, 0xAF, 0xB4, 0x1E, 0x2D, 0x88, 0x06, 0xA7, 0x63, 0xB8,
        0xCF, 0xC8, 0xA2, 0x6E, 0x84, 0xB3, 0x8D, 0xE5, 0x47, 0xE6, 0x13, 0x63, 0x8E, 0xD1, 0x7F, 0xD4,
        0x81, 0x44, 0x38, 0xBF
    )

    $Rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
    $Rsa.ImportCspBlob($RsaKeyBlob)
    
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    $BytesToSign = [Text.Encoding]::UTF8.GetBytes($PropertiesStr)
    $Hash = $Sha256.ComputeHash($BytesToSign)
    
    $SignatureBytes = $Rsa.SignHash($Hash, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $SignatureStr = [Convert]::ToBase64String($SignatureBytes)

    $xml = @"
<?xml version="1.0" encoding="utf-8"?><genuineAuthorization xmlns="http://www.microsoft.com/DRM/SL/GenuineAuthorization/1.0"><version>1.0</version><genuineProperties origin="sppclient"><properties>$PropertiesStr</properties><signatures><signature name="clientLockboxKey" method="rsa-sha256">$SignatureStr</signature></signatures></genuineProperties></genuineAuthorization>
"@
    
    $TicketPath = Join-Path $TicketDirectory "GenuineTicket.xml"
    [IO.File]::WriteAllText($TicketPath, $xml, [System.Text.Encoding]::ASCII)

    try {
        Restart-Service -Name "ClipSVC" -Force -ErrorAction SilentlyContinue
    }
    catch {
        Start-Sleep -Seconds 2
    }

    Start-Sleep -Seconds 2
    $FileStillExists = Test-Path -LiteralPath $TicketPath

    if ($FileStillExists) {
        Start-Sleep -Seconds 2
        $FileStillExists = Test-Path -LiteralPath $TicketPath
    }

    if ($FileStillExists) {
        $Sys32Path = "$env:SystemRoot\System32"
        if (Test-Path "$Sys32Path\clipup.exe") {
            Start-Process -FilePath "$Sys32Path\clipup.exe" -ArgumentList "-v -o" -NoNewWindow -Wait
        }

        $ProductInstance = Get-CimInstance -ClassName "SoftwareLicensingProduct" -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue
        if ($ProductInstance) {
            $null = Invoke-CimMethod -InputObject $ProductInstance -MethodName "Activate" -ErrorAction SilentlyContinue
        }
    }    
}

function Restore-EnvironmentState {
    [CmdletBinding()]
    param()

    Invoke-SppServiceReevaluation
}

function Main {
    [CmdletBinding()]
    param()

    Write-Host "[1/5] Validando entorno de ejecución..." -ForegroundColor Cyan
    Assert-ExecutionEnvironment

    Write-Host "[2/5] Verificando salud de componentes..." -ForegroundColor Cyan
    Assert-SystemHealth

    Write-Host "[3/5] Obteniendo configuración de edición y clave..." -ForegroundColor Cyan
    $activationConfig = Get-EditionActivationConfig

    $activationConfig | Format-List

    Write-Host "[4/5] Aplicando clave genérica base..." -ForegroundColor Cyan
    Set-GenericProductKey -ProductKey $activationConfig.ProductKey

    try {
        Write-Host "[5/5] Registrando ticket digital y solicitando activación..." -ForegroundColor Cyan
        Register-DigitalLicenseTicket -SkuId $activationConfig.SkuId -ProductID $activationConfig.ProductID -ProductKey $activationConfig.ProductKey

        Write-Host "Proceso completado exitosamente." -ForegroundColor Green
    }
    catch {
        Write-Error "Error durante el registro de la licencia: $_"
    }
    finally {
        Write-Host "Finalizando y actualizando tareas del subsistema de licencias..." -ForegroundColor Gray
        Restore-EnvironmentState
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Main
}