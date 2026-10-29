#!/usr/bin/env bash
# Genera /var/www/html/index.html con un enlace por cada /home/<usuario>/public_html.
# Lo ejecuta setup.sh y después cron cada 5 minutos, así un usuario nuevo aparece solo.
set -euo pipefail

DESTINO=/var/www/html/index.html
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

{
    echo '<!doctype html>'
    echo '<html lang="es">'
    echo '<head><meta charset="utf-8"><title>Servidor TP2</title></head>'
    echo '<body>'
    echo '<h1>Servidor TP2</h1>'
    echo '<p>Directorios públicos de los usuarios:</p>'
    echo '<ul>'
    for dir in /home/*/public_html; do
        [ -d "$dir" ] || continue
        u=$(basename "$(dirname "$dir")")
        echo "  <li><a href=\"/~$u/\">$u</a></li>"
    done
    echo '</ul>'
    echo '</body>'
    echo '</html>'
} > "$TMP"

install -D -m 644 "$TMP" "$DESTINO"
