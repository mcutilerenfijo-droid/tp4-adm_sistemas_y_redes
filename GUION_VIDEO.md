# Guion del video de demostración (≈ 8 minutos)

El enunciado pide mostrar el acceso **por la VPN, desde otra computadora**, a la web, al panel de
métricas y a SSH. Todo lo que diga **[cliente]** se hace en esa otra PC, no en la consola de la VM.

## Preparación (antes de grabar)

- [ ] `sudo ./setup.sh` sin errores, y el cliente agregado con `wg-agregar-peer.sh`.
- [ ] En el cliente: túnel WireGuard importado (apagado al empezar), claves SSH de `kakashi` y
      `vboxuser`, y `nmap` instalado (o usar `Test-NetConnection` en Windows).
- [ ] Una imagen en `/home/kakashi/public_html/naruto-run.jpg` (dueño `kakashi`, permisos `644`).
- [ ] Un backup hecho **antes** de la demo: `sudo tp2-backup-home.sh`.
- [ ] Opcional: cambiar el cron a `*/5 * * * *` un rato antes, para mostrar en
      `/var/log/tp2-backup.log` backups hechos por cron y no a mano. Después dejarlo en `0 2 * * *`.
- [ ] Letra de la terminal grande (VirtualBox: *Ver → Factor de escala*) y comandos preparados en un
      bloc de notas para pegar sin errores de tipeo.
- [ ] Grabar con las dos pantallas visibles: la VM y la PC cliente.
- [ ] No mostrar claves privadas (`privatekey`, `id_ed25519`, `/root/wg-clientes/*.conf`). Las
      públicas no son un problema.

## Escenas

| # | Tiempo | Dónde | Qué se hace | Qué se tiene que ver |
|---|---|---|---|---|
| 1 | 0:00 – 0:20 | README | Presentar la arquitectura (diagrama de la sección 1). | — |
| 2 | 0:20 – 1:20 | Servidor | `sudo reboot`. Al volver, iniciar sesión y **sin tocar nada**: `systemctl is-active wg-quick@wg0 docker ssh cron` y `sudo docker ps`. | Todo `active`; `tp-web` y `tp-monitoreo` con `Up X seconds` (req. 1). |
| 3 | 1:20 – 2:10 | Cliente, VPN apagada | `nmap -Pn -p 22,80,19999 <IP_VM>` y abrir `http://<IP_VM>/` en el navegador. | 22 `open`, 80 y 19999 cerrados; la web no carga (req. 2). |
| 4 | 2:10 – 2:40 | Servidor | `sudo ufw status verbose` y `sudo ss -tulnp \| grep -E ':80 \|:19999 \|:22 \|:51820'`. | 80 y 19999 escuchan solo en `10.0.0.1` (req. 2 y 3). |
| 5 | 2:40 – 3:10 | Cliente → servidor | Activar el túnel; en el cliente `ping 10.0.0.1`; en el servidor `sudo wg`. | El ping responde; `sudo wg` muestra el `peer` con `latest handshake` (VPN). |
| 6 | 3:10 – 4:00 | Cliente | `ssh -i ~/.ssh/tp2_kakashi kakashi@10.0.0.1` entra. Después `ssh -o PubkeyAuthentication=no kakashi@10.0.0.1` y `ssh root@10.0.0.1`. | Entra con clave sin pedir contraseña; los otros dos dan `Permission denied (publickey)` (req. 4). |
| 7 | 4:00 – 5:10 | Cliente, navegador | `http://10.0.0.1/` → clic en *kakashi* → `http://10.0.0.1/~kakashi/naruto-run.jpg` → `/~naruto/`. En la sesión SSH de kakashi: `echo hola > ~/public_html/nuevo.txt` y recargar `/~kakashi/`. | Página principal con todos los usuarios; la imagen se ve; el archivo nuevo aparece (req. 5). |
| 8 | 5:10 – 5:30 | Cliente, navegador | Bonus: `http://10.0.0.1/~kakashi/privado/`. | Pide usuario y contraseña; con las credenciales correctas se ve `secreto.txt`. |
| 9 | 5:30 – 6:30 | Cliente, navegador | `http://10.0.0.1:19999/`: mostrar CPU, RAM y disco. Ir a *Network Interfaces → wg0*. Generar tráfico: en el servidor `sudo -u kakashi dd if=/dev/urandom of=/home/kakashi/public_html/grande.bin bs=1M count=200` y descargar `http://10.0.0.1/~kakashi/grande.bin` en el cliente. | El gráfico de `wg0` sube mientras dura la descarga (req. 6). Después borrar `grande.bin`. |
| 10 | 6:30 – 7:40 | Cliente (SSH) + servidor | `cat /etc/cron.d/tp2` y `sudo tail /var/log/tp2-backup.log`; `sudo tp2-restaurar.sh -l`. Como kakashi: `rm ~/public_html/naruto-run.jpg` y recargar (404). En el servidor: `sudo tp2-restaurar.sh kakashi/public_html/naruto-run.jpg`. Recargar. | La tarea de cron, la lista de backups, el 404 y la imagen de vuelta con dueño `kakashi` (`ls -l`) (req. 7). |
| 11 | 7:40 – 8:00 | Cliente | Desactivar el túnel y recargar `http://10.0.0.1/`. | Ya no carga: el acceso depende de la VPN. Cierre. |

## Errores del video anterior que no hay que repetir

- Todo se mostró desde la consola del servidor: el enunciado pide la demo **desde otra computadora**.
- `sudo wg` sin ningún `peer`: no había clientes configurados.
- `curl http://10.0.0.1~kakashi/` sin la barra antes de `~`.
- Netdata visto con `curl` (HTML crudo): mostrar el panel en el navegador, con `wg0`.
- No hubo reinicio, ni prueba de SSH, ni restauración del backup.
