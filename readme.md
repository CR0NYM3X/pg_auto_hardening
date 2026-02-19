# 🛡️ PostgreSQL Hardening Automator

Funcion anonima robusta en **PL/pgSQL** diseñado para automatizar la configuración de seguridad (Hardening) en servidores PostgreSQL bajo Linux. El script modifica directamente el archivo `postgresql.conf`, asegurando que el motor cumpla con los estándares de seguridad corporativos.

## 🚀 Características Principales

* **Respaldo Automático:** Crea una copia de seguridad de `postgresql.conf` con fecha actual antes de cualquier cambio.
* **Modificación No Destructiva:** No borra la configuración anterior; comenta la línea original con la etiqueta `# Hardened DATE:` y añade la nueva configuración debajo para mantener la trazabilidad.
* **Gestión Inteligente:** Solo actúa sobre los parámetros que no cumplen con el valor objetivo, evitando escrituras innecesarias.
* **Configuraciones Cubiertas:** Logs de auditoría, cifrado SSL/TLS, restricciones de mensajes y seguridad de contraseñas (SCRAM-SHA-256).

## 🛠️ Requisitos

* **Sistema Operativo:** Linux (utiliza el binario `sed`).
* **Privilegios:** Debe ser ejecutado por un **Superusuario** de base de datos (debido al uso de `COPY ... FROM PROGRAM`).
* **Permisos de Archivo:** El usuario de OS `postgres` debe tener permisos de escritura sobre el archivo `postgresql.conf`.

## 📖 Modo de Uso

1. Copia el contenido del script en tu editor de SQL o herramienta preferida (pgAdmin, DBeaver, psql).
2. Ejecuta el bloque anónimo `DO`.
3. Verifica los mensajes en la consola (`NOTICE`) para confirmar qué parámetros fueron actualizados.
4. El script ejecuta automáticamente un `pg_reload_conf()` al finalizar.


## 📝 Ejemplo de Resultado en Configuración

**Antes:**

```conf
log_connections = off

```

**Después de ejecutar el script:**

```conf
log_connections = 'on' # Hardened 2026-02-18: # log_connections = off
```

 
 
