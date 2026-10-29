#!/usr/bin/env bash
# Copia de seguridad de /home en /var/backups/home: un .tar.gz con fecha por ejecución.
# La ejecuta cron (/etc/cron.d/tp2). También se puede correr a mano: sudo tp2-backup-home.sh
set -euo pipefail

DESTINO=/var/backups/home
RETENCION_DIAS=${RETENCION_DIAS:-7}
ARCHIVO="$DESTINO/home_$(date +%F_%H%M%S).tar.gz"

# 700: los backups contienen los homes de todos, solo root puede leerlos.
install -d -m 700 "$DESTINO"

# Se escribe primero a .tmp para que un backup a medio hacer nunca parezca "el último".
# -p conserva permisos. Código 1 = "algún archivo cambió mientras se leía": no es grave.
tar -czpf "$ARCHIVO.tmp" -C / home || [ $? -eq 1 ]
mv "$ARCHIVO.tmp" "$ARCHIVO"
chmod 600 "$ARCHIVO"

# Retención: se borran los backups con más de RETENCION_DIAS días.
find "$DESTINO" -name 'home_*.tar.gz' -mtime +"$RETENCION_DIAS" -delete

echo "$(date '+%F %T') backup OK: $ARCHIVO ($(du -h "$ARCHIVO" | cut -f1))"
