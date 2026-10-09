# Module `delivery`

The BigQuery subscription: it reads the positions topic and writes each message to the table.
Google runs the writer, so there is no consumer code. The table schema decides which messages are
valid. A message that fails `max_delivery_attempts` times moves to the dead-letter topic.

## Inputs

| Name | Default | Meaning |
| --- | --- | --- |
| `project_id` | required | Project of the subscription |
| `subscription_name` | `positions-vers-bigquery` | The lab uses `<prefix>-positions-bq` |
| `topic_id` | required | Source topic, `projects/P/topics/T` (from `messaging`) |
| `table_id` | required | Destination, `P.D.T` (from `analytics`) |
| `dead_letter_topic_id` | required | From `messaging` |
| `service_agent` | required | Pub/Sub service agent email (from `messaging`) |
| `message_retention_duration` | `604800s` | Unacknowledged messages are kept 7 days: the tolerated outage |
| `retry_minimum_backoff`, `retry_maximum_backoff` | `10s`, `600s` | Delay between two attempts |
| `max_delivery_attempts` | `5` | Attempts before the dead letter (5 to 100) |

The subscription never expires, even with no activity.

## Outputs

| Name | Used by |
| --- | --- |
| `export_subscription_id` | `observability` (alerts), the lab outputs |
| `writer_identity` | Documentation of the IAM member that writes |

## Permissions granted to the Pub/Sub service agent

| Role | On | Why |
| --- | --- | --- |
| `bigquery.dataEditor` | The table only | Write the rows |
| `pubsub.publisher` | The dead-letter topic | Move failed messages |
| `pubsub.subscriber` | This subscription | Remove a moved message from the source |

Removing the first binding stops all writes: messages accumulate until it comes back. This is the
lab's outage experiment.
