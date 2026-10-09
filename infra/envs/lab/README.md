# Lab environment

Root module of the lab. It enables the APIs and assembles the modules:

| Module | Builds |
| --- | --- |
| `messaging` | Positions topic, dead-letter topic and inspection subscription, publish right of the producer identity (created by the bootstrap) |
| `analytics` | Dataset `movenow` (`dataset_id`) and the partitioned `positions` table (schema in `infra/schemas/positions.json`) |
| `delivery` | BigQuery subscription from the topic to the table, its dead-letter policy and the Pub/Sub service agent's roles |
| `observability` | Monitoring dashboard and alerts for backlog, delay, export errors and dead-letter messages |

The state lives in the bucket created by `infra/bootstrap` (prefix `lab`), which must be applied
first. The bucket name is given at `init` time.

## Deploy through the CI

Merge into `main`: the `Terraform` workflow validates, plans, waits for an approval in the `lab`
environment, applies the reviewed plan and runs `scripts/nominal-path-test.sh`. The destroy is the
manual `Terraform destroy` workflow. Setup and details: `infra/bootstrap/README.md`.

## Work locally

Locally, plan to check a change; deploy through the CI so every apply is reviewed.

```sh
gcloud auth application-default login       # credentials used by Terraform, no key file
cp ../../../.env.example ../../../.env        # fill it in, then load it:
set -a; source ../../../.env; set +a          # or copy terraform.tfvars.example to terraform.tfvars

terraform init -backend-config="bucket=$TF_STATE_BUCKET"
terraform plan
```

The lock file `.terraform.lock.hcl` is committed. After changing a provider version, refresh it
for every platform the team and the CI use:

```sh
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64 -platform=windows_amd64
```

## Check the pipeline

### Windows: generate a short batch

From the repository root, run `gcloud auth application-default login` once, then:

```powershell
.\scripts\demo-pipeline.ps1
```

The script installs the producer dependencies if needed, publishes 10 valid positions in five
seconds, and polls BigQuery until their `event_id` values appear. It uses the lab's default project,
topic and table names; pass `-ProjectId`, `-Topic`, `-Table` or `-Location` if yours differ. The
generated batch manifest is written to `movenow/producteur/lots/` and ignored by Git. Your ADC
identity needs Pub/Sub Publisher on the topic, and your `gcloud` identity needs BigQuery Data
Viewer on the table plus BigQuery Job User on the project. To publish as the dedicated producer
identity, configure ADC with `gcloud auth application-default login --impersonate-service-account
g3-movenow-producer@<project-id>.iam.gserviceaccount.com` if your account has its Token Creator
role.

For several Monitoring samples, run a **bounded five-minute load** instead:

```powershell
.\scripts\demo-pipeline.ps1 -Rate 5 -Duration 300
```

This publishes 1,500 synthetic positions, then verifies their distinct `event_id` values in
BigQuery. Do not use `-Invalid` for the first load: the dead-letter path is a separate test.
Monitoring samples Pub/Sub metrics roughly once a minute and can display them a few minutes later.

Open the **MoveNow - Flux positions (lab)** dashboard and select the last hour. Pub/Sub metrics can
take a few minutes to appear. The dead-letter charts are expected to stay empty for a valid batch.
To exercise them, run `.\scripts\demo-pipeline.ps1 -Invalid 1`; that one malformed position should
reach the inspection subscription after the configured retries. A successful script run with
`-Invalid 1` only confirms publication and the valid rows in BigQuery; it does not wait for the
dead-letter transfer. The chart of dead-letter transfers can have no time series before that first
transfer, while the inspection backlog shows zero. The BigQuery integration dashboard in the console
is separate from this custom dashboard. The GCS bucket shown elsewhere stores Terraform state and
is not part of the vehicle data pipeline.

To see the **vehicle map and event list** from the kit, start its local reader in a second
PowerShell terminal with `.\scripts\start-tableau.ps1` from the repository root, then open
`http://localhost:8080`. Its throughput chart groups positions into 10-second intervals and reads
the deployed BigQuery table every 10 seconds by default. Pass `-RefreshSeconds 20` to make fewer
BigQuery queries; the chart intervals stay at 10 seconds. Stop it with Ctrl+C after the demonstration. A VM is not required for this lab
demo; if the team later needs a permanently hosted view, the existing `movenow/tableau/Dockerfile`
is intended for Cloud Run.

Run these from this folder. The CI runs the first check automatically after each apply; run it by
hand with:

```sh
../../../scripts/nominal-path-test.sh "$GOOGLE_CLOUD_PROJECT" "$(terraform output -raw topic_name)" \
  "$(terraform output -raw bigquery_table)" "$REGION"
```

**Nominal path and invalid messages, as the producer identity.** Your account must be listed in
`producer_impersonators` of the bootstrap. The batch has 50 events, 3 of them with an invalid latitude.

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

Run the `Terraform destroy` workflow on `main` (type `destroy lab`, then approve), or locally
`terraform destroy`. The positions table can be destroyed because `table_deletion_protection` is
`false` in the lab. APIs stay enabled (`disable_on_destroy = false`) and the bootstrap is kept. List
what remains:

```sh
../../../scripts/inventory.sh "$GOOGLE_CLOUD_PROJECT" "$PREFIX" movenow
```
