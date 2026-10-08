#!/usr/bin/env bash
# Inventory after a destroy: lists the lab resources of a prefix that still exist, and what the
# bootstrap keeps on purpose. Exits 1 if lab resources remain, 2 if something could not be listed.
#   ./scripts/inventory.sh <project> <prefix>
set -uo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <project> <prefix>" >&2
  exit 2
fi
project=$1
prefix=$2
dataset=${prefix//-/_}
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

list_datasets() {
  bq --quiet --headless --format=json ls --project_id="$project" |
    jq -r '.[]?.datasetReference.datasetId' | { grep -x "$dataset" || true; }
}

echo "Lab resources of $prefix in $project:"
check "Pub/Sub topics" gcloud pubsub topics list --project="$project" \
  --filter="name~/topics/$prefix-" --format="value(name)"
check "Pub/Sub subscriptions" gcloud pubsub subscriptions list --project="$project" \
  --filter="name~/subscriptions/$prefix-" --format="value(name)"
check "Service accounts" gcloud iam service-accounts list --project="$project" \
  --filter="email~^$prefix- AND NOT email~-ci-" --format="value(email)"
check "BigQuery datasets" list_datasets

echo
echo "Kept on purpose by the bootstrap: the state bucket, the workload identity pool and these CI accounts:"
gcloud iam service-accounts list --project="$project" --filter="email~^$prefix-ci-" --format="value(email)" |
  sed 's/^/    /'
exit "$status"
