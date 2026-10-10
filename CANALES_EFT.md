# Web, Móvil y Cajero sobre S8

Los tres BFF consumen Clientes, Cuentas y Pagos. La lógica de negocio permanece
en los dominios. Web conserva administración y respuestas detalladas; Móvil
ofrece resúmenes; Cajero limita datos y operaciones.

| Canal | HTTPS local | Cliente OAuth2 | Operaciones modernas |
|---|---|---|---|
| Web | https://localhost:8081 | web-demo | Clientes, gestión de cuentas, depósitos, transferencias y pagos |
| Móvil | https://localhost:8082 | mobile-demo | Perfil resumido, consulta/apertura de cuentas, transferencias y pagos |
| Cajero | https://localhost:8083 | atm-demo | Saludo, saldo, depósitos y retiros |

Se mantienen las consultas históricas con IDs numéricos; las nuevas usan UUID.
OAuth2: https://localhost:9000/oauth2/token. Los puertos públicos quedan en
loopback; no se abren puertos nuevos en AWS. Cada BFF valida su audiencia y scopes.
Auth no permite solicitar scopes de otro canal. Payment valida además el tipo de
operación permitido por canal, sin delegar esa regla solamente al BFF.

## Seguridad y límites

web-demo/mobile-demo/atm-demo son operadores técnicos de laboratorio, no login
individual con autorización por titular. Sus secretos son para herramientas
locales de demostración; no se deben distribuir en aplicaciones móviles o navegadores.
Las órdenes de Payment se consultan por sujeto OAuth2: el GET de Web no permite
consultar una orden de ATM. No presentar este aislamiento como login de personas.

Móvil omite documento/dirección; Cajero no recibe el perfil completo de Clientes.
Pagos expone ID, tipo, monto, estado y motivo. Los importes mantienen precisión
decimal. RETIRO simula el débito contable; no integra un dispensador físico.

## Preparación y arranque

Reutilizar MySQL, TLS, firma OAuth2 y Kafka ya configurados. Desde proyecto8,
PowerShell 7:

```powershell
./scripts/Initialize-ChannelSecurity.ps1
foreach ($module in @('auth-server','customer-service','account-service','payment-service','bff-mobile','bff-atm')) {
    Push-Location $module
    ./mvnw.cmd package
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Fallo en $module" }
    Pop-Location
}
docker compose -f compose.yaml -f compose.payments-kafka.yaml up -d --build
docker compose -f compose.yaml -f compose.payments-kafka.yaml restart https-proxy
./scripts/Test-ChannelsFlow.ps1
./scripts/Test-Stack.ps1 -CuentaId 137
```

El script genera únicamente secretos faltantes, sin imprimirlos. .env y secrets
siguen excluidos de Git. Para un entorno nuevo completar además la preparación
de MySQL/TLS/Kafka del README principal.

Flyway V2 permite destino nulo en RETIRO; no cambia V1 ni elimina órdenes previas.
Account conserva el mismo motor transaccional, outbox, idempotencia y auditoría.
Una indisponibilidad de Kafka deja la orden pendiente; 202 no confirma movimiento.

## Consultas manuales

Guardar el token en una variable; no imprimirlo en capturas:

```powershell
$token = ./scripts/Get-ChannelToken.ps1 -Channel mobile -Scope 'mobile.read'
./scripts/Invoke-LocalHttps.ps1 -Uri 'https://localhost:8082/api/mobile/cuentas/137' -Headers @{Authorization="Bearer $token"}
$token = ./scripts/Get-ChannelToken.ps1 -Channel atm -Scope 'atm.read'
./scripts/Invoke-LocalHttps.ps1 -Uri 'https://localhost:8083/api/atm/cuentas/137/saldo' -Headers @{Authorization="Bearer $token"}
```

Los README de [Móvil](bff-mobile/README.md) y [Cajero](bff-atm/README.md) detallan
rutas y scopes. Tokens cruzados: 401; falta de permiso u operación no habilitada: 403.

Ejemplo de POST /api/atm/pagos con atm.payments.write e Idempotency-Key UUID:

```json
{"tipo":"RETIRO","origen":"UUID cuenta moderna","monto":20,"referencia":"Retiro demo"}
```

Consultar el GET del mismo canal hasta APLICADO/RECHAZADO. Si hay incertidumbre,
repetir con la misma clave; no crear otra orden para intentar resolverla.

## Validación reproducible

Test-ChannelsFlow.ps1 conserva datos sintéticos y comprueba:

1. Consultas legacy, rechazo sin token y rechazo de tokens de otro BFF.
2. Perfil resumido Móvil y saludo mínimo Cajero.
3. Apertura de dos cuentas desde Móvil; apertura desde Cajero rechazada.
4. Depósito ATM de 100 y transferencia Móvil de 30.
5. Retiro ATM de 20, repetido con la misma clave sin un segundo débito.
6. Retiro de 1000 rechazado y pago Móvil de 10; saldos finales 40/40.
7. Depósito desde Móvil y transferencia desde Cajero rechazados por Payment.

Requiere Kafka AWS activo. No modifica el histórico ETL ni muestra secretos.
Pendientes, retención y recuperación: [Pagos EFT](PAGOS_EFT.md).
