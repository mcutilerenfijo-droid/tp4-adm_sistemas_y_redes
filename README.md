# TP2 — Servidor Linux aislado detrás de WireGuard

**Administración de Sistemas y Redes · Instituto Industrial Luis A. Huergo · 6° AO**
Integrantes: Valentino Barrio · Matías Budani

Servidor Ubuntu cuyos servicios (web, monitoreo y SSH) solo son accesibles a través de una VPN
WireGuard. La web y el monitoreo corren en Docker, el firewall bloquea todo lo demás en la
interfaz pública, y `/home` se respalda todos los días con cron.

---

## 1. Arquitectura

```
          Red local de la demo (ej. 192.168.1.0/24) = "red pública" del servidor
 ┌─────────────────────────┐                     ┌───────────────────────────────────────────┐
 │ PC cliente              │   UDP 51820 túnel   │ ServidorTP2 (VM Ubuntu, adaptador puente) │
 │ WireGuard: 10.0.0.2     │ ──────────────────► │ enp0s3: solo 51820/udp y 22/tcp           │
 │ navegador / ssh         │                     │ wg0 10.0.0.1: todo permitido              │
 └─────────────────────────┘                     │   ├─ :80     nginx    (contenedor tp-web)  │
                                                 │   ├─ :19999  Netdata  (tp-monitoreo)       │
                                                 │   └─ :22     sshd (solo con clave)         │
                                                 │ cron 02:00 → /var/backups/home/*.tar.gz    │
                                                 └───────────────────────────────────────────┘
```

| Dato | Valor |
|---|---|
| Sistema operativo | Ubuntu Server 24.04 LTS |
| Administrador | `vboxuser` |
| Usuarios web | `kakashi`, `naruto` |
| VPN | `wg0`, servidor `10.0.0.1/24`, clientes `10.0.0.2` en adelante, puerto `51820/udp` |
| Web | `http://10.0.0.1/` y `http://10.0.0.1/~<usuario>/` |
| Monitoreo | `http://10.0.0.1:19999/` |
| Backups | `/var/backups/home/home_AAAA-MM-DD_HHMMSS.tar.gz`, se guardan 7 días |

### Estructura del repositorio

```
tp2-servidor/
├── setup.sh                         instalación automática e idempotente (bonus)
├── docker/
│   ├── docker-compose.yml           nginx + Netdata
│   ├── nginx/default.conf           /~usuario, autoindex y carpeta privado/ con contraseña
│   └── netdata/netdata.conf         Netdata escucha solo en 10.0.0.1
├── wireguard/
│   ├── wg0.conf.example             plantilla del servidor
│   └── cliente.conf.example         plantilla del cliente
├── scripts/
│   ├── wg-agregar-peer.sh           agrega un cliente a la VPN
│   └── tp2-generar-index.sh         genera la página principal con los usuarios
├── backup/
│   ├── tp2-backup-home.sh           backup de /home
│   └── tp2-restaurar.sh             restaura un archivo o carpeta
├── sistema/
│   ├── ssh/00-tp2.conf              endurecimiento de sshd
│   ├── systemd/docker-espera-wg0.conf   Docker arranca después de wg0
│   └── cron/tp2                     tareas programadas
├── claves/                          claves PÚBLICAS SSH de los usuarios (<usuario>.pub)
└── GUION_VIDEO.md                   guion de la demostración
```

---

## 2. Antes de empezar: red de VirtualBox

La otra computadora tiene que poder llegar a la VM por UDP 51820. Se recomienda el
**adaptador puente**:

1. VirtualBox → la VM apagada → *Configuración → Red → Adaptador 1 → Conectado a: Adaptador puente*,
   eligiendo la placa de red del host que está en la misma red que la PC cliente.
2. Arrancar la VM y anotar su IP en la red local: `ip -4 addr show enp0s3` (ej. `192.168.1.50`).
   Esa es la **IP pública** del servidor durante la demo.

> Alternativa con NAT: *Avanzadas → Reenvío de puertos* con `UDP host 51820 → invitado 51820`
> y `TCP host 2222 → invitado 22`. En ese caso el `Endpoint` del cliente es la IP del host.

---

## 3. Instalación rápida (bonus: `setup.sh`)

```bash
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/<usuario>/tp2-servidor.git /opt/tp2
cd /opt/tp2
# (opcional) copiar las claves públicas de los usuarios a claves/<usuario>.pub
sudo ./setup.sh
sudo ./scripts/wg-agregar-peer.sh notebook 10.0.0.2 192.168.1.50
```

`setup.sh` es idempotente: ejecutarlo de nuevo no duplica usuarios, reglas, claves ni tareas de cron.
No desactiva el login con contraseña hasta que el administrador tenga una clave instalada, para
no dejarlo afuera.

La sección siguiente hace exactamente lo mismo, a mano y paso a paso.

---

## 4. Instalación paso a paso

Todos los comandos se ejecutan en el servidor, desde la raíz del repo (`cd /opt/tp2`), salvo que
diga **[cliente]**.

### Paso 1 — Paquetes

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y openssh-server wireguard ufw docker.io docker-compose-v2 openssl cron tar git
```

**Verificación:** `systemctl is-active ssh docker cron` devuelve `active` tres veces.
`ssh` puede figurar como `inactive` hasta la primera conexión, porque en 24.04 se activa por socket.

### Paso 2 — WireGuard en el servidor

```bash
sudo install -d -m 700 /etc/wireguard
sudo sh -c 'umask 077; wg genkey > /etc/wireguard/privatekey'
sudo sh -c 'wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey'

sudo install -m 600 wireguard/wg0.conf.example /etc/wireguard/wg0.conf
sudo sed -i "s|__PRIVATE_KEY__|$(sudo cat /etc/wireguard/privatekey)|" /etc/wireguard/wg0.conf

sudo systemctl enable --now wg-quick@wg0
```

**Verificación:** `sudo wg show wg0` muestra `listening port: 51820` e `ip -4 addr show wg0`
muestra `10.0.0.1/24`.

### Paso 3 — Cliente de la VPN (la otra computadora)

**Opción A, la más simple:** el servidor genera todo.

```bash
sudo ./scripts/wg-agregar-peer.sh notebook 10.0.0.2 192.168.1.50
sudo cat /root/wg-clientes/notebook.conf
```

Pasar ese contenido al cliente y después borrarlo del servidor:
`sudo rm /root/wg-clientes/notebook.conf`.

**Opción B, la más segura:** la clave privada se genera en el cliente.

- **[cliente] Windows:** instalar WireGuard desde wireguard.com → *Agregar túnel → Agregar túnel
  vacío*. La app genera las claves y muestra la **clave pública**.
- **[cliente] Linux:** `sudo apt install wireguard && wg genkey | tee priv | wg pubkey`.

En el servidor, pasando esa clave pública como cuarto argumento:

```bash
sudo ./scripts/wg-agregar-peer.sh notebook 10.0.0.2 192.168.1.50 'CLAVE_PUBLICA_DEL_CLIENTE='
```

El archivo generado trae todo menos la `PrivateKey`, que queda en el cliente.

**[cliente]** El túnel tiene que quedar como `wireguard/cliente.conf.example`
(`Address = 10.0.0.2/24`, `Endpoint = 192.168.1.50:51820`, `AllowedIPs = 10.0.0.0/24`). Después:
*Activar* en Windows, o `sudo wg-quick up wg0` en Linux.

**Verificación:**
- **[cliente]** `ping 10.0.0.1` responde.
- En el servidor, `sudo wg` muestra el `peer:` con `latest handshake` y `transfer`.

### Paso 4 — Usuarios, `public_html` y claves SSH

```bash
sudo groupadd -f sshusers
sudo usermod -aG sshusers vboxuser

# Usuario sin contraseña: solo podrá entrar con su clave SSH.
sudo useradd -m -s /bin/bash -G sshusers kakashi
sudo chmod 711 /home/kakashi                       # nginx atraviesa el home pero no lo lista
sudo install -d -o kakashi -g kakashi -m 755 /home/kakashi/public_html
echo '<h1>Bienvenido al espacio de kakashi</h1>' | sudo -u kakashi tee /home/kakashi/public_html/index.html
# Repetir para naruto (y los usuarios que hagan falta).
```

**[cliente]** Generar un par de claves por usuario:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/tp2_kakashi -C "kakashi@tp2"
```

Instalar la **clave pública** en el servidor. Para `kakashi`, que no tiene contraseña, el
administrador la copia:

```bash
sudo install -d -o kakashi -g kakashi -m 700 /home/kakashi/.ssh
echo 'ssh-ed25519 AAAA... kakashi@tp2' | sudo tee -a /home/kakashi/.ssh/authorized_keys
sudo chown kakashi:kakashi /home/kakashi/.ssh/authorized_keys
sudo chmod 600 /home/kakashi/.ssh/authorized_keys
```

O se guarda en `claves/kakashi.pub` y lo hace `setup.sh`. Para `vboxuser`, mientras todavía
acepta contraseña, alcanza con esto desde el cliente:

- Linux: `ssh-copy-id -i ~/.ssh/tp2_vboxuser.pub vboxuser@10.0.0.1`
- Windows (PowerShell):
  `type $env:USERPROFILE\.ssh\tp2_vboxuser.pub | ssh vboxuser@10.0.0.1 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"`

**Verificación:** **[cliente]** `ssh -i ~/.ssh/tp2_kakashi kakashi@10.0.0.1` entra sin pedir
contraseña.

### Paso 5 — Endurecer SSH

> Hacerlo **después** del paso 4: si el administrador no tiene su clave instalada, queda afuera
> y solo podría entrar por la consola de VirtualBox.

```bash
sudo install -m 644 sistema/ssh/00-tp2.conf /etc/ssh/sshd_config.d/00-tp2.conf
sudo install -d -m 755 /run/sshd
sudo sshd -t && sudo systemctl restart ssh
```

El archivo se llama `00-…` porque sshd se queda con el primer valor que lee. Así gana sobre
`50-cloud-init.conf`, que en Ubuntu suele traer `PasswordAuthentication yes`.

**Verificación:**
- `sudo sshd -T | grep -Ei 'passwordauth|kbdinteractive|permitroot|allowgroups'` muestra
  `passwordauthentication no`, `kbdinteractiveauthentication no`, `permitrootlogin no` y
  `allowgroups sshusers`.
- **[cliente]** `ssh -o PubkeyAuthentication=no kakashi@10.0.0.1` es rechazado con
  `Permission denied (publickey)`.

### Paso 6 — Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed
sudo ufw allow 51820/udp comment 'WireGuard'
sudo ufw limit 22/tcp comment 'SSH de administracion'      # SSH con límite anti fuerza bruta
sudo ufw allow in on wg0 comment 'Todo lo que entra por la VPN'
sudo ufw --force enable
```

En la interfaz pública solo quedan 51820/udp y 22/tcp. Los puertos 80 y 19999 no se abren en
ufw porque, además, **no escuchan** en la IP pública: Docker los publica solo en `10.0.0.1`
(paso 8). Por eso no hay problema con el conocido salto de ufw que hace Docker.

**Verificación:**
- `sudo ufw status verbose`.
- **[cliente, con la VPN apagada]** `nmap -Pn -p 22,80,19999 192.168.1.50` muestra 22 `open`
  y 80 y 19999 `closed` o `filtered`.
- En Windows sin nmap: `Test-NetConnection 192.168.1.50 -Port 80` da `TcpTestSucceeded : False`.

### Paso 7 — Docker arranca después de la VPN

```bash
sudo install -D -m 644 sistema/systemd/docker-espera-wg0.conf \
    /etc/systemd/system/docker.service.d/10-espera-wg0.conf
sudo systemctl daemon-reload
sudo systemctl enable docker
```

Sin esto, si Docker arranca antes que `wg0`, la IP `10.0.0.1` no existe todavía, los contenedores
no pueden publicar sus puertos y quedan caídos después de un reinicio.

**Verificación:** `systemctl show docker -p After | grep -o wg-quick@wg0.service`.

### Paso 8 — Web (nginx) y monitoreo (Netdata)

```bash
# Página principal: un enlace por cada /home/*/public_html (cron la regenera cada 5 min).
sudo install -m 755 scripts/tp2-generar-index.sh /usr/local/bin/
sudo tp2-generar-index.sh

# Bonus: usuario y contraseña para /~<usuario>/privado/ (101 = grupo nginx del contenedor).
sudo install -d -m 750 -o root -g 101 /etc/tp2/web
printf 'invitado:%s\n' "$(openssl passwd -apr1 'ELEGIR_UNA_CONTRASEÑA')" | sudo tee /etc/tp2/web/htpasswd >/dev/null
sudo chown root:101 /etc/tp2/web/htpasswd && sudo chmod 640 /etc/tp2/web/htpasswd
sudo -u kakashi mkdir -p /home/kakashi/public_html/privado
echo 'secreto' | sudo -u kakashi tee /home/kakashi/public_html/privado/secreto.txt

sudo docker compose -f docker/docker-compose.yml up -d
```

Qué hace cada pieza (ver `docker/`):

- **nginx** publica `10.0.0.1:80`. Monta `/home` en solo lectura y resuelve `/~usuario/ruta` →
  `/home/usuario/public_html/ruta` con una regla genérica, así que un usuario nuevo funciona sin
  tocar la configuración. Corre como uid 101, por lo que solo lee lo que el sistema permite a
  "otros": home `711`, `public_html` `755`, archivos `644`.
- **Netdata** usa la red y el PID del host (`network_mode: host`, `pid: host`) y monta `/proc` y
  `/sys`. Por eso ve la interfaz `wg0`, los discos y la CPU reales del servidor. Escucha solo en
  `10.0.0.1:19999` (`netdata.conf`).

**Verificación:**
- `sudo docker ps` muestra `tp-web` (`10.0.0.1:80->80/tcp`) y `tp-monitoreo` (`healthy`).
- `sudo ss -tlnp | grep -E ':80 |:19999 '` muestra ambos escuchando solo en `10.0.0.1`.
- **[cliente, con la VPN]** En el navegador:
  - `http://10.0.0.1/` muestra la lista de usuarios.
  - `http://10.0.0.1/~kakashi/` muestra su página.
  - `http://10.0.0.1/~kakashi/privado/` pide usuario y contraseña.
  - `http://10.0.0.1:19999/` abre Netdata; en *Network Interfaces → wg0* se ve el tráfico del túnel.

### Paso 9 — Backup periódico

```bash
sudo install -m 755 backup/tp2-backup-home.sh backup/tp2-restaurar.sh /usr/local/bin/
sudo install -m 644 sistema/cron/tp2 /etc/cron.d/tp2
sudo tp2-backup-home.sh          # primer backup a mano
```

- Cron ejecuta el backup todos los días a las 02:00 (`/etc/cron.d/tp2`) y deja el registro en
  `/var/log/tp2-backup.log`.
- Cada ejecución genera un archivo nuevo con fecha y se borran los de más de 7 días.
- La carpeta `/var/backups/home` es `700` y los archivos `600`, porque contienen los homes de
  todos los usuarios.

**Verificación:** `sudo tp2-restaurar.sh -l` lista al menos un backup.

### Paso 10 — Prueba de reinicio

```bash
sudo reboot
# después de iniciar sesión, sin ejecutar nada más:
systemctl is-active wg-quick@wg0 docker cron
sudo docker ps          # los dos contenedores "Up X seconds"
```

---

## 5. Operación

### Recuperar un archivo borrado

```bash
sudo tp2-restaurar.sh -l                                           # backups disponibles
sudo tp2-restaurar.sh kakashi/public_html/naruto-run.jpg           # desde el último
sudo tp2-restaurar.sh kakashi/public_html /var/backups/home/home_2026-10-29_020000.tar.gz  # carpeta entera, de una fecha
```

Se restaura en su lugar original, con sus permisos y dueño. Si el archivo todavía existe, se
reemplaza por la versión del backup.

### Agregar un usuario nuevo

```bash
sudo USUARIOS="kakashi naruto sakura" ./setup.sh
```

O a mano, repitiendo el paso 4. Aparece solo en la página principal en menos de 5 minutos, o al
momento con `sudo tp2-generar-index.sh`.

### Agregar otro cliente a la VPN

```bash
sudo ./scripts/wg-agregar-peer.sh pc-valentino 10.0.0.3 192.168.1.50
```

---

## 6. Cumplimiento de requisitos

| Requisito | Dónde se resuelve | Cómo se verifica |
|---|---|---|
| 1. Arranque automático | `systemctl enable` de wg-quick@wg0, docker, ssh y cron; `restart: always`; override de Docker | Paso 10 |
| 2. Aislamiento y firewall | ufw: deny incoming, solo 51820/udp, 22/tcp limitado y todo por `wg0` | Paso 6: `nmap` desde afuera |
| 3. Contenedores | `docker/docker-compose.yml`, puertos enlazados a `10.0.0.1` | `docker ps`, `ss -tlnp` |
| 4. Autenticación | WireGuard con claves; SSH solo con clave, sin root y solo el grupo `sshusers` | Paso 5 |
| 5. `public_html` | `nginx/default.conf` + `/home:/home:ro` + página generada | `http://10.0.0.1/~kakashi/` |
| 6. Monitoreo | Netdata con red del host, solo en `10.0.0.1:19999` | Gráfico de `wg0` en Netdata |
| 7. Backup | `tp2-backup-home.sh` + `/etc/cron.d/tp2` + `tp2-restaurar.sh` | Borrar un archivo y restaurarlo |
| Bonus: aprovisionamiento | `setup.sh` idempotente | Ejecutarlo dos veces |
| Bonus: control de acceso web | `auth_basic` en `/~<usuario>/privado/` | El navegador pide credenciales |

---

## 7. Migración desde la instalación anterior

Si el servidor ya tenía la primera versión del TP, `setup.sh` se encarga solo de estas tareas.
A mano serían:

```bash
sudo docker compose -f /opt/tp/docker-compose.yml down         # contenedores tp-web-1 / tp-monitoreo-1
sudo crontab -e                                                # borrar: 0 2 * * * tar -czf /var/backup.tar.gz /home
sudo rm -f /var/www/html/~kakashi /var/www/html/~vboxuser     # symlinks viejos, ya no se usan
sudo chown -R kakashi:kakashi /home/kakashi/public_html        # quedó de root por crearlo con sudo
sudo chmod 711 /home/kakashi /home/vboxuser
sudo chmod 600 /var/backups/home_backup.tar.gz                # el backup viejo era legible por todos
```

---

## 8. Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| `403 Forbidden` en `/~usuario/` | El home tiene `750`. Corregir con `chmod 711 /home/usuario`, `755` para `public_html` y `644` para los archivos. |
| Los contenedores no levantan después de reiniciar | Docker arrancó antes que `wg0`. Falta el override del paso 7. |
| El cliente no hace handshake | Revisar: `Endpoint` con la IP correcta de la VM, adaptador puente, `ufw allow 51820/udp` y que las claves públicas estén cruzadas. |
| Netdata no muestra `wg0` | El contenedor no está con `network_mode: host`. |
| SSH sigue aceptando contraseña | Hay otro archivo en `sshd_config.d` que se lee antes. Revisar con `sudo sshd -T \| grep passwordauth`. |
| `/~usuario/privado/` da 500 | Falta `/etc/tp2/web/htpasswd` o no es legible por el grupo 101. |
