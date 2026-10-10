# Organización y ejecución

Este repositorio utiliza las mismas rutas de Compose y de los scripts del proyecto original. Para ejecutarlo, los repositorios independientes se clonan dentro de esta carpeta:

```text
bancoxyz-infra/
  compose.yaml
  compose.payments-kafka.yaml
  scripts/
  proxy/
  deploy/kafka/
  entrega-eft/
  account-service/          ← repositorio independiente
  auth-server/              ← repositorio independiente
  bff-web/                  ← repositorio independiente
  bff-mobile/               ← repositorio independiente
  bff-atm/                  ← repositorio independiente
  customer-service/         ← repositorio independiente
  payment-service/          ← repositorio independiente
  platform-service/         ← repositorio independiente
  config-repo/              ← repositorio independiente
  legacy-batch-migrator/     ← repositorio independiente
```

Las diez carpetas de código están excluidas del Git de infraestructura. No se incorporan como repositorios incrustados ni se duplican sus fuentes. `config-repo` sigue siendo exclusivamente la fuente de propiedades de Config Server.

## Preparar el código

Las seis URL conocidas están registradas en `repositories.json`. Las cuatro URL todavía no configuradas se dejan vacías para no inventar repositorios. Después de publicarlas, completar los valores correspondientes.

Desde PowerShell 7, en esta carpeta:

```powershell
./scripts/Initialize-Repositories.ps1 -OnlyAvailable -WhatIf
./scripts/Initialize-Repositories.ps1 -OnlyAvailable
```

La primera instrucción muestra qué se clonaría. La segunda clona solo los repositorios con URL y omite carpetas existentes, sin hacer pull ni sobrescribir cambios. Con todas las URL completas puede omitirse `-OnlyAvailable`.

Los repositorios remotos deben contener las versiones EFT de los servicios antes de compilar. Clonar la rama predeterminada no incorpora cambios locales que aún no se hayan publicado o integrado mediante PR.

## Configuración y arranque

Seguir [las instrucciones de ejecución](entrega-eft/instrucciones.md), reemplazando su directorio de partida `s8/proyecto8` por esta carpeta. Esas instrucciones describen el entorno original ya validado y la preparación de otra instalación.

Se necesitan las credenciales privadas locales, el certificado y las credenciales cliente de Kafka, los esquemas MySQL y los JAR compilados de cada servicio. Se mantienen fuera de Git; no se incluyen en este repositorio ni se generaron de nuevo al crearlo.

Con esos requisitos preparados:

```powershell
docker compose -f compose.yaml -f compose.payments-kafka.yaml --profile tools up -d --build
docker compose -f compose.yaml -f compose.payments-kafka.yaml --profile tools ps
```

No iniciar esta copia al mismo tiempo que el entorno original: ambos usan el nombre de proyecto Compose `bancoxyz-local` y los mismos puertos. Para la demostración actual puede seguir utilizándose `s8/proyecto8`, que conserva sus servicios, datos y secretos.

La documentación de validación y los informes son los entregables originales de la EFT; sus resultados corresponden al entorno original, no a una ejecución nueva de esta copia.
