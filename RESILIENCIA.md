# Resilience4j en BFF Web

La protección se aplica a las consultas GET de cuentas y transacciones que
Web envía a Account. Usa los módulos circuitbreaker, retry y bulkhead de
Resilience4j 2.4.0 mediante composición Java; no requiere un starter de Boot 3
ni proxies de anotaciones en el proyecto Boot 4.

| Protección | Configuración |
|---|---|
| Timeout de conexión | 1 segundo |
| Timeout de lectura HTTP | 2 segundos por intento |
| Retry | Máximo 2 intentos totales, pausa de 200 ms |
| Fallos reintentables | Conexión/timeout, HTTP 5xx, ausencia de instancia en Eureka |
| Circuit breaker | Ventana de 8 solicitudes, mínimo 4, apertura con 50% de fallos |
| Circuito abierto | 10 segundos antes de permitir pruebas |
| Recuperación | 2 llamadas en HALF_OPEN; evaluación según el umbral de fallos |
| Bulkhead | 10 solicitudes concurrentes; exceso rechazado sin espera |
| Respuesta de indisponibilidad | HTTP 503 con ApiError, sin saldos ficticios |

Un 404 conserva su respuesta, no se reintenta ni cuenta como fallo del circuito.
Los demás HTTP 4xx del backend tampoco se reintentan ni cuentan para abrirlo;
se traducen a indisponibilidad del backend sin exponer sus detalles al cliente.
Los errores de autenticación del BFF siguen respondiendo 401/403 antes de llamar
a Account. Las reglas no se extienden automáticamente a futuros POST.

El orden es bulkhead → circuit breaker → retry → HTTP. El cupo se mantiene
durante los reintentos. El circuito cuenta una solicitud lógica, no cada intento.
Un rechazo del bulkhead no se contabiliza como fallo de Account.
Los reintentos de Spring Cloud LoadBalancer se desactivan en el perfil cloud
para evitar multiplicar los intentos.

Los timeouts y límites de concurrencia reducen el tiempo y recursos consumidos;
no se usa TimeLimiter para envolver hilos que continúen ejecutándose en segundo
plano. Esta implementación usa los timeouts del cliente HTTP síncrono.

## Configuración y evidencia

Los valores de timeout, intentos, pausas y concurrencia están en
config-repo/bff-web-cloud.properties. El código mantiene valores por defecto
para el modo individual. Reiniciar Web después de cambiar configuración central.
Los umbrales y tamaño de ventana se definen en AccountResilience.

El endpoint HTTPS /actuator/info muestra resilience.accountService:
state, failedCalls, bufferedCalls y availableConcurrentCalls. Requiere web.info.
No se publica el detalle de fallos en el endpoint público de salud.
Los cambios de estado y reintentos se registran sin tokens ni datos bancarios.

```powershell
$token = .\scripts\Get-WebToken.ps1 -Scope 'web.info'
$info = .\scripts\Invoke-LocalHttps.ps1 -Uri https://localhost:8081/actuator/info -Headers @{Authorization="Bearer $token"}
($info.Content | ConvertFrom-Json).resilience
Remove-Variable token
```

## Demostración de caída y recuperación

```powershell
.\scripts\Test-Stack.ps1 -CuentaId 137
.\scripts\Test-Resilience.ps1 -CuentaId 137
docker compose logs --tail 80 bff-web
```

Usar una cuenta existente. Test-Resilience pausa temporalmente Account,
comprueba respuestas 503 y apertura del circuito, verifica rechazo rápido y
restaura el contenedor mediante finally. Luego comprueba recuperación a 200
y CLOSED. Pausar conserva el registro en Eureka y permite demostrar timeouts.
No modifica MySQL. Si se termina el proceso de PowerShell forzosamente,
restaurar con docker compose unpause account-service.

El estado y las métricas del circuito están en memoria de cada BFF; se reinician
al recrear ese contenedor. No representan métricas acumuladas persistentes.

## Pruebas

Pruebas automatizadas: recuperación tras un fallo transitorio, 404 sin reintento,
apertura/rechazo/recuperación del circuito, rechazo por concurrencia y liberación
del cupo, ausencia de instancia y timeout HTTP real. Además se comprueba el
contrato 503 y que OAuth2 siga protegiendo los endpoints.

Verificación del 5 de octubre de 2026: las 19 pruebas del BFF pasaron.
Test-Stack confirmó la integración por HTTPS/OAuth2 y Test-Resilience comprobó
en Docker 503 y OPEN con Account pausado, rechazo rápido y recuperación a
200/CLOSED. Account quedó reactivado; no se modificaron datos.

Referencia: [ejemplos de composición de Resilience4j](https://resilience4j.readme.io/docs/examples).
