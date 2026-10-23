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
function BgRgb($cr, $cg, $cb) { "$e[48;2;$cr;$cg;${cb}m" }

# windows powershell arranca con fondo azul y ESC[0m vuelve a ese azul: se fuerza el negro de la paleta
$OrigBg = $Host.UI.RawUI.BackgroundColor; $OrigFg = $Host.UI.RawUI.ForegroundColor
$BGDEF  = if ($OrigBg -ne 'Black') { "$e[40m" } else { "$e[49m" }
$Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'Gray'
try { $Host.PrivateData.ProgressBackgroundColor = 'Black'; $Host.PrivateData.ProgressForegroundColor = 'Gray' } catch {}

$RST    = "$e[0m$BGDEF"
$BOLD   = "$e[1m"
$BGSEL  = BgRgb 16 28 50
$BGKEY  = (BgRgb 36 38 48) + (Rgb 225 225 232)
$cAcc   = Rgb 90 170 255
$cWhi   = Rgb 245 245 247
$cTxt   = Rgb 214 214 220
$cMut   = Rgb 142 150 166
$cDim   = Rgb 90 98 116
$cLine  = Rgb 50 58 76
$cOk    = Rgb 61 220 151
$cWarn  = Rgb 245 184 65
$cBad   = Rgb 255 92 92
$gDot   = [string][char]0x25CF; $gEdge = [string][char]0x258C; $gLine = [string][char]0x2500
$gHeavy = [string][char]0x2501; $gStep = [string][char]0x203A; $gTri  = [string][char]0x25B2
$gX     = [string][char]0x00D7; $gUp   = [string][char]0x2191; $gDn   = [string][char]0x2193
$gLeft  = [string][char]0x2190; $gRight = [string][char]0x2192; $gSep = [string][char]0x00B7
$gTL    = [string][char]0x256D; $gTR   = [string][char]0x256E; $gBL   = [string][char]0x2570
$gBR    = [string][char]0x256F; $gV    = [string][char]0x2502; $gPlay = [string][char]0x25B8
$gTop   = [string][char]0x2580; $gBot  = [string][char]0x2584; $gRing = [string][char]0x25CB
$MG     = '   '
$CW     = [math]::Min(92, [Console]::WindowWidth - 5)
$Brand  = U 'Servicio T\u00e9cnico'
$Host.UI.RawUI.WindowTitle = "$Brand $gSep Luca Mengarelli"

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

# barra indeterminada: un segmento que va y viene
function Get-Loader([int]$i, [int]$w = 16) {
    $seg = 4; $span = $w - $seg
    $p = $i % (2 * $span); if ($p -gt $span) { $p = 2 * $span - $p }
    "$cLine$($gHeavy * $p)$cAcc$($gHeavy * $seg)$cLine$($gHeavy * ($span - $p))$RST"
}

# ---------- panel led ----------
# tipografia de 5x7 puntos para el nombre
$Font = @{
    'L' = '#....', '#....', '#....', '#....', '#....', '#....', '#####'
    'U' = '#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'
    'C' = '.####', '#....', '#....', '#....', '#....', '#....', '.####'
    'A' = '.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'
    'M' = '#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'
    'E' = '#####', '#....', '#....', '####.', '#....', '#....', '#####'
    'N' = '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'
    'G' = '.####', '#....', '#....', '#..##', '#...#', '#...#', '.###.'
    'R' = '####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'
    'I' = '###', '.#.', '.#.', '.#.', '.#.', '.#.', '###'
    ' ' = '...', '...', '...', '...', '...', '...', '...'
}

# version de 5 filas para el encabezado, donde cada punto ocupa una celda entera
$FontSmall = @{
    'L' = '#...', '#...', '#...', '#...', '####'
    'U' = '#..#', '#..#', '#..#', '#..#', '.##.'
    'C' = '.###', '#...', '#...', '#...', '.###'
    'A' = '.##.', '#..#', '####', '#..#', '#..#'
    'M' = '#...#', '##.##', '#.#.#', '#...#', '#...#'
    'E' = '####', '#...', '###.', '#...', '####'
    'N' = '#..#', '##.#', '#.##', '#..#', '#..#'
    'G' = '.###', '#...', '#.##', '#..#', '.###'
    'R' = '###.', '#..#', '###.', '#.#.', '#..#'
    'I' = '###', '.#.', '.#.', '.#.', '###'
    ' ' = '..', '..', '..', '..', '..'
}

# el render va en c# porque powershell solo no llega a 20 cuadros por segundo
$LedSrc = @'
using System;
using System.Text;
using System.Collections.Generic;

// acuario ascii: la escena se calcula en pixeles cuadrados (2 por caracter de alto) y cada celda
// se dibuja con un caracter segun lo que la cubre: simbolos densos sobre una baldosa, ' y . en los bordes
public class Aquarium
{
    public int W, Rows, PH;
    public double IntroEnd = 5.4;
    bool intro;
    string reset, bgDef, margin;
    Random rnd = new Random(11);
    List<double[]> bubbles = new List<double[]>();   // x, y, velocidad, fase, brillo
    List<double[]> trail = new List<double[]>();     // x, y, nacimiento
    List<int[]> namePx = new List<int[]>();
    List<double[]> nameFrom = new List<double[]>();  // x0, y0, demora
    string[] fg = new string[24], bg = new string[24];
    double lastT = -1;
    double[,] I;
    int[,] K;
    bool[,] Bub;
    double[,] Tr;

    const string Dense = "$%SX&#8@$%SX";
    const string Mid = "xts+=";

    // nameRows: bitmap del nombre (# = punto). cada punto ocupa sx columnas y una fila entera
    public Aquarium(int w, int rows, bool intro, string[] nameRows, int sx, string reset, string bgDef, string margin, bool mascot)
    {
        W = w; Rows = rows; PH = rows * 2; this.intro = intro;
        this.reset = reset; this.bgDef = bgDef; this.margin = margin;
        I = new double[PH, W]; K = new int[PH, W]; Bub = new bool[PH, W]; Tr = new double[Rows, W];
        this.mascot = mascot; mx = -20; targetX = W * 0.3; stateEnd = 1e9;

        // 0-13 escala azul; 14-21 mascota y su compu; 22-23 baldosas
        string[] fixedColors = { "217;119;87", "232;145;112", "176;88;62", "24;20;20", "170;175;185", "95;100;112", "40;90;160", "150;220;255", "14;22;40", "20;34;62" };
        for (int q = 0; q < 24; q++) { string c = q < 14 ? Ramp(q / 10.0) : fixedColors[q - 14]; fg[q] = "\x1b[38;2;" + c + "m"; bg[q] = "\x1b[48;2;" + c + "m"; }

        int bw = nameRows[0].Length * sx, bh = nameRows.Length;
        int ox = Math.Max(0, (W - bw) / 2);
        int oy = intro ? (int)(Rows * 0.42 - bh / 2.0) : 0;
        for (int r = 0; r < nameRows.Length; r++)
            for (int c = 0; c < nameRows[r].Length; c++)
            {
                if (nameRows[r][c] != '#') continue;
                for (int k = 0; k < sx; k++)
                    for (int h = 0; h < 2; h++)
                    {
                        int x = ox + c * sx + k, y = 2 * (oy + r) + h;
                        if (x < 0 || x >= W || y < 0 || y >= PH) continue;
                        namePx.Add(new int[] { x, y });
                        // cada punto del nombre sube desde abajo, como una burbuja, y se acomoda en su lugar
                        nameFrom.Add(new double[] { x + (rnd.NextDouble() - 0.5) * W * 0.5, PH + rnd.NextDouble() * PH * 0.6, rnd.NextDouble() * 0.5 + (double)x / W * 0.6 });
                    }
            }
    }

    // azul: tenue, azul electrico, y casi blanco cuando se pasa de 1 (destellos)
    static string Ramp(double v)
    {
        if (v <= 0) return "22;30;48";
        int r, g, b;
        if (v <= 0.6) { double f = v / 0.6; r = (int)(30 + 10 * f); g = (int)(60 + 60 * f); b = (int)(130 + 125 * f); }
        else if (v <= 1.0) { double f = (v - 0.6) / 0.4; r = (int)(40 + 90 * f); g = (int)(120 + 80 * f); b = 255; }
        else { double f = Math.Min(1, (v - 1) / 0.3); r = (int)(130 + 100 * f); g = (int)(200 + 45 * f); b = 255; }
        return r + ";" + g + ";" + b;
    }

    static double Hash(int n) { n = (n << 13) ^ n; return ((n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff) / 2147483647.0; }

    void Plot(double x, double y, double v)
    {
        int ix = (int)Math.Round(x), iy = (int)Math.Round(y);
        if (ix >= 0 && ix < W && iy >= 0 && iy < PH && v > I[iy, ix]) I[iy, ix] = v;
    }

    // tiburon de perfil: hocico en punta, aleta dorsal, pectoral, cola en medialuna, ojo y branquias
    void Shark(double hx, double hy, double ang, double L, double t, int seed)
    {
        double ca = Math.Cos(ang), sa = Math.Sin(ang);
        int x0 = (int)(hx - 1.1 * L), x1 = (int)(hx + 1.1 * L), y0 = (int)(hy - 1.1 * L), y1 = (int)(hy + 1.1 * L);
        for (int y = Math.Max(0, y0); y <= Math.Min(PH - 1, y1); y++)
            for (int x = Math.Max(0, x0); x <= Math.Min(W - 1, x1); x++)
            {
                double dx = x - hx, dy = y - hy;
                double u = -(dx * ca + dy * sa);          // distancia hacia la cola
                double v = -dx * sa + dy * ca;            // lateral (negativo = lomo)
                if (u < 0 || u > L) continue;
                double w = v - L * 0.05 * Math.Sin(u / L * 4 - t * 6 + seed) * (u / L) * (u / L);
                double s = u / (0.84 * L);
                double hw = s <= 1 ? 0.12 * L * Math.Pow(Math.Sin(Math.PI * s), 0.65) + 0.3 : 0;
                double val = 0;
                if (s <= 1 && Math.Abs(w) <= hw)
                {
                    val = 0.72 + 0.3 * (w / hw);                                        // panza mas clara
                    double ex = u - 0.09 * L, ey = w + 0.035 * L;
                    if (ex * ex + ey * ey < Math.Max(0.8, 0.0009 * L * L)) val = 0.15;  // ojo
                    for (int g = 0; g < 3; g++)
                        if (Math.Abs(u - (0.2 + g * 0.035) * L) < 0.45 && Math.Abs(w) < hw * 0.6) val = 0.25;   // branquias
                }
                else
                {
                    if (u > 0.28 * L && u < 0.5 * L)
                    {   // aleta dorsal
                        double pk = u < 0.43 * L ? (u - 0.28 * L) / (0.15 * L) : (0.5 * L - u) / (0.07 * L);
                        if (w < -hw && w > -hw - 0.24 * L * pk) val = 0.55;
                    }
                    if (u > 0.2 * L && u < 0.42 * L)
                    {   // aleta pectoral
                        double pk = u < 0.3 * L ? (u - 0.2 * L) / (0.1 * L) : (0.42 * L - u) / (0.12 * L);
                        if (w > hw && w < hw + 0.15 * L * pk) val = Math.Max(val, 0.6);
                    }
                    if (u > 0.8 * L)
                    {   // cola: lobulo de arriba mas largo
                        double f = (u - 0.8 * L) / (0.2 * L), up = 0.3 * L * f, dn = 0.18 * L * f, th = 0.05 * L + 0.04 * L * (1 - f);
                        if ((w < 0 && -w < up && -w > up - th) || (w >= 0 && w < dn && w > dn - th) || Math.Abs(w) < 0.03 * L + 0.5) val = Math.Max(val, 0.6);
                    }
                }
                if (val > I[y, x]) I[y, x] = val;
            }
        // estela de guiones detras de la cola
        if (rnd.NextDouble() < 0.7) trail.Add(new double[] { hx - ca * L + (rnd.NextDouble() - 0.5) * 3, hy - sa * L + (rnd.NextDouble() - 0.5) * 4, t });
    }

    public string Frame(double t)
    {
        double dt = lastT < 0 ? 0 : Math.Max(0, Math.Min(0.2, t - lastT));
        lastT = t;
        Array.Clear(I, 0, I.Length);
        Array.Clear(Bub, 0, Bub.Length);
        Array.Clear(Tr, 0, Tr.Length);

        // burbujas: columnas a los costados al empezar la intro, sueltas el resto del tiempo
        double rate = intro ? 18 : 2.5;
        int n = (int)(rate * dt) + (rnd.NextDouble() < rate * dt % 1 ? 1 : 0);
        for (int k = 0; k < n; k++)
        {
            double bx = intro && t < 2.4 && rnd.NextDouble() < 0.7 ? (rnd.Next(2) == 0 ? W * 0.06 : W * 0.94) + (rnd.NextDouble() - 0.5) * W * 0.05 : rnd.NextDouble() * W;
            bubbles.Add(new double[] { bx, PH + 1, (intro ? 10 : 5) + rnd.NextDouble() * 10, rnd.NextDouble() * 6.3, 0.5 + rnd.NextDouble() * 0.5 });
        }
        for (int i = bubbles.Count - 1; i >= 0; i--)
        {
            double[] b = bubbles[i];
            b[1] -= b[2] * dt;
            if (b[1] < -2) { bubbles.RemoveAt(i); continue; }
            int bx = (int)Math.Round(b[0] + Math.Sin(t * 3 + b[3]) * 0.8), by = (int)Math.Round(b[1]);
            if (bx >= 0 && bx < W && by >= 0 && by < PH) Bub[by, bx] = true;
        }

        // tiburones (antes que el nombre: nadan por detras de las letras)
        if (intro)
        {
            double L = Math.Min(54, W * 0.45), cx = W / 2.0, cy = PH / 2.0;
            double ta = -2.7 + t * 0.75, rx = W * 0.40, ry = PH * 0.40;
            Shark(cx + rx * Math.Cos(ta), cy + ry * Math.Sin(ta), Math.Atan2(ry * Math.Cos(ta), -rx * Math.Sin(ta)), L, t, 0);
            double tb = 0.5 - t * 0.6, rx2 = W * 0.33, ry2 = PH * 0.30;
            Shark(cx + rx2 * Math.Cos(tb), cy + ry2 * Math.Sin(tb), Math.Atan2(-ry2 * Math.Cos(tb), rx2 * Math.Sin(tb)), L * 0.75, t, 4);
        }
        else
        {
            double cyc = (t - 6) % 45;
            if (t > 6 && cyc < 7)
            {
                double L = 30, x = -0.2 * L + cyc * (W + 1.4 * L) / 7;
                Shark(x, PH * 0.45 + Math.Sin(t * 1.2) * 2, 0.06 * Math.Cos(t * 1.2), L, t, 2);
            }
        }

        // nombre: en la intro cada punto sube y se acomoda; ya ubicado, tapa lo que pase por detras
        double start = 2.0;
        for (int i = 0; i < namePx.Count; i++)
        {
            int x = namePx[i][0], y = namePx[i][1];
            double shimmer = 0.78 + 0.22 * Math.Sin(t * 2.2 - x * 0.12 + y * 0.15);
            if (!intro) { I[y, x] = shimmer; continue; }
            double p = (t - start - nameFrom[i][2]) / 1.1;
            if (p <= 0) continue;
            if (p >= 1) { I[y, x] = shimmer + Math.Max(0, 0.45 - (p - 1) * 1.1 * 0.9); continue; }   // destello al llegar
            double e = 1 - Math.Pow(1 - p, 3);
            Plot(nameFrom[i][0] + (x - nameFrom[i][0]) * e, nameFrom[i][1] + (y - nameFrom[i][1]) * e, 0.55 + 0.4 * p);
        }

        // estela: guiones que se apagan
        for (int i = trail.Count - 1; i >= 0; i--)
        {
            double age = t - trail[i][2];
            if (age > 1.6 || age < 0) { trail.RemoveAt(i); continue; }
            int tx = (int)Math.Round(trail[i][0]), ty = (int)Math.Round(trail[i][1]) / 2;
            if (tx >= 0 && tx < W && ty >= 0 && ty < Rows) Tr[ty, tx] = Math.Max(Tr[ty, tx], 0.7 - age * 0.4);
        }

        for (int y = 0; y < PH; y++)
            for (int x = 0; x < W; x++) K[y, x] = Q(I[y, x]);
        if (mascot) DrawMascot(t, dt);

        StringBuilder sb = new StringBuilder(W * Rows * 10);
        int slot = (int)(t * 3);
        for (int r = 0; r < Rows; r++)
        {
            sb.Append(margin);
            int cf = -1, cb = -1;   // color actual de frente y fondo (-1 = sin definir, -2 = fondo de la consola)
            for (int x = 0; x < W; x++)
            {
                int a = K[2 * r, x], b = K[2 * r + 1, x];
                char ch;
                int wf, wb = -2;
                if (a >= 14 || b >= 14)
                {   // mascota: pixel art solido con medios bloques
                    if (a == 0) { ch = '\u2584'; wf = b; }
                    else if (b == 0) { ch = '\u2580'; wf = a; }
                    else { ch = '\u2580'; wf = a; wb = b; }
                }
                else
                {
                    double va = I[2 * r, x], vb = I[2 * r + 1, x], m = Math.Max(va, vb);
                    if (va >= 0.06 && vb >= 0.06)
                    {   // celda llena: simbolo denso sobre baldosa; algunos cambian de a ratos
                        int h = x * 7919 + r * 104729;
                        if (Hash(h + slot) < 0.04) h += slot;
                        ch = m < 0.32 ? ':' : (m < 0.6 ? Mid[(int)(Hash(h) * Mid.Length)] : Dense[(int)(Hash(h) * Dense.Length)]);
                        wf = Q(m); wb = m < 0.6 ? 22 : 23;
                    }
                    else if (m >= 0.06) { ch = va >= 0.06 ? (m > 0.6 ? '"' : '\'') : (m > 0.6 ? ',' : '.'); wf = Q(m); }
                    else if (Bub[2 * r, x] || Bub[2 * r + 1, x]) { ch = 'o'; wf = 7; }
                    else if (Tr[r, x] > 0.05) { ch = Tr[r, x] > 0.45 ? '-' : '.'; wf = Q(Tr[r, x]); }
                    else { ch = (x & 1) == 0 ? '\u00b7' : ' '; wf = 0; }
                }
                if (wb != cb) { sb.Append(wb == -2 ? bgDef : bg[wb]); cb = wb; }
                if (wf != cf) { sb.Append(fg[wf]); cf = wf; }
                sb.Append(ch);
            }
            sb.Append(reset);
            if (r < Rows - 1) sb.Append("\r\n");
        }
        return sb.ToString();
    }

    // ---- mascota de claude: camina, salta, parpadea y se sienta a laburar con su compu ----
    bool mascot;
    double mx, targetX, stateEnd, jumpAt = -9, nextBlink = 2;
    int mState = 0, facing = 1;   // 0 camina, 1 trabaja, 2 mira
    static readonly string[] Body = {
        ".#######.",
        ".#e###e#.",
        "a#######a",
        ".#######."
    };
    static readonly string[] Laptop = {
        "..DDDDDDDD..",
        "..DSSSSSSD..",
        "..DSSSSSSD..",
        "..DSSSSSSD..",
        "..DSSSSSSD..",
        "..DDDDDDDD..",
        ".KKKKKKKKKK.",
        "KKKKKKKKKKKK"
    };
    const int MS = 2;   // cada pixel de la mascota ocupa 2x2

    void Put(int x, int y, int c) { if (x >= 0 && x < W && y >= 0 && y < PH) K[y, x] = c; }
    void PutBig(int sx, int sy, int c) { for (int dy = 0; dy < MS; dy++) for (int dx = 0; dx < MS; dx++) Put(sx + dx, sy + dy, c); }

    void DrawMascot(double t, double dt)
    {
        int mw = 9 * MS, lw = Laptop[0].Length;
        if (t >= stateEnd)
        {
            double roll = rnd.NextDouble();
            if (mState != 1 && roll < 0.45)
            {   // se sienta mirando hacia donde hay lugar para la compu
                mState = 1; stateEnd = t + 5 + rnd.NextDouble() * 4;
                facing = mx + mw + lw + 2 > W ? -1 : (mx - lw - 2 < 0 ? 1 : (rnd.Next(2) == 0 ? 1 : -1));
            }
            else if (roll < 0.6) { mState = 2; stateEnd = t + 1.2 + rnd.NextDouble(); }
            else
            {
                mState = 0; targetX = lw + 2 + rnd.NextDouble() * Math.Max(1, W - mw - 2 * lw - 4);
                facing = targetX > mx ? 1 : -1; stateEnd = t + 12;
            }
        }
        if (mState == 0)
        {
            mx += facing * 9 * dt;
            if ((facing > 0 && mx >= targetX) || (facing < 0 && mx <= targetX)) { mx = targetX; stateEnd = t; }
            if (rnd.NextDouble() < dt * 0.25) jumpAt = t;
        }
        double jt = t - jumpAt;
        int lift = jt >= 0 && jt < 0.5 ? (int)Math.Round(7 * Math.Sin(Math.PI * jt / 0.5)) : 0;
        if (t > nextBlink + 0.13) nextBlink = t + 2 + rnd.NextDouble() * 3;
        bool blink = t > nextBlink;

        int ox = (int)Math.Round(mx), floor = PH - 1;
        int top = floor - 5 * MS + 1 - lift;
        bool step = ((int)(t / 0.14)) % 2 == 0;
        bool typing = mState == 1;
        bool armUp = ((int)(t / 0.11)) % 2 == 0;

        for (int r = 0; r < Body.Length; r++)
            for (int c = 0; c < 9; c++)
            {
                char ch = Body[r][c];
                if (ch == '.') continue;
                int col = r == 0 ? 15 : (r == 3 ? 16 : 14), ry = r;
                if (ch == 'e') col = blink ? 14 : 17;
                if (ch == 'a' && typing && (c == 0) == armUp) ry = r - 1;   // tecleando, los bracitos suben alternados
                PutBig(ox + c * MS, top + ry * MS, col);
            }
        // patas: las 4 quieto, alternadas al caminar
        int[] legs = { 2, 3, 5, 6 };
        for (int i = 0; i < 4; i++)
        {
            if (mState == 0 && lift == 0 && (i % 2 == 0) == step) continue;
            PutBig(ox + legs[i] * MS, top + 4 * MS, 16);
        }

        if (!typing) return;
        int lx = facing > 0 ? ox + mw + 1 : ox - lw - 1, ly = floor - Laptop.Length + 1, frame = (int)(t / 0.75);
        for (int r = 0; r < Laptop.Length; r++)
            for (int c = 0; c < lw; c++)
            {
                char ch = Laptop[r][c];
                if (ch == '.') continue;
                int col = ch == 'D' ? 19 : (ch == 'K' ? 18 : 20);
                if (ch == 'S')
                {   // lineas de codigo que cambian mientras escribe
                    int line = r - 1, len = (int)(Hash(frame * 7 + line * 13) * 5) + 1, indent = (int)(Hash(line * 31 + frame) * 2);
                    if (c - 3 >= indent && c - 3 < indent + len) col = 21;
                }
                Put(lx + c, ly + r, col);
            }
    }

    static int Q(double v) { return (int)Math.Round(Math.Max(0, Math.Min(1.3, v)) * 10); }
}
'@

# bitmap del nombre: una o mas lineas centradas, separadas por 2 filas vacias
function Get-NameRows([string[]]$lines, $fnt = $Font) {
    $blocks = New-Object Collections.Generic.List[object]
    foreach ($l in $lines) { $blocks.Add([string[]]@(for ($y = 0; $y -lt $fnt[' '].Count; $y++) { ($l.ToCharArray() | ForEach-Object { $fnt[[string]$_][$y] }) -join '.' })) }
    $w = 0; foreach ($bk in $blocks) { $w = [math]::Max($w, $bk[0].Length) }
    $all = New-Object Collections.Generic.List[string]
    for ($k = 0; $k -lt $blocks.Count; $k++) {
        if ($k) { $all.Add('.' * $w); $all.Add('.' * $w) }
        foreach ($r in $blocks[$k]) { $p = [int][math]::Floor(($w - $r.Length) / 2); $all.Add(('.' * $p) + $r + ('.' * ($w - $r.Length - $p))) }
    }
    , $all.ToArray()
}

function Initialize-Led {
    try {
        if (-not ('Aquarium' -as [type])) { Add-Type -TypeDefinition $LedSrc -Language CSharp -ErrorAction Stop }
        $wide = [Console]::WindowWidth -ge 98
        # encabezado: nombre arriba y la mascota de claude dando vueltas abajo
        $script:Led = [Aquarium]::new($CW, 10, $false, (Get-NameRows $(if ($wide) { 'LUCA MENGARELLI' } else { 'LUCA' }) $FontSmall), 1, $RST, $BGDEF, $MG, $true)
        # intro a pantalla completa; el nombre va en dos lineas y al doble de ancho si entra
        $iw = [Console]::WindowWidth - 4
        $rows = Get-NameRows 'LUCA', 'MENGARELLI'
        $scale = if ($rows[0].Length * 2 -le $iw - 2) { 2 } else { 1 }
        $script:IntroLed = [Aquarium]::new($iw, [math]::Max(10, [Console]::WindowHeight - 9), $true, $rows, $scale, $RST, $BGDEF, '  ', $false)
    } catch { $script:Led = $null; $script:IntroLed = $null }   # sin compilador c#: arranca sin animacion
    $script:LedClock = [Diagnostics.Stopwatch]::StartNew()
    $script:LedSkip = 0
}
function Get-LedTime { $LedClock.Elapsed.TotalSeconds + $LedSkip }

# redibuja el panel en su lugar sin mover el resto de la pantalla
function Write-Led {
    if (-not $Led) { return }
    [Console]::SetCursorPosition(0, $LedTop)
    [Console]::Write($Led.Frame((Get-LedTime)))
}

function Write-Tagline([string]$right = '') {
    $tag = (U 'SERVICIO T\u00c9CNICO').ToCharArray() -join ' '
    $gap = [math]::Max(2, $CW - 4 - $tag.Length - $right.Length)
    Write-Host "$MG$cAcc$gHeavy$gHeavy$RST  $cMut$tag$RST$(' ' * $gap)$cDim$right$RST"
}

# ---------- arranque ----------
# los datos lentos se piden en paralelo (runspaces) mientras corre la intro; cualquier tecla la saltea
function Show-Intro {
    $jobs = [ordered]@{
        'Sistema'    = { $os = Get-CimInstance Win32_OperatingSystem; $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
                         $os.Caption; $(if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }); $os.BuildNumber }
        'Procesador' = { $c = Get-CimInstance Win32_Processor | Select-Object -First 1; $c.Name; $c.NumberOfCores; $c.NumberOfLogicalProcessors }
        'Red'        = { (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4Address.IPAddress }
        'Licencia'   = { (Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" | Select-Object -First 1).LicenseStatus -eq 1 }
    }
    $run = foreach ($n in $jobs.Keys) { $ps = [powershell]::Create().AddScript($jobs[$n]); @{ Name = $n; Ps = $ps; H = $ps.BeginInvoke() } }

    Clear-Host
    Write-Host ''
    $introTop = [Console]::CursorTop
    if ($IntroLed) { [Console]::Write($IntroLed.Frame(0) + "`r`n") }
    Write-Tagline 'Luca Mengarelli'
    Write-Host ''
    $bootTop = [Console]::CursorTop
    Write-Host "`n`n`n"
    $introEnd = if ($IntroLed) { $IntroLed.IntroEnd + 0.4 } else { 0 }

    $res = @{}; $shown = @{}; $i = 0
    [Console]::CursorVisible = $false
    while ($true) {
        if ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
            $t = Get-LedTime
            if ($t -lt $introEnd) { $script:LedSkip += $introEnd - $t }
        }
        if ($IntroLed) { [Console]::SetCursorPosition(0, $introTop); [Console]::Write($IntroLed.Frame((Get-LedTime))) }
        $row = 0
        foreach ($j in $run) {
            if (-not $res.ContainsKey($j.Name) -and $j.H.IsCompleted) {
                $out = @(try { $j.Ps.EndInvoke($j.H) } catch { }); $j.Ps.Dispose()
                $res[$j.Name] = $out
                $shown[$j.Name] = switch ($j.Name) {
                    'Sistema'    { '{0} {1}' -f ("$($out[0])" -replace '^Microsoft\s+', ''), $out[1] }
                    'Procesador' { "$($out[0])".Trim() }
                    'Red'        { if ($out[0]) { "$($out[0])" } else { U 'Sin conexi\u00f3n' } }
                    'Licencia'   { if ("$($out[0])" -eq 'True') { 'Windows activado' } else { 'Windows sin activar' } }
                }
            }
            [Console]::SetCursorPosition(0, $bootTop + $row)
            if ($shown.ContainsKey($j.Name)) { [Console]::Write("$MG$cOk$gDot$RST $cMut$($j.Name.PadRight(12))$RST$cTxt$($shown[$j.Name])$RST$e[K") }
            else { [Console]::Write("$MG$cDim$gRing$RST $cMut$($j.Name.PadRight(12))$RST$(Get-Loader ($i + $row * 5))$e[K") }
            $row++
        }
        if ($res.Count -eq $run.Count -and (Get-LedTime) -ge $introEnd) { break }
        Start-Sleep -Milliseconds 30; $i++
    }
    [Console]::CursorVisible = $true

    $o = $res['Sistema']; $c = $res['Procesador']
    $script:Activated = "$($res['Licencia'][0])" -eq 'True'
    $script:Sys = @{
        Os    = "$($o[0])" -replace '^Microsoft\s+', ''
        Ver   = "$($o[1])"
        Build = "$($o[2])"
        Cpu   = (("$($c[0])" -replace '\((R|TM)\)|CPU|Processor|\d+-Core|with .*|@.*$', '') -replace '\s+', ' ').Trim()
        Cores = U ('{0} n\u00facleos {1} {2} hilos' -f $c[1], $gSep, $c[2])
        Ip    = if ($res['Red'][0]) { "$($res['Red'][0])" } else { 'Sin red' }
    }
    Start-Sleep -Milliseconds 350
}

function Update-Activation {
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction SilentlyContinue | Select-Object -First 1
    $script:Activated = $lic.LicenseStatus -eq 1
}

# ---------- pantalla ----------
# un segmento = @(largo visible, texto con color)
function Seg([string]$text, $color, [int]$max) { $t = Fit $text $max; , @($t.Length, "$color$t$RST") }
function Get-Meter([double]$p, [int]$w) {
    $n = [int][math]::Round([math]::Min(1.0, $p) * $w)
    $col = if ($p -lt .75) { $cAcc } elseif ($p -lt .9) { $cWarn } else { $cBad }
    , @($w, "$col$($gHeavy * $n)$cLine$($gHeavy * ($w - $n))$RST")
}

function Get-Card([string]$title, [int]$w, $l1, $l2, $foot) {
    $in = $w - 4
    "$cLine$gTL$gLine $cDim$title$cLine $($gLine * [math]::Max(0, $w - 5 - $title.Length))$gTR$RST"
    foreach ($l in $l1, $l2) { "$cLine$gV$RST " + $l[1] + (' ' * [math]::Max(0, $in - $l[0])) + " $cLine$gV$RST" }
    "$cLine$gBL$gLine $RST$($foot[1])$cLine $($gLine * [math]::Max(0, $w - 5 - $foot[0]))$gBR$RST"
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

    Write-Host ''
    $script:LedTop = [Console]::CursorTop
    if ($Led) { [Console]::Write($Led.Frame((Get-LedTime)) + "`r`n") }
    Write-Tagline "Encendido $onS  $gSep  $(Get-Date -Format 'HH:mm')"
    Write-Host ''

    $osTxt = if ($Sys.Os.Length -gt 25) { $Sys.Os -replace 'Enterprise', 'Ent.' -replace 'Professional', 'Pro' } else { $Sys.Os }
    $licP  = if ($Activated) { 'Activado' } else { 'Sin activar' }
    $licC  = if ($Activated) { $cOk } else { $cBad }
    $ver   = Fit $Sys.Ver 8
    $f1    = @(($ver.Length + 5 + $licP.Length), "$cMut$ver $cDim$gSep$RST $licC$gDot$RST $cTxt$licP$RST")
    $pct   = $ramU / $ramT
    $c1 = @(Get-Card 'EQUIPO' 29 (Seg $env:COMPUTERNAME $cWhi 25) (Seg $osTxt $cMut 25) $f1)
    $c2 = @(Get-Card 'PROCESADOR' 23 (Seg $Sys.Cpu $cWhi 19) (Seg $Sys.Cores $cMut 19) (Seg $Sys.Ip $cMut 17))
    $c3 = @(Get-Card 'MEMORIA' 18 (Seg ('{0:N1} / {1:N0} GB' -f $ramU, $ramT) $cWhi 14) (Get-Meter $pct 14) (Seg ('{0:N0} % en uso' -f ($pct * 100)) $cMut 12))
    $c4 = @(Get-Card "DISCO $($env:SystemDrive)" 19 (Seg ('{0:N0} / {1:N0} GB' -f ($dT - $dF), $dT) $cWhi 15) (Get-Meter (($dT - $dF) / $dT) 15) (Seg ('{0:N0} GB libres' -f $dF) $cMut 13))
    for ($j = 0; $j -lt 4; $j++) { Write-Host "$MG$($c1[$j]) $($c2[$j]) $($c3[$j]) $($c4[$j])" }
    Write-Host ''
}

# fila de 44 columnas visibles
function Format-Row($it, $on) {
    $name  = (Fit $it.Name 21).PadRight(22)
    $badge = ' ' * 16
    if ($it.B) {
        $txt   = Fit $it.B[0] 14
        $badge = (' ' * (14 - $txt.Length)) + "$($it.B[1])$gDot $cMut$txt"
    }
    $k = "$($it.Key)".ToUpper()
    if ($on) { "$cAcc$gEdge$BGSEL $cAcc$BOLD$k$RST$BGSEL  $cWhi$BOLD$name$RST$BGSEL$badge $RST" }
    else     { "  $cDim$k  $cTxt$name$badge $RST" }
}

# menu en dos columnas (Col 0/1); los items Hide solo responden a su tecla
function Select-Menu($Items, [int]$Index = 0, [switch]$Main) {
    $vis = @(for ($i = 0; $i -lt $Items.Count; $i++) { if (-not $Items[$i].Hide) { $i } })
    $pos = @{}; $rowN = @(0, 0); $sec = @($null, $null)
    foreach ($i in $vis) {
        $c = [int]$Items[$i].Col
        if ($Items[$i].Sec -and $Items[$i].Sec -ne $sec[$c]) { if ($rowN[$c]) { $rowN[$c]++ }; $sec[$c] = $Items[$i].Sec; $rowN[$c]++ }
        $pos[$i] = @($c, $rowN[$c]); $rowN[$c]++
    }
    if ($vis -notcontains $Index) { $Index = $vis[0] }
    $hints = if ($Main) { "$(Key "$gUp$gDn$gLeft$gRight") ${cMut}Navegar$RST   $(Key 'Enter') ${cMut}Abrir$RST   $(Key '1-9') ${cMut}Atajo$RST   $(Key 'X') ${cMut}Reiniciar$RST   $(Key 'Q') ${cMut}Salir$RST" }
             else { "$(Key "$gUp$gDn") ${cMut}Navegar$RST   $(Key 'Enter') ${cMut}Elegir$RST   $(Key 'Esc') ${cMut}Volver$RST" }
    $top = [Console]::CursorTop
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $cols = @((New-Object Collections.Generic.List[string]), (New-Object Collections.Generic.List[string]))
            $sec = @($null, $null)
            foreach ($i in $vis) {
                $c = [int]$Items[$i].Col
                if ($Items[$i].Sec -and $Items[$i].Sec -ne $sec[$c]) {
                    $sec[$c] = $Items[$i].Sec
                    if ($cols[$c].Count) { $cols[$c].Add(' ' * 44) }
                    $cols[$c].Add("  $cDim$($sec[$c])$RST" + (' ' * (42 - $sec[$c].Length)))
                }
                $cols[$c].Add((Format-Row $Items[$i] ($i -eq $Index)))
            }
            $sb = New-Object Text.StringBuilder
            for ($j = 0; $j -lt [math]::Max($cols[0].Count, $cols[1].Count); $j++) {
                $lft = if ($j -lt $cols[0].Count) { $cols[0][$j] } else { ' ' * 44 }
                $rgt = if ($j -lt $cols[1].Count) { $cols[1][$j] } else { '' }
                [void]$sb.Append("$MG$lft    $rgt$RST$e[K`r`n")
            }
            [void]$sb.Append("`r`n$MG$cAcc$gPlay$RST $cMut$($Items[$Index].Desc)$RST$e[K`r`n`r`n$MG$hints$e[K")
            [Console]::SetCursorPosition(0, $top)
            [Console]::Write($sb.ToString())

            while (-not [Console]::KeyAvailable) { if ($Main) { Write-Led }; Start-Sleep -Milliseconds 45 }
            $k = [Console]::ReadKey($true)
            $c0 = $pos[$Index][0]; $r0 = $pos[$Index][1]
            $same = @($vis | Where-Object { $pos[$_][0] -eq $c0 })
            $next = $null
            switch ($k.Key) {
                'UpArrow'    { $next = $same | Where-Object { $pos[$_][1] -lt $r0 } | Select-Object -Last 1; if ($null -eq $next) { $next = $same[-1] } }
                'DownArrow'  { $next = $same | Where-Object { $pos[$_][1] -gt $r0 } | Select-Object -First 1; if ($null -eq $next) { $next = $same[0] } }
                'LeftArrow'  { $next = $vis | Where-Object { $pos[$_][0] -ne $c0 } | Sort-Object { [math]::Abs($pos[$_][1] - $r0) } | Select-Object -First 1 }
                'RightArrow' { $next = $vis | Where-Object { $pos[$_][0] -ne $c0 } | Sort-Object { [math]::Abs($pos[$_][1] - $r0) } | Select-Object -First 1 }
                'Tab'        { $next = $vis[([array]::IndexOf($vis, $Index) + 1) % $vis.Count] }
                'Home'       { $next = $vis[0] }
                'End'        { $next = $vis[-1] }
                'Enter'      { return $Index }
                'Escape'     { return -1 }
            }
            if ($null -ne $next) { $Index = $next; continue }
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
    Write-Host "$MG$cAcc$gHeavy$gHeavy$RST  $cMut$Brand$RST  $cDim$gStep$RST  $BOLD$cWhi$title$RST"
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
# wsreset -i (ltsc 2021 en adelante) pide la store a windows update y la instala en segundo plano:
# hay que esperarla varios minutos, y no anda si winutil dejo windows update deshabilitado
function Install-Store {
    if (Get-AppxPackage Microsoft.WindowsStore) { Good (U 'Microsoft Store ya est\u00e1 instalada.'); return }
    if ([int](Get-CimInstance Win32_OperatingSystem).BuildNumber -lt 19041) {
        Fail (U 'Esta versi\u00f3n de Windows (LTSC 2019 o anterior) no permite instalar la Store con wsreset.')
        return
    }
    $off = @(foreach ($n in 'wuauserv', 'BITS', 'InstallService', 'ClipSVC') {
        $s = Get-Service $n -ErrorAction SilentlyContinue
        if ($s -and $s.StartType -eq 'Disabled') { Set-Service $n -StartupType Manual -ErrorAction SilentlyContinue; $n }
    })
    if ($off) { Warn "Habilitados temporalmente: $($off -join ', ')" }
    Step 'Pidiendo Microsoft Store a Windows Update...'
    Start-Process wsreset.exe -ArgumentList '-i' -WindowStyle Hidden
    $ini = Get-Date; $i = 0; $ok = $false
    [Console]::CursorVisible = $false
    while (((Get-Date) - $ini).TotalMinutes -lt 8) {
        if ($i % 40 -eq 0 -and (Get-AppxPackage Microsoft.WindowsStore)) { $ok = $true; break }
        [Console]::Write("`r$MG  $(Get-Loader $i 20)  ${cMut}Instalando en segundo plano  $([int]((Get-Date) - $ini).TotalSeconds) s$RST$e[K")
        Start-Sleep -Milliseconds 50; $i++
    }
    [Console]::CursorVisible = $true
    [Console]::Write("`r$e[K")
    foreach ($n in $off) { Set-Service $n -StartupType Disabled -ErrorAction SilentlyContinue }
    if ($ok) { Good 'Microsoft Store instalada. Puede tardar un minuto en aparecer en Inicio.' }
    else { Fail (U 'No termin\u00f3 en 8 minutos. Revis\u00e1 la conexi\u00f3n y que Windows Update funcione, y reintent\u00e1.') }
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
    @{ Col = 0; Sec = 'HERRAMIENTAS'; Key = '1'; Name = 'WinUtil'; Desc = 'Ajustes, programas y optimizaciones de Windows (Chris Titus Tech)'
       Run = { Invoke-RestMethod 'https://christitus.com/win' | Invoke-Expression } },
    @{ Col = 0; Sec = 'HERRAMIENTAS'; Key = '2'; Name = U 'Activaci\u00f3n'; Desc = 'Activa Windows y Office mediante get.activated.win'
       Badge = { if ($Activated) { 'Activado', $cOk } else { 'Sin activar', $cBad } }
       Run = { Invoke-RestMethod 'https://get.activated.win' | Invoke-Expression; Update-Activation } },
    @{ Col = 0; Sec = (U 'INSTALACI\u00d3N'); Key = '3'; Name = 'Office LTSC'; Desc = U 'Descarga e instala Office 2021 o 2024 en espa\u00f1ol desde Microsoft'
       Badge = { $ids = Get-OfficeIds; if ($ids -match '20\d\d') { "$($Matches[0]) instalado", $cOk } elseif ($ids) { 'Instalado', $cOk } else { 'No instalado', $cDim } }
       Run = { Install-Office } },
    @{ Col = 0; Sec = (U 'INSTALACI\u00d3N'); Key = '4'; Name = 'Microsoft Store'; Desc = 'Instala la tienda de Microsoft en ediciones LTSC'
       Badge = { if (Get-AppxPackage Microsoft.WindowsStore) { 'Instalada', $cOk } else { 'No instalada', $cDim } }
       Run = { Install-Store } },
    @{ Col = 0; Sec = 'EQUIPO'; Key = 'r'; Name = 'Informe del equipo'; Desc = U 'Genera un informe HTML con hardware, discos y bater\u00eda para el cliente'
       Run = { New-Report } },
    @{ Col = 1; Sec = 'MANTENIMIENTO'; Key = '5'; Name = 'Limpieza'; Desc = U 'Borra temporales, actualizaciones descargadas y vac\u00eda la papelera'
       Badge = { $l = Get-Content "$Base\limpieza.log" -Tail 1 -ErrorAction SilentlyContinue
                 if ($l) { (Get-Ago ([datetime]::ParseExact($l.Substring(0, 16), 'yyyy-MM-dd HH:mm', $null))), $cMut } else { 'Nunca', $cWarn } }
       Run = { Invoke-Clean } },
    @{ Col = 1; Sec = 'MANTENIMIENTO'; Key = '6'; Name = U 'Limpieza autom\u00e1tica'; Desc = 'Tarea programada que limpia en cada inicio de Windows'
       Badge = { if (Get-ScheduledTask -TaskName 'ServicioTecnico-Limpieza' -ErrorAction SilentlyContinue) { 'Activa', $cOk } else { 'Inactiva', $cDim } }
       Run = { Install-CleanTask } },
    @{ Col = 1; Sec = 'MANTENIMIENTO'; Key = '7'; Name = 'Reparar Windows'; Desc = 'Repara la imagen y los archivos del sistema con DISM y SFC'
       Run = { Repair-Windows } },
    @{ Col = 1; Sec = 'MANTENIMIENTO'; Key = '8'; Name = 'Restablecer red'; Desc = U 'Vac\u00eda la cach\u00e9 DNS y restablece Winsock y TCP/IP'
       Run = { Reset-Network } },
    @{ Col = 1; Sec = 'MANTENIMIENTO'; Key = '9'; Name = U 'Punto de restauraci\u00f3n'; Desc = U 'Crea un punto para volver atr\u00e1s antes de hacer cambios'
       Badge = { $p = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Select-Object -Last 1
                 if ($p) { (Get-Ago ([Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime))), $cMut } else { 'Ninguno', $cWarn } }
       Run = { New-RestorePoint } },
    @{ Hide = $true; Key = 'x'; Name = 'Reiniciar equipo'; Run = { Restart-Now } },
    @{ Hide = $true; Key = 'q'; Name = 'Salir' }
)

# nombre completo si entra; si la ventana es angosta, solo "LUCA"
# si la ventana es baja se agranda para que entre el panel (en windows terminal no se puede y se ignora)
try {
    $ws = $Host.UI.RawUI.WindowSize
    if ($ws.Height -lt 36 -and $Host.UI.RawUI.MaxPhysicalWindowSize.Height -ge 36) { $Host.UI.RawUI.WindowSize = New-Object Management.Automation.Host.Size $ws.Width, 36 }
} catch {}
Clear-Host
Write-Host ''
Write-Host "$MG$cAcc$gHeavy$gHeavy$RST  ${cMut}Preparando...$RST"
Initialize-Led
Show-Intro
$cur = 0
while ($true) {
    try {
        Show-Banner
        foreach ($it in $Menu) { $it.B = if ($it.Badge) { try { & $it.Badge } catch { $null } } }
        $pick = Select-Menu $Menu $cur -Main
        if ($pick -eq -1 -or -not $Menu[$pick].Run) {
            $Host.UI.RawUI.BackgroundColor = $OrigBg; $Host.UI.RawUI.ForegroundColor = $OrigFg
            Write-Host -NoNewline "$e[0m"
            Clear-Host
            return
        }
        if (-not $Menu[$pick].Hide) { $cur = $pick }
        $it = $Menu[$pick]
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
