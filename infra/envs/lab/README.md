# Lab environment

Root module of the lab. It enables the APIs and assembles the modules:

| Module | Builds |
| --- | --- |
| `messaging` | Positions topic, dead-letter topic and inspection subscription, producer identity |
| `analytics` | Dataset `<prefix with underscores>` and the partitioned `positions` table (schema in `infra/schemas/positions.json`) |
| `delivery` | BigQuery subscription from the topic to the table, its dead-letter policy and the Pub/Sub service agent's roles |

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

## Check the pipeline

Run these from this folder.

**Nominal path and invalid messages, as the producer identity.** Your account must be listed in
`producer_impersonators`. The batch has 50 events, 3 of them with an invalid latitude.

```sh
TOPIC=$(terraform output -raw topic_name)
PRODUCER_SA=$(terraform output -raw producer_service_account_email)

gcloud auth application-default login --impersonate-service-account="$PRODUCER_SA"
(cd ../../../movenow/producteur && npm ci && \
  node producteur.mjs --project "$GOOGLE_CLOUD_PROJECT" --topic "$TOPIC" --rate 5 --duration 10 \
    --batch lot-01 --invalid 3)
gcloud auth application-default login         # back to your own identity
```

The 47 valid events reach the table within seconds:

```sql
SELECT event_id, COUNT(*) AS copies
FROM `<bigquery_table output>`
WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND STARTS_WITH(event_id, 'lot-01-')
GROUP BY event_id;
```

The 3 invalid ones reach the inspection subscription after `max_delivery_attempts` failed writes,
a few minutes later. Pub/Sub counts the attempts on a best-effort basis: note how many it took.

```sh
jq -r 'select(.invalide) | .event_id' ../../../movenow/producteur/lot-01.jsonl
gcloud pubsub subscriptions pull "$(terraform output -raw dead_letter_subscription_name)" --limit=10 \
  --format="value(message.data)" | jq -r .event_id
```

**Negative test: the producer cannot publish anywhere else.** Expect `PERMISSION_DENIED`.

```sh
gcloud pubsub topics publish "$PREFIX-positions-dead-letter" --message=test \
  --impersonate-service-account="$PRODUCER_SA"
```

## Destroy

```sh
terraform destroy
```

The `analytics` table has `deletion_protection = true`: set it to `false` and apply before
destroying, otherwise the destroy stops at the table. APIs stay enabled
(`disable_on_destroy = false`). List what remains afterwards:

```sh
gcloud pubsub topics list --filter="name~$PREFIX"
gcloud pubsub subscriptions list --filter="name~$PREFIX"
gcloud iam service-accounts list --filter="email~$PREFIX"
bq ls --project_id="$GOOGLE_CLOUD_PROJECT"
```
