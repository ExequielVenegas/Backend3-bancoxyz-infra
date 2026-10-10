# Proxy HTTPS

Nginx termina TLS y dirige las rutas públicas hacia los tres BFF y Auth Server. Los servicios de dominio no publican puertos en el host.

## Participación en el proyecto

| Aspecto | Función |
|---|---|
| Entrada | HTTPS en la interfaz local |
| Salida | HTTP dentro de las redes Docker hacia BFF y Auth |
| Ejecución | Loopback: 8081, 8082, 8083 y 9000 |

## Flujo completo

Los CSV se procesan localmente con Spring Batch y sus resultados se guardan en MySQL. Los datos históricos permanecen disponibles; las asociaciones revisadas permiten crear cuentas modernas con trazabilidad al archivo de origen.

El cliente obtiene un JWT en Auth Server y accede por HTTPS a su BFF (Web, Móvil o Cajero). El BFF valida el token y sus permisos, adapta la respuesta y descubre los servicios mediante Eureka. Customer administra perfiles; Account administra cuentas, saldos y movimientos; Payment administra órdenes de pago.

Para una operación monetaria, el BFF envía la orden a Payment, que guarda la orden y su outbox. Kafka en AWS transporta el comando hasta Account. Account aplica los movimientos en una transacción de MySQL y publica el resultado mediante su outbox. Payment consume el resultado y la consulta del BFF informa APLICADO o RECHAZADO. La clave de idempotencia evita repetir el efecto de una misma operación. El flujo de solicitudes de estado de cuenta se publica directamente desde BFF Web hacia Kafka y lo consume Account.

Config Server centraliza propiedades y Resilience4j limita los fallos en llamadas HTTP. Docker Compose ejecuta los servicios locales; MySQL y el batch permanecen en el PC. AWS aloja únicamente Kafka, en modo KRaft.
