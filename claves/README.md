# Claves públicas SSH

Poner acá **solo claves públicas** (`.pub`), una por usuario: `claves/<usuario>.pub`.
`setup.sh` las agrega a `/home/<usuario>/.ssh/authorized_keys` sin duplicarlas.

Las claves públicas se pueden subir al repo sin problema. Las privadas (`id_ed25519` sin `.pub`)
quedan **solo** en la computadora del cliente y no se suben nunca.

Generar el par en el cliente (Linux, macOS o Windows 10/11 con OpenSSH):

```bash
ssh-keygen -t ed25519 -C "kakashi@tp2"
```

Después copiar el contenido de `~/.ssh/id_ed25519.pub` a `claves/kakashi.pub`.
Un archivo puede tener varias claves, una por línea.
