#!/usr/bin/env bash
# Agrega un cliente (peer) a wg0 y deja lista su configuración.
# Uso:
#   sudo ./scripts/wg-agregar-peer.sh <nombre> <ip_vpn> <endpoint> [clave_publica_cliente]
# Ejemplos:
#   sudo ./scripts/wg-agregar-peer.sh notebook-matias 10.0.0.2 192.168.1.50
#   sudo ./scripts/wg-agregar-peer.sh pc-valentino 10.0.0.3 192.168.1.50 'AbC...='
#
# Sin clave pública: genera el par de claves acá y escribe la config completa del cliente en
# /root/wg-clientes/<nombre>.conf (hay que copiarla al cliente y borrarla del servidor).
# Con clave pública (generada en el cliente, lo más seguro): la privada nunca pasa por el servidor.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo" >&2; exit 1; }
[ $# -ge 3 ] || { sed -n '3,11p' "$0"; exit 1; }

NOMBRE=$1
IP=$2
ENDPOINT=$3
PUB_CLIENTE=${4:-}
CONF=/etc/wireguard/wg0.conf
SALIDA=/root/wg-clientes
RED_VPN=10.0.0.0/24

[[ $NOMBRE =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Nombre inválido: usar letras, números, - o _" >&2; exit 1; }
[[ $IP =~ ^10\.0\.0\.([2-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-4])$ ]] \
    || { echo "IP inválida: tiene que ser 10.0.0.2 - 10.0.0.254" >&2; exit 1; }

if grep -qxF "# peer: $NOMBRE" "$CONF"; then
    echo "El peer '$NOMBRE' ya existe en $CONF. No se cambia nada."
    exit 0
fi
if grep -qF "AllowedIPs = $IP/32" "$CONF"; then
    echo "La IP $IP ya está asignada a otro peer" >&2
    exit 1
fi

umask 077
PRIV_CLIENTE=""
if [ -z "$PUB_CLIENTE" ]; then
    PRIV_CLIENTE=$(wg genkey)
    PUB_CLIENTE=$(printf '%s' "$PRIV_CLIENTE" | wg pubkey)
fi

cat >> "$CONF" <<EOF

# peer: $NOMBRE
[Peer]
PublicKey = $PUB_CLIENTE
AllowedIPs = $IP/32
EOF

# Aplica el cambio sin cortar la VPN a los clientes conectados.
wg syncconf wg0 <(wg-quick strip wg0)

install -d -m 700 "$SALIDA"
cat > "$SALIDA/$NOMBRE.conf" <<EOF
[Interface]
PrivateKey = ${PRIV_CLIENTE:-<pegar acá la clave privada generada en el cliente>}
Address = $IP/24

[Peer]
PublicKey = $(wg show wg0 public-key)
Endpoint = $ENDPOINT:$(wg show wg0 listen-port)
AllowedIPs = $RED_VPN
PersistentKeepalive = 25
EOF

echo "Peer '$NOMBRE' agregado con IP $IP."
echo "Configuración del cliente: $SALIDA/$NOMBRE.conf"
