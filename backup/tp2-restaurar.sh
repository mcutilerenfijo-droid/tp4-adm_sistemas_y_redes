#!/usr/bin/env bash
# Restaura un archivo o una carpeta de /home desde un backup de tp2-backup-home.sh.
# Uso:
#   sudo tp2-restaurar.sh -l                        lista los backups disponibles
#   sudo tp2-restaurar.sh <ruta>                    restaura <ruta> desde el último backup
#   sudo tp2-restaurar.sh <ruta> <backup.tar.gz>    restaura <ruta> desde ese backup
# <ruta> es relativa a /home, por ejemplo: kakashi/public_html/naruto-run.jpg
set -euo pipefail

DESTINO=/var/backups/home

if [ "${1:-}" = "-l" ]; then
    ls -lh "$DESTINO"/home_*.tar.gz
    exit 0
fi
[ $# -ge 1 ] || { sed -n '3,7p' "$0"; exit 1; }

# Acepta "kakashi/x", "/home/kakashi/x" o "home/kakashi/x/".
RUTA=${1#/}
RUTA=${RUTA#home/}
RUTA=${RUTA%/}
case "/$RUTA/" in
    */../*|//) echo "Ruta inválida: $1" >&2; exit 1 ;;
esac

BACKUP=${2:-$( (ls -1t "$DESTINO"/home_*.tar.gz 2>/dev/null || true) | head -n 1)}
[ -n "$BACKUP" ] && [ -f "$BACKUP" ] || { echo "No se encontró el backup en $DESTINO" >&2; exit 1; }

# grep sin -q: con pipefail, -q cortaría el pipe y tar fallaría por SIGPIPE.
if ! tar -tzf "$BACKUP" | sed 's:/$::' | grep -xF "home/$RUTA" >/dev/null; then
    echo "/home/$RUTA no está en $(basename "$BACKUP")" >&2
    exit 1
fi

# -p restaura permisos y dueños originales. Si es una carpeta, se restaura completa.
tar -xzpf "$BACKUP" -C / "home/$RUTA"
echo "Restaurado /home/$RUTA desde $(basename "$BACKUP")"
