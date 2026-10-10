# HTTPS local y acceso a servicios internos

Nginx termina TLS en https://localhost:8081 (Web), https://localhost:8082 (Móvil),
https://localhost:8083 (Cajero) y https://localhost:9000 (OAuth2).
Estos cuatro puertos de API se publican ligados a 127.0.0.1.
Los contenedores Java no publican puertos. Account y Platform comparten la red
backend; Auth y Nginx comparten frontend. Web participa en ambas.
No hay una ruta pública a Account, Config Server o Eureka.

## Certificado

Desde PowerShell 7, ejecutar:

```powershell
.\scripts\Initialize-LocalTls.ps1
```

Genera un certificado autofirmado RSA de 3072 bits, válido durante un año,
con SAN localhost, 127.0.0.1 y ::1. Admite uso de servidor TLS; no es una CA.
Nginx acepta TLS 1.2 y 1.3. No escucha en HTTP ni redirige credenciales enviadas
por HTTP: ese protocolo se rechaza con 400.

| Archivo local excluido de Git | Uso |
|---|---|
| secrets/tls/localhost.crt | Certificado público PEM para clientes y Nginx |
| secrets/tls/localhost.key | Clave privada TLS, montada solo en el proxy |
| secrets/tls/localhost.cer | Copia pública DER para importar en Windows |
| secrets/auth-signing.p12 | Clave distinta, usada por Auth para firmar JWT |

El script no reemplaza un certificado existente. Para renovar, detener el proxy,
conservar los archivos antiguos fuera de secrets/tls, generar el nuevo certificado
y actualizar la confianza del cliente. No cambiar la clave JWT para renovar TLS.
No publicar .env ni secrets en GitHub ni mostrarlos en el video.

## Scripts sin modificar Windows

Invoke-LocalHttps.ps1 construye una cadena de confianza propia usando únicamente
localhost.crt. También comprueba nombre, vigencia y uso de servidor del certificado.
No usa SkipCertificateCheck ni acepta certificados arbitrarios.
No instala certificados en Windows. Requiere PowerShell 7 y acceso normal
al proveedor criptográfico de Windows.

```powershell
$token = .\scripts\Get-WebToken.ps1 -Scope 'web.read'
$response = .\scripts\Invoke-LocalHttps.ps1 -Uri https://localhost:8081/api/web/cuentas/137 -Headers @{Authorization="Bearer $token"}
$response.Content | ConvertFrom-Json
Remove-Variable token
```

## Navegador y Postman

Un navegador no confía automáticamente en un certificado autofirmado.
Para confiar en este certificado en el almacén del usuario actual de Windows,
puedes ejecutar voluntariamente:

```powershell
Import-Certificate -FilePath .\secrets\tls\localhost.cer -CertStoreLocation Cert:\CurrentUser\Root
```

Este paso no se ejecutó automáticamente. Para revertirlo, eliminar únicamente
el certificado con la huella correspondiente desde el administrador de
certificados del usuario. Reiniciar el navegador si no reconoce la importación;
algunos clientes utilizan su propio almacén.

En Postman configurar el certificado público en las opciones de certificados
de confianza/CA si no usa el almacén de Windows; mantener activada la
verificación SSL. No usar una excepción general de certificados.

Con el certificado confiable, la consulta Web todavía devuelve 401 si no incluye
el token Bearer: TLS y autorización OAuth2 cumplen funciones distintas.
El emisor OAuth2 ahora es https://localhost:9000. Los tokens emitidos con el
antiguo emisor HTTP ya no son válidos; obtener uno nuevo con Get-WebToken.

## Diagnóstico sin abrir puertos

```powershell
docker compose exec -T platform-service curl -fsS -H "Accept: application/json" http://localhost:8761/eureka/apps
docker compose exec -T platform-service curl -fsS http://localhost:8761/bff-web/cloud
docker compose exec -T account-service curl -fsS http://localhost:8090/actuator/health
docker compose exec -T https-proxy nginx -t
.\scripts\Test-Https.ps1
.\scripts\Test-WebSecurity.ps1 -CuentaId 137
.\scripts\Test-Stack.ps1 -CuentaId 137
```

El panel de Eureka ya no está disponible en localhost:8761. El registro JSON
obtenido desde Docker permite demostrar los servicios UP sin publicar el panel.

## Límite de esta etapa

HTTPS protege el acceso del cliente al proxy; los enlaces proxy→Java, Eureka,
Config y Account usan HTTP dentro de las redes de Docker. MySQL conserva su
conexión local. No es cifrado de extremo a extremo ni mTLS.
La separación por redes reduce los accesos expuestos; un administrador con
acceso a Docker sigue pudiendo inspeccionar los servicios y secretos.

## Verificación realizada

Se comprobó HTTPS con el certificado del proyecto, rechazo de HTTP plano,
rechazo de una confianza TLS diferente, inaccesibilidad de 8090/8761 desde
Windows y rechazo de rutas internas en el proxy. OAuth2 mantuvo 401, 403 y
200 según token/permisos; la prueba integral consultó MySQL mediante Eureka.
