# Module `messaging`

Pub/Sub part of the MoveNow pipeline: the topic the producer publishes to, the main subscription
that delivers positions to BigQuery, the dead-letter path, and the identities allowed to use them.

```text
producer ──publish──▶ <prefix>-positions ──▶ <prefix>-positions-bq ──▶ BigQuery table
                                                   │ after max_delivery_attempts
                                                   ▼
                          <prefix>-positions-dead-letter ──▶ <prefix>-positions-dead-letter-inspection
```

## Delivery modes

| `bigquery_table` | Main subscription | Use |
| --- | --- | --- |
| `null` (default) | Pull subscription | Test the messaging part before the table exists: publish, then pull with `gcloud` |
| `{ project, dataset_id, table_id }` | BigQuery subscription, `use_table_schema = true` | Normal operation. Messages that do not match the table schema are retried, then dead-lettered |

Switching from pull to BigQuery is a change of `bigquery_table` only. Read the plan: it adds the
table permission and updates the subscription.

## Inputs

| Name | Default | Meaning |
| --- | --- | --- |
| `project_id` | required | Project hosting the resources |
| `prefix` | required | Name prefix, 3 to 21 characters, e.g. `g3-movenow` |
| `allowed_persistence_regions` | `[]` | Regions where messages may be stored; empty means no restriction |
| `topic_message_retention_duration` | `86400s` | Topic retention, which allows a subscription to seek back and replay; `null` disables it |
| `message_retention_duration` | `604800s` | Unacknowledged messages kept by the main subscription: the tolerated outage (10 min to 31 days) |
| `ack_deadline_seconds` | `60` | Time to acknowledge before redelivery (10 to 600) |
| `minimum_backoff`, `maximum_backoff` | `10s`, `600s` | Delay between two deliveries of a failing message |
| `max_delivery_attempts` | `5` | Attempts before dead-lettering (5 to 100, counted on a best-effort basis) |
| `dead_letter_message_retention_duration` | `604800s` | How long failed messages wait in the inspection subscription |
| `bigquery_table` | `null` | Destination table, see above |
| `bigquery_write_metadata` | `false` | Also write `subscription_name`, `message_id`, `publish_time`, `attributes`; the table needs these columns |
| `bigquery_drop_unknown_fields` | `false` | Drop fields the table does not know instead of failing the message |
| `producer_impersonators` | `[]` | Members allowed to act as the producer, e.g. `user:first.last@example.com` |

## Outputs

| Name | Used by |
| --- | --- |
| `topic_id`, `topic_name` | Producer (`--topic`) |
| `subscription_id`, `subscription_name` | Backlog and oldest unacked message age alerts |
| `delivery_mode` | `pull` or `bigquery` |
| `dead_letter_topic_id` | Replay procedure |
| `dead_letter_subscription_id`, `dead_letter_subscription_name` | Dead-letter alert, dashboard (`DEAD_LETTER_SUBSCRIPTION`) |
| `producer_service_account_email` | Running the producer |
| `pubsub_service_agent` | Documentation, debugging IAM |

## Permissions granted

| Identity | Role | On | Why |
| --- | --- | --- | --- |
| Pub/Sub service agent | `roles/pubsub.publisher` | Dead-letter topic | Move failed messages there |
| Pub/Sub service agent | `roles/pubsub.subscriber` | Main subscription | Acknowledge the messages it dead-letters |
| Pub/Sub service agent | `roles/bigquery.dataEditor` | Destination table only (BigQuery mode) | Write the positions |
| Producer service account | `roles/pubsub.publisher` | Positions topic only | Publish, nothing else |
| `producer_impersonators` | `roles/iam.serviceAccountTokenCreator` | Producer service account | Run the producer as it, without a key |

Removing the `bigquery.dataEditor` binding is the lab's way to break the transfer on purpose:
messages accumulate in the main subscription until the binding is restored.

## Requirements

- Terraform `>= 1.16.0`, provider `hashicorp/google` `>= 8.6.0, < 9.0.0`.
- APIs enabled by the caller: `pubsub`, `iam`, `cloudresourcemanager`.
- The module has no provider block; labels come from the provider's `default_labels`.
