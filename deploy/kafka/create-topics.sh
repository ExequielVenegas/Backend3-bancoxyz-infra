#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
kafka() { docker compose exec -T kafka "/opt/kafka/bin/$1" --bootstrap-server 127.0.0.1:9092 "${@:2}"; }
for topic in bancoxyz.cuentas.commands.v1 bancoxyz.cuentas.commands.v1.dlt; do
  kafka kafka-topics.sh --create --if-not-exists --topic "$topic" --partitions 1 --replication-factor 1
done
kafka kafka-acls.sh --add --allow-principal User:web --producer --topic bancoxyz.cuentas.commands.v1
kafka kafka-acls.sh --add --allow-principal User:web --operation IdempotentWrite --cluster
kafka kafka-acls.sh --add --allow-principal User:account --consumer --topic bancoxyz.cuentas.commands.v1 --group account-service
kafka kafka-acls.sh --add --allow-principal User:account --producer --topic bancoxyz.cuentas.commands.v1.dlt
kafka kafka-acls.sh --add --allow-principal User:account --operation IdempotentWrite --cluster
kafka kafka-topics.sh --describe
