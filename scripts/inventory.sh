#!/usr/bin/env bash
# Inventory after a destroy: lists the lab resources that still exist.
# Exits 1 if some remain, 2 if something could not be listed.
#   ./scripts/inventory.sh <project> <prefix> [dataset, default movenow]
set -uo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <project> <prefix> [dataset]" >&2
  exit 2
fi
project=$1
prefix=$2
dataset=${3:-movenow}
status=0

check() {
  local label=$1
  shift
  local items
  if ! items=$("$@"); then
    echo "- $label: could not be listed"
    status=2
  elif [ -n "$items" ]; then
    echo "- $label: still present"
    echo "$items" | sed 's/^/    /'
    if [ "$status" -eq 0 ]; then status=1; fi
  else
    echo "- $label: none"
  fi
}

list_dataset() {
  bq --quiet --headless --format=json ls --project_id="$project" |
    jq -r '.[]?.datasetReference.datasetId' | { grep -x "$dataset" || true; }
}

echo "Lab resources of $prefix in $project:"
check "Pub/Sub topics" gcloud pubsub topics list --project="$project" \
  --filter="name~/topics/$prefix-" --format="value(name)"
check "Pub/Sub subscriptions" gcloud pubsub subscriptions list --project="$project" \
  --filter="name~/subscriptions/$prefix-" --format="value(name)"
check "BigQuery dataset $dataset" list_dataset
echo
echo "Kept on purpose by the bootstrap: the state bucket, the workload identity pool, the CI and producer service accounts."
exit "$status"
