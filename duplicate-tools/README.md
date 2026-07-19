# duplicate-tools

Dos scripts para detectar y limpiar archivos duplicados. Uno solo mira y reporta, el otro actúa. Ambos generan un reporte en TXT y un dashboard HTML con tabla interactiva y filtros.

---

## Scripts

### `scan_duplicates.sh` — Escanea y reporta

Recorre una ruta, calcula el SHA256 de cada archivo y agrupa los que son idénticos. No toca nada, solo informa. El resultado es un `.txt` y un `.html` que podés abrir en el navegador.

El HTML muestra una tabla con todos los grupos de duplicados. Podés filtrar por ruta, directorio, propietario, tamaño mínimo y cantidad de copias. Cada fila muestra hash, tamaño, permisos, propietario, fecha de modificación y fecha de creación.

**Uso:**

```bash
./scan_duplicates.sh <ruta> [--output <dir>]
```

**Flags:**

| Flag | Descripción |
|---|---|
| `--output <dir>` | Carpeta donde se guardan los reportes. Por defecto crea `./scan_report_TIMESTAMP` |
| `--help` | Muestra el uso |

**Ejemplos:**

```bash
# Escanear tu carpeta de Descargas
./scan_duplicates.sh ~/Descargas

# Escanear una SDCard montada y guardar el reporte en un lugar específico
./scan_duplicates.sh /media/user/SDCARD --output ~/reportes/sdcard
```

---

### `clean_duplicates.sh` — Elimina duplicados

Hace lo mismo que `scan_duplicates.sh` pero con la opción de eliminar. Cuando encuentra dos archivos con el mismo SHA256, conserva el primero que encontró y elimina el resto. También puede borrar carpetas que quedaron vacías después de la limpieza, y apagar el equipo al terminar si lo dejás corriendo desatendido.

Siempre conviene correrlo con `--dry-run` la primera vez para ver qué va a eliminar antes de confirmar.

**Uso:**

```bash
./clean_duplicates.sh <ruta> [flags]
```

**Flags:**

| Flag | Descripción |
|---|---|
| `--dry-run` | Simula la ejecución completa sin eliminar nada. Ideal para revisar antes de actuar |
| `--remove-empty-dirs` | Después de eliminar duplicados, borra las carpetas que quedaron vacías |
| `--shutdown` | Apaga el equipo cuando termina. Útil si lo dejás corriendo de noche |
| `--shutdown-delay <seg>` | Cuántos segundos esperar antes de apagar. Por defecto: 60 |
| `--output <dir>` | Carpeta de destino para los reportes generados |
| `--help` | Muestra el uso |

**Ejemplos:**

```bash
# Ver qué se eliminaría sin borrar nada
./clean_duplicates.sh ~/Descargas --dry-run

# Limpiar una SDCard, borrar carpetas vacías y apagar al terminar
./clean_duplicates.sh /media/user/SDCARD --remove-empty-dirs --shutdown

# Limpiar y apagar después de 5 minutos
./clean_duplicates.sh ~/Fotos --shutdown --shutdown-delay 300

# Guardar el reporte en una ruta específica
./clean_duplicates.sh ~/Documentos --output ~/reportes/docs
```

---

## Reportes generados

Cada ejecución crea una carpeta con dos archivos:
scan_report_20250719_143022/
├── reporte_20250719_143022.txt   # Log plano, legible en terminal
└── reporte_20250719_143022.html  # Dashboard interactivo, abrir en navegador 

El HTML no necesita internet ni dependencias externas. Todo está embebido en el archivo.

---

## Requisitos

- Bash 4.0+
- `sha256sum`, `find`, `stat`, `awk`, `sort` (GNU coreutils, vienen en cualquier Linux)

---

## Advertencia

`clean_duplicates.sh` elimina archivos de forma permanente. Siempre usá `--dry-run` primero y revisá el reporte antes de ejecutarlo en modo real.
EOF

---

## Instalación

```bash
git clone https://github.com/tu-usuario/bash-scripts.git
cd bash-scripts/duplicate-tools
./setup.sh
```
