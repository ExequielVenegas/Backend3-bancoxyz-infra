# Proxy HTTPS

Configuración de Nginx para acceder por HTTPS a los BFF Web, Móvil y Cajero y a Auth Server.

| Servicio | Puerto local |
|---|---|
| Web | 8081 |
| Móvil | 8082 |
| Cajero | 8083 |
| Auth Server | 9000 |

Se ejecuta mediante el Compose principal. Los certificados se guardan en `secrets/tls`, fuera de Git.
