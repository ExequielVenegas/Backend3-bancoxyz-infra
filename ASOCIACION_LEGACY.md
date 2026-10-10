# Asociación revisada entre legacy, Clientes y Cuentas

Se agrega un flujo administrativo al BFF Web y Account. La revisión elige una
fila del ETL y un cliente existente. Account valida ese cliente mediante su API,
crea una cuenta moderna de ahorro BLOQUEADA y registra la asociación junto con
el saldo inicial y la auditoría en una única transacción.

No se infieren identidades por nombre ni se elige automáticamente la primera o
última fila del archivo. Los CSV contienen cuentas repetidas con titulares,
tipos y saldos contradictorios. El archivo de revisión no aprueba ninguna fila.

## Qué se conserva y qué cambia

| Dato | Regla |
|---|---|
| Identidad legacy | Número de cuenta del conjunto EFT; una asociación por número |
| Titular moderno | UUID de un cliente existente, seleccionado explícitamente |
| Fuente elegida | SHA-256 del archivo, línea y período ETL |
| Saldo inicial | saldo_original de la fila elegida, sin sumar interés ni movimientos |
| Tipo moderno | Solo AHORRO; no convierte préstamos o hipotecas en activos disponibles |
| Estado inicial | BLOQUEADA hasta revisar y habilitar mediante el mantenimiento existente |
| Auditoría | Operador OAuth2, motivo y acción IMPORTACION_LEGACY |
| Repetición idéntica | Devuelve la cuenta existente con su saldo actual; no recarga fondos |
| Otra decisión para el mismo número legacy | 409; no cambia titular, fuente ni saldo |

La asociación pertenece al conjunto EFT, no une automáticamente los números
con las tablas antiguas de S8. La consulta legacy `/api/web/cuentas/{id}` sigue
mostrando el histórico anterior. Para la cuenta moderna se usa el UUID devuelto.
Móvil y Cajero pueden consultarla con sus rutas y permisos normales. Mientras
esté bloqueada, el dominio rechazará operaciones monetarias sobre ella.

Las transacciones diarias sin cuenta identificable permanecen históricas.
Los estados anuales no se aplican como nuevos débitos/créditos. No hay escritura
directa desde Batch a Clientes, Cuentas o Pagos ni joins entre sus esquemas.

## Revisar las correspondencias

Desde s8/proyecto8, con MySQL iniciado:

```powershell
./scripts/New-LegacyAssociationReview.ps1 -Period 2026-10
```

Ya se generó `secrets/legacy-associations/revision-2026-10.json`. El comando
rechaza sobrescribirlo para preservar la revisión. Hay 422 candidatos calculables:
152 filas de ahorro distribuidas entre 47 números de cuenta. Los demás son
préstamos/hipotecas, incluidos como contexto y marcados no importables.

En ese JSON, elegir como máximo una fila importable por `legacyId` y completar:

1. `clienteId`: UUID del titular moderno que se decidió asociar. Si no existe un
   cliente apropiado, crearlo por el flujo Web de Clientes con datos explícitos;
   no inventar documento/correo ni reutilizar un cliente solo por su nombre.
2. `alias`: nombre de la nueva cuenta (máximo 80 caracteres).
3. `motivo`: fundamento de la elección (10 a 500 caracteres). Si la asociación
   es sintética para una demostración, dejarlo expresamente indicado.
4. `revisado`: cambiar a `true` exclusivamente en la decisión elegida.

No modificar número legacy, hash, línea, período, tipo ni saldo. El saldo se
guarda como texto decimal en el archivo de revisión para evitar pérdida de
precisión al editarlo; el lanzador lo convierte a decimal antes de enviarlo.
Los nombres de origen son contexto, no una prueba de identidad.

## Validar antes de aplicar

```powershell
$revision = './secrets/legacy-associations/revision-2026-10.json'
./scripts/Invoke-LegacyAssociations.ps1 -ReviewFile $revision
```

El modo predeterminado solo lee: vuelve a consultar el ETL, exige un job de
intereses COMPLETED, valida fila/hash/período/saldo, rechaza cuentas repetidas
entre decisiones aprobadas y tipos no soportados. Comprueba el formato del UUID;
su existencia real se verifica por Account al aplicar. No crea clientes ni cuentas.

## Aplicar las decisiones elegidas

Requiere los servicios locales activos y compilados:

```powershell
foreach ($module in @('auth-server','customer-service','account-service','bff-web')) {
    Push-Location $module
    ./mvnw.cmd package
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Fallo compilacion: $module" }
    Pop-Location
}
docker compose -f compose.yaml -f compose.payments-kafka.yaml up -d --build auth-server customer-service account-service bff-web https-proxy
docker compose -f compose.yaml -f compose.payments-kafka.yaml restart https-proxy
./scripts/Invoke-LegacyAssociations.ps1 -ReviewFile $revision -Apply
```

Cada decisión es una transacción independiente. Si falla una posterior, las
anteriores permanecen confirmadas; repetir el mismo archivo es seguro. No cambiar
los datos de una decisión ya aplicada. No se genera otra carga de saldo aunque
entre ambos intentos la cuenta haya recibido pagos o depósitos.

## Consultar la asociación

```powershell
$token = ./scripts/Get-WebToken.ps1 -Scope 'web.accounts.import'
$r = ./scripts/Invoke-LocalHttps.ps1 -Uri https://localhost:8081/api/web/cuentas-modernas/importaciones/137 -Headers @{Authorization="Bearer $token"}
$r.Content | ConvertFrom-Json
Remove-Variable token
```

Cambiar 137 por un número asociado. Antes de importar devuelve 404. La respuesta
incluye el UUID moderno, cliente, fuente, saldo original y motivo. El saldo actual
se consulta con `web.accounts.read` en `/api/web/cuentas-modernas/{uuid}`.

El scope `web.accounts.import` es un permiso administrativo explícito. Los
permisos normales de apertura/consulta no lo incluyen y Móvil/Cajero no pueden
obtenerlo. También permite comprobar existencia del cliente, pero no leer ni
modificar su perfil. Auth añade audiencias BFF Web, Account y Customer.

El script verifica la fuente con el ETL. La API confía en la decisión del operador
con permiso de importación: no verifica criptográficamente el documento ni consulta
directamente el esquema Batch. No distribuir ese secreto administrativo en un
frontend público. La autenticación sigue siendo de clientes técnicos de laboratorio.

## Validación y estado

Pruebas Maven aprobadas: Account 40, BFF Web 33, Auth 10 y Customer 12 (95 total).
Las nuevas pruebas cubren asociación, saldo original, auditoría, cliente inexistente,
conflicto de decisión, concurrencia, permisos y repetición tras un cambio de saldo.
La simulación del script se validó contra el ETL y rechazó un saldo adulterado.

Se aplicó la selección sintética autorizada: 47 clientes ficticios y 47 cuentas modernas bloqueadas. El archivo manual original conserva sus decisiones en false; la selección aplicada está en sintetica-2026-10.json.
No se alteraron las cuentas antiguas ni se sumaron intereses automáticamente.

Los JSON de revisión y resultados locales permanecen en secrets/, excluidos de
GitHub. Incluir en Git solamente código, esquema, scripts, pruebas y esta guía.

Validación integrada del 8 de octubre de 2026, con los servicios actualizados en
Docker: Test-Stack confirmó HTTPS/OAuth2/Config/Eureka y consulta legacy 137.
Test-LegacyAssociationSecurity comprobó 401 anónimo, 403 con permiso normal,
400 para decisión incompleta, 422 para cliente inexistente y 404 al consultar
esa asociación rechazada. No se importaron datos durante esta comprobación.

## Preparar y aplicar la selección sintética autorizada

El estudiante autorizó una selección sintética para la demostración. La regla
SINTETICA_DEMO_V1 elige la primera fila de ahorro calculable por número de línea
para cada legacyId de una única versión del archivo. No afirma que esa fila sea
la verdadera ni que su nombre identifique al titular moderno.

New-SyntheticLegacyAssociations.ps1 crea un cliente independiente por legacyId,
con nombre DEMO SINTETICO EFT - Legacy N y sin documento, correo, teléfono ni
dirección. Sus claves de creación son deterministas: reintentar una preparación
parcial no duplica clientes. El campo origen de Customer sigue siendo MODERNO;
la condición sintética se declara en nombre, alias y motivo de la asociación.

```powershell
./scripts/New-SyntheticLegacyAssociations.ps1 -Period 2026-10
$demo = './secrets/legacy-associations/sintetica-2026-10.json'
./scripts/Invoke-LegacyAssociations.ps1 -ReviewFile $demo -Apply
./scripts/Test-SyntheticLegacyAssociations.ps1 -ReviewFile $demo
```

El archivo manual revision-2026-10.json se conserva sin aprobar. La selección
sintética usa un archivo separado. No se convierte ninguna hipoteca o préstamo.
El script de comprobación verifica el estado inicial de todas las cuentas y
repite una importación para confirmar idempotencia; no activa cuentas ni paga.
Si luego se realizan operaciones o se habilitan cuentas, esa comprobación del
estado inicial dejará de ser aplicable: no se deben restaurar saldos para hacerla pasar.

Una decisión aplicada es inmutable. Un CSV posterior con otro saldo o titular
para el mismo número legacy requiere diseñar una nueva conciliación; no se
sobrescribe una cuenta que ya recibió operaciones modernas.


Verificación real: Test-SyntheticLegacyAssociations confirmó las 47 cuentas, su saldo inicial total de 377000 CLP y una repetición sin duplicado. Resultado local: secrets/legacy-associations/resultado-sintetica-2026-10.json.

