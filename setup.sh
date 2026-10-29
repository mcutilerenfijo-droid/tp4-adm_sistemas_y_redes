#!/usr/bin/env bash
# setup.sh — Aprovisiona el servidor del TP2 de punta a punta (Ubuntu Server 24.04 LTS).
#
# Idempotente: se puede ejecutar todas las veces que haga falta; solo crea o corrige lo que
# falta y nunca pisa claves, peers ni contenido de los usuarios que ya existan.
#
# Uso (desde la raíz del repo):
#   sudo ./setup.sh
#   sudo USUARIOS="kakashi naruto sakura" ./setup.sh      # otros usuarios
set -euo pipefail

USUARIOS="${USUARIOS:-kakashi naruto}"        # usuarios con public_html
ADMIN="${ADMIN:-${SUDO_USER:-vboxuser}}"      # administrador que entra por SSH
HTPASSWD_USUARIO="${HTPASSWD_USUARIO:-invitado}"

REPO="$(cd "$(dirname "$0")" && pwd)"

log()   { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo: sudo ./setup.sh" >&2; exit 1; }
id "$ADMIN" >/dev/null 2>&1 || { echo "No existe el usuario administrador '$ADMIN'" >&2; exit 1; }

# Copia las claves públicas de claves/<usuario>.pub a su authorized_keys (sin duplicar).
instalar_claves() {
    local u=$1 archivo="$REPO/claves/$1.pub" home grupo clave
    home=$(getent passwd "$u" | cut -d: -f6)
    grupo=$(id -gn "$u")
    if [ ! -f "$archivo" ]; then
        aviso "No hay claves/$u.pub: se mantiene lo que ya tenga $home/.ssh/authorized_keys"
        return 0
    fi
    install -d -o "$u" -g "$grupo" -m 700 "$home/.ssh"
    touch "$home/.ssh/authorized_keys"
    while IFS= read -r clave || [ -n "$clave" ]; do
        clave=${clave%$'\r'}                       # por si el .pub se guardó desde Windows
        case "$clave" in ''|'#'*) continue ;; esac
        grep -qxF "$clave" "$home/.ssh/authorized_keys" \
            || printf '%s\n' "$clave" >> "$home/.ssh/authorized_keys"
    done < "$archivo"
    chown "$u:$grupo" "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
}

# ---------------------------------------------------------------------------------------
log "1/8 Paquetes"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssh-server wireguard ufw docker.io docker-compose-v2 openssl cron tar

# ---------------------------------------------------------------------------------------
log "2/8 WireGuard (wg0 = 10.0.0.1/24, puerto 51820/udp)"
install -d -m 700 /etc/wireguard
if [ ! -f /etc/wireguard/privatekey ]; then
    (umask 077; wg genkey > /etc/wireguard/privatekey)
    wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey
fi
if [ ! -f /etc/wireguard/wg0.conf ]; then
    (umask 077
     sed "s|__PRIVATE_KEY__|$(cat /etc/wireguard/privatekey)|" \
         "$REPO/wireguard/wg0.conf.example" > /etc/wireguard/wg0.conf)
else
    echo "/etc/wireguard/wg0.conf ya existe: no se modifica (peers: scripts/wg-agregar-peer.sh)"
fi
systemctl enable --now wg-quick@wg0

# ---------------------------------------------------------------------------------------
log "3/8 Docker arranca después de wg0"
install -D -m 644 "$REPO/sistema/systemd/docker-espera-wg0.conf" \
    /etc/systemd/system/docker.service.d/10-espera-wg0.conf
systemctl daemon-reload
systemctl enable --now docker

# ---------------------------------------------------------------------------------------
log "4/8 Usuarios, public_html y claves SSH"
groupadd -f sshusers
usermod -aG sshusers "$ADMIN"
instalar_claves "$ADMIN"

for u in $USUARIOS; do
    # Sin contraseña: el usuario solo puede entrar por SSH con su clave.
    id "$u" >/dev/null 2>&1 || useradd -m -s /bin/bash "$u"
    usermod -aG sshusers "$u"
    chmod 711 "/home/$u"                               # nginx puede atravesar, no listar
    install -d -o "$u" -g "$(id -gn "$u")" -m 755 "/home/$u/public_html"
    if [ ! -e "/home/$u/public_html/index.html" ]; then
        printf '<!doctype html>\n<meta charset="utf-8">\n<h1>Bienvenido al espacio de %s</h1>\n' "$u" \
            > "/home/$u/public_html/index.html"
        chown "$u:$(id -gn "$u")" "/home/$u/public_html/index.html"
        chmod 644 "/home/$u/public_html/index.html"
    fi
    instalar_claves "$u"
done

# Bonus: carpeta protegida con contraseña para el primer usuario de la lista.
PRIMERO=${USUARIOS%% *}
if [ ! -d "/home/$PRIMERO/public_html/privado" ]; then
    install -d -o "$PRIMERO" -g "$(id -gn "$PRIMERO")" -m 755 "/home/$PRIMERO/public_html/privado"
    echo "Contenido protegido con autenticación HTTP básica." > "/home/$PRIMERO/public_html/privado/secreto.txt"
    chown "$PRIMERO:$(id -gn "$PRIMERO")" "/home/$PRIMERO/public_html/privado/secreto.txt"
    chmod 644 "/home/$PRIMERO/public_html/privado/secreto.txt"
fi

# ---------------------------------------------------------------------------------------
log "5/8 SSH: solo con clave, sin root"
ADMIN_HOME=$(getent passwd "$ADMIN" | cut -d: -f6)
if [ -s "$ADMIN_HOME/.ssh/authorized_keys" ]; then
    install -m 644 "$REPO/sistema/ssh/00-tp2.conf" /etc/ssh/sshd_config.d/00-tp2.conf
    install -d -m 755 /run/sshd      # en 24.04 (activación por socket) puede no existir todavía
    sshd -t
    systemctl restart ssh
else
    aviso "$ADMIN no tiene claves en $ADMIN_HOME/.ssh/authorized_keys."
    aviso "NO se desactivan las contraseñas para no dejarlo afuera. Copiar su clave y volver a ejecutar."
fi

# ---------------------------------------------------------------------------------------
log "6/8 Firewall (ufw)"
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed
ufw allow 51820/udp comment 'WireGuard'
ufw delete allow 22/tcp >/dev/null 2>&1 || true      # se reemplaza por "limit"
ufw limit 22/tcp comment 'SSH de administracion'
ufw allow in on wg0 comment 'Todo lo que entra por la VPN'
ufw --force enable

# ---------------------------------------------------------------------------------------
log "7/8 Web (nginx) y monitoreo (Netdata) en Docker"
install -m 755 "$REPO/scripts/tp2-generar-index.sh" /usr/local/bin/tp2-generar-index.sh
/usr/local/bin/tp2-generar-index.sh

# Bonus: credenciales de /~<usuario>/privado/. 101 = grupo "nginx" dentro del contenedor.
install -d -m 750 -o root -g 101 /etc/tp2/web
if [ ! -s /etc/tp2/web/htpasswd ]; then
    PASS=$(openssl rand -base64 12)
    printf '%s:%s\n' "$HTPASSWD_USUARIO" "$(openssl passwd -apr1 "$PASS")" > /etc/tp2/web/htpasswd
    (umask 077; printf 'usuario: %s\ncontraseña: %s\n' "$HTPASSWD_USUARIO" "$PASS" > /root/tp2-htpasswd.txt)
    aviso "Credenciales de la carpeta privado/ guardadas en /root/tp2-htpasswd.txt"
fi
chown root:101 /etc/tp2/web/htpasswd
chmod 640 /etc/tp2/web/htpasswd

# Contenedores de la versión anterior (proyecto "tp"): ocupan los mismos puertos.
for viejo in tp-web-1 tp-monitoreo-1; do
    if docker container inspect "$viejo" >/dev/null 2>&1; then
        aviso "Se elimina el contenedor anterior $viejo"
        docker rm -f "$viejo" >/dev/null
    fi
done
docker compose -f "$REPO/docker/docker-compose.yml" up -d

# ---------------------------------------------------------------------------------------
log "8/8 Backup programado"
install -m 755 "$REPO/backup/tp2-backup-home.sh" /usr/local/bin/tp2-backup-home.sh
install -m 755 "$REPO/backup/tp2-restaurar.sh"   /usr/local/bin/tp2-restaurar.sh
install -m 644 "$REPO/sistema/cron/tp2" /etc/cron.d/tp2
install -d -m 700 /var/backups/home

# Línea de cron de la versión anterior (escribía siempre el mismo /var/backup.tar.gz).
if crontab -l 2>/dev/null | grep -F '/var/backup.tar.gz' >/dev/null; then
    { crontab -l | grep -vF '/var/backup.tar.gz' || true; } | crontab -
    aviso "Se quitó del crontab de root la tarea de backup anterior"
fi
[ -n "$(ls -A /var/backups/home)" ] || /usr/local/bin/tp2-backup-home.sh

# ---------------------------------------------------------------------------------------
log "Listo"
echo "Clave pública del servidor: $(wg show wg0 public-key)"
echo "Siguiente paso: agregar el cliente de la demo, por ejemplo:"
echo "  sudo ./scripts/wg-agregar-peer.sh notebook 10.0.0.2 <IP_de_la_VM_en_la_red_local>"
echo
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
