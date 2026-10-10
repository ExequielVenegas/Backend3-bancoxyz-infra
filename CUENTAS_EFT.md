# Gestión de Cuentas — segundo bloque EFT

Se amplía account-service dentro de s8/proyecto8. No se crea otro servicio de
cuentas. Los datos migrados siguen disponibles en /api/web/cuentas/{id}, con
identificadores numéricos. Las cuentas modernas usan UUID y rutas independientes
para no confundir los saldos históricos con operaciones bancarias nuevas.

## Responsabilidades

Web autentica, comprueba permisos y adapta las rutas. Account valida las reglas,
consulta a Clientes mediante Eureka y es el único servicio que escribe cuentas.
Clientes confirma la existencia del titular sin entregar su perfil al permiso de
Cuentas. No hay claves foráneas entre servicios; Clientes no permite eliminación
de perfiles en este bloque, por lo que la referencia validada permanece vigente.

MySQL local conserva lab_batch. Account añade modern_accounts y
modern_account_audit con CREATE TABLE IF NOT EXISTS al arrancar; no altera ni
limpia las tablas legacy. El script es aditivo para esta primera versión; cambios
posteriores de columnas requieren una migración explícita. Cada operación y su
auditoría se confirman en la misma transacción.

## Reglas implementadas

- Apertura con cliente UUID existente, tipo AHORRO o CORRIENTE y alias obligatorio.
- Moneda CLP y saldo inicial cero. El cliente HTTP no puede asignar el saldo.
- Idempotency-Key UUID obligatoria al abrir. Misma identidad, clave y contenido
  devuelve la misma cuenta; distinto contenido con esa clave devuelve 409.
- Mantenimiento de alias y estado ACTIVA/BLOQUEADA. No cambia titular, tipo o saldo.
- Cada cambio requiere la versión actual. Dos cambios simultáneos con la misma
  versión tienen un único ganador; el otro recibe 409.
- Cierre únicamente con saldo cero. Una cuenta cerrada permanece consultable y
  no se reabre ni se modifica. No se borran cuentas.
- Cliente inexistente: 422. Cliente no verificable por indisponibilidad: 503 y
  no se crea la cuenta. Cuenta inexistente: 404. Solicitud inválida: 400.

Estas son reglas elegidas para la demostración académica. Los préstamos e hipotecas
históricos conservan sus consultas; este bloque no implementa apertura de créditos.
Tampoco migra automáticamente cuentas históricas al modelo moderno.

## Contrato público

Base: https://localhost:8081. OAuth2 client_credentials con el operador técnico
web-demo; no representa todavía login individual de titulares.

| Método y ruta | Scope | Cuerpo / uso |
|---|---|---|
| POST /api/web/cuentas-modernas | web.accounts.write | clienteId, tipo, alias; cabecera Idempotency-Key |
| GET /api/web/cuentas-modernas?page=0&size=20 | web.accounts.read | Listado paginado, máximo 100 |
| GET /api/web/cuentas-modernas/{uuid} | web.accounts.read | Consulta de una cuenta |
| PUT /api/web/cuentas-modernas/{uuid} | web.accounts.write | version, alias y estado ACTIVA/BLOQUEADA |
| POST /api/web/cuentas-modernas/{uuid}/cierre | web.accounts.write | version |

Ejemplo de apertura:

```json
{"clienteId":"UUID de un cliente existente","tipo":"AHORRO","alias":"Ahorro personal"}
```

Ejemplo de bloqueo:

```json
{"version":0,"alias":"Reserva","estado":"BLOQUEADA"}
```

Auth emite audiencia account-service para scopes de Cuentas y customer-service
si el token permite apertura. Account valida issuer, firma, audiencia y scope.
El permiso web.accounts.write solo permite consultar la existencia del cliente;
no permite listar ni leer sus datos personales. El BFF tiene un circuito y límite
de concurrencia para estas operaciones; solo reintenta lecturas automáticamente.
Las consultas internas legacy mantienen su protección por aislamiento de red y
autorización en BFF; no se deben publicar directamente los puertos de Account.

## Arranque y demostración

Requiere el entorno S8 ya preparado, MySQL local y Docker Desktop iniciados.
Desde proyecto8 en PowerShell 7, compilar los módulos modificados:

```powershell
foreach ($module in @('account-service','customer-service','auth-server','bff-web')) {
    Push-Location $module
    ./mvnw.cmd package
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Fallo en $module" }
    Pop-Location
}
docker compose up -d --build account-service customer-service auth-server bff-web https-proxy
docker compose restart https-proxy
./scripts/Test-AccountLifecycle.ps1
./scripts/Test-Stack.ps1 -CuentaId 137
```

La prueba espera el descubrimiento de Account, crea un titular sintético y una
cuenta con saldo cero, verifica idempotencia, la bloquea, desbloquea y cierra.
Comprueba además permisos, versiones obsoletas, rechazo de reapertura y titular
inexistente. Conserva los UUID al terminar, sin imprimir tokens. Cada ejecución
crea nuevos datos de demostración; no ejecutar como una tarea periódica.
El cierre con saldo pendiente y las carreras concurrentes se prueban en H2 aislado.
No se modifica artificialmente un saldo en el MySQL real para demostrar el cierre.

Pagos y depósitos reales, el enlace explícito de datos legacy, y los canales
Móvil/Cajero siguen siendo los próximos bloques. No es necesario iniciar Kafka
AWS para probar esta gestión síncrona de Cuentas.

## Importación revisada EFT

POST /api/web/cuentas-modernas/importaciones y GET de /importaciones/{legacyId}
requieren web.accounts.import. La importación crea una cuenta nueva BLOQUEADA con
saldo original explícitamente revisado; no modifica las cuentas abiertas normalmente
ni convierte préstamos/hipotecas. Ver [ASOCIACION_LEGACY.md](ASOCIACION_LEGACY.md).
