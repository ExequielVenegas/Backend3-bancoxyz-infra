# Guion de presentación Banco XYZ

Duración objetivo: **7 minutos**. La instrucción EFT indica 5–7 minutos y el encargo pide 7–9; se utiliza el punto común de 7 minutos. Grabar pantalla y webcam y exportar a MP4. Ensayar el ritmo antes de grabar; recortar únicamente esperas, sin alterar respuestas ni presentar resultados previos como operaciones nuevas.

## Preparación antes de grabar

Abrir PowerShell 7 en `s8/proyecto8`, el informe, Docker Desktop y Kafka UI en `http://localhost:8084`. Iniciar MySQL, Docker Desktop, Learner Lab y EC2. Ejecutar los comandos de `instrucciones.md` para comprobar el entorno. No mostrar `.env`, archivos de credenciales ni tokens.

Usar una sesión NUEVA para cada toma completa. Mantener el mismo nombre si se interrumpe y se retoma una toma. No borrar los JSON de `secrets/demo-eft`: conservan las claves que impiden duplicados. No ejecutar dos sesiones al mismo tiempo ni cambiar los saldos desde SQL.

```powershell
$sesion = 'video-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
./scripts/Invoke-EftDemo.ps1 -Paso Preparar -Sesion $sesion
```

Este paso muestra el saldo inicial real y activa solamente las cuentas sintéticas asociadas a legacy 101 y 102. Después del ensayo del 8 de octubre quedaron en 5040 y 5040 CLP; una nueva toma puede comenzar con otros saldos. El resumen siempre calcula el resultado relativo al inicio de SU sesión.

Antes de grabar, ejecutar `Test-CustomerFlow.ps1` y `Test-AccountLifecycle.ps1`, conservar sus salidas visibles en otra pestaña y titularla «Validación previa de clientes y cuentas». Estas pruebas crean datos de demostración independientes. No presentarlas como una ejecución en vivo si solo se muestra la salida anterior.

## 0:00 a 0:40 Presentación y objetivo

**Mostrar:** portada del informe y luego la tabla de componentes del README raíz. Webcam visible.

**Decir:**

«Soy Exequiel y presentaré la modernización del Banco XYZ. El proyecto aborda cinco procesos: migración batch, separación del sistema en microservicios, adaptación por canal mediante BFF, seguridad distribuida y mensajería asíncrona con Kafka. Desarrollé gestión de clientes, cuentas y pagos, con canales Web, Móvil y Cajero. En este laboratorio los servicios y MySQL se ejecutan localmente, mientras Kafka está desplegado en AWS, según la indicación del profesor.»

## 0:40 a 1:15 Arquitectura y decisiones

**Mostrar:** diagrama del informe, luego contenedores con:

```powershell
docker compose -f compose.yaml -f compose.payments-kafka.yaml --profile tools ps
```

**Decir:**

«La arquitectura responde a tres necesidades: conservar el histórico con trazabilidad, entregar información adecuada a cada canal y procesar dinero sin aplicar dos veces una orden. Spring Batch cubre la migración; los BFF separan los contratos de cada canal; Account conserva la responsabilidad de los saldos. Config Server entrega propiedades y Eureka permite descubrir los servicios. Docker Compose coordina el entorno. La autenticación se resuelve con OAuth2, y cada BFF verifica los permisos del token antes de acceder al dominio.»

## 1:15 a 2:00 Batch y origen de los datos

**Mostrar:** ejecutar la consulta, señalar las tres ejecuciones COMPLETED y los conteos. Abrir el informe en la sección de migración.

```powershell
./scripts/Get-EftBatchReport.ps1 -Period 2026-10
```

**Decir:**

«Hay tres procesos: transacciones diarias, intereses mensuales y estados anuales. Cada uno utiliza lectura, procesamiento y escritura, con ejecución particionada, metadatos persistentes y recuperación acotada. Aquí consulto los resultados existentes; no estoy cargando de nuevo los archivos. Cada CSV tiene mil filas. Las filas inválidas conservan su motivo, y las cuentas repetidas del archivo de intereses quedan pendientes de conciliación. Para la demostración se asociaron 47 cuentas de ahorro a clientes explícitamente sintéticos, conservando archivo, línea, período y saldo original. No se reconstruyeron transferencias históricas que el CSV no permite identificar.»

## 2:00 a 2:45 Seguridad y contratos por canal

**Mostrar:** ejecutar ambos pasos; señalar 401, 403 y los campos diferentes de perfiles y saldo.

```powershell
./scripts/Invoke-EftDemo.ps1 -Paso Seguridad -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Consultas -Sesion $sesion
```

**Decir:**

«Sin token se devuelve 401; un token sin el permiso necesario recibe 403. Además, un token del canal Móvil no funciona en Cajero. Web entrega el perfil completo, Móvil lo reduce y Cajero devuelve solamente el saludo y los campos mínimos de saldo. Los accesos públicos utilizan HTTPS. Estos clientes OAuth representan los canales de prueba; no equivalen a un inicio de sesión personal de cada cliente bancario. La lógica de saldos y pagos permanece en los servicios de dominio.»

## 2:45 a 3:10 Clientes y ciclo de vida de cuentas

**Mostrar:** pestaña «Validación previa de clientes y cuentas» con las salidas de `Test-CustomerFlow.ps1` y `Test-AccountLifecycle.ps1`. Señalar creación, actualización, bloqueo, cierre y rechazo de una versión antigua.

**Decir:**

«En estas pruebas ejecutadas antes de la grabación comprobé creación y mantenimiento de clientes. También validé apertura, bloqueo, desbloqueo y cierre de una cuenta sin saldo. Una actualización con una versión antigua devuelve conflicto y una cuenta cerrada no se reabre. Estas reglas están implementadas en Customer y Account, no en los BFF.»

## 3:10 a 5:15 Flujo monetario real con Kafka

**Mostrar:** ejecutar en orden. Se puede recortar la espera de una orden PENDIENTE, conservando en pantalla el mismo pagoId antes y después.

```powershell
./scripts/Invoke-EftDemo.ps1 -Paso Deposito -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Transferencia -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Retiro -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Duplicado -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso Pago -Sesion $sesion
./scripts/Invoke-EftDemo.ps1 -Paso SinFondos -Sesion $sesion
```

**Decir mientras se ejecuta:**

«Deposito cien pesos por Cajero, transfiero treinta por Móvil, retiro veinte por Cajero y realizo un pago de diez por Web. El 202 solo significa que la orden fue aceptada. Payment guarda la orden junto con su outbox, Kafka transporta el comando y Account aplica los movimientos en una transacción. Luego publica el resultado y Payment cambia el estado a APLICADO o RECHAZADO.

Ahora repito el retiro con la misma clave de idempotencia. Se devuelve el mismo pagoId y el saldo no vuelve a disminuir. La prueba siguiente intenta retirar más de lo disponible: la orden termina RECHAZADO por SALDO_INSUFICIENTE y no altera el saldo. La tabla contrasta el saldo esperado con el que realmente devuelve Account.»

**Mostrar Kafka UI:** entrar a Topics → `bancoxyz.pagos.commands.v1` → Messages. Buscar el `pagoId` mostrado por la terminal; si la interfaz limita el rango temporal, elegir los últimos mensajes. Abrir el resultado correspondiente en `bancoxyz.pagos.results.v1`. Mostrar comando y resultado con el mismo identificador. No editar ni publicar mensajes desde la UI.

**Decir:** «En Kafka UI puedo observar el comando y su resultado. Los mensajes transportan el identificador de la operación, que permite seguir el recorrido completo y evitar efectos duplicados.»

## 5:15 a 6:00 Resiliencia y recuperación

**Mostrar:** ejecutar la prueba una vez terminados los pagos. Dejar visibles OPEN, 503 y recuperación CLOSED con 200.

```powershell
./scripts/Test-Resilience.ps1 -CuentaId 137
```

**Decir:**

«Esta prueba pausa temporalmente Account. Resilience4j limita la espera, devuelve 503 y abre el circuito para evitar insistir sobre un servicio que no responde. Después se restablece Account y el circuito vuelve a CLOSED. No se inventa un saldo como respuesta alternativa. En la mensajería, los fallos técnicos conservan las órdenes pendientes para su recuperación; los mensajes inválidos tienen tópicos de error. Un rechazo de negocio, como saldo insuficiente, es un resultado esperado, no un mensaje técnico fallido.»

## 6:00 a 7:00 Resultados y cierre

**Mostrar:** resumen final y sección de conclusiones del informe.

```powershell
./scripts/Invoke-EftDemo.ps1 -Paso Resumen -Sesion $sesion
```

**Decir:**

«El resultado es un flujo verificable desde los tres canales hasta Kafka y MySQL. En esta sesión la cuenta de origen aumenta cuarenta pesos y la de destino otros cuarenta. El depósito añade cien al total y el retiro resta veinte; la transferencia y el pago solo redistribuyen fondos.

Frente al sistema monolítico descrito en el caso, ahora cada dominio tiene una responsabilidad clara, los canales reciben contratos diferentes y las operaciones se pueden rastrear. Esta es una comparación funcional; no presento mediciones de rendimiento contra un mainframe.

Los principales desafíos fueron la ambigüedad de los CSV, resuelta mediante trazabilidad y asociaciones sintéticas explícitas; los mensajes duplicados, controlados con idempotencia y transacciones; y las restricciones del laboratorio, por las que AWS se utiliza solo para Kafka. Como mejoras futuras propongo autenticación personal con autorización por titular, conciliación con datos reales y mayor observabilidad. El código incluye los README, el informe y las instrucciones para reproducir la solución.»

## Comprobaciones al terminar la grabación

La salida Resumen debe ser correcta y Account debe estar recuperado. Verificar que el MP4 tenga webcam, texto legible y duración final de 7:00. Si una orden falla o queda pendiente, no afirmar que fue aplicada: recuperar el entorno, repetir su paso con la misma sesión y volver a grabar ese segmento. El video y el enlace GitHub los incorpora el estudiante a la entrega.
