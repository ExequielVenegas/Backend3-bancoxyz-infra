# POST Web → Kafka AWS → Account → MySQL

El caso implementado es **registrar una solicitud de estado de cuenta** para una
cuenta cargada por el batch. No genera un PDF ni modifica saldos. Este flujo S8
se conserva durante la evolución EFT, que incorpora Clientes, gestión de Cuentas
y posteriormente Pagos según la aclaración docente más reciente.

## Recorrido

1. Auth emite un JWT para `web-demo` con `web.write` (POST) y `web.read` (consulta).
2. Web valida JWT, cuerpo y existencia de la cuenta mediante Account/Eureka.
3. Web publica JSON v1 en `bancoxyz.cuentas.commands.v1` usando SASL_SSL,
   credenciales `web`, clave de partición igual a `solicitudId`, `acks=all` e
   idempotencia del productor. Espera la confirmación del broker antes de dar 202.
4. Account consume con el grupo `account-service`, valida contrato y cuenta,
   e inserta en `solicitudes_estado_cuenta` dentro de una transacción JDBC.
5. El listener termina después del COMMIT; `AckMode.RECORD` confirma el offset.
   Una caída entre COMMIT y confirmación puede entregar de nuevo el mensaje:
   la clave primaria de MySQL impide una segunda fila.
6. GET consulta Account/MySQL y devuelve `REGISTRADA`. `ACEPTADA` no significa
   que la base de datos ya haya confirmado la operación.

## Contratos

| Operación | Ruta | Scope | Resultado |
|---|---|---|---|
| POST | `/api/web/cuentas/{cuentaId}/solicitudes-estado` | web.write | 202 + Location/URL de consulta |
| GET | `/api/web/solicitudes-estado/{solicitudId}` | web.read | 200 REGISTRADA; 404 si aún no existe o pertenece a otro cliente |

POST requiere `Idempotency-Key: <UUID>` y JSON `{"anio":2026}` (2000–2100).
El identificador se deriva de cliente autenticado + clave, no del contenido.
El evento contiene `solicitudId`, `version:1`, `tipo:SOLICITAR_ESTADO_CUENTA`,
`cliente`, `cuentaId` y `anio`. Ambas aplicaciones conservan el mismo contrato
en `messaging/EstadoCuentaCommand.java`; no se usan cabeceras de tipos Java.

## Duplicados y fallos

- La misma clave y cuerpo producen el mismo evento. El consumidor registra
  `DUPLICADA_IGNORADA` y conserva la fila y la fecha originales, también ante
  entregas concurrentes. La garantía es un único efecto en esta tabla, no una
  transacción distribuida exactamente una vez entre Kafka y MySQL.
- Nunca reutilizar la clave para cambiar cuenta o año. El consumidor detecta
  ese conflicto y lo envía a DLT sin sobrescribir la solicitud original. El
  POST puede haber respondido 202: el rechazo es asíncrono; no hay endpoint de
  estado de DLT ni respuesta HTTP 409 para este caso.
- Sin token: 401; sin scope: 403; parámetros/JSON inválidos: 400; cuenta
  inexistente: 404; Account o Kafka no disponibles: 503.
- Ante timeout/503 o respuesta perdida, reintentar con **la misma clave y
  contenido**: la publicación puede haber llegado al broker aunque no se
  haya recibido la confirmación. No generar otra clave para ese reintento.
- Errores transitorios del consumidor: dos reintentos, separados por un segundo.
  JSON inválido, versión desconocida, cuenta inexistente o conflicto de clave:
  DLT inmediata. DLT: `bancoxyz.cuentas.commands.v1.dlt`, misma partición.
- Si falla la publicación en DLT, el error se propaga: no se considera
  recuperado el registro y se vuelve a intentar. Una DLT requiere revisión y
  eventual reproceso manual; no existe recuperación automática desde DLT.
- El broker del laboratorio tiene una réplica y retención limitada. `acks=all`
  no convierte esa instalación en alta disponibilidad.

## Preparación

Mantener MySQL iniciado con las tablas ETL existentes. No volver a ejecutar batch.
Account ejecuta únicamente `CREATE TABLE IF NOT EXISTS solicitudes_estado_cuenta`
al activar Kafka; requiere permiso CREATE. No elimina ni modifica tablas ETL.
El archivo es `account-service/src/main/resources/solicitudes-schema.sql`.

Compose activa `LAB_KAFKA_ENABLED=true` y monta solo las credenciales de cada
aplicación en `/secrets/client.properties`, además del certificado público
`/secrets/broker.crt`. No se incrustan credenciales en las imágenes ni el código.
Se conservan SASL_SSL y la verificación del hostname del certificado.

```powershell
# Desde s8/proyecto8, JDK 21+ y Docker Desktop en ejecución:
foreach ($service in @('auth-server','account-service','bff-web')) {
    Push-Location $service
    .\mvnw.cmd package
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Fallo $service" }
    Pop-Location
}
docker compose up -d --build
# Reiniciar el proxy si ya estaba levantado para resolver las IP nuevas de los servicios.
docker compose restart https-proxy
.\scripts\Test-Stack.ps1 -CuentaId 137
.\scripts\Test-KafkaConnection.ps1
.\scripts\Test-KafkaFlow.ps1 -CuentaId 137 -Anio 2026
```

`Test-KafkaFlow.ps1` agrega una solicitud de demostración y la reenvía; espera
persistencia, verifica el mismo ID/fecha y observa `DUPLICADA_IGNORADA` en Account.
Imprime la clave para poder repetirla con `-IdempotencyKey <UUID>` si fuera necesario.
La fila de demostración permanece en MySQL. Los tests de concurrencia y rollback
de Maven usan H2 aislado, no borran registros de MySQL.

Para ejecutar fuera de Compose, Kafka está desactivado por defecto. Activarlo
con `LAB_KAFKA_ENABLED=true`, `LAB_KAFKA_BOOTSTRAP_SERVERS` y
`LAB_KAFKA_CLIENT_PROPERTIES` apuntando al archivo correspondiente. En ejecución
Java directa, corregir también `ssl.truststore.location` a la ruta real del
certificado en esa máquina; la ruta `/secrets/...` corresponde a contenedores.

## Demostración manual para la presentación

En PowerShell 7, desde `s8/proyecto8`:

```powershell
$token = .\scripts\Get-WebToken.ps1 -Scope 'web.read web.write'
$clave = [guid]::NewGuid().ToString()
$headers = @{Authorization="Bearer $token"; 'Idempotency-Key'=$clave}
$post = .\scripts\Invoke-LocalHttps.ps1 -Uri https://localhost:8081/api/web/cuentas/137/solicitudes-estado -Method POST -Headers $headers -JsonBody '{"anio":2026}'
$post
$solicitud = $post.Content | ConvertFrom-Json
.\scripts\Invoke-LocalHttps.ps1 -Uri "https://localhost:8081$($solicitud.consulta)" -Headers $headers
# Reenviar exactamente el mismo POST, con los mismos headers y cuerpo.
.\scripts\Invoke-LocalHttps.ps1 -Uri https://localhost:8081/api/web/cuentas/137/solicitudes-estado -Method POST -Headers $headers -JsonBody '{"anio":2026}'
docker compose logs --since 5m account-service | Select-String 'REGISTRADA|DUPLICADA_IGNORADA'
```

En MySQL Workbench, usando el ID devuelto:

```sql
SELECT solicitud_id, cuenta_id, anio, estado, recibida_en
FROM solicitudes_estado_cuenta WHERE solicitud_id = '<solicitudId>';
SELECT COUNT(*) AS filas
FROM solicitudes_estado_cuenta WHERE solicitud_id = '<solicitudId>';
-- Debe ser 1 tras reenviar la misma solicitud.
```

Postman: token de Auth con scope `web.read web.write`, Bearer en el BFF,
header `Idempotency-Key` y cuerpo raw JSON. Confiar en el certificado local
según [HTTPS.md](HTTPS.md); no desactivar verificación TLS. No mostrar ni guardar
el token/secreto en capturas o repositorios públicos.

## Diagnóstico de AWS

Estado de esta implementación: 43 pruebas Maven aprobadas (26 BFF, 12 Account,
5 Auth), incluidos duplicados concurrentes y rollback en H2. Contenedores
reconstruidos; consultas MySQL y OAuth2 verificados. El 6 de octubre de 2026
se verificó el flujo real contra Kafka AWS en 100.29.239.217:9093: POST 202,
consumo por Account, GET REGISTRADA desde MySQL y reenvío con
DUPLICADA_IGNORADA conservando ID y fecha. Solicitud de demostración:
`b5d5f776-695f-3c3b-826c-c041d809e289`; clave de idempotencia:
`4d6dec8e-cb5f-4966-937b-233143f2e20c`. La fila permanece en MySQL.
Prueba DLT posterior: se publicó el comando de versión inválida 99 con ID
`00be9a1f-0b75-4f81-93dd-829ee27ae0f5`. El siguiente offset de DLT avanzó de
0 a 1. El usuario confirmó la lectura administrativa en EC2 del offset 0:
coinciden el ID, version=99, el tópico original y el grupo account-service.
La cabecera informa IllegalArgumentException: Contrato de comando invalido.
Queda verificada la entrega real del mensaje rechazado en DLT. El cliente
Account no tiene permiso de lectura DLT.
Para repetir la prueba usar `scripts/Test-KafkaDlt.ps1`; imprime el ID y el
comando de lectura del offset correspondiente. Envía directamente al broker
para probar la validación del consumidor, no la validación HTTP del BFF.

Si `100.29.239.217:9093` no responde, comprobar Learner Lab activo, EC2 y contenedor
Kafka iniciados, IP pública vigente y entrada 9093 limitada a la IP pública del PC.
Cambiar `KAFKA_BOOTSTRAP_SERVERS` en `.env` si cambia EC2; actualizar también
`advertised.listeners` y el certificado SAN del broker según el despliegue.
No basta con cambiar únicamente la dirección del cliente.

Referencias de implementación:
[starter Kafka de Spring Boot](https://docs.spring.io/spring-kafka/reference/quick-tour.html)
y [reintentos y DLT](https://docs.spring.io/spring-kafka/reference/4.0/kafka/annotation-error-handling.html).
