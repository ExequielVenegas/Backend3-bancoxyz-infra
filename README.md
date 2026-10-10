# Banco XYZ Infraestructura

Configuración para ejecutar Banco XYZ con Docker Compose y conectar los servicios locales con Kafka en AWS.

| Contenido | Uso |
|---|---|
| `compose*.yaml` | Servicios, redes y conexión con Kafka. |
| `scripts/` | Preparación y pruebas del proyecto. |
| `proxy/` | Acceso HTTPS a los BFF y Auth Server. |
| `deploy/kafka/` | Kafka KRaft en EC2. |
| `entrega-eft/` | Informe, instrucciones y guion del video. |
| `repositories.json` | Repositorios de los microservicios. |

El batch carga los CSV en MySQL. Los BFF Web, Móvil y Cajero acceden a Clientes, Cuentas y Pagos; Kafka comunica las operaciones y sus resultados. AWS aloja únicamente Kafka.

Ver [cómo ejecutar el proyecto](EJECUCION.md).
