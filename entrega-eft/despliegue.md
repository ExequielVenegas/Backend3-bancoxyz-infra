# Kafka en AWS y servicios locales

AWS aloja únicamente Kafka, conforme a la indicación del profesor. MySQL, Spring Batch y los microservicios permanecen en el PC. Este documento describe el despliegue de laboratorio existente, sin escalabilidad horizontal.

## Configuración

| Recurso | Valor |
|---|---|
| Región | us-east-1 |
| EC2 | i-05c6942a4f6dd7734 |
| Tipo | c7i-flex.large |
| Sistema | Amazon Linux, usuario ec2-user |
| IP elástica | 100.29.239.217 |
| Kafka | apache/kafka:4.1.2, KRaft, un broker/controlador |
| Puerto de clientes | TCP 9093 con SASL_SSL |
| SSH | TCP 22 |
| Security group | Autorizar 22 y 9093 desde la IP pública actual del PC /32. |
| Persistencia | Volumen Docker bancoxyz-kafka-data en el disco de EC2. |
| Tópicos | Comandos de cuentas, comandos y resultados de pagos, y sus DLT. |
| Réplicas | Una por partición; no hay alta disponibilidad. |

La IP elástica permanece asociada al recurso mientras se conserve. Si cambia el endpoint, actualizar advertised.listeners, el SAN del certificado y KAFKA_BOOTSTRAP_SERVERS de los clientes. No basta con cambiar la dirección local.

## Encender la instalación existente

1. Iniciar el Learner Lab y la instancia EC2. Revisar que conserve la IP elástica y que el security group permita la IP pública actual del PC.
2. Conectarse desde PowerShell con la clave privada local, sin copiarla al proyecto:

```powershell
ssh -i "$env:USERPROFILE\Documents\bancoxyz-kafka.pem" ec2-user@100.29.239.217
```

3. En EC2, iniciar Docker y el broker existente:

```bash
sudo systemctl start docker
cd ~/kafka
docker compose up -d --wait --wait-timeout 180
docker compose ps
```

No ejecutar `prepare.sh` otra vez sobre una instalación configurada. No borrar el volumen ni los secretos del broker.

4. En el PC, comprobar TCP y clientes:

```powershell
Test-NetConnection 100.29.239.217 -Port 9093
./scripts/Test-KafkaConnection.ps1
docker compose -f compose.yaml -f compose.payments-kafka.yaml --profile tools up -d
```

## Reproducir el despliegue desde una EC2 vacía

1. Crear la EC2 del laboratorio, asignar el par de claves y un security group con 22/9093 limitados al PC. Asociar la IP estable antes de generar certificados. No publicar 9092 ni el puerto del controlador.
2. En Amazon Linux, instalar e iniciar Docker y habilitar al usuario:

```bash
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
```

Cerrar y volver a abrir SSH para aplicar el grupo. Instalar el plugin Compose oficial compatible con Linux x86_64; esta instalación utiliza Compose v5.6.0:

```bash
mkdir -p "$HOME/.docker/cli-plugins"
curl -fSL https://github.com/docker/compose/releases/download/v5.6.0/docker-compose-linux-x86_64 -o "$HOME/.docker/cli-plugins/docker-compose"
chmod +x "$HOME/.docker/cli-plugins/docker-compose"
docker version
docker compose version
```

3. Copiar el contenido de `deploy/kafka` a `~/kafka`. En esa carpeta ejecutar, sustituyendo la IP si se utiliza otra instancia:

```bash
bash prepare.sh 100.29.239.217
docker compose up -d --wait --wait-timeout 180
bash create-topics.sh
bash create-payments.sh
bash create-ui-user.sh
docker compose ps
```

Los scripts generan secretos sin imprimirlos, preparan tópicos y ACL, y recrean el broker cuando corresponde. No ejecutarlos con `bash -x`. No cambiar CLUSTER_ID de un volumen existente.

4. Copiar al PC únicamente `broker.crt`, `web.properties`, `account.properties`, `payment.properties`, `ui.properties` y `ui-config.yml` desde `~/kafka/secrets` hacia `s8/proyecto8/secrets/kafka`. No copiar las claves privadas del broker ni las credenciales administrativas. Los archivos cliente referencian el certificado dentro del contenedor en `/secrets/broker.crt`.
5. Ajustar KAFKA_BOOTSTRAP_SERVERS en `.env`, mantener los secretos fuera de Git y continuar con `instrucciones.md`. Confirmar TLS/SASL con Test-KafkaConnection antes de probar pagos.

La retención de mensajes es limitada: Kafka UI puede no mostrar mensajes de ensayos antiguos. Generar la operación durante la demostración y buscar su ID actual. La base de datos conserva las órdenes y sus resultados aunque Kafka haya eliminado mensajes por retención.
