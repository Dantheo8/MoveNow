#!/usr/bin/env bash
# Nominal path test: publishes a small traceable batch with the kit producer, then waits until
# every event_id of the batch is in BigQuery. Exits 1 and lists the missing ids on timeout.
#   ./scripts/nominal-path-test.sh <project> <topic> <project.dataset.table> <location>
# Needs credentials (ADC) allowed to publish to the topic and to query the table, node and bq.
set -euo pipefail

if [ $# -ne 4 ]; then
  echo "Usage: $0 <project> <topic> <project.dataset.table> <location>" >&2
  exit 2
fi
project=$1
topic=$2
table=$3
location=$4
timeout_seconds=${TIMEOUT_SECONDS:-180}
poll_seconds=${POLL_SECONDS:-10}
batch="nominal-$(date -u +%Y%m%d%H%M%S)"
work=$(mktemp -d)
producer_dir="$(cd "$(dirname "$0")/../movenow/producteur" && pwd)"

echo "== Publishing batch $batch to $topic"
(cd "$producer_dir" && npm ci --silent --no-audit --no-fund &&
  node producteur.mjs --project "$project" --topic "$topic" --rate 2 --duration 5 --batch "$batch" --out "$work")
expected_file="$work/$batch.jsonl"
expected=$(grep -c . "$expected_file")

query() {
  bq --quiet --headless --format=csv --location="$location" --project_id="$project" \
    query --nouse_legacy_sql "$1"
}
count() {
  query "$1" | tail -n 1
}
filter="WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AND STARTS_WITH(event_id, '$batch-')"

echo "== Waiting for the $expected event_ids in $table"
deadline=$((SECONDS + timeout_seconds))
while :; do
  found=$(count "SELECT COUNT(DISTINCT event_id) FROM \`$table\` $filter")
  echo "$found / $expected"
  if [ "$found" -ge "$expected" ]; then
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "Timed out after ${timeout_seconds}s. Missing event_ids:"
    comm -23 <(sed -E 's/.*"event_id":"([^"]+)".*/\1/' "$expected_file" | sort) \
      <(query "SELECT DISTINCT event_id FROM \`$table\` $filter" | grep -- "^$batch-" | sort)
    exit 1
  fi
  sleep "$poll_seconds"
done

duplicates=$(count "SELECT COUNT(*) - COUNT(DISTINCT event_id) FROM \`$table\` $filter")
echo "All $expected event_ids of $batch reached BigQuery ($duplicates duplicate rows)."
