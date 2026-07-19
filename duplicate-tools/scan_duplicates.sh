#!/usr/bin/env bash
# ============================================================
# scan_duplicates.sh
# Escanea una ruta en busca de archivos duplicados.
# Genera reporte en TXT y HTML con tabla interactiva.
# USO: ./scan_duplicates.sh <ruta> [--output <dir>]
# ============================================================
set -euo pipefail

# ── Colores terminal ─────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Ayuda ────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}USO:${RESET} $0 <ruta> [--output <dir>]"
  echo ""
  echo "  <ruta>            Directorio a escanear (obligatorio)"
  echo "  --output <dir>    Directorio de salida para reportes (default: ./scan_report_TIMESTAMP)"
  echo "  --help            Muestra esta ayuda"
  exit 0
}

# ── Argumentos ───────────────────────────────────────────────
SCAN_DIR=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage ;;
    --output|-o) OUTPUT_DIR="$2"; shift 2 ;;
    -*) echo -e "${RED}Flag desconocida: $1${RESET}"; usage ;;
    *) SCAN_DIR="$1"; shift ;;
  esac
done

[[ -z "$SCAN_DIR" ]] && { echo -e "${RED}Error: debes indicar una ruta a escanear.${RESET}"; usage; }
[[ ! -d "$SCAN_DIR" ]] && { echo -e "${RED}Error: '$SCAN_DIR' no es un directorio válido.${RESET}"; exit 1; }

SCAN_DIR=$(realpath "$SCAN_DIR")
TS=$(date +%Y%m%d_%H%M%S)
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="./scan_report_${TS}"
mkdir -p "$OUTPUT_DIR"

TXT_REPORT="${OUTPUT_DIR}/reporte_${TS}.txt"
HTML_REPORT="${OUTPUT_DIR}/reporte_${TS}.html"
TMPDIR_WORK=$(mktemp -d /tmp/scan_dup_XXXX)
HASH_FILE="${TMPDIR_WORK}/hashes.txt"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

log()  { echo -e "${CYAN}[$(date '+%F %T')]${RESET} $1" | tee -a "$TXT_REPORT"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1" | tee -a "$TXT_REPORT"; }

# ── Header TXT ───────────────────────────────────────────────
{
  echo "============================================================"
  echo " REPORTE DE DUPLICADOS - scan_duplicates.sh"
  echo " Ruta escaneada : $SCAN_DIR"
  echo " Generado       : $(date '+%F %T')"
  echo "============================================================"
  echo ""
} | tee "$TXT_REPORT"

# ── Verificar dependencias ────────────────────────────────────
for cmd in find sha256sum stat awk sort; do
  command -v "$cmd" >/dev/null 2>&1 || { echo -e "${RED}Falta: $cmd${RESET}"; exit 1; }
done

# ── Etapa 1: Conteo ──────────────────────────────────────────
log "ETAPA 1/3: Contando archivos en '$SCAN_DIR'..."
TOTAL=$(find "$SCAN_DIR" -type f 2>/dev/null | wc -l)
log "Total de archivos encontrados: $TOTAL"
[[ "$TOTAL" -eq 0 ]] && { warn "No hay archivos que analizar."; exit 0; }

# ── Etapa 2: Hash + metadata ─────────────────────────────────
log "ETAPA 2/3: Calculando SHA256 y recopilando metadata..."
PROCESSED=0

find "$SCAN_DIR" -type f -print0 2>/dev/null | \
while IFS= read -r -d '' f; do
  PROCESSED=$((PROCESSED + 1))
  echo -ne "${CYAN}  Progreso: $PROCESSED / $TOTAL${RESET}\r" >&2

  hash=$(sha256sum "$f" 2>/dev/null | awk '{print $1}') || continue
  size=$(stat -c '%s' "$f" 2>/dev/null) || continue
  mtime=$(stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1) || continue
  ctime=$(stat -c '%z' "$f" 2>/dev/null | cut -d'.' -f1) || continue
  owner=$(stat -c '%U' "$f" 2>/dev/null) || continue
  perms=$(stat -c '%A' "$f" 2>/dev/null) || continue

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$hash" "$size" "$owner" "$perms" "$mtime" "$ctime" "$f"
done > "$HASH_FILE"

echo "" >&2

# ── Etapa 3: Detectar duplicados ─────────────────────────────
log "ETAPA 3/3: Detectando grupos de duplicados..."

sort -k1,1 "$HASH_FILE" > "${TMPDIR_WORK}/sorted.txt"

# Construir JSON para HTML y datos para TXT
JSON_GROUPS="["
FIRST_GROUP=true
TOTAL_GROUPS=0
TOTAL_DUP_FILES=0
TOTAL_DUP_BYTES=0

{
  echo ""
  echo "------------------------------------------------------------"
  echo " GRUPOS DE DUPLICADOS"
  echo "------------------------------------------------------------"
} >> "$TXT_REPORT"

prev_hash=""
declare -a group_lines=()

process_group() {
  local lines=("$@")
  [[ ${#lines[@]} -lt 2 ]] && return

  TOTAL_GROUPS=$((TOTAL_GROUPS + 1))
  local group_size=${#lines[@]}
  TOTAL_DUP_FILES=$((TOTAL_DUP_FILES + group_size))

  local first_line="${lines[0]}"
  local hash size owner perms mtime ctime path
  IFS=$'\t' read -r hash size owner perms mtime ctime path <<< "$first_line"
  TOTAL_DUP_BYTES=$((TOTAL_DUP_BYTES + size * (group_size - 1)))

  # TXT
  {
    echo ""
    echo "GRUPO $TOTAL_GROUPS (${group_size} archivos idénticos | SHA256: $hash)"
    printf "  %-12s %-10s %-11s %-20s %-20s %s\n" "TAMAÑO(B)" "USUARIO" "PERMISOS" "MODIFICADO" "CREADO" "RUTA"
    printf "  %s\n" "$(printf '─%.0s' {1..110})"
    for line in "${lines[@]}"; do
      IFS=$'\t' read -r h s o p m c fp <<< "$line"
      printf "  %-12s %-10s %-11s %-20s %-20s %s\n" "$s" "$o" "$p" "$m" "$c" "$fp"
    done
  } >> "$TXT_REPORT"

  # JSON para HTML
  $FIRST_GROUP || JSON_GROUPS+=","
  FIRST_GROUP=false
  JSON_GROUPS+="{"
  JSON_GROUPS+="\"hash\":\"$hash\","
  JSON_GROUPS+="\"count\":$group_size,"
  JSON_GROUPS+="\"size\":$size,"
  JSON_GROUPS+="\"files\":["
  local first_file=true
  for line in "${lines[@]}"; do
    IFS=$'\t' read -r h s o p m c fp <<< "$line"
    local dir
    dir=$(dirname "$fp")
    local fname
    fname=$(basename "$fp")
    $first_file || JSON_GROUPS+=","
    first_file=false
    # Escapar caracteres especiales para JSON
    fp_esc="${fp//\\/\\\\}"; fp_esc="${fp_esc//\"/\\\"}"
    dir_esc="${dir//\\/\\\\}"; dir_esc="${dir_esc//\"/\\\"}"
    fname_esc="${fname//\\/\\\\}"; fname_esc="${fname_esc//\"/\\\"}"
    JSON_GROUPS+="{\"path\":\"$fp_esc\",\"dir\":\"$dir_esc\",\"name\":\"$fname_esc\",\"size\":\"$s\",\"owner\":\"$o\",\"perms\":\"$p\",\"mtime\":\"$m\",\"ctime\":\"$c\"}"
  done
  JSON_GROUPS+="]}"
}

while IFS=$'\t' read -r hash size owner perms mtime ctime path; do
  if [[ "$hash" != "$prev_hash" ]]; then
    [[ ${#group_lines[@]} -gt 0 ]] && process_group "${group_lines[@]}"
    group_lines=()
    prev_hash="$hash"
  fi
  group_lines+=("$hash	$size	$owner	$perms	$mtime	$ctime	$path")
done < "${TMPDIR_WORK}/sorted.txt"

[[ ${#group_lines[@]} -gt 0 ]] && process_group "${group_lines[@]}"
JSON_GROUPS+="]"

# ── Resumen TXT ──────────────────────────────────────────────
{
  echo ""
  echo "============================================================"
  echo " RESUMEN"
  echo "  Grupos de duplicados : $TOTAL_GROUPS"
  echo "  Archivos duplicados  : $TOTAL_DUP_FILES"
  echo "  Espacio desperdiciado: $((TOTAL_DUP_BYTES / 1024 / 1024)) MB"
  echo "  Reporte HTML         : $HTML_REPORT"
  echo "============================================================"
} | tee -a "$TXT_REPORT"

# ── Generar HTML ─────────────────────────────────────────────
log "Generando reporte HTML..."

cat > "$HTML_REPORT" << HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Reporte de Duplicados</title>
<style>
  :root {
    --bg:        #0d1117;
    --surface:   #161b22;
    --surface2:  #1c2333;
    --border:    #30363d;
    --accent:    #1e6eb5;
    --accent2:   #2d8dd4;
    --accent3:   #58a6ff;
    --text:      #e6edf3;
    --text-muted:#8b949e;
    --danger:    #f85149;
    --warn:      #d29922;
    --success:   #3fb950;
    --tag-bg:    #1f3a5f;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; min-height: 100vh; }

  /* ── Header ── */
  .header {
    background: linear-gradient(135deg, #0d1f3c 0%, #1e3a5f 50%, #0d2137 100%);
    border-bottom: 1px solid var(--accent);
    padding: 2rem 2.5rem;
    display: flex; align-items: center; gap: 1.5rem;
  }
  .header-icon { font-size: 2.5rem; }
  .header h1 { font-size: 1.6rem; font-weight: 700; color: var(--accent3); }
  .header p  { color: var(--text-muted); font-size: 0.85rem; margin-top: 0.25rem; }

  /* ── Stats cards ── */
  .stats {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 1rem; padding: 1.5rem 2.5rem;
  }
  .stat-card {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 10px; padding: 1.2rem 1.5rem;
    display: flex; flex-direction: column; gap: 0.3rem;
    transition: border-color .2s;
  }
  .stat-card:hover { border-color: var(--accent2); }
  .stat-label { font-size: 0.75rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: .05em; }
  .stat-value { font-size: 1.8rem; font-weight: 700; color: var(--accent3); }
  .stat-sub   { font-size: 0.75rem; color: var(--text-muted); }

  /* ── Filters ── */
  .filters {
    background: var(--surface); border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border); padding: 1rem 2.5rem;
    display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: center;
  }
  .filters label { font-size: 0.8rem; color: var(--text-muted); }
  .filters input, .filters select {
    background: var(--surface2); border: 1px solid var(--border);
    color: var(--text); border-radius: 6px; padding: 0.4rem 0.75rem;
    font-size: 0.85rem; outline: none; transition: border-color .2s;
  }
  .filters input:focus, .filters select:focus { border-color: var(--accent2); }
  .filters input[type=text] { width: 220px; }
  .filter-group { display: flex; align-items: center; gap: 0.4rem; }
  .btn-reset {
    background: var(--surface2); border: 1px solid var(--border);
    color: var(--text-muted); border-radius: 6px; padding: 0.4rem 0.9rem;
    font-size: 0.8rem; cursor: pointer; transition: all .2s;
  }
  .btn-reset:hover { border-color: var(--accent2); color: var(--text); }

  /* ── Main content ── */
  .content { padding: 1.5rem 2.5rem; }
  .results-header {
    display: flex; justify-content: space-between; align-items: center;
    margin-bottom: 1rem;
  }
  .results-count { font-size: 0.85rem; color: var(--text-muted); }

  /* ── Group card ── */
  .group-card {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 10px; margin-bottom: 1.2rem; overflow: hidden;
    transition: border-color .2s;
  }
  .group-card:hover { border-color: var(--accent); }
  .group-header {
    background: var(--surface2); padding: 0.85rem 1.25rem;
    display: flex; align-items: center; justify-content: space-between;
    cursor: pointer; user-select: none;
  }
  .group-header:hover { background: #1f2d42; }
  .group-title { display: flex; align-items: center; gap: 0.75rem; }
  .group-num {
    background: var(--accent); color: #fff;
    border-radius: 6px; padding: 0.15rem 0.6rem; font-size: 0.75rem; font-weight: 700;
  }
  .group-hash { font-family: monospace; font-size: 0.78rem; color: var(--text-muted); }
  .group-badges { display: flex; gap: 0.5rem; align-items: center; }
  .badge {
    border-radius: 20px; padding: 0.2rem 0.65rem; font-size: 0.72rem; font-weight: 600;
  }
  .badge-count { background: #1f3a5f; color: var(--accent3); }
  .badge-size  { background: #2d1f0e; color: var(--warn); }
  .chevron { color: var(--text-muted); transition: transform .2s; font-size: 0.8rem; }
  .group-card.open .chevron { transform: rotate(180deg); }

  /* ── Files table ── */
  .files-table { display: none; overflow-x: auto; }
  .group-card.open .files-table { display: block; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
  th {
    background: #111827; color: var(--text-muted); text-align: left;
    padding: 0.6rem 1rem; font-size: 0.72rem; text-transform: uppercase;
    letter-spacing: .05em; border-bottom: 1px solid var(--border); white-space: nowrap;
  }
  td {
    padding: 0.6rem 1rem; border-bottom: 1px solid #1e2432;
    vertical-align: middle;
  }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #1a2233; }
  .path-cell { font-family: monospace; font-size: 0.78rem; word-break: break-all; }
  .dir-part  { color: var(--text-muted); }
  .file-part { color: var(--accent3); font-weight: 600; }
  .size-cell { white-space: nowrap; color: var(--warn); }
  .date-cell { white-space: nowrap; color: var(--text-muted); font-size: 0.75rem; }
  .perms-cell { font-family: monospace; font-size: 0.75rem; color: var(--success); }
  .owner-cell { color: var(--text-muted); }

  /* ── No results ── */
  .no-results {
    text-align: center; padding: 3rem; color: var(--text-muted);
  }
  .no-results .icon { font-size: 3rem; margin-bottom: 0.5rem; }

  /* ── Footer ── */
  footer {
    text-align: center; padding: 1.5rem; font-size: 0.75rem;
    color: var(--text-muted); border-top: 1px solid var(--border);
  }
</style>
</head>
<body>

<div class="header">
  <div class="header-icon">🔍</div>
  <div>
    <h1>Reporte de Archivos Duplicados</h1>
    <p>Ruta escaneada: <strong>SCAN_DIR_PLACEHOLDER</strong> &nbsp;|&nbsp; Generado: <strong>TS_PLACEHOLDER</strong></p>
  </div>
</div>

<div class="stats">
  <div class="stat-card">
    <span class="stat-label">Archivos totales</span>
    <span class="stat-value" id="s-total">0</span>
    <span class="stat-sub">en la ruta escaneada</span>
  </div>
  <div class="stat-card">
    <span class="stat-label">Grupos duplicados</span>
    <span class="stat-value" id="s-groups">0</span>
    <span class="stat-sub">conjuntos idénticos</span>
  </div>
  <div class="stat-card">
    <span class="stat-label">Archivos duplicados</span>
    <span class="stat-value" id="s-files">0</span>
    <span class="stat-sub">instancias redundantes</span>
  </div>
  <div class="stat-card">
    <span class="stat-label">Espacio desperdiciado</span>
    <span class="stat-value" id="s-space">0 MB</span>
    <span class="stat-sub">espacio recuperable</span>
  </div>
</div>

<div class="filters">
  <div class="filter-group">
    <label>🔎 Buscar ruta / archivo</label>
    <input type="text" id="f-search" placeholder="Ej: /home/inti/Documentos">
  </div>
  <div class="filter-group">
    <label>📂 Directorio</label>
    <select id="f-dir"><option value="">Todos</option></select>
  </div>
  <div class="filter-group">
    <label>👤 Propietario</label>
    <select id="f-owner"><option value="">Todos</option></select>
  </div>
  <div class="filter-group">
    <label>📦 Tamaño mín. (KB)</label>
    <input type="number" id="f-size" placeholder="0" style="width:100px">
  </div>
  <div class="filter-group">
    <label>📋 Copias mín.</label>
    <select id="f-count">
      <option value="0">Todas</option>
      <option value="2">≥ 2</option>
      <option value="3">≥ 3</option>
      <option value="5">≥ 5</option>
      <option value="10">≥ 10</option>
    </select>
  </div>
  <button class="btn-reset" onclick="resetFilters()">✕ Limpiar filtros</button>
</div>

<div class="content">
  <div class="results-header">
    <span class="results-count" id="results-count"></span>
  </div>
  <div id="groups-container"></div>
  <div class="no-results" id="no-results" style="display:none">
    <div class="icon">📭</div>
    <p>No se encontraron grupos con los filtros aplicados.</p>
  </div>
</div>

<footer>scan_duplicates.sh &nbsp;|&nbsp; Reporte generado el TS_PLACEHOLDER</footer>

<script>
const RAW_DATA = JSONEOF;
const TOTAL_FILES = TOTAL_FILES_PLACEHOLDER;

function fmtSize(bytes) {
  bytes = parseInt(bytes);
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024*1024) return (bytes/1024).toFixed(1) + ' KB';
  return (bytes/1024/1024).toFixed(2) + ' MB';
}

function fmtWasted(bytes, count) {
  const w = bytes * (count - 1);
  return fmtSize(w);
}

// Populate filter dropdowns
const dirs   = new Set();
const owners = new Set();
RAW_DATA.forEach(g => g.files.forEach(f => { dirs.add(f.dir); owners.add(f.owner); }));
const selDir = document.getElementById('f-dir');
const selOwn = document.getElementById('f-owner');
[...dirs].sort().forEach(d => { const o = document.createElement('option'); o.value=d; o.textContent=d; selDir.appendChild(o); });
[...owners].sort().forEach(d => { const o = document.createElement('option'); o.value=d; o.textContent=d; selOwn.appendChild(o); });

// Stats
let totalDupFiles = 0, totalWasted = 0;
RAW_DATA.forEach(g => { totalDupFiles += g.count; totalWasted += parseInt(g.size) * (g.count - 1); });
document.getElementById('s-total').textContent  = TOTAL_FILES.toLocaleString();
document.getElementById('s-groups').textContent = RAW_DATA.length.toLocaleString();
document.getElementById('s-files').textContent  = totalDupFiles.toLocaleString();
document.getElementById('s-space').textContent  = fmtSize(totalWasted);

function buildGroups(data) {
  const container = document.getElementById('groups-container');
  container.innerHTML = '';
  const noRes = document.getElementById('no-results');

  if (data.length === 0) { noRes.style.display='block'; document.getElementById('results-count').textContent=''; return; }
  noRes.style.display = 'none';
  document.getElementById('results-count').textContent = `Mostrando ${data.length} grupo(s)`;

  data.forEach((g, idx) => {
    const card = document.createElement('div');
    card.className = 'group-card';
    card.innerHTML = \`
      <div class="group-header" onclick="this.parentElement.classList.toggle('open')">
        <div class="group-title">
          <span class="group-num">G\${idx+1}</span>
          <span class="group-hash">\${g.hash}</span>
        </div>
        <div class="group-badges">
          <span class="badge badge-count">📋 \${g.count} copias</span>
          <span class="badge badge-size">💾 \${fmtWasted(g.size, g.count)} desperdiciados</span>
          <span class="chevron">▼</span>
        </div>
      </div>
      <div class="files-table">
        <table>
          <thead>
            <tr>
              <th>#</th><th>Ruta completa</th><th>Tamaño</th>
              <th>Propietario</th><th>Permisos</th>
              <th>Modificado</th><th>Creado</th>
            </tr>
          </thead>
          <tbody>
            \${g.files.map((f,i) => \`
              <tr>
                <td>\${i+1}</td>
                <td class="path-cell"><span class="dir-part">\${f.dir}/</span><span class="file-part">\${f.name}</span></td>
                <td class="size-cell">\${fmtSize(f.size)}</td>
                <td class="owner-cell">\${f.owner}</td>
                <td class="perms-cell">\${f.perms}</td>
                <td class="date-cell">\${f.mtime}</td>
                <td class="date-cell">\${f.ctime}</td>
              </tr>
            \`).join('')}
          </tbody>
        </table>
      </div>
    \`;
    container.appendChild(card);
  });
}

function applyFilters() {
  const search = document.getElementById('f-search').value.toLowerCase();
  const dir    = document.getElementById('f-dir').value;
  const owner  = document.getElementById('f-owner').value;
  const minSize= parseFloat(document.getElementById('f-size').value || 0) * 1024;
  const minCount = parseInt(document.getElementById('f-count').value || 0);

  const filtered = RAW_DATA.filter(g => {
    if (minCount && g.count < minCount) return false;
    if (minSize  && parseInt(g.size) < minSize) return false;
    if (dir   && !g.files.some(f => f.dir === dir))    return false;
    if (owner && !g.files.some(f => f.owner === owner)) return false;
    if (search && !g.files.some(f => f.path.toLowerCase().includes(search))) return false;
    return true;
  });

  buildGroups(filtered);
}

function resetFilters() {
  document.getElementById('f-search').value = '';
  document.getElementById('f-dir').value    = '';
  document.getElementById('f-owner').value  = '';
  document.getElementById('f-size').value   = '';
  document.getElementById('f-count').value  = '0';
  buildGroups(RAW_DATA);
}

['f-search','f-dir','f-owner','f-size','f-count'].forEach(id =>
  document.getElementById(id).addEventListener('input', applyFilters)
);

buildGroups(RAW_DATA);
</script>
</body>
</html>
HTMLEOF

# Inyectar datos reales en HTML
sed -i \
  -e "s|SCAN_DIR_PLACEHOLDER|$SCAN_DIR|g" \
  -e "s|TS_PLACEHOLDER|$(date '+%F %T')|g" \
  -e "s|TOTAL_FILES_PLACEHOLDER|$TOTAL|g" \
  -e "s|JSONEOF|$JSON_GROUPS|g" \
  "$HTML_REPORT"

log "✅ Escaneo completado."
log "   TXT : $TXT_REPORT"
log "   HTML: $HTML_REPORT"
