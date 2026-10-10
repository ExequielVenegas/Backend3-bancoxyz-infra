# Kafka UI local

EFT añade los tópicos bancoxyz.pagos.commands.v1, bancoxyz.pagos.results.v1 y sus
DLT. create-payments.sh otorga lectura al mismo usuario UI y descripción de los
grupos account-payments y payment-service. Ver [Pagos EFT](PAGOS_EFT.md).

Kafbat UI v1.5.0 corre en Docker local y se conecta al Kafka real de AWS mediante
SASL_SSL. Abrir http://localhost:8084 y seleccionar el cluster **aws-lab**.
Solo se publica en 127.0.0.1; no se abre ningún puerto adicional en AWS.

## Ver el flujo

1. Abrir **Topics** y `bancoxyz.cuentas.commands.v1`.
2. En **Messages**, consultar desde el inicio (Earliest) para ver las solicitudes
   publicadas por Web. Repetir el POST con la misma clave genera dos registros
   Kafka; Account debe mantener una sola fila en MySQL.
3. Abrir `bancoxyz.cuentas.commands.v1.dlt` → **Messages** y expandir el mensaje
   con `version: 99`. Revisar el valor JSON y las cabeceras de error/origen.
4. En **Consumer Groups**, abrir `account-service` para ver offsets y lag.
   Lag cero indica que el consumidor alcanzó el final del tópico, no prueba
   por sí solo persistencia: comprobar también el GET o MySQL Workbench.

La retención del broker es de 24 horas o 256 MiB por partición: estas pruebas
pueden desaparecer con el tiempo. Se pueden repetir con Test-KafkaFlow.ps1 y
Test-KafkaDlt.ps1 antes de la presentación. La UI solo visualiza; los POST se
hacen en el BFF para demostrar autenticación y producción.

## Arranque

Desde `s8/proyecto8`:

```powershell
docker compose --profile tools up -d kafka-ui
docker compose logs --tail 50 kafka-ui
# Detener únicamente la interfaz:
docker compose stop kafka-ui
```

El perfil opcional `tools` mantiene los servicios principales independientes
de esta herramienta. Tras reiniciar Docker, el contenedor existente se inicia
por su política unless-stopped, salvo que se haya detenido manualmente.

## Acceso y secretos

- Usuario Kafka exclusivo `ui`; no utiliza las credenciales de administrador,
  Web ni Account. Dos tópicos con Read, Describe y DescribeConfigs.
- Cluster con Describe/DescribeConfigs; grupo `account-service` solo Describe.
  No concede Write, Create, Delete, Alter ni modificación de offsets.
- `readOnly: true` impide operaciones de escritura desde la interfaz.
- Conexión al broker con certificado verificado, incluido el hostname.
- La interfaz HTTP local no requiere login. Cualquier usuario/proceso con acceso
  al PC puede usarla mientras esté encendida. No cambiar el enlace de puerto
  a 0.0.0.0 ni publicarla en AWS sin configurar autenticación y TLS de la web.
- `secrets/kafka/ui-config.yml` contiene la credencial y queda excluido de Git,
  igual que `ui.properties` y los demás secretos. No imprimir estos archivos.

## Reproducir la preparación del usuario

Copiar `deploy/kafka/create-ui-user.sh` a `~/kafka/` en EC2 y ejecutar:

```bash
cd ~/kafka
bash create-ui-user.sh
```

El script preserva usuarios existentes, guarda respaldo privado antes de cambiar
server.properties, crea la credencial ui si falta y reutiliza la existente si
ya está. Recrea el broker con el mismo volumen y añade ACL de lectura. Requiere
sudo para acceder a archivos secretos, Python 3 y Docker Compose. No ejecutar
con bash -x. Copiar después `secrets/ui-config.yml` a `secrets/kafka/` en el PC,
sin publicar su contenido. El certificado público broker.crt debe estar actualizado.

Referencias: [Kafbat UI v1.5.0](https://github.com/kafbat/kafka-ui/releases/tag/v1.5.0)
y [configuración](https://ui.docs.kafbat.io/configuration/configuration-file).
