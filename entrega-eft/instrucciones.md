# Ejecución y validación Banco XYZ

## Entorno que ya está configurado

Usar PowerShell 7 desde `s8/proyecto8`. Se requieren Docker Desktop con contenedores Linux, MySQL local, Java y los archivos privados locales de `.env` y `secrets/`. Para Kafka deben estar activos Learner Lab y EC2. No volver a inicializar bases ni reemplazar `.env` si el entorno ya funciona.

1. Iniciar MySQL y Docker Desktop. Confirmar acceso a Kafka:

```powershell
Test-NetConnection 100.29.239.217 -Port 9093
```

2. Levantar los contenedores, incluyendo el archivo que activa pagos por Kafka:

```powershell
docker compose -f compose.yaml -f compose.payments-kafka.yaml --profile tools up -d
docker compose -f compose.yaml -f compose.payments-kafka.yaml --profile tools ps
```

Esperar el registro en Eureka y comprobar el flujo histórico. Si una primera consulta devuelve 503 durante el arranque, esperar unos segundos antes de repetirla. En escrituras, conservar siempre la misma sesión y clave.

```powershell
./scripts/Test-Stack.ps1 -CuentaId 137
./scripts/Test-KafkaConnection.ps1
```

3. Consultar los tres procesos batch existentes, sin recargar los CSV:

```powershell
./scripts/Get-EftBatchReport.ps1 -Period 2026-10
```

Resultado esperado en este entorno: tres jobs COMPLETED; 1000 filas por archivo; transacciones 392 válidas y 608 rechazadas; intereses 422 pendientes y 578 rechazadas; estados anuales 473 válidas y 527 rechazadas.

4. Validar perfiles y ciclo de vida con datos de prueba independientes:

```powershell
./scripts/Test-CustomerFlow.ps1
./scripts/Test-AccountLifecycle.ps1
```

Cada ejecución crea datos sintéticos propios. Deben comprobarse alta, consulta, actualización y conflictos; en cuentas, apertura, bloqueo, desbloqueo y cierre con saldo cero. Estas pruebas no cierran las cuentas importadas de la demostración monetaria.

5. Preparar una sesión para probar los tres canales sobre las cuentas sintéticas asociadas a legacy 101 y 102:

```powershell
$sesion = 'demo-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
./scripts/Invoke-EftDemo.ps1 -Paso Preparar -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Seguridad -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Consultas -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Deposito -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Transferencia -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Retiro -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Duplicado -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Pago -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso SinFondos -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Resumen -Sesion $sesion
```

El script guarda antes de cada POST la clave y el cuerpo de la orden en `secrets/demo-eft`. Si se interrumpe un paso, repetir SOLO ese paso con la misma sesión. No borrar su JSON ni cambiar la clave. `-Paso Todo` ejecuta todos los pasos para un ensayo completo. Si existe una orden PENDIENTE, recuperar Kafka y consultar/repetir esa misma orden antes de continuar.

Cada sesión completa añade 40 CLP a cada cuenta respecto de su saldo inicial. El depósito es de 100, la transferencia de 30, el retiro de 20 y el pago de 10. El retiro repetido y el rechazado no descuentan. No ejecutar otra sesión o hacer operaciones manuales sobre estas cuentas durante la demostración.

6. Abrir `http://localhost:8084`, seleccionar el clúster y revisar Topics → Messages. Buscar el pagoId en `bancoxyz.pagos.commands.v1` y su resultado en `bancoxyz.pagos.results.v1`. El script muestra aceptación 202 y consulta hasta observar el desenlace real. Kafka UI muestra mensajes; los saldos se verifican con el BFF contra Account y MySQL.

7. Con los pagos terminados, ejecutar la prueba de resiliencia:

```powershell
./scripts/Test-Resilience.ps1 -CuentaId 137
```

La prueba pausa Account y lo reanuda en un bloque de recuperación. Debe mostrar 503/OPEN y luego 200/CLOSED. Si se cerró la terminal durante la pausa, restaurar manualmente:

```powershell
docker compose -f compose.yaml -f compose.payments-kafka.yaml unpause account-service
```

8. Para validar adicionalmente el productor directo Web y un mensaje inválido:

```powershell
$clave = [guid]::NewGuid()
./scripts/Test-KafkaFlow.ps1 -CuentaId 137 -IdempotencyKey $clave
./scripts/Test-KafkaDlt.ps1
```

La primera prueba agrega una solicitud de estado de cuenta, no altera saldos. Si falla el envío, repetir con `$clave` sin generarla otra vez. La segunda publica un contrato con versión 99 y comprueba avance de la DLT; verificar en Kafka UI el identificador concreto mostrado por la prueba. Un avance de offset por sí solo no identifica el contenido del mensaje.

## Primera preparación en otra máquina

Conservar la misma estructura de carpetas si los módulos se clonan desde repositorios separados. Instalar PowerShell 7, Docker Desktop, MySQL 8 y un JDK compatible con el proyecto (compilación Java 21; el entorno validado usa JDK 25.0.4). Copiar `.env.example` a `.env` SOLO si este no existe. Configurar en privado el usuario y contraseña reales de MySQL en ACCOUNT_DB_USERNAME y ACCOUNT_DB_PASSWORD. El esquema histórico `lab_batch` debe provenir del respaldo autorizado del laboratorio; no se distribuye la base ni sus credenciales por GitHub.

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
./scripts/Initialize-LocalSecurity.ps1
./scripts/Initialize-ChannelSecurity.ps1
./scripts/Initialize-LocalTls.ps1
./scripts/Initialize-CustomerDatabase.ps1
./scripts/Initialize-PaymentDatabase.ps1
./scripts/Initialize-EftBatchDatabase.ps1
```

Configurar JAVA_HOME/PATH para que `java` y `keytool` correspondan al JDK instalado. Los inicializadores de esquemas requieren una cuenta MySQL con permiso para crear sus esquemas y usuarios. Los secretos se generan localmente y no se muestran en pantalla.

Compilar los módulos antes de construir sus imágenes:

```powershell
$modulos = 'legacy-batch-migrator','auth-server','platform-service','customer-service','account-service','payment-service','bff-web','bff-mobile','bff-atm'
foreach ($modulo in $modulos) {
    Push-Location $modulo
    try { ./mvnw.cmd package; if ($LASTEXITCODE -ne 0) { throw "Fallo $modulo" } }
    finally { Pop-Location }
}
```

Preparar Kafka siguiendo `despliegue.md` y copiar solo las credenciales cliente y el certificado público a `secrets/kafka`. Luego ejecutar Compose con `up -d --build` y ambos archivos.

En una base EFT nueva, cargar una vez los CSV con las mismas columnas:

```powershell
./scripts/Invoke-EftBatch.ps1 -Kind transactions -Period 2026-10
./scripts/Invoke-EftBatch.ps1 -Kind interest -Period 2026-10
./scripts/Invoke-EftBatch.ps1 -Kind annual -Period 2026-10
./scripts/Get-EftBatchReport.ps1 -Period 2026-10
```

Se puede proporcionar `-InputFile` para un CSV alternativo. No limpiar tablas del entorno en uso para una toma. La cuenta 137 de las pruebas históricas requiere la carga histórica S8 correspondiente.

En una instalación nueva, preparar las cuentas sintéticas después de cargar el batch y levantar los servicios:

```powershell
./scripts/New-SyntheticLegacyAssociations.ps1 -Period 2026-10
$demo = './secrets/legacy-associations/sintetica-2026-10.json'
./scripts/Invoke-LegacyAssociations.ps1 -ReviewFile $demo
./scripts/Invoke-LegacyAssociations.ps1 -ReviewFile $demo -Apply
./scripts/Test-SyntheticLegacyAssociations.ps1 -ReviewFile $demo
```

La primera llamada a Invoke-LegacyAssociations solo valida; `-Apply` crea las asociaciones y cuentas bloqueadas. Se utiliza el saldo original de la primera fila de ahorro calculable por ID, sin sumar intereses ni movimientos históricos. Los titulares se identifican como sintéticos y no representan una conciliación de identidades reales. La comprobación final genera el archivo de cuentas que utiliza Invoke-EftDemo. Ejecutarla antes de la primera demostración: después de realizar pagos, comprobar el estado con `Invoke-EftDemo.ps1 -Paso Resumen`, sin restaurar los saldos iniciales.

## Accesos

| Componente | Acceso o validación |
|---|---|
| Web, Móvil y Cajero | HTTPS localhost 8081, 8082 y 8083; Invoke-EftDemo valida los tres. |
| Auth | HTTPS localhost:9000; los scripts obtienen JWT sin imprimirlos. |
| Clientes y Cuentas | Test-CustomerFlow y Test-AccountLifecycle a través del BFF. |
| Pagos | Invoke-EftDemo más Kafka UI y saldos de Account. |
| Platform | Test-Stack y salud del contenedor; 8761 no se publica. |
| Batch | Get-EftBatchReport; ejecución puntual con Invoke-EftBatch. |
| Kafka | Test-KafkaConnection, Test-KafkaFlow y Test-KafkaDlt. |

No abrir `.env` ni utilizar `docker compose config` sin filtros en el video, porque puede expandir credenciales. Los scripts HTTPS confían en el certificado local generado; no desactivan la verificación del nombre del servidor.
