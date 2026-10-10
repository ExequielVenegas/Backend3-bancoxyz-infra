#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# Ejecutar en ~/kafka como ec2-user. Nunca usar bash -x ni publicar secrets.
sudo python3 - <<'PY'
from pathlib import Path
import os, re, secrets, shutil, tempfile
root = Path('secrets')
server = root / 'server.properties'
original = server.read_text()
match = re.search(r'^listener\.name\.external\.plain\.sasl\.jaas\.config=(.*)$', original, re.M)
if not match or not match.group(1).rstrip().endswith(';'):
    raise SystemExit('Configuracion SASL/PLAIN no reconocida; sin cambios')
existing = re.search(r'\buser_payment="([a-f0-9]{64})"', match.group(1))
if 'user_payment=' in match.group(1) and not existing:
    raise SystemExit('Credencial payment existente con formato distinto; sin cambios')
password = existing.group(1) if existing else secrets.token_hex(32)
stat = server.stat()
def private_write(path, content):
    fd, tmp = tempfile.mkstemp(prefix='.payments-', dir=root)
    try:
        with os.fdopen(fd, 'w') as stream: stream.write(content)
        os.chown(tmp, stat.st_uid, stat.st_gid)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
if not existing:
    backup = Path(tempfile.mkdtemp(prefix='payments-backup.', dir=root))
    shutil.copy2(server, backup / 'server.properties')
    updated = match.group(1).rstrip()[:-1] + ' user_payment="' + password + '";'
    private_write(server, original[:match.start(1)] + updated + original[match.end(1):])
jaas = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="payment" password="' + password + '";'
private_write(root / 'payment.properties', 'security.protocol=SASL_SSL\nsasl.mechanism=PLAIN\nsasl.jaas.config=' + jaas + '\nssl.truststore.type=PEM\nssl.truststore.location=/secrets/broker.crt\nssl.endpoint.identification.algorithm=https\n')
print('Credencial de Pagos preparada sin imprimir secretos.')
PY
docker compose up -d --force-recreate --wait --wait-timeout 180 kafka
acl() { docker compose exec -T kafka /opt/kafka/bin/kafka-acls.sh --bootstrap-server 127.0.0.1:9092 --add "$@"; }
for topic in bancoxyz.pagos.commands.v1 bancoxyz.pagos.results.v1 bancoxyz.pagos.commands.v1.dlt bancoxyz.pagos.results.v1.dlt; do
  docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server 127.0.0.1:9092 --create --if-not-exists --topic "$topic" --partitions 1 --replication-factor 1 --config min.insync.replicas=1 --config retention.ms=86400000 --config retention.bytes=268435456
  acl --allow-principal User:ui --operation Read --operation Describe --operation DescribeConfigs --topic "$topic"
done
acl --allow-principal User:payment --operation Write --operation Describe --topic bancoxyz.pagos.commands.v1
acl --allow-principal User:payment --operation Read --operation Describe --topic bancoxyz.pagos.results.v1
acl --allow-principal User:payment --operation Write --operation Describe --topic bancoxyz.pagos.results.v1.dlt
acl --allow-principal User:payment --operation Read --group payment-service
acl --allow-principal User:payment --operation IdempotentWrite --cluster
acl --allow-principal User:account --operation Read --operation Describe --topic bancoxyz.pagos.commands.v1
acl --allow-principal User:account --operation Write --operation Describe --topic bancoxyz.pagos.commands.v1.dlt
acl --allow-principal User:account --operation Write --operation Describe --topic bancoxyz.pagos.results.v1
acl --allow-principal User:account --operation Read --group account-payments
acl --allow-principal User:account --operation IdempotentWrite --cluster
acl --allow-principal User:ui --operation Describe --group payment-service
acl --allow-principal User:ui --operation Describe --group account-payments
echo 'Topicos y permisos de Pagos preparados. Copiar secrets/payment.properties al proyecto local.'
