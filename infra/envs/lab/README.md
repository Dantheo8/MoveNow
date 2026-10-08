# Lab environment

Root module of the lab. It enables the APIs and assembles the modules (only `messaging` for now).

State is local until the bootstrap creates the state bucket. Then add this block inside
`terraform { }` in `versions.tf` and run `terraform init -migrate-state`:

```hcl
backend "gcs" {
  bucket = "<state-bucket>"
  prefix = "lab"
}
```

## Deploy

```sh
gcloud auth application-default login       # credentials used by Terraform, no key file
cp ../../../.env.example ../../../.env        # fill it in, then load it:
set -a; source ../../../.env; set +a          # or copy terraform.tfvars.example to terraform.tfvars

terraform init
terraform plan -out=lab.tfplan                # read it before applying
terraform apply lab.tfplan
terraform plan                                # must print "No changes": no drift
```

The lock file `.terraform.lock.hcl` is committed. After changing a provider version, refresh it
for every platform the team and the CI use:

```sh
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64 -platform=windows_amd64
```

## Check the messaging part

Start from an empty main subscription. Run these from this folder.

**Nominal path, as the producer identity.** Your account must be listed in
`producer_impersonators`.

```sh
TOPIC=$(terraform output -raw topic_name)
PRODUCER_SA=$(terraform output -raw producer_service_account_email)

gcloud auth application-default login --impersonate-service-account="$PRODUCER_SA"
(cd ../../../movenow/producteur && npm ci && \
  node producteur.mjs --project "$GOOGLE_CLOUD_PROJECT" --topic "$TOPIC" --rate 1 --duration 10 --batch lot-01)
gcloud auth application-default login         # back to your own identity

# Pull mode only: read the messages back and compare with movenow/producteur/lot-01.jsonl
gcloud pubsub subscriptions pull "$(terraform output -raw subscription_name)" --limit=20 --auto-ack \
  --format="value(message.data)" | jq -r .event_id | sort
```

**Negative test: the producer cannot publish anywhere else.** Expect `PERMISSION_DENIED`.

```sh
gcloud pubsub topics publish "$PREFIX-positions-dead-letter" --message=test \
  --impersonate-service-account="$(terraform output -raw producer_service_account_email)"
```

**Dead-letter path, in pull mode.** Publish one message, refuse it more than
`max_delivery_attempts` times, then find it in the inspection subscription. Pub/Sub counts the
attempts on a best-effort basis: note how many it actually took.

```sh
SUB=$(terraform output -raw subscription_name)
gcloud pubsub topics publish "$(terraform output -raw topic_name)" --message='{"event_id":"dl-test-1"}'
for attempt in 1 2 3 4 5 6 7; do
  ACK=$(gcloud pubsub subscriptions pull "$SUB" --limit=1 --format='value(ackId)')
  [ -n "$ACK" ] && gcloud pubsub subscriptions modify-message-ack-deadline "$SUB" --ack-ids="$ACK" --ack-deadline=0
  sleep 15
done
gcloud pubsub subscriptions pull "$(terraform output -raw dead_letter_subscription_name)" --limit=5 --auto-ack
```

## Switch to BigQuery delivery

Once the table exists, set `bigquery_table` in `terraform.tfvars`:

```hcl
bigquery_table = {
  project    = "your-project"
  dataset_id = "g3_movenow"
  table_id   = "positions"
}
```

Then `terraform plan`: it adds the table permission for the Pub/Sub service agent and updates the
subscription. Apply, publish a batch, and look for its `event_id`s in the table.

## Destroy

```sh
terraform destroy
```

APIs stay enabled (`disable_on_destroy = false`). List what remains afterwards:

```sh
gcloud pubsub topics list --filter="name~$PREFIX"
gcloud pubsub subscriptions list --filter="name~$PREFIX"
gcloud iam service-accounts list --filter="email~$PREFIX"
```
