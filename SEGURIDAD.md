# OAuth2 en el BFF Web

El cliente se autentica ante auth-server y obtiene un access token JWT.
El BFF actúa como Resource Server: valida firma RSA, emisor, caducidad,
audiencia bff-web y permiso antes de llamar a Account mediante Eureka.

## Alcance

Esta entrega utiliza client_credentials para probar la API con el cliente
confidencial web-demo. Representa una aplicación de demostración con acceso a
las consultas académicas; no representa a una persona ni aplica propiedad de
cuentas. No entregar su secreto a JavaScript de un navegador.
El login de personas requerirá Authorization Code con PKCE y una política
de acceso a las cuentas. No se implementa el grant password.

| Elemento | Configuración |
|---|---|
| Servidor OAuth2 | auth-server, localhost:9000 |
| Grant | client_credentials |
| Autenticación del cliente | client_secret_basic, secreto aleatorio local |
| Firma de access tokens | RSA / RS256 |
| Duración | 5 minutos; sin refresh token |
| Emisor | https://localhost:9000 |
| Audiencia obligatoria | bff-web |
| GET /api/web/** | scope web.read |
| POST /api/web/cuentas/{id}/solicitudes-estado | scope web.write |
| GET /actuator/info en Web | scope web.info |
| /actuator/health | Público, sin detalles internos |
| Otros endpoints/métodos del BFF | Denegados |

Sin token o con token inválido: 401. Token válido sin permiso: 403.
Un token autorizado permite seguir recibiendo el 404 de una cuenta inexistente.
El BFF es stateless y no acepta autenticación por cookie de sesión ni Basic.
CSRF está desactivado solamente en esta API Bearer.

## Archivos locales

Initialize-LocalSecurity.ps1 genera secretos de 32 bytes aleatorios en .env y
una clave RSA de firma de 3072 bits en secrets/auth-signing.p12. El certificado
del keystore identifica la clave de firma; no configura HTTPS.
La clave se monta en Auth como archivo de solo lectura y se conserva al recrear
el contenedor. No se genera una clave distinta en cada arranque.

Guardar .env y secrets fuera de GitHub y no mostrarlos en el video. El script
es repetible: no cambia claves existentes y comprueba la contraseña del keystore.
La pérdida de estos archivos requiere generar credenciales nuevas; no borrarlos
para cambiar los CSV de S9.

Los clientes OAuth2 y autorizaciones están en memoria para este laboratorio.
El cliente se reconstruye al arrancar a partir del secreto local. La firma
persistente permite validar JWT emitidos antes de un reinicio hasta su caducidad.
La revocación inmediata de JWT requeriría un mecanismo adicional.

## Ejecución y prueba

Desde la raíz del proyecto:

```powershell
.\scripts\Test-Stack.ps1 -CuentaId 137
.\scripts\Test-WebSecurity.ps1 -CuentaId 137
$token = .\scripts\Get-WebToken.ps1 -Scope 'web.read'
.\scripts\Invoke-LocalHttps.ps1 -Uri https://localhost:8081/api/web/cuentas/137 -Headers @{Authorization="Bearer $token"}
Remove-Variable token
```

Elegir un ID presente en el conjunto de CSV cargado. Los scripts solo consultan.
Get-WebToken lee AUTH_WEB_CLIENT_SECRET del entorno o del .env local; asignar
el resultado a una variable para evitar mostrarlo.

Para Postman: POST https://localhost:9000/oauth2/token, Basic Auth con usuario
web-demo y el secreto local; cuerpo x-www-form-urlencoded con
grant_type=client_credentials y scope=web.read. Usar el access_token como Bearer
en la consulta HTTPS al BFF. Configurar la confianza del certificado según HTTPS.md; no desactivar su verificación. No guardar el secreto en colecciones publicadas.

Desde el PC, emisor y JWKS usan HTTPS en localhost:9000. Dentro de Docker, el BFF
descarga las claves desde http://auth-server:9000/oauth2/jwks, pero valida
el emisor público https://localhost:9000. Esta separación evita interpretar
localhost como el propio contenedor del BFF.

Auth arranca de forma independiente de Config/Eureka para no crear un ciclo
de autenticación de infraestructura. La configuración pública de validación
del BFF sí está centralizada; los secretos no pasan por Config Server.
Para ejecutar Auth directamente, exportar AUTH_WEB_CLIENT_SECRET y
AUTH_KEYSTORE_PASSWORD a la sesión y ejecutar mvnw.cmd spring-boot:run desde
auth-server. Spring Boot no carga .env automáticamente; Compose sí.

## Transporte y acceso interno

Compose publica Web y OAuth2 mediante Nginx con HTTPS; el cliente valida el
certificado local. Ver [HTTPS.md](HTTPS.md). Account y Platform ya no publican
puertos en Windows: el diagnóstico se realiza con docker compose exec.
El proxy no pertenece a la red de Account/Platform ni publica sus rutas.

TLS termina en el proxy. Los enlaces entre contenedores y la conexión a MySQL
mantienen su configuración actual; no hay mTLS ni autenticación de servicio a
servicio añadida en esta etapa. Se requerirá ampliar esas medidas antes de
desplegar el conjunto en una red no confiable. AWS no fue modificado.

## Referencias

- [Authorization Server de Spring Security](https://docs.spring.io/spring-security/reference/servlet/oauth2/authorization-server/getting-started.html)
- [Validación JWT en Resource Server](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html)
