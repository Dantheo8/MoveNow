# Module `messaging`

Pub/Sub entry point of the MoveNow pipeline: the topic the producer publishes to, the dead-letter
topic with its inspection subscription, and the producer identity. The subscription that writes
to BigQuery belongs to the `delivery` module, which plugs into the outputs of this one.

```text
producer ──publish──▶ <prefix>-positions ──▶ (delivery: BigQuery subscription) ──▶ BigQuery
                                                     │ after max_delivery_attempts
                                                     ▼
                       <prefix>-positions-dead-letter ──▶ <prefix>-positions-dead-letter-inspection
```

## Inputs

| Name | Default | Meaning |
| --- | --- | --- |
| `project_id` | required | Project hosting the resources |
| `prefix` | required | Name prefix, 3 to 21 characters, e.g. `g3-movenow` |
| `allowed_persistence_regions` | `[]` | Regions where messages may be stored; empty means no restriction |
| `topic_message_retention_duration` | `86400s` | Topic retention, which lets a subscription seek back and replay; `null` disables it |
| `dead_letter_message_retention_duration` | `604800s` | How long failed messages wait in the inspection subscription (10 min to 31 days) |
| `producer_impersonators` | `[]` | Members allowed to act as the producer, e.g. `user:first.last@example.com` |

## Outputs

| Name | Used by |
| --- | --- |
| `topic_id` | `delivery` (`topic_id`) |
| `topic_name` | Producer (`--topic`) |
| `dead_letter_topic_id` | `delivery` (`dead_letter_topic_id`), replay procedure |
| `dead_letter_subscription_id`, `dead_letter_subscription_name` | Dead-letter alert, dashboard (`DEAD_LETTER_SUBSCRIPTION`) |
| `producer_service_account_email` | Running the producer |
| `pubsub_service_agent_email` | `delivery` (`service_agent`). Resolved after the topics exist, so the agent is provisioned before it gets any role |

## Permissions granted

| Identity | Role | On | Why |
| --- | --- | --- | --- |
| Producer service account | `roles/pubsub.publisher` | Positions topic only | Publish, nothing else |
| `producer_impersonators` | `roles/iam.serviceAccountTokenCreator` | Producer service account | Run the producer as it, without a key |

The Pub/Sub service agent's roles (write to the table, publish to the dead-letter topic,
acknowledge on the source subscription) are granted by `delivery`.

## Requirements

- Terraform `>= 1.16.0`, provider `hashicorp/google` `>= 8.6.0, < 9.0.0`.
- APIs enabled by the caller: `pubsub`, `iam`, `cloudresourcemanager`.
- The module has no provider block; labels come from the provider's `default_labels`.
