# servicio tecnico - luca mengarelli
$ErrorActionPreference = 'Continue'
$Url = 'https://raw.githubusercontent.com/lfmen/servicio-tecnico/main/st.ps1'
$Base = 'C:\ServicioTecnico'
$OfficeDir = 'C:\Office'

# --- relanzar como administrador (sin cerrar la ventana si falla) ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    try {
        if ($PSCommandPath) {
            Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        } else {
            Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"[Net.ServicePointManager]::SecurityProtocol=3072; irm $Url`?t=$(Get-Date -f yyyyMMddHHmmss) | iex`""
        }
    } catch {
        Write-Host ("no se pudo pedir permisos de administrador: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host 'abri una powershell comun (win + x > terminal) y volve a correr el comando.' -ForegroundColor Yellow
    }
    return
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.Encoding]::UTF8
New-Item -ItemType Directory -Force -Path $Base | Out-Null
# solo SYSTEM y administradores escriben (la tarea corre como SYSTEM); usuarios solo leen
icacls $Base /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null

# ---------- estilo ----------
# el archivo queda en ascii (ps 5.1 lee -File sin bom como ansi): acentos con \u00xx via U, glifos con [char]
# ojo: ps no distingue mayusculas, asi que ninguna variable local puede llamarse como estas
function U([string]$s) { [regex]::Unescape($s) }
$e = [char]27
function Rgb($cr, $cg, $cb) { "$e[38;2;$cr;$cg;${cb}m" }
$RST    = "$e[0m"
$BOLD   = "$e[1m"
$BGSEL  = "$e[48;2;24;28;38m"
$BGKEY  = "$e[48;2;40;42;50m$(Rgb 230 230 235)"
$cAcc   = Rgb 91 155 255
$cWhi   = Rgb 245 245 247
$cTxt   = Rgb 214 214 220
$cMut   = Rgb 138 138 148
$cDim   = Rgb 82 82 92
$cLine  = Rgb 44 44 52
$cOk    = Rgb 61 220 151
$cWarn  = Rgb 245 184 65
$cBad   = Rgb 255 92 92
$gDot  = [string][char]0x25CF; $gEdge = [string][char]0x258C; $gLine = [string][char]0x2500
$gHeavy = [string][char]0x2501; $gStep = [string][char]0x203A; $gTri = [string][char]0x25B2
$gX    = [string][char]0x00D7; $gUp = [string][char]0x2191; $gDn = [string][char]0x2193
$gSep  = [string][char]0x00B7
$MG    = '   '
$Brand = U 'Servicio T\u00e9cnico'
$Host.UI.RawUI.WindowTitle = "$Brand $gSep Luca Mengarelli"

# fondo negro en vez del azul de windows powershell; se restaura al salir
$OrigBg = $Host.UI.RawUI.BackgroundColor; $OrigFg = $Host.UI.RawUI.ForegroundColor
$Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'Gray'
try { $Host.PrivateData.ProgressBackgroundColor = 'Black'; $Host.PrivateData.ProgressForegroundColor = 'Gray' } catch {}

function Say($color, $mark, $text) { Write-Host "$MG$color$mark$RST $cTxt$text$RST" }
function Step($t) { Say $cAcc $gStep $t }
function Good($t) { Say $cOk $gDot $t }
function Warn($t) { Say $cWarn $gTri $t }
function Fail($t) { Say $cBad $gX $t }
function Key($k) { "$BGKEY $k $RST" }
function Rule { Write-Host "$MG$cLine$($gLine * $CW)$RST" }
function Fit([string]$s, [int]$n) { if ($n -lt 2) { '' } elseif ($s.Length -gt $n) { $s.Substring(0, $n - 1) + [char]0x2026 } else { $s } }
function Write-Log($msg) { Add-Content "$Base\historial.log" ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $msg) -Encoding UTF8 }

function Get-Ago([datetime]$d) {
    $s = (Get-Date) - $d
    if ($s.TotalDays -ge 1) { 'Hace {0} d' -f [int][math]::Floor($s.TotalDays) }
    elseif ($s.TotalHours -ge 1) { 'Hace {0} h' -f [int][math]::Floor($s.TotalHours) }
    else { 'Hace {0} min' -f [int][math]::Floor($s.TotalMinutes) }
}

function Confirm-Action($q) {
    Write-Host -NoNewline "$MG$cWarn?$RST $cTxt$q$RST   $(Key 'S') $cMut$(U 'S\u00ed')$RST  $(Key 'N') ${cMut}No$RST  "
    $k = [Console]::ReadKey($true)
    $y = "$($k.KeyChar)" -match '^[sy]$'
    Write-Host ''
    $y
}

# ---------- datos del equipo ----------
function Update-Activation {
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:Activated = $lic.LicenseStatus -eq 1
}

function Get-Static {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cv  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $ip  = try { (Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4Address.IPAddress } catch { $null }
    $script:Sys = @{
        Os    = $os.Caption -replace '^Microsoft\s+', ''
        Ver   = ('{0} ({1})' -f $(if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }), $os.BuildNumber).Trim()
        Cpu   = (($cpu.Name -replace '\((R|TM)\)|CPU|Processor|\d+-Core|with .*|@.*$', '') -replace '\s+', ' ').Trim()
        Cores = U ('{0} n\u00facleos {1} {2} hilos' -f $cpu.NumberOfCores, $gSep, $cpu.NumberOfLogicalProcessors)
        Ip    = if ($ip) { $ip } else { 'Sin red' }
    }
    Update-Activation
}

# ---------- pantalla ----------
function Cell([string]$text, $color, [int]$w) { $t = Fit $text ($w - 3); "$color$t$RST" + (' ' * ($w - $t.Length)) }
function Bar([double]$p, [int]$w) {
    $bw = $w - 4
    $n = [int][math]::Round([math]::Min(1.0, $p) * $bw)
    $col = if ($p -lt .75) { $cAcc } elseif ($p -lt .9) { $cWarn } else { $cBad }
    "$col$($gHeavy * $n)$cLine$($gHeavy * ($bw - $n))$RST    "
}

function Show-Banner {
    Clear-Host
    $os   = Get-CimInstance Win32_OperatingSystem
    $ramT = $os.TotalVisibleMemorySize / 1MB
    $ramU = $ramT - $os.FreePhysicalMemory / 1MB
    $dk   = New-Object IO.DriveInfo $env:SystemDrive
    $dT   = $dk.TotalSize / 1GB
    $dF   = $dk.AvailableFreeSpace / 1GB
    $on   = (Get-Date) - $os.LastBootUpTime
    $onS  = if ($on.TotalDays -ge 1) { '{0} d {1} h' -f $on.Days, $on.Hours } else { '{0} h {1} min' -f $on.Hours, $on.Minutes }

    # marca a la izquierda, red y hora a la derecha
    Write-Host ''
    $who   = 'Luca Mengarelli'
    $right = "$($Sys.Ip)   $gSep   $(Get-Date -Format 'dd/MM/yyyy  HH:mm')"
    $gap   = [math]::Max(2, $CW - 2 - $Brand.Length - 3 - $who.Length - $right.Length)
    Write-Host "$MG$cAcc$gEdge$RST $BOLD$cWhi$Brand$RST   $cMut$who$(' ' * $gap)$cDim$right$RST"
    Rule
    Write-Host ''

    # cuatro columnas de estado
    $w = @(34, 23, 17, 18) | ForEach-Object { [int][math]::Floor($_ * $CW / 92) }
    $lic = if ($Activated) { "$cOk$gDot$RST ${cTxt}Activado" } else { "$cBad$gDot$RST ${cTxt}Sin activar" }
    $licLen = if ($Activated) { 10 } else { 13 }
    $verTxt = Fit $Sys.Ver ($w[0] - 3 - $licLen - 5)
    Write-Host ($MG + (Cell 'EQUIPO' $cDim $w[0]) + (Cell 'PROCESADOR' $cDim $w[1]) + (Cell 'MEMORIA' $cDim $w[2]) + (Cell "DISCO $($env:SystemDrive)" $cDim $w[3]))
    Write-Host ($MG + (Cell $env:COMPUTERNAME $cWhi $w[0]) + (Cell $Sys.Cpu $cWhi $w[1]) + (Cell ('{0:N1} / {1:N0} GB' -f $ramU, $ramT) $cWhi $w[2]) + (Cell ('{0:N0} / {1:N0} GB' -f ($dT - $dF), $dT) $cWhi $w[3]))
    Write-Host ($MG + (Cell $Sys.Os $cMut $w[0]) + (Cell $Sys.Cores $cMut $w[1]) + (Bar ($ramU / $ramT) $w[2]) + (Bar (($dT - $dF) / $dT) $w[3]))
    Write-Host ($MG + "$cMut$verTxt$RST  $cDim$gSep$RST  $lic$RST" + (' ' * [math]::Max(0, $w[0] - $verTxt.Length - 5 - $licLen)) + (Cell "Encendido $onS" $cMut $w[1]) + (Cell ('{0:N0} % en uso' -f ($ramU / $ramT * 100)) $cMut $w[2]) + (Cell ('{0:N0} GB libres' -f $dF) $cMut $w[3]))
    Write-Host ''
}

function Format-Row($it, $on) {
    $name  = (Fit $it.Name 25).PadRight(26)
    $desc  = if ($DescW) { (Fit "$($it.Desc)" ($DescW - 2)).PadRight($DescW) } else { '' }
    $badge = ' ' * $BadgeW
    if ($it.B) {
        $txt   = Fit $it.B[0] ($BadgeW - 2)
        $badge = (' ' * ($BadgeW - 2 - $txt.Length)) + "$($it.B[1])$gDot $cMut$txt"
    }
    $k = "$($it.Key)".ToUpper()
    if ($on) { "  $cAcc$gEdge$BGSEL $cAcc$BOLD$k$RST$BGSEL   $cWhi$BOLD$name$RST$BGSEL$cTxt$desc$badge $RST" }
    else     { "    $cDim$k   $cTxt$name$cMut$desc$badge $RST" }
}

function Select-Menu($Items, [int]$Index = 0) {
    $top = [Console]::CursorTop
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $sb = New-Object Text.StringBuilder
            $sec = $null
            for ($i = 0; $i -lt $Items.Count; $i++) {
                if ($Items[$i].Sec -and $Items[$i].Sec -ne $sec) {
                    $sec = $Items[$i].Sec
                    [void]$sb.Append("$MG $cDim$sec$RST$e[K`r`n")
                }
                [void]$sb.Append((Format-Row $Items[$i] ($i -eq $Index)) + "`r`n")
            }
            [void]$sb.Append("`r`n$MG$(Key "$gUp$gDn") ${cMut}Navegar$RST   $(Key 'Enter') ${cMut}Abrir$RST   $(Key '1-9') ${cMut}Atajo$RST   $(Key 'Esc') ${cMut}Salir$RST$e[K")
            [Console]::SetCursorPosition(0, $top)
            [Console]::Write($sb.ToString())
            $k = [Console]::ReadKey($true)
            switch ($k.Key) {
                'UpArrow'   { $Index = ($Index - 1 + $Items.Count) % $Items.Count; continue }
                'DownArrow' { $Index = ($Index + 1) % $Items.Count; continue }
                'Home'      { $Index = 0; continue }
                'End'       { $Index = $Items.Count - 1; continue }
                'Enter'     { return $Index }
                'Escape'    { return -1 }
            }
            for ($i = 0; $i -lt $Items.Count; $i++) { if ($Items[$i].Key -eq "$($k.KeyChar)") { return $i } }
        }
    } finally {
        [Console]::CursorVisible = $true
        Write-Host ''
    }
}

function Show-Header($title) {
    Clear-Host
    Write-Host ''
    Write-Host "$MG$cAcc$gEdge$RST $cMut$Brand  $gStep  $RST$BOLD$cWhi$title$RST"
    Rule
    Write-Host ''
}

# ---------- limpieza ----------
$CleanScript = @'
param([switch]$Todo)
$ErrorActionPreference = 'SilentlyContinue'
$log = Join-Path $PSScriptRoot 'limpieza.log'
$antes = (New-Object IO.DriveInfo $env:SystemDrive).AvailableFreeSpace
# automatico: solo archivos con mas de 1 dia. -Todo (manual): todo, y vacia la papelera
$limite = if ($Todo) { Get-Date } else { (Get-Date).AddDays(-1) }
function Clear-Dir($p) {
    if (-not (Test-Path -LiteralPath $p)) { return }
    Get-ChildItem -LiteralPath $p -Force | Where-Object { $_.LastWriteTime -lt $limite } | ForEach-Object {
        if ($_.PSIsContainer) { cmd /c rd /s /q $_.FullName 2>&1 | Out-Null }   # rd no sigue junctions
        else { Remove-Item -LiteralPath $_.FullName -Force }
    }
}
Clear-Dir "$env:windir\Temp"
Clear-Dir "$env:windir\Minidump"
Clear-Dir "$env:windir\Logs\CBS"
Clear-Dir "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
Clear-Dir "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"
Get-ChildItem 'C:\Users' -Directory | ForEach-Object {
    Clear-Dir "$($_.FullName)\AppData\Local\Temp"
    Clear-Dir "$($_.FullName)\AppData\Local\CrashDumps"
    Get-ChildItem "$($_.FullName)\AppData\Local\Microsoft\Windows\Explorer" -Filter 'thumbcache_*.db' -Force | Where-Object { $_.LastWriteTime -lt $limite } | Remove-Item -Force
}
if ($Todo) {
    $wu = (Get-Service wuauserv).Status -eq 'Running'
    Stop-Service wuauserv -Force
    Clear-Dir "$env:windir\SoftwareDistribution\Download"
    if ($wu) { Start-Service wuauserv }
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { Clear-Dir "$($_.DeviceID)\`$Recycle.Bin" }
    Remove-Item "$env:windir\MEMORY.DMP" -Force
} else {
    Clear-Dir "$env:windir\SoftwareDistribution\Download"
}
$liberado = [math]::Round(((New-Object IO.DriveInfo $env:SystemDrive).AvailableFreeSpace - $antes) / 1MB, 1)
Add-Content $log ("{0}  {1}  liberado: {2} mb" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $(if ($Todo) { 'manual' } else { 'auto' }), $liberado)
'@

function Get-Freed { $l = Get-Content "$Base\limpieza.log" -Tail 1 -ErrorAction SilentlyContinue; if ($l) { ($l -split 'liberado: ')[1].ToUpper() } }

function Invoke-Clean {
    Warn (U 'Se borran temporales, la cach\u00e9 de actualizaciones y volcados, y se vac\u00eda la papelera.')
    if (-not (Confirm-Action (U '\u00bfContinuar?'))) { return }
    $f = Join-Path $Base 'limpieza.ps1'
    Set-Content -Path $f -Value $CleanScript -Encoding ASCII
    Step 'Limpiando...'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $f -Todo
    Good "Listo. Se liberaron $(Get-Freed)."
}

function Install-CleanTask {
    $name = 'ServicioTecnico-Limpieza'
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Good (U 'La limpieza autom\u00e1tica ya est\u00e1 activa.')
        if (Confirm-Action (U '\u00bfDesactivarla?')) { Unregister-ScheduledTask -TaskName $name -Confirm:$false; Good 'Tarea eliminada.' }
        return
    }
    $f = Join-Path $Base 'limpieza.ps1'
    Set-Content -Path $f -Value $CleanScript -Encoding ASCII
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$f`""
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT3M'   # espera 3 min para no competir con el arranque
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    Step 'Tarea creada. Probando como SYSTEM...'
    $ini = Get-Date
    Start-ScheduledTask -TaskName $name
    $fin = $ini.AddMinutes(10)
    do {
        Start-Sleep 2
        $info = Get-ScheduledTaskInfo -TaskName $name
        $listo = ($info.LastRunTime -ge $ini.AddSeconds(-2)) -and ((Get-ScheduledTask -TaskName $name).State -eq 'Ready')
    } until ($listo -or (Get-Date) -gt $fin)
    if ($listo -and $info.LastTaskResult -eq 0) {
        Good 'Prueba correcta: la limpieza se va a ejecutar en cada inicio.'
        $fr = Get-Freed
        if ($fr) { Good "Primera pasada: se liberaron $fr." }
    } else {
        Fail (U ('La tarea se cre\u00f3 pero la prueba fall\u00f3 (resultado {0}).' -f $info.LastTaskResult))
    }
}

# ---------- office ----------
function Get-OfficeIds { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue).ProductReleaseIds }

function Install-Office {
    $ids = Get-OfficeIds
    if ($ids) {
        Warn "Ya hay Office instalado: $ids"
        if (-not (Confirm-Action (U '\u00bfInstalar de todos modos?'))) { return }
        Write-Host ''
    }
    Write-Host "$MG $cDim$(U 'VERSI\u00d3N')$RST"
    $v = Select-Menu @(
        @{ Key = '1'; Name = 'Office 2021 LTSC'; Desc = 'Word, Excel, PowerPoint y Outlook' },
        @{ Key = '2'; Name = 'Office 2024 LTSC'; Desc = U 'La versi\u00f3n m\u00e1s reciente' }
    )
    if ($v -eq -1) { return }
    if ($v -eq 1) { $ch = 'PerpetualVL2024'; $prod = 'ProPlus2024Volume' } else { $ch = 'PerpetualVL2021'; $prod = 'ProPlus2021Volume' }
    New-Item -ItemType Directory -Force -Path $OfficeDir | Out-Null
    $setup = Join-Path $OfficeDir 'setup.exe'
    $cfg   = Join-Path $OfficeDir 'config.xml'
    if (-not (Test-Path $setup)) {
        Step 'Descargando setup.exe de Microsoft...'
        $ProgressPreference = 'SilentlyContinue'   # la barra de progreso de ps 5.1 hace la descarga muy lenta
        Invoke-WebRequest 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $setup -UseBasicParsing -ErrorAction Stop
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
    Step 'Descargando e instalando Office. Puede tardar varios minutos...'
    $p = Start-Process $setup -ArgumentList "/configure `"$cfg`"" -WorkingDirectory $OfficeDir -Wait -PassThru
    if ($p.ExitCode -eq 0) { Good 'Office instalado.' } else { Fail (U "El instalador termin\u00f3 con c\u00f3digo $($p.ExitCode).") }
}

# ---------- store ----------
function Install-Store {
    Step 'Instalando Microsoft Store...'
    try { Start-Process wsreset.exe -ArgumentList '-i' -Wait -ErrorAction Stop } catch {}
    Start-Sleep 5
    $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    if (-not $pkg) {
        Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.WindowsStore*' -ErrorAction SilentlyContinue | ForEach-Object {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.FullName)\AppxManifest.xml" -ErrorAction SilentlyContinue
        }
        $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    }
    if ($pkg) { Good 'Microsoft Store instalada.' }
    else { Fail (U 'No se pudo confirmar. Revis\u00e1 la conexi\u00f3n y reintent\u00e1; puede tardar unos minutos.') }
}

# ---------- reparacion ----------
function Repair-Windows {
    Warn 'Puede tardar entre 10 y 30 minutos. No cierres la ventana.'
    if (-not (Confirm-Action (U '\u00bfContinuar?'))) { return }
    Write-Host ''
    Step 'DISM: reparando la imagen de Windows'
    DISM.exe /Online /Cleanup-Image /RestoreHealth
    if ($LASTEXITCODE -eq 0) { Good 'Imagen de Windows correcta.' } else { Fail (U "DISM termin\u00f3 con c\u00f3digo $LASTEXITCODE.") }
    Write-Host ''
    Step 'SFC: verificando archivos del sistema'
    sfc.exe /scannow
    if ($LASTEXITCODE -eq 0) { Good 'Archivos del sistema correctos.' }
    else { Warn (U 'SFC encontr\u00f3 o repar\u00f3 problemas (ver arriba). Conviene reiniciar.') }
}

function Reset-Network {
    Warn (U 'La conexi\u00f3n se corta unos segundos.')
    if (-not (Confirm-Action (U '\u00bfContinuar?'))) { return }
    Write-Host ''
    ipconfig /flushdns | Out-Null;   Good (U 'Cach\u00e9 DNS vaciada')
    netsh winsock reset | Out-Null;  Good 'Winsock restablecido'
    netsh int ip reset | Out-Null;   Good 'Pila TCP/IP restablecida'
    ipconfig /release | Out-Null
    ipconfig /renew | Out-Null;      Good 'IP renovada'
    Write-Host ''
    Warn 'Hace falta reiniciar para completar el cambio.'
    Restart-Now
}

function New-RestorePoint {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    # windows deja crear uno cada 24 h; esto saca el limite
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord
    Step (U 'Creando punto de restauraci\u00f3n...')
    Checkpoint-Computer -Description ("Servicio tecnico {0}" -f (Get-Date -Format 'dd/MM HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Good (U 'Punto creado. Se puede volver desde rstrui.exe.')
}

function Restart-Now {
    if (Confirm-Action (U '\u00bfReiniciar el equipo ahora?')) { Good 'Reiniciando en 5 segundos...'; shutdown.exe /r /t 5 }
}

# ---------- informe ----------
function New-Report {
    Step 'Recopilando datos del equipo...'
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $mb   = Get-CimInstance Win32_BaseBoard
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $mem  = @(Get-CimInstance Win32_PhysicalMemory)
    $gpu  = @(Get-CimInstance Win32_VideoController)
    $cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $ddr  = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5' }
    # Enc y no H: H es alias de Get-History y los alias le ganan a las funciones
    function Enc($s) { [Net.WebUtility]::HtmlEncode(([string]$s -replace 'To Be Filled By O\.E\.M\.\s*|System Product Name|Default string|\((R|TM)\)', '').Trim()) }
    function Row($k, $v, $sub, $tag) {
        $t = Enc $v; if (-not $t) { $t = '<span class=na>Sin dato</span>' }
        $s = if ($sub) { "<small>$sub</small>" } else { '' }
        "<div class=row><div class=k>$k</div><div class=v>$t$s</div><div class=t>$tag</div></div>"
    }
    function Tag($cls, $text) { "<span class=tag><i class='dot $cls'></i>$text</span>" }
    function Meter([int]$p) { $c = if ($p -ge 90) { 'bad' } elseif ($p -ge 75) { 'warn' } else { '' }; "<div class=meter><i class='$c' style='width:$p%'></i></div>" }
    function Stat($label, $value, $cls) { "<div class=stat><dt><i class='dot $cls'></i>$label</dt><dd>$(Enc $value)</dd></div>" }

    Step 'Analizando discos...'
    $sick = 0
    $disks = foreach ($d in Get-PhysicalDisk) {
        $rc = try { $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { $null }
        $x = @()
        if ($null -ne $rc.Wear) { $x += "Desgaste $($rc.Wear) %" }
        if ($rc.Temperature) { $x += "$($rc.Temperature) &deg;C" }
        if ($rc.PowerOnHours) { $x += '{0:N0} h de uso' -f $rc.PowerOnHours }
        $ok = $d.HealthStatus -eq 'Healthy'
        if (-not $ok) { $sick++ }
        $tag = if ($ok) { Tag 'ok' 'Sano' } else { Tag 'bad' (Enc $d.HealthStatus) }
        Row (Enc $d.FriendlyName) ('{0} {1} {2} {3} {4:N0} GB' -f $d.MediaType, $gSep, $d.BusType, $gSep, ($d.Size / 1GB)) ($x -join ' &middot; ') $tag
    }
    $vols = foreach ($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 } | Sort-Object DriveLetter) {
        $p = [int](($v.Size - $v.SizeRemaining) / $v.Size * 100)
        $lbl = if ($v.FileSystemLabel) { " &middot; $(Enc $v.FileSystemLabel)" } else { '' }
        "<div class=row><div class=k>$($v.DriveLetter):$lbl</div><div class=v>$('{0:N0} GB libres de {1:N0} GB' -f ($v.SizeRemaining / 1GB), ($v.Size / 1GB))$(Meter $p)</div><div class=t><span class=tag>$p % en uso</span></div></div>"
    }

    Step (U 'Leyendo bater\u00eda...')
    $batStat = Stat 'Bater&iacute;a' (U 'Sin bater\u00eda') ''
    $batRows = Row 'Estado' (U 'Equipo sin bater\u00eda')
    if (Get-CimInstance Win32_Battery) {
        try {
            $xf = Join-Path $env:TEMP 'st-bateria.xml'
            powercfg /batteryreport /xml /output $xf | Out-Null
            $b = @(([xml](Get-Content $xf -Raw)).BatteryReport.Batteries.Battery)[0]
            $s = [int]([double]$b.FullChargeCapacity / [double]$b.DesignCapacity * 100)
            $cls = if ($s -ge 80) { 'ok' } elseif ($s -ge 60) { 'warn' } else { 'bad' }
            $batStat = Stat 'Salud de bater&iacute;a' "$s %" $cls
            $batRows = (Row 'Modelo' "$($b.Manufacturer) $($b.Id)") + (Row 'Capacidad de f&aacute;brica' ('{0:N0} mWh' -f [double]$b.DesignCapacity)) +
                       (Row 'Capacidad actual' ('{0:N0} mWh' -f [double]$b.FullChargeCapacity) "$s % de la original" (Tag $cls "$s %")) + (Row 'Ciclos de carga' $b.CycleCount)
        } catch { $batRows = Row 'Estado' (U 'No se pudo leer el informe de bater\u00eda') }
    }

    $ram   = [math]::Round(($mem | Measure-Object Capacity -Sum).Sum / 1GB)
    $mods  = ($mem | ForEach-Object { '{0} GB {1} {2} MHz' -f ($_.Capacity / 1GB), $ddr[[int]$_.SMBIOSMemoryType], $_.Speed }) -join ' + '
    $cFree = (New-Object IO.DriveInfo $env:SystemDrive).AvailableFreeSpace / 1GB
    $up    = (Get-Date) - $os.LastBootUpTime
    $hist  = @(Get-Content "$Base\historial.log" -Tail 12 -ErrorAction SilentlyContinue) + @(Get-Content "$Base\limpieza.log" -Tail 5 -ErrorAction SilentlyContinue) | Sort-Object
    $pc    = $env:COMPUTERNAME
    $now   = Get-Date
    $meses = 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    $fecha = '{0} de {1} de {2}, {3:HH:mm}' -f $now.Day, $meses[$now.Month - 1], $now.Year, $now
    $model = Enc "$($cs.Manufacturer) $($cs.Model)"
    if (-not $model) { $model = Enc "$($mb.Manufacturer) $($mb.Product)" }
    $lic   = if ($Activated) { Tag 'ok' 'Activado' } else { Tag 'bad' 'Sin activar' }

    $html = @"
<!doctype html><html lang=es><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Informe &middot; $(Enc $pc)</title>
<link rel=preconnect href="https://fonts.googleapis.com"><link rel=preconnect href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel=stylesheet>
<style>
:root{--ink:#0b0b0c;--sub:#6e6e73;--faint:#a1a1a6;--line:#ececee;--tile:#f5f5f7;--ok:#22a06b;--warn:#e2a03f;--bad:#e5484d}
*{box-sizing:border-box;margin:0;padding:0}
body{background:#fff;color:var(--ink);font:15px/1.55 Inter,-apple-system,"Segoe UI Variable Text","Segoe UI",system-ui,sans-serif;-webkit-font-smoothing:antialiased;font-feature-settings:"cv11","ss01","tnum"}
.wrap{max-width:860px;margin:0 auto;padding:64px 24px 88px}
.top{display:flex;justify-content:space-between;align-items:center;gap:16px;font-size:14px;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:10px;font-weight:500}
.mark{width:26px;height:26px;border-radius:8px;background:var(--ink);color:#fff;display:grid;place-items:center;font-size:13px;font-weight:600}
.top .muted,.brand span{color:var(--sub);font-weight:400}
h1{font-size:48px;line-height:1.05;font-weight:600;letter-spacing:-.035em;margin:72px 0 14px}
.lead{color:var(--sub);font-size:17px;letter-spacing:-.01em}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:48px 0 8px}
.stat{background:var(--tile);border-radius:18px;padding:18px 20px 20px}
.stat dt{color:var(--sub);font-size:13px;display:flex;align-items:center;gap:8px}
.stat dd{font-size:22px;font-weight:600;letter-spacing:-.025em;margin-top:10px}
.dot{width:7px;height:7px;border-radius:50%;background:var(--faint);display:inline-block;flex:none}
.dot.ok{background:var(--ok)}.dot.warn{background:var(--warn)}.dot.bad{background:var(--bad)}
section{margin-top:64px}
h2{font-size:20px;font-weight:600;letter-spacing:-.02em;margin-bottom:14px}
.row{display:grid;grid-template-columns:210px 1fr auto;gap:20px;padding:15px 0;border-top:1px solid var(--line);align-items:baseline}
.row:last-child{border-bottom:1px solid var(--line)}
.k{color:var(--sub)}.v{font-weight:500}.v small{display:block;color:var(--sub);font-weight:400;font-size:13px;margin-top:3px}
.na{color:var(--faint);font-weight:400}
.tag{font-size:13px;color:var(--sub);display:inline-flex;align-items:center;gap:7px;white-space:nowrap}
.meter{height:4px;background:var(--line);border-radius:4px;margin-top:12px;overflow:hidden;max-width:360px}
.meter i{display:block;height:100%;background:var(--ink);border-radius:4px}.meter i.warn{background:var(--warn)}.meter i.bad{background:var(--bad)}
.log{font:12.5px/1.9 ui-monospace,"Cascadia Mono",Consolas,monospace;color:var(--sub);white-space:pre-wrap;border-top:1px solid var(--line);padding-top:14px}
footer{margin-top:88px;padding-top:20px;border-top:1px solid var(--line);display:flex;justify-content:space-between;gap:16px;color:var(--faint);font-size:13px}
@media(max-width:640px){h1{font-size:36px}.row{grid-template-columns:1fr auto;gap:4px 16px}.k{grid-column:1/-1}}
@media print{.wrap{padding:0}section,.stat{break-inside:avoid}}
</style></head><body><div class=wrap>
<div class=top><div class=brand><div class=mark>L</div>Luca Mengarelli <span>&middot; Servicio t&eacute;cnico</span></div><div class=muted>$fecha</div></div>
<h1>Informe del equipo</h1>
<p class=lead>$(Enc $pc)$(if ($model) { " &middot; $model" })</p>
<dl class=stats>
$(Stat 'Windows' $(if ($Activated) { 'Activado' } else { 'Sin activar' }) $(if ($Activated) { 'ok' } else { 'bad' }))
$(Stat 'Discos' $(if ($sick) { "$sick con fallas" } else { 'Sanos' }) $(if ($sick) { 'bad' } else { 'ok' }))
$batStat
$(Stat 'Memoria' "$ram GB" '')
$(Stat "Libre en $($env:SystemDrive)" ('{0:N0} GB' -f $cFree) $(if ($cFree -lt 15) { 'bad' } elseif ($cFree -lt 40) { 'warn' } else { 'ok' }))
</dl>
<section><h2>Equipo</h2>
$(Row 'Fabricante' $cs.Manufacturer)$(Row 'Modelo' $cs.Model)$(Row 'N&uacute;mero de serie' $bios.SerialNumber)$(Row 'Placa base' "$($mb.Manufacturer) $($mb.Product)")$(Row 'BIOS' $bios.SMBIOSBIOSVersion ('{0:dd/MM/yyyy}' -f $bios.ReleaseDate))
</section>
<section><h2>Sistema</h2>
$(Row 'Windows' $os.Caption ('Versi&oacute;n {0} &middot; compilaci&oacute;n {1}' -f $(if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }), $os.BuildNumber) $lic)$(Row 'Instalado' ('{0:dd/MM/yyyy}' -f $os.InstallDate))$(Row 'Encendido hace' (('{0} d {1} h {2} min' -f $up.Days, $up.Hours, $up.Minutes) -replace '^0 d (0 h )?', ''))$(Row 'Red' $Sys.Ip)
</section>
<section><h2>Hardware</h2>
$(Row 'Procesador' $cpu.Name.Trim() ('{0} n&uacute;cleos &middot; {1} hilos' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors))$(Row 'Memoria' "$ram GB" $mods)$(Row 'Gr&aacute;ficos' (($gpu | ForEach-Object Name) -join ', '))
</section>
<section><h2>Almacenamiento</h2>
$($disks -join '')
</section>
<section><h2>Unidades</h2>
$($vols -join '')
</section>
<section><h2>Bater&iacute;a</h2>
$batRows
</section>
<section><h2>Historial de servicio</h2>
<div class=log>$(if ($hist) { Enc ($hist -join "`n") } else { 'Sin registros todav&iacute;a.' })</div>
</section>
<footer><span>Luca Mengarelli &middot; Servicio t&eacute;cnico</span><span>$(Enc $pc)</span></footer>
</div></body></html>
"@
    $file = Join-Path ([Environment]::GetFolderPath('Desktop')) ('Informe {0} {1}.html' -f $pc, (Get-Date -Format 'yyyy-MM-dd HHmm'))
    Set-Content -Path $file -Value $html -Encoding UTF8
    Good "Informe guardado en el escritorio: $(Split-Path $file -Leaf)"
    Start-Process $file
}

# ---------- menu ----------
$Menu = @(
    @{ Sec = 'HERRAMIENTAS'; Key = '1'; Name = 'WinUtil'; Desc = 'Ajustes y programas de Windows'
       Run = { Invoke-RestMethod 'https://christitus.com/win' | Invoke-Expression } },
    @{ Sec = 'HERRAMIENTAS'; Key = '2'; Name = 'Activar Windows y Office'; Desc = 'Mediante get.activated.win'
       Badge = { if ($Activated) { 'Activado', $cOk } else { 'Sin activar', $cBad } }
       Run = { Invoke-RestMethod 'https://get.activated.win' | Invoke-Expression; Update-Activation } },
    @{ Sec = (U 'INSTALACI\u00d3N'); Key = '3'; Name = 'Office LTSC'; Desc = U 'Versi\u00f3n 2021 o 2024 en espa\u00f1ol'
       Badge = { $ids = Get-OfficeIds; if ($ids -match '20\d\d') { "$($Matches[0]) instalado", $cOk } elseif ($ids) { 'Instalado', $cOk } else { 'No instalado', $cDim } }
       Run = { Install-Office } },
    @{ Sec = (U 'INSTALACI\u00d3N'); Key = '4'; Name = 'Microsoft Store'; Desc = 'Para ediciones LTSC'
       Badge = { if (Get-AppxPackage Microsoft.WindowsStore) { 'Instalada', $cOk } else { 'No instalada', $cDim } }
       Run = { Install-Store } },
    @{ Sec = 'MANTENIMIENTO'; Key = '5'; Name = 'Limpieza'; Desc = 'Temporales, actualizaciones y papelera'
       Badge = { $l = Get-Content "$Base\limpieza.log" -Tail 1 -ErrorAction SilentlyContinue
                 if ($l) { (Get-Ago ([datetime]::ParseExact($l.Substring(0, 16), 'yyyy-MM-dd HH:mm', $null))), $cMut } else { 'Nunca', $cWarn } }
       Run = { Invoke-Clean } },
    @{ Sec = 'MANTENIMIENTO'; Key = '6'; Name = U 'Limpieza autom\u00e1tica'; Desc = 'Se ejecuta en cada inicio'
       Badge = { if (Get-ScheduledTask -TaskName 'ServicioTecnico-Limpieza' -ErrorAction SilentlyContinue) { 'Activa', $cOk } else { 'Inactiva', $cDim } }
       Run = { Install-CleanTask } },
    @{ Sec = 'MANTENIMIENTO'; Key = '7'; Name = 'Reparar Windows'; Desc = 'DISM y SFC sobre archivos del sistema'
       Run = { Repair-Windows } },
    @{ Sec = 'MANTENIMIENTO'; Key = '8'; Name = 'Restablecer red'; Desc = 'DNS, Winsock y TCP/IP'
       Run = { Reset-Network } },
    @{ Sec = 'MANTENIMIENTO'; Key = '9'; Name = U 'Punto de restauraci\u00f3n'; Desc = 'Crear uno antes de hacer cambios'
       Badge = { $p = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Select-Object -Last 1
                 if ($p) { (Get-Ago ([Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime))), $cMut } else { 'Ninguno', $cWarn } }
       Run = { New-RestorePoint } },
    @{ Sec = 'EQUIPO'; Key = 'r'; Name = 'Informe del equipo'; Desc = U 'Hardware, discos y bater\u00eda en HTML'
       Run = { New-Report } },
    @{ Sec = 'EQUIPO'; Key = 'x'; Name = 'Reiniciar equipo'; Desc = ''
       Run = { Restart-Now } },
    @{ Sec = 'EQUIPO'; Key = 'q'; Name = 'Salir'; Desc = '' }
)

$CW     = [math]::Min(92, [Console]::WindowWidth - 6)
$BadgeW = 18
$DescW  = [math]::Max(0, $CW - 32 - $BadgeW)
if ($DescW -lt 16) { $DescW = 0 }

Clear-Host
Write-Host ''
Write-Host "$MG$cAcc$gEdge$RST $BOLD$cWhi$Brand$RST   ${cMut}Preparando...$RST"
Get-Static
$cur = 0
while ($true) {
    try {
        Show-Banner
        foreach ($it in $Menu) { $it.B = if ($it.Badge) { try { & $it.Badge } catch { $null } } }
        $pick = Select-Menu $Menu $cur
        if ($pick -eq -1 -or -not $Menu[$pick].Run) {
            $Host.UI.RawUI.BackgroundColor = $OrigBg; $Host.UI.RawUI.ForegroundColor = $OrigFg
            Clear-Host
            return
        }
        $cur = $pick
        $it = $Menu[$cur]
        Show-Header $it.Name
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $res = 'ok'
        try { & $it.Run } catch { $res = 'error'; Fail $_.Exception.Message }
        Write-Log ('{0}: {1} ({2:N0} s)' -f $it.Name, $res, $sw.Elapsed.TotalSeconds)
        $t = if ($sw.Elapsed.TotalMinutes -ge 1) { '{0} min {1} s' -f [int][math]::Floor($sw.Elapsed.TotalMinutes), $sw.Elapsed.Seconds } else { '{0} s' -f $sw.Elapsed.Seconds }
        Write-Host ''
        Rule
        $fin = if ($res -eq 'ok') { "$cOk$gDot$RST ${cTxt}Finalizado en $t" } else { "$cBad$gX$RST ${cTxt}Finalizado con errores en $t" }
        Write-Host "$MG$fin$RST     $(Key 'Enter') ${cMut}Volver al panel$RST"
    } catch {
        Fail ('Error: {0}' -f $_.Exception.Message)
        Write-Host "$MG$(Key 'Enter') ${cMut}Volver al panel$RST"
    }
    do { $k = [Console]::ReadKey($true) } until ($k.Key -eq 'Enter' -or $k.Key -eq 'Escape')
}
