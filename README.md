# Banco XYZ Infraestructura

Repositorio de infraestructura y documentación de Banco XYZ. Reúne la configuración para ejecutar los microservicios y los tres BFF con Docker Compose, conectar MySQL local y utilizar Kafka desplegado en AWS. El código de los servicios y las propiedades de Spring Cloud se mantienen en repositorios independientes.

## Contenido

| Componente | Función en el proyecto |
|---|---|
| `compose.yaml` | Define los servicios locales, redes, proxy y Kafka UI. |
| `compose.payments-kafka.yaml` | Activa el procesamiento asíncrono de pagos mediante Kafka. |
| `scripts/` | Inicialización local, batch y validaciones de seguridad, negocio y mensajería. |
| `proxy/` | Nginx para HTTPS de Web, Móvil, Cajero y Auth Server. |
| `deploy/kafka/` | Despliegue KRaft en EC2, tópicos y permisos de los clientes. |
| `repositories.json` | Relación entre carpetas de servicios y repositorios de código. |
| [Ejecución](EJECUCION.md) | Organización de los repositorios para utilizar Compose. |
| [Entrega EFT](entrega-eft/instrucciones.md) | Informe, guion de presentación, ejecución y validaciones. |

## Flujo completo

Spring Batch procesa los CSV en el PC y guarda los resultados y su trazabilidad en MySQL. Las asociaciones revisadas vinculan datos históricos con cuentas modernas; los registros ambiguos no actualizan automáticamente los saldos operativos.

El cliente obtiene un JWT en Auth Server y accede por HTTPS al BFF Web, Móvil o Cajero. Cada BFF valida sus permisos y adapta la información a su canal. Eureka permite descubrir los servicios y Config Server carga las propiedades del repositorio independiente `config-repo`.

Customer administra los perfiles. Account administra apertura, mantenimiento y cierre de cuentas, además de sus saldos y movimientos. Payment recibe las órdenes monetarias enviadas por los BFF y publica sus comandos mediante outbox hacia Kafka en AWS. Account consume el comando, aplica los movimientos en una transacción de MySQL y publica el resultado. Payment consume ese resultado y expone el estado APLICADO o RECHAZADO. Las claves de idempotencia evitan repetir el efecto de una misma orden.

El flujo de solicitudes de estado de cuenta se publica directamente desde BFF Web hacia Kafka y lo consume Account. Resilience4j limita los fallos en las llamadas HTTP y Kafka UI permite consultar los mensajes. Los servicios funcionan localmente con Docker; el batch y MySQL permanecen en el PC. AWS aloja únicamente Kafka.
