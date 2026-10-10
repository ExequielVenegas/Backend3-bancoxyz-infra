# Batch EFT: carga mensual, trazabilidad y recuperación

La adaptación se implementa en legacy-batch-migrator dentro de s8/proyecto8.
MySQL y Java siguen en el PC; AWS se utiliza solamente para Kafka.
El perfil optativo `eft` carga un esquema separado: `bancoxyz_batch_eft`.
No escribe en lab_batch ni en Clientes, cuentas modernas o Pagos.

## Procesos

| Job EFT | CSV original | Resultado |
|---|---|---|
| eftTransaccionesJob | movimientos_financieros_diarios.csv | Movimientos históricos validados, anomalías y resumen por fecha/tipo |
| eftInteresesMensualesJob | intereses_trimestrales.csv | Cálculo mensual por fila y detección de cuentas repetidas |
| eftEstadosAnualesJob | estados_financieros_anuales.csv | Historial validado y totales por cuenta/año/tipo |

El nombre trimestral del archivo se conserva por trazabilidad. Por decisión del
estudiante se aplica un período mensual. El parámetro `Period` identifica el mes
de cálculo de intereses; para los otros dos jobs identifica el lote de informe,
sin cambiar ni filtrar las fechas originales del histórico. El informe anual
agrupa por el año de la fecha original, aunque el lote se ejecute en 2026.

Los tres jobs S8 originales siguen disponibles sin el perfil eft y mantienen sus
entradas y tablas. Sus pruebas aisladas siguen aprobadas. No se ejecutaron de
nuevo contra lab_batch. El módulo ahora utiliza el starter JDBC de Spring Batch
para persistir el repositorio de ejecuciones; antes usaba el starter en memoria.
Antes de volver a ejecutar un job antiguo, comprobar la compatibilidad de sus
metadatos BATCH_* con Spring Batch 6 y conservar el respaldo existente.

## Reglas explícitas del laboratorio

- Importes decimales, máximo 17 dígitos enteros y dos decimales. No se redondea
  silenciosamente un monto de entrada con fracciones menores que un centavo.
- Movimientos: ID positivo, fecha válida y monto positivo; crédito o débito.
- Fechas admitidas: yyyy-MM-dd, dd-MM-yyyy, yyyy/MM/dd y dd/MM/yyyy. La validación
  es estricta: 29/02/2023 se rechaza; no se corrige automáticamente a otra fecha.
- Estados anuales: cuenta positiva, fecha válida, monto positivo, descripción
  presente y tipo depósito/retiro/compra/pago/transferencia.
- Intereses: cuenta positiva, nombre presente, saldo no negativo, edad entre
  18 y 120 y tipo ahorro/préstamo/hipoteca. Estos límites son reglas adoptadas
  para el laboratorio, no reglas de negocio proporcionadas por el docente.
- Tasas mensuales `monthly-v1`: ahorro 3 %, préstamo 5 %, hipoteca 4 %. Se conservan
  las tasas numéricas del procesador previo, interpretadas como mensuales; no se
  afirma que sean tasas anuales ni se dividen por doce. Interés = saldo × tasa,
  con HALF_UP a dos decimales; saldo calculado = saldo + interés.
- Todo ID de cuenta repetido en el archivo de intereses exige conciliación.
  Las filas calculables se conservan como PENDING_RECONCILIATION; no se elige
  el último saldo ni se combinan identidades por coincidencia de nombre.

Cada fila física conserva hash SHA-256, número de línea (cabecera en línea 1),
período, versión de reglas, contenido original, resultado y motivo. Se registra
el primer error encontrado en cada fila. El CSV de laboratorio tiene un registro
por línea; no se admiten campos que contengan saltos de línea.

Los datos de [fin_legacy_data](https://github.com/KariVillagran/fin_legacy_data)
incluyen errores intencionales, pero no aportan un motor de cálculo legacy ni
una salida esperada o tasas de referencia. Se comprobó equivalencia entre modos
secuencial y paralelo y resultados de ejemplos manuales; la equivalencia exacta
con un sistema legacy externo todavía no puede afirmarse.

## Ejecutar desde PowerShell 7

Desde s8/proyecto8, con MySQL iniciado:

```powershell
Push-Location legacy-batch-migrator
./mvnw.cmd package
Pop-Location
./scripts/Initialize-EftBatchDatabase.ps1
./scripts/Invoke-EftBatch.ps1 -Kind transactions -Period 2026-10
./scripts/Invoke-EftBatch.ps1 -Kind interest -Period 2026-10
./scripts/Invoke-EftBatch.ps1 -Kind annual -Period 2026-10
./scripts/Get-EftBatchReport.ps1 -Period 2026-10
./scripts/Export-EftBatchReports.ps1 -Period 2026-10
```

El script de preparación usa las credenciales administrativas locales ya
guardadas en .env. Crea un usuario exclusivo `bancoxyz_batch_eft@localhost`, con
SELECT/INSERT/UPDATE/CREATE/REFERENCES solamente en el esquema EFT. REFERENCES
permite crear las claves foráneas de los metadatos de Spring Batch.
El usuario del batch no tiene permisos sobre lab_batch ni sobre otros dominios.
El lanzador admite `-JavaPath` si Java está instalado en otra ruta y
`-InputFile` para usar otro CSV con la misma cabecera. No publica credenciales
en los argumentos del proceso. El perfil EFT exige sus propias variables;
el script rechaza una URL que apunte a lab_batch o a un servidor remoto.

Se guarda una copia del archivo en secrets/batch-input/<sha256>.csv, excluida de
Git. Conservarla sin editar para los reinicios. Los logs eft-run-*.log están en
legacy-batch-migrator y también quedan excluidos de Git.

## Informes y comprobación

Los CSV generados están en `secrets/batch-reports/2026-10/`:

| Archivo | Contenido |
|---|---|
| resumen-diario.csv | Totales por archivo, fecha y tipo, solo movimientos válidos |
| estado-anual.csv | Totales por archivo, cuenta, año y tipo; no inventa un saldo inicial/final |
| intereses-mensuales.csv | Cálculo por fila, con estado y motivo; no suma cuentas ambiguas |
| rechazos-y-pendientes.csv | Tipo de proceso, hash, línea, estado y motivo para localizar el dato original |

Los informes separan archivos por hash para no sumar accidentalmente distintas
versiones de una misma fuente. No incluyen secretos. Revisarlos antes de usar
capturas o compartir datos; el contenido original completo permanece en MySQL.

La validación real del 7 de octubre de 2026 produjo:

| Proceso | Filas | Válidas | Pendientes de conciliación | Rechazadas |
|---|---:|---:|---:|---:|
| Transacciones | 1000 | 392 | 0 | 608 |
| Intereses mensuales | 1000 | 0 | 422 | 578 |
| Estados anuales | 1000 | 473 | 0 | 527 |

Los tres jobs terminaron COMPLETED con tres hilos y cada fila contabilizada.
COMPLETED significa que la clasificación terminó, no que todos los datos sean
válidos. El archivo de intereses repite cuentas en todo el conjunto; por eso
sus 422 cálculos no rechazados requieren conciliación antes de promover saldos.

## Paralelismo, idempotencia y fallos

Se particiona cada archivo en intervalos disjuntos. Cada partición tiene su
propio lector y contexto de reinicio; el TaskExecutor ejecuta los workers.
El tamaño de chunk predeterminado es 100. `-Workers 1` permite ejecutar sin
paralelismo; el máximo del lanzador es ocho. El archivo se recorre para inspección
y cada lector avanza a su intervalo: existe costo adicional de lectura. No se
afirma una mejora de tiempo para estos CSV pequeños ni escalabilidad ilimitada.

La clave del lote incluye job, hash, período y versión de reglas. La ruta de la
copia no cambia la identidad. El hash se comprueba antes del lanzamiento y al
preparar las particiones. La clave de cada fila añade su número de línea.

- Datos inválidos: se escriben como REJECTED, sin perder su trazabilidad.
- Error transitorio de escritura: hasta tres intentos del chunk.
- Fallo del job: el lanzador admite hasta tres ejecuciones totales, con pausas
  de uno y dos segundos. Reutiliza los mismos parámetros y puntos de recuperación.
- Entrada alterada/cabecera incorrecta: se rechaza antes de iniciar el lote.
- Lote ya completado: repetir el mismo comando finaliza sin nueva carga.
- Si la base no permite consultar los metadatos o Java se termina abruptamente,
  no se promete recuperación automática ilimitada. Una ejecución que quede
  STARTED necesita diagnóstico; no cambiar su estado o borrar metadatos a ciegas.

Las filas y sus checkpoints se confirman por chunk. La unicidad de la salida
añade protección ante reentregas. No cambiar el período para eludir un fallo ni
editar una copia con la que ya se comenzó una ejecución.

Pruebas: 16 aprobadas (14 EFT y 2 existentes). Cubren cálculos manuales, fechas
imposibles, montos, duplicados, fallos temporales, fallo después de commits,
reinicio del mismo JobInstance y agotamiento de tres intentos. Para los tres
CSV completos se compararon todas las columnas de salida relevantes entre uno
y tres workers y se verificó que cada worker procesara filas.

## Integración pendiente con los dominios

Este bloque carga y concilia datos históricos; no abona intereses automáticamente
ni crea personas o cuentas modernas desde entradas ambiguas. La próxima etapa
debe aportar una asociación explícita cuenta legacy → cliente/cuenta moderna y
una fuente única de saldo inicial. Los movimientos sin cuenta origen/destino
se mantienen como historial; no se reconstruyen transferencias inexistentes.
La promoción debe ser idempotente y no volver a sumar un histórico ya incluido
en el saldo de apertura. No hace falta borrar ninguna tabla para avanzar.

La asociación revisada de filas del ETL con Clientes/Cuentas está implementada
mediante BFF Web; aún requiere elegir correspondencias explícitas. Ver
[ASOCIACION_LEGACY.md](ASOCIACION_LEGACY.md). Batch no escribe en los dominios.
