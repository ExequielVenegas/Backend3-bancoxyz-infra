#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# Ejecutar como ec2-user. sudo se usa solo para archivos secretos del broker.
# No usar bash -x: este proceso prepara una credencial que no debe imprimirse.
sudo python3 - <<'PY'
from pathlib import Path
import os, re, secrets, shutil, tempfile
root = Path('secrets')
server = root / 'server.properties'
original = server.read_text()
match = re.search(r'^listener\.name\.external\.plain\.sasl\.jaas\.config=(.*)$', original, re.M)
if not match or not match.group(1).rstrip().endswith(';'):
    raise SystemExit('No se encontro la configuracion SASL/PLAIN esperada')
existing = re.search(r'\buser_ui="([a-f0-9]{64})"', match.group(1))
if 'user_ui=' in match.group(1) and not existing:
    raise SystemExit('Existe un usuario ui con formato distinto; no se reemplazara')
password = existing.group(1) if existing else secrets.token_hex(32)
stat = server.stat()
def write_private(path, content):
    fd, tmp = tempfile.mkstemp(prefix='.ui-', dir=root)
    try:
        with os.fdopen(fd, 'w') as stream: stream.write(content)
        os.chown(tmp, stat.st_uid, stat.st_gid)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
if not existing:
    backup = Path(tempfile.mkdtemp(prefix='ui-backup.', dir=root))
    shutil.copy2(server, backup / 'server.properties')
    updated = match.group(1).rstrip()[:-1] + ' user_ui="' + password + '";'
    write_private(server, original[:match.start(1)] + updated + original[match.end(1):])
jaas = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="ui" password="' + password + '";'
write_private(root / 'ui.properties', 'security.protocol=SASL_SSL\nsasl.mechanism=PLAIN\nsasl.jaas.config=' + jaas + '\nssl.truststore.type=PEM\nssl.truststore.location=/secrets/broker.crt\nssl.endpoint.identification.algorithm=https\n')
write_private(root / 'ui-config.yml', '''auth:
  type: DISABLED
kafka:
  clusters:
    - name: aws-lab
      bootstrapServers: ${KAFKA_BOOTSTRAP_SERVERS}
      readOnly: true
      properties:
        security.protocol: SASL_SSL
        sasl.mechanism: PLAIN
        sasl.jaas.config: 'JAAS'
        ssl.truststore.type: PEM
        ssl.truststore.location: /secrets/broker.crt
        ssl.endpoint.identification.algorithm: https
'''.replace('JAAS', jaas))
print('Usuario UI preparado. Secretos guardados sin imprimirlos.')
PY
docker compose up -d --force-recreate --wait --wait-timeout 180 kafka
acl() { docker compose exec -T kafka /opt/kafka/bin/kafka-acls.sh --bootstrap-server 127.0.0.1:9092 --add --allow-principal User:ui "$@"; }
for topic in bancoxyz.cuentas.commands.v1 bancoxyz.cuentas.commands.v1.dlt; do
  acl --operation Read --operation Describe --operation DescribeConfigs --topic "$topic"
done
acl --operation Describe --operation DescribeConfigs --cluster
acl --operation Describe --group account-service
echo 'UI: lectura habilitada, sin permisos de escritura, borrado ni cambio de offsets.'
