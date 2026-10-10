#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
endpoint="${1:?Uso: bash prepare.sh IP_PUBLICA_O_DNS}"
[[ "$endpoint" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || { echo 'Direccion invalida'; exit 1; }
command -v openssl >/dev/null
docker compose version
image=apache/kafka:4.1.2
docker pull "$image"
if [[ -f .env || -d secrets ]]; then
  echo 'Ya existe configuracion. No se reemplazan claves ni el identificador del cluster.'
  echo 'Para iniciar: docker compose up -d --wait --wait-timeout 180'
  exit 1
fi
umask 077
mkdir secrets
admin_password=$(openssl rand -hex 32)
web_password=$(openssl rand -hex 32)
account_password=$(openssl rand -hex 32)
cluster_id=$(docker run --rm --entrypoint /opt/kafka/bin/kafka-storage.sh "$image" random-uuid)
printf 'CLUSTER_ID=%s\n' "$cluster_id" > .env
san="DNS:$endpoint"
[[ "$endpoint" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && san="IP:$endpoint"
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
  -keyout secrets/broker.key -out secrets/broker.crt -subj "/CN=$endpoint" \
  -addext "subjectAltName=$san,DNS:kafka" \
  -addext "extendedKeyUsage=serverAuth"
cat secrets/broker.key secrets/broker.crt > secrets/broker.pem
cat > secrets/server.properties <<EOF
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@127.0.0.1:9094
controller.listener.names=CONTROLLER
listeners=INTERNAL://127.0.0.1:9092,EXTERNAL://0.0.0.0:9093,CONTROLLER://127.0.0.1:9094
advertised.listeners=INTERNAL://127.0.0.1:9092,EXTERNAL://$endpoint:9093
listener.security.protocol.map=INTERNAL:PLAINTEXT,EXTERNAL:SASL_SSL,CONTROLLER:PLAINTEXT
inter.broker.listener.name=INTERNAL
sasl.enabled.mechanisms=PLAIN
listener.name.external.plain.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required user_admin="$admin_password" user_web="$web_password" user_account="$account_password";
ssl.keystore.type=PEM
ssl.keystore.location=/secrets/broker.pem
ssl.client.auth=none
authorizer.class.name=org.apache.kafka.metadata.authorizer.StandardAuthorizer
super.users=User:ANONYMOUS;User:admin
allow.everyone.if.no.acl.found=false
early.start.listeners=CONTROLLER
log.dirs=/var/lib/kafka/data
num.partitions=1
default.replication.factor=1
min.insync.replicas=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
auto.create.topics.enable=false
log.retention.hours=24
log.retention.bytes=268435456
log.segment.bytes=67108864
EOF
for user in admin web account; do
  password_var="${user}_password"
  password="${!password_var}"
  cat > "secrets/$user.properties" <<EOF
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="$user" password="$password";
ssl.truststore.type=PEM
ssl.truststore.location=/secrets/broker.crt
ssl.endpoint.identification.algorithm=https
EOF
done
# La imagen oficial corre como appuser; comprobar sus IDs antes de asignar permisos.
uid=$(docker run --rm --entrypoint id "$image" -u)
gid=$(docker run --rm --entrypoint id "$image" -g)
sudo chown -R "$uid:$gid" secrets
sudo chmod 700 secrets
docker volume create bancoxyz-kafka-data >/dev/null
docker run --rm --user 0 --entrypoint sh -v bancoxyz-kafka-data:/data "$image" -c "chown $uid:$gid /data"
echo 'Configuracion creada sin imprimir credenciales. No publicar .env ni secrets.'
