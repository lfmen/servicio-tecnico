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
    }
    return
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'servicio tecnico - luca mengarelli'
New-Item -ItemType Directory -Force -Path $Base | Out-Null
# solo SYSTEM y administradores escriben (la tarea corre como SYSTEM); usuarios solo leen
icacls $Base /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null

# ---------- estilo ----------
# el archivo queda en ascii (ps 5.1 lee -File sin bom como ansi); los glifos se arman con [char]
$e = [char]27
function Rgb($r, $g, $b) { "$e[38;2;$r;$g;${b}m" }
$R     = "$e[0m"
$Sel   = "$e[48;2;20;34;54m"
$cAcc  = Rgb 60 200 255
$cWhi  = Rgb 245 245 250
$cTxt  = Rgb 205 205 220
$cMut  = Rgb 140 140 160
$cDim  = Rgb 85 85 105
$cOk   = Rgb 80 220 140
$cWarn = Rgb 255 196 80
$cBad  = Rgb 255 95 95
$Blk = [string][char]0x2588; $Shd = [string][char]0x2591; $Dot = [string][char]0x25CF
$Arr = [string][char]0x25BA; $Edge = [string][char]0x258C; $Ln = [string][char]0x2500
$Up  = [string][char]0x2191; $Dn = [string][char]0x2193; $Md = [string][char]0x00B7

function Get-Grad([string]$s, [switch]$Shadow) {
    $o = ''
    for ($i = 0; $i -lt $s.Length; $i++) {
        $c = $s[$i]
        if ($c -eq ' ') { $o += ' '; continue }
        $t = $i / [math]::Max(1, $s.Length - 1)
        $cr = 40 + 150 * $t; $cg = 220 - 120 * $t; $cb = 255   # no usar $r: pisa $R (ps no distingue mayusculas)
        if ($Shadow -and $c -ne $Blk[0]) { $cr *= .4; $cg *= .4; $cb *= .5 }   # bordes mas oscuros = efecto 3d
        $o += (Rgb ([int]$cr) ([int]$cg) ([int]$cb)) + $c
    }
    $o + $R
}

# "luca" en ansi shadow, escrito en ascii y traducido a bloques
$Glyph = @{ '#' = 0x2588; '7' = 0x2557; 'I' = 0x2551; 'r' = 0x2554; '=' = 0x2550; 'J' = 0x255D; 'L' = 0x255A; ' ' = 0x20 }
$Art = @(
    '##7     ##7   ##7 ######7 #####7 ',
    '##I     ##I   ##I##r====J##r==##7',
    '##I     ##I   ##I##I     #######I',
    '##I     ##I   ##I##I     ##r==##I',
    '#######7L######rJL######7##I  ##I',
    'L======J L=====J  L=====JL=J  L=J'
) | ForEach-Object { Get-Grad -Shadow (-join ($_.ToCharArray() | ForEach-Object { [char]$Glyph[[string]$_] })) }

function Say($color, $mark, $text) { Write-Host "    $color$mark$R $cTxt$text$R" }
function Step($t) { Say $cAcc $Arr $t }
function Good($t) { Say $cOk $Dot $t }
function Warn($t) { Say $cWarn $Dot $t }
function Fail($t) { Say $cBad $Dot $t }
function Fit([string]$s, [int]$n) { if ($s.Length -gt $n) { $s.Substring(0, $n - 1) + [char]0x2026 } else { $s } }
function Write-Log($msg) { Add-Content "$Base\historial.log" ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $msg) }

function Get-Ago([datetime]$d) {
    $s = (Get-Date) - $d
    if ($s.TotalDays -ge 1) { '{0}d' -f [int][math]::Floor($s.TotalDays) }
    elseif ($s.TotalHours -ge 1) { '{0}h' -f [int][math]::Floor($s.TotalHours) }
    else { '{0}m' -f [int][math]::Floor($s.TotalMinutes) }
}

function Get-Bar([double]$p, [int]$w = 14) {
    $n = [int][math]::Round([math]::Min(1.0, $p) * $w)
    $col = if ($p -lt .6) { $cOk } elseif ($p -lt .85) { $cWarn } else { $cBad }
    "$col$($Blk * $n)$cDim$($Shd * ($w - $n))$R"
}

function Confirm-Action($q) {
    Write-Host -NoNewline "    $cWarn?$R $cTxt$q $cDim(s/n)$R "
    $k = [Console]::ReadKey($true)
    $y = "$($k.KeyChar)" -match '^[sy]$'
    Write-Host $(if ($y) { "${cOk}si$R" } else { "${cDim}no$R" })
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
        Os    = ($os.Caption -replace '^Microsoft\s+Windows\s+', '').ToLower()
        Ver   = ("{0} {1}" -f $(if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }), $os.BuildNumber).Trim().ToLower()
        Cpu   = (($cpu.Name -replace '\((R|TM)\)|CPU|Processor|\d+-Core|with .*|@.*$', '') -replace '\s+', ' ').Trim().ToLower()
        Cores = '{0}c/{1}t' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors
        Ip    = if ($ip) { $ip } else { 'sin red' }
    }
    Update-Activation
}

# ---------- pantalla ----------
function Show-Banner {
    Clear-Host
    $os   = Get-CimInstance Win32_OperatingSystem
    $ramT = $os.TotalVisibleMemorySize / 1MB
    $ramU = $ramT - $os.FreePhysicalMemory / 1MB
    $d    = New-Object IO.DriveInfo $env:SystemDrive
    $dT   = $d.TotalSize / 1GB
    $dU   = $dT - $d.AvailableFreeSpace / 1GB
    $up   = (Get-Date) - $os.LastBootUpTime
    $lic  = if ($Activated) { "$cOk$Dot ${cTxt}activado" } else { "$cBad$Dot ${cTxt}sin activar" }
    $info = @(
        ("equipo   $cTxt{0} $cDim$Md$cTxt {1}" -f (Fit $env:COMPUTERNAME.ToLower() 20), (Fit $env:USERNAME.ToLower() 18)),
        ("windows  $cTxt{0} $cDim$Md$cTxt {1}" -f (Fit $Sys.Os 28), $Sys.Ver),
        "licencia $lic",
        ("cpu      $cTxt{0} $cDim$Md$cTxt {1}" -f (Fit $Sys.Cpu 28), $Sys.Cores),
        ("ram      {0}  $cTxt{1,3:N0}%  $cMut{2:N1} / {3:N0} gb" -f (Get-Bar ($ramU / $ramT)), ($ramU / $ramT * 100), $ramU, $ramT),
        ("disco {4}  {0}  $cTxt{1,3:N0}%  $cMut{2:N0} / {3:N0} gb" -f (Get-Bar ($dU / $dT)), ($dU / $dT * 100), $dU, $dT, $env:SystemDrive.TrimEnd(':').ToLower())
    ) | ForEach-Object { "$cDim$_$R" }

    Write-Host ''
    $side = [Console]::WindowWidth -ge 88
    for ($i = 0; $i -lt 6; $i++) {
        if ($side) { Write-Host "    $($Art[$i])    $($info[$i])" } else { Write-Host "    $($Art[$i])" }
    }
    if (-not $side) { Write-Host ''; $info | ForEach-Object { Write-Host "    $_" } }
    Write-Host ''
    $upS   = if ($up.TotalDays -ge 1) { '{0}d {1}h' -f $up.Days, $up.Hours } else { '{0}h {1}m' -f $up.Hours, $up.Minutes }
    $right = " $($Sys.Ip) $Md encendido $upS $Md $(Get-Date -Format 'dd/MM HH:mm')"
    $rule  = [math]::Max(3, $W - 17 - $right.Length)
    Write-Host "    $(Get-Grad 'servicio tecnico') $cDim$($Ln * $rule)$cMut$right$R"
    Write-Host ''
}

function Format-Row($it, $on) {
    $name = (Fit $it.Name 25).PadRight(26)
    $desc = if ($DescW) { (Fit "$($it.Desc)" ($DescW - 2)).PadRight($DescW) } else { '' }
    $badge = ' ' * $BadgeW
    if ($it.B) {
        $plain = "$Dot $($it.B[0])"
        $badge = (' ' * [math]::Max(0, $BadgeW - $plain.Length)) + "$($it.B[1])$Dot $cMut$($it.B[0])"
    }
    if ($on) { "    $Sel$cAcc$Edge $cAcc$($it.Key)  $cWhi$name$cTxt$desc$badge $R" }
    else     { "      $cDim$($it.Key)  $cTxt$name$cDim$desc$badge $R" }
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
                    [void]$sb.Append("    $cDim$Ln$Ln $sec$R$e[K`r`n")
                }
                [void]$sb.Append((Format-Row $Items[$i] ($i -eq $Index)) + "`r`n")
            }
            [void]$sb.Append("`r`n    $cAcc$Up$Dn$cDim mover   ${cAcc}enter$cDim elegir   ${cAcc}tecla$cDim atajo   ${cAcc}esc$cDim salir$R$e[K")
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
    Write-Host "    $cAcc$Arr $cWhi$title$R"
    Write-Host "    $(Get-Grad ($Ln * $W))"
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

function Invoke-Clean {
    Warn 'borra temporales, cache de updates, volcados y vacia la papelera.'
    if (-not (Confirm-Action 'seguir?')) { return }
    $f = Join-Path $Base 'limpieza.ps1'
    Set-Content -Path $f -Value $CleanScript -Encoding ASCII
    Step 'limpiando...'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $f -Todo
    $last = Get-Content "$Base\limpieza.log" -Tail 1 -ErrorAction SilentlyContinue
    Good ('listo. liberado: {0}' -f ($last -split 'liberado: ')[1])
}

function Install-CleanTask {
    $name = 'ServicioTecnico-Limpieza'
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Good 'la limpieza automatica ya esta activa.'
        if (Confirm-Action 'desactivarla?') { Unregister-ScheduledTask -TaskName $name -Confirm:$false; Good 'tarea quitada.' }
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
    Step 'tarea creada. probandola ahora (como SYSTEM)...'
    $ini = Get-Date
    Start-ScheduledTask -TaskName $name
    $fin = $ini.AddMinutes(10)
    do {
        Start-Sleep 2
        $info = Get-ScheduledTaskInfo -TaskName $name
        $listo = ($info.LastRunTime -ge $ini.AddSeconds(-2)) -and ((Get-ScheduledTask -TaskName $name).State -eq 'Ready')
    } until ($listo -or (Get-Date) -gt $fin)
    if ($listo -and $info.LastTaskResult -eq 0) {
        Good 'prueba ok: la tarea corre sola en cada inicio.'
        $last = Get-Content "$Base\limpieza.log" -Tail 1 -ErrorAction SilentlyContinue
        if ($last) { Good ('primera pasada, liberado: {0}' -f ($last -split 'liberado: ')[1]) }
    } else {
        Fail ('la tarea se creo pero la prueba fallo (resultado: {0}). revisar.' -f $info.LastTaskResult)
    }
}

# ---------- office ----------
function Get-OfficeIds { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue).ProductReleaseIds }

function Install-Office {
    $ids = Get-OfficeIds
    if ($ids) {
        Warn "ya hay office instalado: $ids"
        if (-not (Confirm-Action 'instalar igual?')) { return }
        Write-Host ''
    }
    Write-Host "    ${cMut}elegir version$R"
    $v = Select-Menu @(
        @{ Key = '1'; Name = 'office 2021 ltsc'; Desc = 'word, excel, powerpoint, outlook' },
        @{ Key = '2'; Name = 'office 2024 ltsc'; Desc = 'la mas nueva, mismas apps' }
    )
    if ($v -eq -1) { return }
    if ($v -eq 1) { $ch = 'PerpetualVL2024'; $prod = 'ProPlus2024Volume' } else { $ch = 'PerpetualVL2021'; $prod = 'ProPlus2021Volume' }
    New-Item -ItemType Directory -Force -Path $OfficeDir | Out-Null
    $setup = Join-Path $OfficeDir 'setup.exe'
    $cfg   = Join-Path $OfficeDir 'config.xml'
    if (-not (Test-Path $setup)) {
        Step 'descargando setup.exe de microsoft...'
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
    Step 'descargando e instalando office (puede tardar)...'
    $p = Start-Process $setup -ArgumentList "/configure `"$cfg`"" -WorkingDirectory $OfficeDir -Wait -PassThru
    if ($p.ExitCode -eq 0) { Good 'office instalado.' } else { Fail "el instalador termino con codigo $($p.ExitCode)" }
}

# ---------- store ----------
function Install-Store {
    Step 'instalando microsoft store...'
    try { Start-Process wsreset.exe -ArgumentList '-i' -Wait -ErrorAction Stop } catch {}
    Start-Sleep 5
    $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    if (-not $pkg) {
        Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.WindowsStore*' -ErrorAction SilentlyContinue | ForEach-Object {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.FullName)\AppxManifest.xml" -ErrorAction SilentlyContinue
        }
        $pkg = Get-AppxPackage -AllUsers Microsoft.WindowsStore
    }
    if ($pkg) { Good 'microsoft store instalada.' }
    else { Fail 'no se pudo confirmar. revisa la conexion y reintenta, puede tardar unos minutos.' }
}

# ---------- reparacion ----------
function Repair-Windows {
    Warn 'puede tardar entre 10 y 30 minutos. no cerrar la ventana.'
    if (-not (Confirm-Action 'seguir?')) { return }
    Write-Host ''
    Step 'dism: reparando la imagen de windows'
    DISM.exe /Online /Cleanup-Image /RestoreHealth
    if ($LASTEXITCODE -eq 0) { Good 'imagen de windows ok.' } else { Fail "dism termino con codigo $LASTEXITCODE" }
    Write-Host ''
    Step 'sfc: verificando archivos del sistema'
    sfc.exe /scannow
    if ($LASTEXITCODE -eq 0) { Good 'archivos del sistema ok.' }
    else { Warn 'sfc encontro o reparo problemas, ver el resultado de arriba. conviene reiniciar.' }
}

function Reset-Network {
    Warn 'se corta la conexion unos segundos.'
    if (-not (Confirm-Action 'seguir?')) { return }
    Write-Host ''
    ipconfig /flushdns | Out-Null;          Good 'cache dns vaciada'
    netsh winsock reset | Out-Null;         Good 'winsock reiniciado'
    netsh int ip reset | Out-Null;          Good 'pila tcp/ip reiniciada'
    ipconfig /release | Out-Null
    ipconfig /renew | Out-Null;             Good 'ip renovada'
    Write-Host ''
    Warn 'hay que reiniciar para terminar.'
    Restart-Now
}

function New-RestorePoint {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    # windows deja crear uno cada 24 h; esto saca el limite
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord
    Step 'creando punto de restauracion...'
    Checkpoint-Computer -Description ("servicio tecnico {0}" -f (Get-Date -Format 'dd/MM HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Good 'punto creado. se puede volver desde rstrui.exe'
}

function Restart-Now {
    if (Confirm-Action 'reiniciar el equipo ahora?') { Good 'reiniciando en 5 segundos...'; shutdown.exe /r /t 5 }
}

# ---------- reporte ----------
function New-Report {
    Step 'juntando datos del equipo...'
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $mb   = Get-CimInstance Win32_BaseBoard
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $mem  = @(Get-CimInstance Win32_PhysicalMemory)
    $gpu  = @(Get-CimInstance Win32_VideoController)
    $ddr  = @{ 20 = 'ddr'; 21 = 'ddr2'; 24 = 'ddr3'; 26 = 'ddr4'; 34 = 'ddr5' }
    function Enc($s) { [Net.WebUtility]::HtmlEncode(([string]$s -replace 'To Be Filled By O\.E\.M\.\s*', '').Trim()) }   # H choca con el alias de Get-History
    function Kv($k, $v) { $t = Enc $v; if (-not $t) { $t = '<small>sin dato</small>' }; "<tr><th>$k</th><td>$t</td></tr>" }
    function Meter([int]$p, [switch]$Health) {
        $bad = if ($Health) { 100 - $p } else { $p }
        $c = if ($bad -lt 60) { 'ok' } elseif ($bad -lt 85) { 'warn' } else { 'bad' }
        "<div class=bar><i class=$c style='width:$p%'></i></div>"
    }
    function Kpi($label, $value, $cls) { "<div class='kpi $cls'><span>$label</span><b>$(Enc $value)</b></div>" }

    Step 'discos...'
    $sick = 0
    $disks = foreach ($d in Get-PhysicalDisk) {
        $rc = try { $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { $null }
        $x = @()
        if ($null -ne $rc.Wear) { $x += "desgaste $($rc.Wear)%" }
        if ($rc.Temperature) { $x += "$($rc.Temperature) $([char]0xB0)c" }
        if ($rc.PowerOnHours) { $x += '{0:N0} h de uso' -f $rc.PowerOnHours }
        $ok = $d.HealthStatus -eq 'Healthy'
        if (-not $ok) { $sick++ }
        "<tr><th>$(Enc $d.FriendlyName)</th><td>$(Enc ("{0} $Md {1} $Md {2:N0} gb" -f $d.MediaType, $d.BusType, ($d.Size / 1GB)))<br><small>$(Enc ($x -join " $Md "))</small></td><td><span class='pill $(if ($ok) { 'ok' } else { 'bad' })'>$(if ($ok) { 'sano' } else { Enc $d.HealthStatus })</span></td></tr>"
    }
    $vols = foreach ($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 } | Sort-Object DriveLetter) {
        $p = [int](($v.Size - $v.SizeRemaining) / $v.Size * 100)
        "<tr><th>$($v.DriveLetter):</th><td>$(Meter $p)<small>$(Enc ("{0:N0} de {1:N0} gb usados $Md {2:N0} gb libres" -f (($v.Size - $v.SizeRemaining) / 1GB), ($v.Size / 1GB), ($v.SizeRemaining / 1GB)))</small></td></tr>"
    }

    Step 'bateria...'
    $batKpi = Kpi 'bateria' 'sin bateria' ''
    $batHtml = '<p class=muted>sin bateria (equipo de escritorio)</p>'
    if (Get-CimInstance Win32_Battery) {
        try {
            $xf = Join-Path $env:TEMP 'st-bateria.xml'
            powercfg /batteryreport /xml /output $xf | Out-Null
            $b = @(([xml](Get-Content $xf -Raw)).BatteryReport.Batteries.Battery)[0]
            $s = [int]([double]$b.FullChargeCapacity / [double]$b.DesignCapacity * 100)
            $batKpi = Kpi 'salud bateria' "$s%" $(if ($s -ge 80) { 'ok' } elseif ($s -ge 60) { 'warn' } else { 'bad' })
            $batHtml = "$(Meter $s -Health)<table>$(Kv 'modelo' "$($b.Manufacturer) $($b.Id)")$(Kv 'capacidad de fabrica' ('{0:N0} mwh' -f [double]$b.DesignCapacity))$(Kv 'capacidad actual' ('{0:N0} mwh ({1}%)' -f [double]$b.FullChargeCapacity, $s))$(Kv 'ciclos de carga' $b.CycleCount)</table>"
        } catch { $batHtml = '<p class=muted>no se pudo leer el reporte de bateria</p>' }
    }

    $ram   = [math]::Round(($mem | Measure-Object Capacity -Sum).Sum / 1GB)
    $mods  = ($mem | ForEach-Object { '{0} gb {1} {2} mhz' -f ($_.Capacity / 1GB), $ddr[[int]$_.SMBIOSMemoryType], $_.Speed }) -join ' + '
    $cFree = (New-Object IO.DriveInfo $env:SystemDrive).AvailableFreeSpace / 1GB
    $up    = (Get-Date) - $os.LastBootUpTime
    $hist  = @(Get-Content "$Base\historial.log" -Tail 12 -ErrorAction SilentlyContinue) + @(Get-Content "$Base\limpieza.log" -Tail 5 -ErrorAction SilentlyContinue)
    $pc    = $env:COMPUTERNAME.ToLower()
    $cv    = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $html = @"
<!doctype html><html lang=es><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>reporte $pc</title><style>
:root{--bg:#0a0c11;--card:#11141c;--line:#1d2230;--txt:#e6e8ef;--mut:#8a90a2;--ok:#4ade80;--warn:#fbbf24;--bad:#f87171;--a1:#28dcff;--a2:#aa64ff}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(1200px 600px at 10% -10%,#16213a 0,transparent 60%),var(--bg);color:var(--txt);font:15px/1.5 "Segoe UI",system-ui,sans-serif;padding:48px 16px}
.wrap{max-width:1040px;margin:auto}
header{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;flex-wrap:wrap;margin-bottom:32px}
h1{font-size:72px;line-height:.9;margin:0;font-weight:800;letter-spacing:-3px;background:linear-gradient(90deg,var(--a1),var(--a2));-webkit-background-clip:text;background-clip:text;color:transparent}
.sub{color:var(--mut);letter-spacing:.25em;text-transform:uppercase;font-size:12px;margin-top:10px}
.meta{text-align:right;color:var(--mut);font-size:13px}.meta b{color:var(--txt);font-size:20px;display:block}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin-bottom:16px}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px 18px;position:relative;overflow:hidden}
.kpi:before{content:"";position:absolute;inset:0 auto 0 0;width:3px;background:var(--line)}
.kpi.ok:before{background:var(--ok)}.kpi.warn:before{background:var(--warn)}.kpi.bad:before{background:var(--bad)}
.kpi span{display:block;color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.14em}.kpi b{font-size:22px;font-weight:600}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr));gap:16px}
section{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:20px 22px}
h2{margin:0 0 10px;font-size:12px;text-transform:uppercase;letter-spacing:.18em;color:var(--a1)}
table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:9px 0;border-top:1px solid var(--line);vertical-align:top}
tr:first-child th,tr:first-child td{border-top:0}th{color:var(--mut);font-weight:500;width:36%;padding-right:12px}
small,.muted{color:var(--mut)}td:last-child{text-align:right}td:only-of-type{text-align:left}
.bar{height:6px;background:var(--line);border-radius:6px;overflow:hidden;margin:6px 0}.bar i{display:block;height:100%;border-radius:6px}
.bar .ok{background:var(--ok)}.bar .warn{background:var(--warn)}.bar .bad{background:var(--bad)}
.pill{font-size:12px;padding:2px 10px;border-radius:99px;white-space:nowrap}.pill.ok{background:#4ade8022;color:var(--ok)}.pill.bad{background:#f8717122;color:var(--bad)}
pre{margin:0;color:var(--mut);font:12px/1.7 Consolas,monospace;white-space:pre-wrap}.full{grid-column:1/-1}
footer{margin-top:32px;color:var(--mut);font-size:12px;text-align:center}
@media print{:root{--bg:#fff;--card:#fff;--line:#ddd;--txt:#111;--mut:#555}body{background:#fff;padding:0}}
</style></head><body><div class=wrap>
<header><div><h1>luca</h1><div class=sub>servicio t&eacute;cnico &middot; reporte del equipo</div></div>
<div class=meta><b>$(Enc $pc)</b>$(Enc "$($cs.Manufacturer) $($cs.Model)")<br>$(Get-Date -Format 'dd/MM/yyyy HH:mm')</div></header>
<div class=kpis>
$(Kpi 'windows' $(if ($Activated) { 'activado' } else { 'sin activar' }) $(if ($Activated) { 'ok' } else { 'bad' }))
$(Kpi 'discos' $(if ($sick) { "$sick con problemas" } else { 'todos sanos' }) $(if ($sick) { 'bad' } else { 'ok' }))
$batKpi
$(Kpi 'memoria' "$ram gb" '')
$(Kpi "libre en $($env:SystemDrive)" ('{0:N0} gb' -f $cFree) $(if ($cFree -lt 15) { 'bad' } elseif ($cFree -lt 40) { 'warn' } else { 'ok' }))
</div>
<div class=grid>
<section><h2>equipo</h2><table>
$(Kv 'fabricante' $cs.Manufacturer)$(Kv 'modelo' $cs.Model)$(Kv 'numero de serie' $bios.SerialNumber)$(Kv 'placa madre' "$($mb.Manufacturer) $($mb.Product)")$(Kv 'bios' ("{0} $Md {1:dd/MM/yyyy}" -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate))
</table></section>
<section><h2>windows</h2><table>
$(Kv 'version' $os.Caption)$(Kv 'compilacion' ("{0} $Md {1}" -f $(if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }), $os.BuildNumber))$(Kv 'instalado' ('{0:dd/MM/yyyy}' -f $os.InstallDate))$(Kv 'licencia' $(if ($Activated) { 'activado' } else { 'sin activar' }))$(Kv 'encendido hace' ('{0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes))
</table></section>
<section><h2>hardware</h2><table>
$(Kv 'procesador' $cpu.Name)$(Kv 'nucleos' ('{0} nucleos / {1} hilos' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors))$(Kv 'memoria' "$ram gb ($mods)")$(Kv 'video' (($gpu | ForEach-Object Name) -join ' + '))
</table></section>
<section><h2>bateria</h2>$batHtml</section>
<section class=full><h2>discos fisicos</h2><table>$($disks -join '')</table></section>
<section class=full><h2>unidades</h2><table>$($vols -join '')</table></section>
<section class=full><h2>historial de servicio</h2><pre>$(Enc ($hist -join "`n"))</pre></section>
</div><footer>generado por servicio t&eacute;cnico &middot; luca mengarelli</footer></div></body></html>
"@
    $file = Join-Path ([Environment]::GetFolderPath('Desktop')) ("reporte-{0}-{1}.html" -f $pc, (Get-Date -Format 'yyyyMMdd-HHmm'))
    Set-Content -Path $file -Value $html -Encoding UTF8
    Good "reporte guardado en el escritorio: $(Split-Path $file -Leaf)"
    Start-Process $file
}

# ---------- menu ----------
$Menu = @(
    @{ Sec = 'herramientas'; Key = '1'; Name = 'winutil'; Desc = 'tweaks y programas de windows'
       Run = { Invoke-RestMethod 'https://christitus.com/win' | Invoke-Expression } },
    @{ Sec = 'herramientas'; Key = '2'; Name = 'activar windows / office'; Desc = 'via get.activated.win'
       Badge = { if ($Activated) { 'activado', $cOk } else { 'sin activar', $cBad } }
       Run = { Invoke-RestMethod 'https://get.activated.win' | Invoke-Expression; Update-Activation } },
    @{ Sec = 'instalar'; Key = '3'; Name = 'office ltsc'; Desc = '2021 o 2024, descarga e instala'
       Badge = { $ids = Get-OfficeIds; if ($ids -match '20\d\d') { "$($Matches[0]) instalado", $cOk } elseif ($ids) { 'instalado', $cOk } else { 'no instalado', $cDim } }
       Run = { Install-Office } },
    @{ Sec = 'instalar'; Key = '4'; Name = 'microsoft store'; Desc = 'instalarla en ltsc'
       Badge = { if (Get-AppxPackage Microsoft.WindowsStore) { 'instalada', $cOk } else { 'no instalada', $cDim } }
       Run = { Install-Store } },
    @{ Sec = 'mantenimiento'; Key = '5'; Name = 'limpiar ahora'; Desc = 'temporales, updates y papelera'
       Badge = { $l = Get-Content "$Base\limpieza.log" -Tail 1 -ErrorAction SilentlyContinue
                 if ($l) { "hace $(Get-Ago ([datetime]::ParseExact($l.Substring(0, 16), 'yyyy-MM-dd HH:mm', $null)))", $cMut } else { 'nunca', $cWarn } }
       Run = { Invoke-Clean } },
    @{ Sec = 'mantenimiento'; Key = '6'; Name = 'limpieza automatica'; Desc = 'tarea que corre en cada inicio'
       Badge = { if (Get-ScheduledTask -TaskName 'ServicioTecnico-Limpieza' -ErrorAction SilentlyContinue) { 'activa', $cOk } else { 'inactiva', $cDim } }
       Run = { Install-CleanTask } },
    @{ Sec = 'mantenimiento'; Key = '7'; Name = 'reparar windows'; Desc = 'dism + sfc, archivos del sistema'
       Run = { Repair-Windows } },
    @{ Sec = 'mantenimiento'; Key = '8'; Name = 'reiniciar red'; Desc = 'dns, winsock y tcp/ip'
       Run = { Reset-Network } },
    @{ Sec = 'mantenimiento'; Key = '9'; Name = 'punto de restauracion'; Desc = 'crear uno antes de tocar algo'
       Badge = { $p = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Select-Object -Last 1
                 if ($p) { "hace $(Get-Ago ([Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime)))", $cMut } else { 'ninguno', $cWarn } }
       Run = { New-RestorePoint } },
    @{ Sec = 'equipo'; Key = 'r'; Name = 'reporte del equipo'; Desc = 'hardware, discos y bateria'
       Run = { New-Report } },
    @{ Sec = 'equipo'; Key = 'x'; Name = 'reiniciar equipo'; Desc = ''
       Run = { Restart-Now } },
    @{ Sec = 'equipo'; Key = 'q'; Name = 'salir'; Desc = '' }
)

$DescW  = if ([Console]::WindowWidth -ge 88) { 35 } else { 0 }
$BadgeW = 16
$W      = 32 + $DescW + $BadgeW

Write-Host ''
Write-Host "    ${cMut}preparando...$R"
Get-Static
$cur = 0
while ($true) {
    try {
        Show-Banner
        foreach ($it in $Menu) { $it.B = if ($it.Badge) { try { & $it.Badge } catch { $null } } }
        $pick = Select-Menu $Menu $cur
        if ($pick -eq -1 -or -not $Menu[$pick].Run) { Clear-Host; return }
        $cur = $pick
        $it = $Menu[$cur]
        Show-Header $it.Name
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $res = 'ok'
        try { & $it.Run } catch { $res = 'error'; Fail $_.Exception.Message }
        Write-Log ('{0}: {1} ({2:N0}s)' -f $it.Name, $res, $sw.Elapsed.TotalSeconds)
        $t = if ($sw.Elapsed.TotalMinutes -ge 1) { '{0}m {1}s' -f [int][math]::Floor($sw.Elapsed.TotalMinutes), $sw.Elapsed.Seconds } else { '{0}s' -f $sw.Elapsed.Seconds }
        Write-Host ''
        Write-Host "    $cDim$Ln$Ln $t $Md enter para volver$R"
    } catch {
        Fail ('error: {0}' -f $_.Exception.Message)
        Write-Host "    ${cDim}enter para volver$R"
    }
    do { $k = [Console]::ReadKey($true) } until ($k.Key -eq 'Enter' -or $k.Key -eq 'Escape')
}
