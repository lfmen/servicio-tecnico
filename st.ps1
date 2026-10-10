# Servicio Tecnico - Luca Mengarelli
$ErrorActionPreference = 'Continue'
$Base = 'C:\ServicioTecnico'
$OfficeDir = 'C:\Office'

# --- auto elevar a administrador ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
if (-not $admin) {
    if ($PSCommandPath) {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        Write-Host 'Abri PowerShell como administrador y volve a pegar el comando.' -ForegroundColor Red
    }
    exit
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Host.UI.RawUI.WindowTitle = 'Servicio Tecnico - Luca Mengarelli'
New-Item -ItemType Directory -Force -Path $Base | Out-Null

function Show-Banner {
    Clear-Host
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $e = [char]27
    $glyph = @{
        'L' = '#    ','#    ','#    ','#    ','#####'
        'U' = '#   #','#   #','#   #','#   #',' ### '
        'C' = ' ####','#    ','#    ','#    ',' ####'
        'A' = '  #  ',' # # ','#####','#   #','#   #'
    }
    $block = [string][char]0x2588
    $word = 'LUCA'.ToCharArray()
    $lines = for ($r = 0; $r -lt 5; $r++) {
        $s = ''
        foreach ($ch in $word) { $s += (($glyph[[string]$ch][$r]).ToCharArray() | ForEach-Object { if ($_ -eq '#') { $block + $block } else { '  ' } }) -join ''; $s += '   ' }
        $s
    }
    Write-Host ''
    for ($r = 0; $r -lt $lines.Count; $r++) {
        $out = '     '
        $line = $lines[$r]
        for ($c = 0; $c -lt $line.Length; $c++) {
            $t = $c / [math]::Max(1, $line.Length - 1)
            $cr = [int](255 * $t); $cg = [int](220 - 150 * $t); $cb = [int](255 - 40 * $t)
            $shade = 1 - 0.12 * $r
            $out += "$e[38;2;$([int]($cr*$shade));$([int]($cg*$shade));$([int]($cb*$shade))m$($line[$c])"
        }
        Write-Host "$out$e[0m"
    }
    $bar = ([string][char]0x2501) * 62
    Write-Host ''
    Write-Host "     $e[38;2;90;90;120m$bar$e[0m"
    Write-Host "     $e[1;38;2;255;200;60mM E N G A R E L L I$e[0m   $e[38;2;90;90;120m$([char]0x2502)$e[0m   $e[1;38;2;0;220;255mS E R V I C I O   T E C N I C O$e[0m"
    Write-Host "     $e[38;2;90;90;120m$bar$e[0m"
    Write-Host ("     $e[38;2;130;130;150mPC {0}  $([char]0x2022)  {1}  $([char]0x2022)  {2}$e[0m" -f $env:COMPUTERNAME, $env:USERNAME, (Get-Date -Format 'dd/MM/yyyy HH:mm'))
    Write-Host ''
}

function Show-Menu {
    Show-Banner
    $items = @(
        @('1', 'WinUtil (Chris Titus)',               'Tweaks, programas y ajustes de Windows', 'Green'),
        @('2', 'Instalar Office LTSC',                'Descarga e instala (2021 o 2024)',       'Green'),
        @('3', 'Activar Office con clave propia',     'Licencia legitima via ospp.vbs',         'Green'),
        @('4', 'Tarea de limpieza automatica',        'Se ejecuta en cada inicio de la PC',     'Green'),
        @('5', 'Limpiar ahora',                       'Temporales y basura, una vez',           'Green'),
        @('6', 'Instalar Microsoft Store',            'Para LTSC / ediciones sin Store',        'Green'),
        @('0', 'Salir',                               '',                                       'Red')
    )
    foreach ($it in $items) {
        Write-Host ('   [{0}] ' -f $it[0]) -NoNewline -ForegroundColor Magenta
        Write-Host ('{0,-34}' -f $it[1]) -NoNewline -ForegroundColor White
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
Add-Content $log ("{0}  liberado: {1} MB" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $liberado)
'@

function Invoke-Clean {
    $f = Join-Path $Base 'limpieza.ps1'
    Set-Content -Path $f -Value $CleanScript -Encoding ASCII
    Write-Host '   Limpiando...' -ForegroundColor Yellow
    & powershell -NoProfile -ExecutionPolicy Bypass -File $f
    Write-Host '   Listo.' -ForegroundColor Green
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
    Write-Host '   Tarea "ServicioTecnico-Limpieza" creada: corre sola en cada inicio.' -ForegroundColor Green
}

# ---------- office ----------
function Install-Office {
    Write-Host '   [1] Office 2021 LTSC   [2] Office 2024 LTSC' -ForegroundColor Cyan
    $v = Read-Host '   Version'
    if ($v -eq '2024') { $v = '2' }
    if ($v -eq '2') { $ch = 'PerpetualVL2024'; $pid_ = 'ProPlus2024Volume' } else { $ch = 'PerpetualVL2021'; $pid_ = 'ProPlus2021Volume' }
    New-Item -ItemType Directory -Force -Path $OfficeDir | Out-Null
    $setup = Join-Path $OfficeDir 'setup.exe'
    $cfg   = Join-Path $OfficeDir 'config.xml'
    if (-not (Test-Path $setup)) {
        Write-Host '   Descargando setup.exe de Microsoft...' -ForegroundColor Yellow
        Invoke-WebRequest 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $setup -UseBasicParsing
    }
    @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="$ch">
    <Product ID="$pid_">
      <Language ID="es-es" />
    </Product>
  </Add>
  <RemoveMSI />
  <Display Level="Full" AcceptEULA="TRUE" />
</Configuration>
"@ | Set-Content -Path $cfg -Encoding ASCII
    Write-Host '   Descargando e instalando Office (puede tardar)...' -ForegroundColor Yellow
    Start-Process $setup -ArgumentList "/configure `"$cfg`"" -WorkingDirectory $OfficeDir -Wait
    Write-Host '   Proceso de instalacion terminado.' -ForegroundColor Green
}

function Set-OfficeKey {
    $ospp = Get-ChildItem 'C:\Program Files\Microsoft Office','C:\Program Files (x86)\Microsoft Office' -Recurse -Filter ospp.vbs -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ospp) { Write-Host '   No encontre Office instalado.' -ForegroundColor Red; return }
    $key = Read-Host '   Clave de producto (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX)'
    if ($key) {
        cscript //nologo $ospp.FullName /inpkey:$key
        cscript //nologo $ospp.FullName /act
    }
}

# ---------- store ----------
function Install-Store {
    Write-Host '   Instalando Microsoft Store...' -ForegroundColor Yellow
    try { Start-Process wsreset.exe -ArgumentList '-i' -Wait -ErrorAction Stop } catch {}
    Start-Sleep 5
    $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    if (-not $pkg) {
        Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.WindowsStore*' -ErrorAction SilentlyContinue | ForEach-Object {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.FullName)\AppxManifest.xml" -ErrorAction SilentlyContinue
        }
        $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    }
    if ($pkg) { Write-Host '   Microsoft Store instalada.' -ForegroundColor Green }
    else { Write-Host '   No se pudo confirmar. Revisa la conexion y reintenta; el instalador de la Store puede tardar unos minutos.' -ForegroundColor Red }
}

# ---------- loop ----------
while ($true) {
    Show-Menu
    $op = Read-Host '   Elegi una opcion'
    Write-Host ''
    switch ($op) {
        '1' { Invoke-RestMethod 'https://christitus.com/win' | Invoke-Expression }
        '2' { Install-Office }
        '3' { Set-OfficeKey }
        '4' { Install-CleanTask }
        '5' { Invoke-Clean }
        '6' { Install-Store }
        '0' { Clear-Host; exit }
        default { Write-Host '   Opcion invalida.' -ForegroundColor Red }
    }
    Write-Host ''
    Read-Host '   Enter para volver al menu' | Out-Null
}
