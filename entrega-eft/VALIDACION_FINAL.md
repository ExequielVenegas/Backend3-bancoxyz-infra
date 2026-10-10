# Validación integrada del 8 de octubre de 2026

Pruebas ejecutadas contra los servicios locales, MySQL y Kafka AWS del laboratorio. No se ejecutó otra carga batch ni una prueba de escalabilidad horizontal.

| Comprobación | Resultado |
|---|---|
| HTTPS, OAuth2, Eureka y Config Server | Test-Stack correcto; consulta coherente entre Web y Account/MySQL. |
| Autenticación y permisos | 401 sin token, 403 sin scope y 401 con token Móvil en Cajero. |
| Tres BFF | Consultas de cuenta y perfil correctas; respuestas Web, Móvil y Cajero diferenciadas. |
| Clientes | Alta 201, repetición sin duplicado, consulta, actualización, 409 por versión antigua y 400 por datos inválidos. |
| Cuentas | Apertura, bloqueo, desbloqueo y cierre correctos; 409 por reapertura y 422 por titular inexistente. |
| Depósito Cajero | 100 CLP, APLICADO. |
| Transferencia Móvil | 30 CLP, APLICADO. |
| Retiro Cajero | 20 CLP, APLICADO. |
| Repetición del retiro | Mismo pagoId, sin segundo descuento. |
| Pago Web | 10 CLP, APLICADO. |
| Retiro sin fondos | RECHAZADO, motivo SALDO_INSUFICIENTE. |
| Saldo final | 5040 CLP en origen y 5040 CLP en destino; inicio 5000/5000. |
| Resilience4j | Account pausado: 503 y OPEN; reanudado: 200 y CLOSED. |
| Web productor directo | Solicitud persistida por Account como REGISTRADA; repetición DUPLICADA_IGNORADA. |
| DLT | Mensaje versión 99 confirmado por lectura del offset 1 y su ID exacto. |
| Batch existente | Tres jobs COMPLETED; consulta de 3000 filas en total, sin recarga. |

## Identificadores para localizar resultados

Sesión monetaria: `validacion-20261008`.

| Registro | Identificador |
|---|---|
| Cuenta origen, legacy 101 | 72bb9863-85c1-339b-b888-e17f0c60b2be |
| Cuenta destino, legacy 102 | c9aec69b-9d28-34a0-9ab0-811b067aee40 |
| Depósito | c4d73d4a-8e9f-3350-a03b-216810c0420f |
| Transferencia | 10aea5bf-a8c4-31f4-8c82-5dd28eef1918 |
| Retiro y su repetición | 9fab4f35-7f93-3ad6-acbe-ee7d142217c8 |
| Pago | 85b9e17d-b445-352f-b856-6a979da0c3af |
| Retiro rechazado | 88bfc1cc-86f6-3acf-a77f-027fb1cbc301 |
| Solicitud de estado de cuenta | 568aa3f4-e7ee-3581-807e-1de0707c242b |
| Mensaje inválido DLT | 460b41a0-2912-4f98-869a-e832eb62ad1e |

Se observaron respuestas 503 transitorias al primer envío del depósito y de la solicitud directa Web. Ambos se retomaron con sus claves originales y luego se verificó persistencia e idempotencia. No se afirma que el arranque haya estado libre de errores.

Las cuentas y los perfiles son de demostración. Las dos cuentas importadas utilizadas permanecen activas; las restantes asociaciones no se activaron durante esta prueba. Los registros y saldos no se eliminaron después de validar. La prueba de ciclo de vida creó y dejó cerrada una cuenta de prueba separada.

La prueba inicial `Test-SyntheticLegacyAssociations.ps1` comprueba cuentas recién importadas, bloqueadas y sin movimientos. Después de esta demostración sus expectativas iniciales ya no se cumplen para 101 y 102; usar el resumen de Invoke-EftDemo para comprobar el estado posterior. No reiniciar saldos ni bloquear todas las cuentas para forzar esa prueba inicial.
