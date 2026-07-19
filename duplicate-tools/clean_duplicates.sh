#!/usr/bin/env bash
# ============================================================
# clean_duplicates.sh
# Elimina archivos duplicados con flags opcionales.
# USO: ./clean_duplicates.sh <ruta> [flags]
# ============================================================
set -euo pipefail

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Defaults ─────────────────────────────────────────────────
SCAN_DIR=""
OUTPUT_DIR=""
DRY_RUN=false
REMOVE_EMPTY=false
DO_SHUTDOWN=false
SHUTDOWN_DELAY=60
ESTIMATE_SAMPLE=3000

# ── Ayuda ────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}USO:${RESET} $0 <ruta> [opciones]"
  echo ""
  echo -e "${BOLD}ARGUMENTOS:${RESET}"
  echo "  <ruta>                     Directorio a limpiar (obligatorio)"
  echo ""
  echo -e "${BOLD}FLAGS OPCIONALES:${RESET}"
  echo "  --dry-run                  Simula sin eliminar nada"
  echo "  --remove-empty-dirs        Elimina carpetas vacías al finalizar"
  echo "  --shutdown                 Apaga el equipo al terminar"
  echo "  --shutdown-delay <seg>     Segundos antes de apagar (default: 60)"
  echo "  --output <dir>             Directorio de salida para reportes"
  echo "  --help                     Muestra esta ayuda"
  echo ""
  echo -e "${BOLD}EJEMPLOS:${RESET}"
  echo "  $0 /mnt/sdcard --dry-run"
  echo "  $0 /home/user/Descargas --remove-empty-dirs --shutdown --shutdown-delay 120"
  exit 0
}

# ── Parse args ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)             usage ;;
    --dry-run)             DRY_RUN=true;       shift ;;
    --remove-empty-dirs)   REMOVE_EMPTY=true;  shift ;;
    --shutdown)            DO_SHUTDOWN=true;    shift ;;
    --shutdown-delay)      SHUTDOWN_DELAY="$2"; shift 2 ;;
    --output|-o)           OUTPUT_DIR="$2";    shift 2 ;;
    -*) echo -e "${RED}Flag desconocida: $1${RESET}"; usage ;;
    *)  SCAN_DIR="$1"; shift ;;
  esac
done

[[ -z "$SCAN_DIR" ]] && { echo -e "${RED}Error: debes indicar una ruta.${RESET}"; usage; }
[[ ! -d "$SCAN_DIR" ]] && { echo -e "${RED}Error: '$SCAN_DIR' no es un directorio válido.${RESET}"; exit 1; }

SCAN_DIR=$(realpath "$SCAN_DIR")
TS=$(date +%Y%m%d_%H%M%S)
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="./clean_report_${TS}"
mkdir -p "$OUTPUT_DIR"

TXT_REPORT="${OUTPUT_DIR}/reporte_${TS}.txt"
HTML_REPORT="${OUTPUT_DIR}/reporte_${TS}.html"
TMPDIR_WORK=$(mktemp -d /tmp/clean_dup_XXXX)
HASH_DB="${TMPDIR_WORK}/hashes.db"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

log()  { echo -e "${CYAN}[$(date '+%F %T')]${RESET} $1" | tee -a "$TXT_REPORT"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1" | tee -a "$TXT_REPORT"; }
ok()   { echo -e "${GREEN}[OK]${RESET} $1"   | tee -a "$TXT_REPORT"; }

# ── Header ───────────────────────────────────────────────────
{
  echo "============================================================"
  echo " REPORTE DE LIMPIEZA - clean_duplicates.sh"
  echo " Ruta       : $SCAN_DIR"
  echo " Modo       : $([ "$DRY_RUN" = true ] && echo 'DRY-RUN (sin cambios)' || echo 'ELIMINACIÓN REAL')"
  echo " Carpetas vacías: $([ "$REMOVE_EMPTY" = true ] && echo 'Sí' || echo 'No')"
  echo " Generado   : $(date '+%F %T')"
  echo "============================================================"
  echo ""
} | tee "$TXT_REPORT"

# ── Dependencias ─────────────────────────────────────────────
for cmd in find sha256sum stat awk sort wc; do
  command -v "$cmd" >/dev/null 2>&1 || { echo -e "${RED}Falta: $cmd${RESET}"; exit 1; }
done

# ── Etapa 1: Conteo ──────────────────────────────────────────
log "ETAPA 1/5: Contando archivos..."
TOTAL=$(find "$SCAN_DIR" -type f 2>/dev/null | wc -l)
log "Total: $TOTAL archivos"
[[ "$TOTAL" -eq 0 ]] && { warn "No hay archivos."; exit 0; }

# ── Etapa 2: Estimación ──────────────────────────────────────
log "ETAPA 2/5: Estimando tiempo (muestra de $ESTIMATE_SAMPLE archivos)..."
SAMPLE_COUNT=$(( TOTAL < ESTIMATE_SAMPLE ? TOTAL : ESTIMATE_SAMPLE ))
START_T=$(date +%s)
find "$SCAN_DIR" -type f -print0 2>/dev/null \
  | head -z -n "$SAMPLE_COUNT" \
  | xargs -0 -r sha256sum > /dev/null 2>&1 || true
END_T=$(date +%s)
DELTA=$(( END_T - START_T ))
[[ "$DELTA" -le 0 ]] && DELTA=1
EST=$(( TOTAL * DELTA / SAMPLE_COUNT ))
log "Tiempo estimado: ~${EST}s (~$((EST / 60)) min)"

# ── Etapa 3: Hash + deduplicación ────────────────────────────
log "ETAPA 3/5: Calculando hashes y eliminando duplicados..."
[[ "$DRY_RUN" = true ]] && warn "MODO DRY-RUN: no se eliminará ningún archivo."

ELIMINADOS=0
ESPACIO_BYTES=0
PROCESSED=0

JSON_REMOVED="["
FIRST_JSON=true

{
  echo ""
  echo "------------------------------------------------------------"
  echo " ARCHIVOS ELIMINADOS"
  echo "------------------------------------------------------------"
} >> "$TXT_REPORT"

find "$SCAN_DIR" -type f -print0 2>/dev/null | \
while IFS= read -r -d '' f; do
  PROCESSED=$((PROCESSED + 1))
  echo -ne "${CYAN}  Progreso: $PROCESSED / $TOTAL${RESET}\r" >&2

  hash=$(sha256sum "$f" 2>/dev/null | awk '{print $1}') || continue
  size=$(stat -c '%s' "$f" 2>/dev/null) || continue
  mtime=$(stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1) || continue
  owner=$(stat -c '%U' "$f" 2>/dev/null) || continue

  if grep -qF "$hash" "$HASH_DB" 2>/dev/null; then
    ELIMINADOS=$((ELIMINADOS + 1))
    ESPACIO_BYTES=$((ESPACIO_BYTES + size))

    original=$(grep "^$hash|" "$HASH_DB" | cut -d'|' -f2)

    if [[ "$DRY_RUN" = false ]]; then
      rm -f -- "$f"
      echo "[ELIMINADO] $f  (original: $original)" >> "$TXT_REPORT"
    else
      echo "[DRY-RUN] $f  (original: $original)" >> "$TXT_REPORT"
    fi

    $FIRST_JSON || JSON_REMOVED+=","
    FIRST_JSON=false
    f_esc="${f//\"/\\\"}"; orig_esc="${original//\"/\\\"}"
    JSON_REMOVED+="{\"path\":\"$f_esc\",\"original\":\"$orig_esc\",\"size\":\"$size\",\"owner\":\"$owner\",\"mtime\":\"$mtime\",\"hash\":\"$hash\"}"
  else
    echo "$hash|$f" >> "$HASH_DB"
  fi
done

echo "" >&2
JSON_REMOVED+="]"

# ── Etapa 4: Carpetas vacías ──────────────────────────────────
log "ETAPA 4/5: Carpetas vacías..."
EMPTY_DIRS=0
if [[ "$REMOVE_EMPTY" = true ]]; then
  if [[ "$DRY_RUN" = false ]]; then
    while IFS= read -r -d '' d; do
      rmdir "$d" 2>/dev/null && EMPTY_DIRS=$((EMPTY_DIRS + 1)) || true
    done < <(find "$SCAN_DIR" -mindepth 1 -type d -empty -print0 | sort -rz)
    log "Carpetas vacías eliminadas: $EMPTY_DIRS"
  else
    EMPTY_DIRS=$(find "$SCAN_DIR" -mindepth 1 -type d -empty 2>/dev/null | wc -l)
    warn "DRY-RUN: se eliminarían $EMPTY_DIRS carpetas vacías."
  fi
else
  log "Flag --remove-empty-dirs no activada. Omitido."
fi

# ── Etapa 5: Resumen ─────────────────────────────────────────
log "ETAPA 5/5: Generando reporte..."

MB=$((ESPACIO_BYTES / 1024 / 1024))

{
  echo ""
  echo "============================================================"
  echo " RESUMEN"
  echo "  Modo            : $([ "$DRY_RUN" = true ] && echo 'DRY-RUN' || echo 'REAL')"
  echo "  Total procesados: $TOTAL"
  echo "  Eliminados      : $ELIMINADOS"
  echo "  Espacio liberado: ${MB} MB"
  echo "  Carpetas vacías : $EMPTY_DIRS"
  echo "  Reporte HTML    : $HTML_REPORT"
  echo "============================================================"
} | tee -a "$TXT_REPORT"

# ── Generar HTML ─────────────────────────────────────────────
cat > "$HTML_REPORT" << HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Reporte de Limpieza</title>
<style>
  :root {
    --bg:#0d1117;--surface:#161b22;--surface2:#1c2333;--border:#30363d;
    --accent:#1e6eb5;--accent2:#2d8dd4;--accent3:#58a6ff;
    --text:#e6edf3;--text-muted:#8b949e;
    --danger:#f85149;--warn:#d29922;--success:#3fb950;
  }
  *{box-sizing:border-box;margin:0;padding:0;}
  body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;}
  .header{background:linear-gradient(135deg,#0d1f3c,#1e3a5f,#0d2137);border-bottom:1px solid var(--accent);padding:2rem 2.5rem;display:flex;align-items:center;gap:1.5rem;}
  .header-icon{font-size:2.5rem;}
  .header h1{font-size:1.6rem;font-weight:700;color:var(--accent3);}
  .header p{color:var(--text-muted);font-size:.85rem;margin-top:.25rem;}
  .mode-badge{display:inline-block;padding:.2rem .8rem;border-radius:20px;font-size:.75rem;font-weight:700;margin-top:.4rem;}
  .mode-dry{background:#2d1f0e;color:var(--warn);}
  .mode-real{background:#1a2d1a;color:var(--success);}
  .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:1rem;padding:1.5rem 2.5rem;}
  .stat-card{background:var(--surface);border:1px solid var(--border);border-radius:10px;padding:1.2rem 1.5rem;}
  .stat-label{font-size:.72rem;color:var(--text-muted);text-transform:uppercase;letter-spacing:.05em;}
  .stat-value{font-size:1.8rem;font-weight:700;color:var(--accent3);margin-top:.2rem;}
  .filters{background:var(--surface);border-top:1px solid var(--border);border-bottom:1px solid var(--border);padding:1rem 2.5rem;display:flex;flex-wrap:wrap;gap:.75rem;align-items:center;}
  .filters label{font-size:.8rem;color:var(--text-muted);}
  .filter-group{display:flex;align-items:center;gap:.4rem;}
  .filters input,.filters select{background:var(--surface2);border:1px solid var(--border);color:var(--text);border-radius:6px;padding:.4rem .75rem;font-size:.85rem;outline:none;}
  .filters input:focus,.filters select:focus{border-color:var(--accent2);}
  .filters input[type=text]{width:220px;}
  .btn-reset{background:var(--surface2);border:1px solid var(--border);color:var(--text-muted);border-radius:6px;padding:.4rem .9rem;font-size:.8rem;cursor:pointer;}
  .btn-reset:hover{border-color:var(--accent2);color:var(--text);}
  .content{padding:1.5rem 2.5rem;}
  .results-count{font-size:.85rem;color:var(--text-muted);margin-bottom:1rem;}
  table{width:100%;border-collapse:collapse;font-size:.82rem;background:var(--surface);border-radius:10px;overflow:hidden;border:1px solid var(--border);}
  th{background:#111827;color:var(--text-muted);text-align:left;padding:.6rem 1rem;font-size:.72rem;text-transform:uppercase;letter-spacing:.05em;border-bottom:1px solid var(--border);}
  td{padding:.6rem 1rem;border-bottom:1px solid #1e2432;vertical-align:middle;}
  tr:last-child td{border-bottom:none;}
  tr:hover td{background:#1a2233;}
  .path-mono{font-family:monospace;font-size:.78rem;word-break:break-all;color:var(--danger);}
  .orig-mono{font-family:monospace;font-size:.75rem;word-break:break-all;color:var(--text-muted);}
  .hash-mono{font-family:monospace;font-size:.72rem;color:#6e7681;}
  .size-cell{white-space:nowrap;color:var(--warn);}
  .date-cell{white-space:nowrap;color:var(--text-muted);font-size:.75rem;}
  .no-results{text-align:center;padding:3rem;color:var(--text-muted);}
  footer{text-align:center;padding:1.5rem;font-size:.75rem;color:var(--text-muted);border-top:1px solid var(--border);}
</style>
</head>
<body>
<div class="header">
  <div class="header-icon">🧹</div>
  <div>
    <h1>Reporte de Limpieza de Duplicados</h1>
    <p>Ruta: <strong>SCAN_DIR_PLACEHOLDER</strong> &nbsp;|&nbsp; <strong>TS_PLACEHOLDER</strong></p>
    <span class="mode-badge MODE_CLASS_PLACEHOLDER">MODE_LABEL_PLACEHOLDER</span>
  </div>
</div>

<div class="stats">
  <div class="stat-card"><div class="stat-label">Total escaneados</div><div class="stat-value">TOTAL_PLACEHOLDER</div></div>
  <div class="stat-card"><div class="stat-label">Eliminados</div><div class="stat-value" style="color:var(--danger)">ELIMINADOS_PLACEHOLDER</div></div>
  <div class="stat-card"><div class="stat-label">Espacio liberado</div><div class="stat-value" style="color:var(--success)">MB_PLACEHOLDER MB</div></div>
  <div class="stat-card"><div class="stat-label">Carpetas vacías</div><div class="stat-value">EMPTY_PLACEHOLDER</div></div>
</div>

<div class="filters">
  <div class="filter-group"><label>🔎 Buscar ruta</label>
    <input type="text" id="f-search" placeholder="/home/inti/..."></div>
  <div class="filter-group"><label>👤 Propietario</label>
    <select id="f-owner"><option value="">Todos</option></select></div>
  <div class="filter-group"><label>📦 Tamaño mín. (KB)</label>
    <input type="number" id="f-size" placeholder="0" style="width:100px"></div>
  <button class="btn-reset" onclick="resetFilters()">✕ Limpiar</button>
</div>

<div class="content">
  <div class="results-count" id="results-count"></div>
  <table id="main-table">
    <thead>
      <tr>
        <th>#</th><th>Archivo eliminado</th><th>Original (conservado)</th>
        <th>SHA256</th><th>Tamaño</th><th>Propietario</th><th>Modificado</th>
      </tr>
    </thead>
    <tbody id="table-body"></tbody>
  </table>
  <div class="no-results" id="no-results" style="display:none">
    <p>📭 Sin resultados con los filtros aplicados.</p>
  </div>
</div>

<footer>clean_duplicates.sh &nbsp;|&nbsp; TS_PLACEHOLDER</footer>

<script>
const DATA = JSONEOF;

const owners = new Set(DATA.map(r => r.owner));
const selOwn = document.getElementById('f-owner');
[...owners].sort().forEach(o => { const opt=document.createElement('option'); opt.value=o; opt.textContent=o; selOwn.appendChild(opt); });

function fmtSize(b){ b=parseInt(b); if(b<1024) return b+' B'; if(b<1048576) return (b/1024).toFixed(1)+' KB'; return (b/1048576).toFixed(2)+' MB'; }

function render(data){
  const tbody=document.getElementById('table-body');
  const noRes=document.getElementById('no-results');
  tbody.innerHTML='';
  if(!data.length){ noRes.style.display='block'; document.getElementById('results-count').textContent=''; return; }
  noRes.style.display='none';
  document.getElementById('results-count').textContent=\`Mostrando \${data.length} registro(s)\`;
  data.forEach((r,i)=>{
    const tr=document.createElement('tr');
    tr.innerHTML=\`
      <td>\${i+1}</td>
      <td class="path-mono">\${r.path}</td>
      <td class="orig-mono">\${r.original}</td>
      <td class="hash-mono">\${r.hash.substring(0,16)}…</td>
      <td class="size-cell">\${fmtSize(r.size)}</td>
      <td>\${r.owner}</td>
      <td class="date-cell">\${r.mtime}</td>
    \`;
    tbody.appendChild(tr);
  });
}

function applyFilters(){
  const s=document.getElementById('f-search').value.toLowerCase();
  const o=document.getElementById('f-owner').value;
  const sz=parseFloat(document.getElementById('f-size').value||0)*1024;
  render(DATA.filter(r=>{
    if(o && r.owner!==o) return false;
    if(sz && parseInt(r.size)<sz) return false;
    if(s && !r.path.toLowerCase().includes(s) && !r.original.toLowerCase().includes(s)) return false;
    return true;
  }));
}
function resetFilters(){
  document.getElementById('f-search').value='';
  document.getElementById('f-owner').value='';
  document.getElementById('f-size').value='';
  render(DATA);
}
['f-search','f-owner','f-size'].forEach(id=>document.getElementById(id).addEventListener('input',applyFilters));
render(DATA);
</script>
</body>
</html>
HTMLEOF

# Inyectar valores
MODE_CLASS=$( [[ "$DRY_RUN" = true ]] && echo "mode-dry" || echo "mode-real" )
MODE_LABEL=$( [[ "$DRY_RUN" = true ]] && echo "⚠ DRY-RUN — Sin cambios reales" || echo "✅ MODO REAL — Archivos eliminados" )

sed -i \
  -e "s|SCAN_DIR_PLACEHOLDER|$SCAN_DIR|g" \
  -e "s|TS_PLACEHOLDER|$(date '+%F %T')|g" \
  -e "s|TOTAL_PLACEHOLDER|$TOTAL|g" \
  -e "s|ELIMINADOS_PLACEHOLDER|$ELIMINADOS|g" \
  -e "s|MB_PLACEHOLDER|$MB|g" \
  -e "s|EMPTY_PLACEHOLDER|$EMPTY_DIRS|g" \
  -e "s|MODE_CLASS_PLACEHOLDER|$MODE_CLASS|g" \
  -e "s|MODE_LABEL_PLACEHOLDER|$MODE_LABEL|g" \
  -e "s|JSONEOF|$JSON_REMOVED|g" \
  "$HTML_REPORT"

ok "✅ Limpieza completada."
ok "   TXT : $TXT_REPORT"
ok "   HTML: $HTML_REPORT"

# ── Apagado opcional ─────────────────────────────────────────
if [[ "$DO_SHUTDOWN" = true ]]; then
  log "Apagando en ${SHUTDOWN_DELAY}s..."
  ( sleep "$SHUTDOWN_DELAY" && systemctl poweroff --no-wall ) & disown
fi
