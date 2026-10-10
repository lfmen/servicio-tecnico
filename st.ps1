# servicio tecnico - luca mengarelli
$ErrorActionPreference = 'Continue'
$Url = 'https://raw.githubusercontent.com/lfmen/servicio-tecnico/main/st.ps1'
$Base = 'C:\ServicioTecnico'
$OfficeDir = 'C:\Office'

# --- relanzar como administrador (sin cerrar la ventana si falla) ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
if (-not $admin) {
    try {
        if ($PSCommandPath) {
            Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        } else {
            Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"[Net.ServicePointManager]::SecurityProtocol=3072; irm $Url`?t=$(Get-Date -f yyyyMMddHHmmss) | iex`""
        }
    } catch {
        Write-Host 'no se pudo pedir permisos de administrador. abri powershell como administrador y volve a pegar el comando.' -ForegroundColor Red
    }
    return
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Host.UI.RawUI.WindowTitle = 'servicio tecnico - luca mengarelli'
New-Item -ItemType Directory -Force -Path $Base | Out-Null

function Show-Banner {
    Clear-Host
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $e = [char]27
    $art = @(
        ' _                      ',
        '| |  _   _   ___  __ _  ',
        '| | | | | | / __|/ _` | ',
        '| | | |_| || (__| (_| | ',
        '|_|  \__,_| \___|\__,_| '
    )
    Write-Host ''
    for ($i = 0; $i -lt $art.Count; $i++) {
        $g = 220 - 28 * $i
        Write-Host "    $e[38;2;60;$g;255m$($art[$i])$e[0m"
    }
    Write-Host ''
    Write-Host "    $e[38;2;120;120;140mservicio tecnico  $e[38;2;70;70;90m/  $e[38;2;120;120;140mluca mengarelli$e[0m"
    Write-Host "    $e[38;2;70;70;90m------------------------------------$e[0m"
    Write-Host ("    $e[38;2;90;90;110m{0} - {1} - {2}$e[0m" -f $env:COMPUTERNAME.ToLower(), $env:USERNAME.ToLower(), (Get-Date -Format 'dd/MM/yyyy HH:mm'))
    Write-Host ''
}

function Show-Menu {
    Show-Banner
    $items = @(
        @('1', 'winutil',                    'tweaks y programas de windows'),
        @('2', 'instalar office ltsc',       '2021 o 2024, descarga e instala'),
        @('3', 'activar office con clave',   'licencia propia via ospp'),
        @('4', 'limpieza automatica',        'tarea que corre en cada inicio'),
        @('5', 'limpiar ahora',              'temporales y basura'),
        @('6', 'microsoft store',            'instalarla en ltsc'),
        @('0', 'salir',                      '')
    )
    foreach ($it in $items) {
        Write-Host ('    {0}  ' -f $it[0]) -NoNewline -ForegroundColor Cyan
        Write-Host ('{0,-26}' -f $it[1]) -NoNewline -ForegroundColor Gray
        Write-Host $it[2] -ForegroundColor DarkGray
    }
    Write-Host ''
}

# ---------- limpieza ----------
$CleanScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\ServicioTecnico\limpieza.log'
$antes = (Get-PSDrive C).Free
function Clear-Dir($p) { if (Test-Path $p) { Get-ChildItem $p -Force -Recurse | Remove-Item -Force -Recurse } }
Clear-Dir "$env:windir\Temp"
Clear-Dir "$env:windir\Prefetch"
Clear-Dir "$env:windir\Logs\CBS"
Clear-Dir "$env:ProgramData\Microsoft\Windows\WER"
Get-ChildItem 'C:\Users' -Directory | ForEach-Object {
    Clear-Dir "$($_.FullName)\AppData\Local\Temp"
    Clear-Dir "$($_.FullName)\AppData\Local\CrashDumps"
    Get-ChildItem "$($_.FullName)\AppData\Local\Microsoft\Windows\Explorer" -Filter 'thumbcache_*.db' -Force | Remove-Item -Force
}
Stop-Service wuauserv -Force
Clear-Dir "$env:windir\SoftwareDistribution\Download"
Start-Service wuauserv
Clear-RecycleBin -Force
Remove-Item "$env:windir\MEMORY.DMP" -Force
$liberado = [math]::Round(((Get-PSDrive C).Free - $antes) / 1MB, 1)
Add-Content $log ("{0}  liberado: {1} mb" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $liberado)
'@

function Invoke-Clean {
    $f = Join-Path $Base 'limpieza.ps1'
    Set-Content -Path $f -Value $CleanScript -Encoding ASCII
    Write-Host '    limpiando...' -ForegroundColor Yellow
    & powershell -NoProfile -ExecutionPolicy Bypass -File $f
    Write-Host '    listo.' -ForegroundColor Green
    if (Test-Path "$Base\limpieza.log") { Get-Content "$Base\limpieza.log" -Tail 1 | Write-Host -ForegroundColor Cyan }
}

function Install-CleanTask {
    $f = Join-Path $Base 'limpieza.ps1'
    Set-Content -Path $f -Value $CleanScript -Encoding ASCII
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$f`""
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName 'ServicioTecnico-Limpieza' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host '    tarea creada: corre sola en cada inicio.' -ForegroundColor Green
}

# ---------- office ----------
function Install-Office {
    Write-Host '    1  office 2021 ltsc' -ForegroundColor Cyan
    Write-Host '    2  office 2024 ltsc' -ForegroundColor Cyan
    $v = Read-Host '    version'
    if ($v -eq '2') { $ch = 'PerpetualVL2024'; $prod = 'ProPlus2024Volume' } else { $ch = 'PerpetualVL2021'; $prod = 'ProPlus2021Volume' }
    New-Item -ItemType Directory -Force -Path $OfficeDir | Out-Null
    $setup = Join-Path $OfficeDir 'setup.exe'
    $cfg   = Join-Path $OfficeDir 'config.xml'
    if (-not (Test-Path $setup)) {
        Write-Host '    descargando setup.exe de microsoft...' -ForegroundColor Yellow
        Invoke-WebRequest 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $setup -UseBasicParsing
    }
    @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="$ch">
    <Product ID="$prod">
      <Language ID="es-es" />
    </Product>
  </Add>
  <RemoveMSI />
  <Display Level="Full" AcceptEULA="TRUE" />
</Configuration>
"@ | Set-Content -Path $cfg -Encoding ASCII
    Write-Host '    descargando e instalando office (puede tardar)...' -ForegroundColor Yellow
    Start-Process $setup -ArgumentList "/configure `"$cfg`"" -WorkingDirectory $OfficeDir -Wait
    Write-Host '    instalacion terminada.' -ForegroundColor Green
}

function Set-OfficeKey {
    $ospp = Get-ChildItem 'C:\Program Files\Microsoft Office','C:\Program Files (x86)\Microsoft Office' -Recurse -Filter ospp.vbs -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ospp) { Write-Host '    no encontre office instalado.' -ForegroundColor Red; return }
    $key = Read-Host '    clave de producto'
    if ($key) {
        cscript //nologo $ospp.FullName /inpkey:$key
        cscript //nologo $ospp.FullName /act
    }
}

# ---------- store ----------
function Install-Store {
    Write-Host '    instalando microsoft store...' -ForegroundColor Yellow
    try { Start-Process wsreset.exe -ArgumentList '-i' -Wait -ErrorAction Stop } catch {}
    Start-Sleep 5
    $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    if (-not $pkg) {
        Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.WindowsStore*' -ErrorAction SilentlyContinue | ForEach-Object {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.FullName)\AppxManifest.xml" -ErrorAction SilentlyContinue
        }
        $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    }
    if ($pkg) { Write-Host '    microsoft store instalada.' -ForegroundColor Green }
    else { Write-Host '    no se pudo confirmar. revisa la conexion y reintenta, puede tardar unos minutos.' -ForegroundColor Red }
}

# ---------- loop ----------
while ($true) {
    try {
        Show-Menu
        $op = Read-Host '    >'
        Write-Host ''
        switch ($op) {
            '1' { Invoke-RestMethod 'https://christitus.com/win' | Invoke-Expression }
            '2' { Install-Office }
            '3' { Set-OfficeKey }
            '4' { Install-CleanTask }
            '5' { Invoke-Clean }
            '6' { Install-Store }
            '0' { Clear-Host; return }
            default { Write-Host '    opcion invalida.' -ForegroundColor Red }
        }
    } catch {
        Write-Host ("    error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    Write-Host ''
    Read-Host '    enter para volver' | Out-Null
}
