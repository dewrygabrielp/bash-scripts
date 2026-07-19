#!/usr/bin/env bash
# ============================================================
# setup.sh — Instala las dependencias de duplicate-tools
# Compatible con Debian/Ubuntu
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; RESET='\033[0m'

ok()  { echo -e "${GREEN}[OK]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }
log() { echo -e "${CYAN}[INFO]${RESET} $1"; }

# ── Verificar que es Debian/Ubuntu ───────────────────────────
if ! command -v apt-get &>/dev/null; then
  err "Este script requiere apt-get. Solo compatible con Debian/Ubuntu."
fi

# ── Verificar sudo ───────────────────────────────────────────
if ! command -v sudo &>/dev/null; then
  err "Se requiere sudo para instalar paquetes."
fi

log "Actualizando lista de paquetes..."
sudo apt-get update -qq

# ── Dependencias ─────────────────────────────────────────────
DEPS=(coreutils findutils gawk)
MISSING=()

for pkg in "${DEPS[@]}"; do
  if dpkg -s "$pkg" &>/dev/null; then
    ok "$pkg ya está instalado"
  else
    MISSING+=("$pkg")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  log "Instalando: ${MISSING[*]}"
  sudo apt-get install -y "${MISSING[@]}"
  ok "Dependencias instaladas."
else
  ok "Todo está instalado. No se requiere ninguna acción."
fi

# ── Permisos de ejecución ────────────────────────────────────
log "Verificando permisos de ejecución..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for script in "$SCRIPT_DIR/scan_duplicates.sh" "$SCRIPT_DIR/clean_duplicates.sh"; do
  if [[ -f "$script" ]]; then
    chmod +x "$script"
    ok "$(basename "$script") — ejecutable"
  else
    echo -e "${RED}[WARN]${RESET} No se encontró: $script"
  fi
done

echo ""
ok "Setup completo. Ya podés usar los scripts:"
echo "   ./scan_duplicates.sh <ruta> --help"
echo "   ./clean_duplicates.sh <ruta> --help"
