# Runbook

Names: subscription `g3-movenow-positions-bq`, inspection `g3-movenow-positions-dead-letter-inspection`,
topic `g3-movenow-positions`, table `groupe3inssettp.movenow.positions`.

## Alerts

Recipient: the channels in `notification_channels`. The list is empty for now, so incidents only
appear in Cloud Monitoring.

| Alert | Metric and filter | Window | Threshold | First action |
| --- | --- | --- | --- | --- |
| Backlog | `subscription/num_undelivered_messages`, BigQuery subscription | 5 min | > 100 | Check the export state below. If it is ACTIVE, it is a burst: watch the backlog go down |
| Delay | `subscription/oldest_unacked_message_age`, BigQuery subscription | 5 min | > 300 s | Same as backlog. If only one message is old, it is probably failing: check the dead letters |
| Export error | `subscription/export_push_subscription_details`, state not ACTIVE | 1 min | > 0 | `gcloud pubsub subscriptions describe g3-movenow-positions-bq --format='value(state)'`, then check that the table exists and that the service agent still has `bigquery.dataEditor` on it |
| Dead letter | `subscription/dead_letter_message_count`, BigQuery subscription | 5 min | > 0 | Read the failed messages (procedure B) and find the invalid field |

## A. Return to service after an export error

1. Find the cause: missing table, or missing write permission for the service agent.
2. Restore the expected state with Terraform, not by hand: run `terraform plan` to see the drift,
   then deploy through the CI. If you changed something by hand to diagnose, the next apply undoes it.
3. Watch the backlog drop to 0 on the dashboard. Note the drain time.
4. Nothing is lost if the outage lasted less than 7 days.

## B. Fix and replay dead letters

```sh
# 1. Save the failed messages, then remove them from the inspection subscription
gcloud pubsub subscriptions pull g3-movenow-positions-dead-letter-inspection \
  --limit=100 --auto-ack --format=json > dead-letters.json

# 2. Read them and fix each payload (keep the same event_id)
jq -r '.[].message.data | @base64d' dead-letters.json

# 3. Republish each fixed message
gcloud pubsub topics publish g3-movenow-positions --message='<fixed JSON>'
```

Keep `dead-letters.json` until the replayed rows are in BigQuery. It contains positions: do not
commit it.

## C. Replay everything since a given time

The topic keeps messages for 1 day. Rewinding the subscription delivers them again:

```sh
gcloud pubsub subscriptions seek g3-movenow-positions-bq --time=2026-10-09T10:00:00Z
```

Every message after that time is written again, so expect duplicates (procedure D).

## D. Find and ignore duplicates

Delivery is at least once, and a replay always creates duplicates. Count them by `event_id`:

```sql
SELECT event_id, COUNT(*) AS copies
FROM `groupe3inssettp.movenow.positions`
WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
GROUP BY event_id
HAVING copies > 1;
```

Query without them by keeping one row per `event_id`:

```sql
SELECT *
FROM `groupe3inssettp.movenow.positions`
WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
QUALIFY ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY event_time) = 1;
```

## E. Check after a destroy

```sh
./scripts/inventory.sh groupe3inssettp g3-movenow movenow
```

Exit code 0: nothing left. 1: resources remain (listed). 2: something could not be listed.
