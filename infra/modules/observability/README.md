# Observability

Ce module crée un dashboard Cloud Monitoring pour la subscription Pub/Sub qui exporte vers BigQuery : backlog, âge du plus ancien message, état de l'export et messages transférés en dead-letter. Il montre aussi les messages en attente dans la subscription d'inspection dead-letter.

Il crée quatre alertes : backlog et retard persistants pendant 5 minutes, état d'export non actif, et au moins un transfert dead-letter sur 5 minutes. Les seuils sont des valeurs de départ à ajuster après vos essais. Les canaux de notification doivent déjà exister ; une liste vide crée les incidents sans envoyer de notification.

## Entrées

- `project_id` : projet GCP.
- `subscription_ids.export` : sortie `export_subscription_id` de `delivery`.
- `subscription_ids.dead_letter` : sortie `dead_letter_subscription` de `messaging`.
- `backlog_threshold`, `oldest_message_age_threshold_seconds`, `dead_letter_threshold` : seuils.
- `notification_channels` : noms complets des canaux Monitoring existants.

## Sorties

`dashboard_id` et `alert_policy_ids` permettent de retrouver les ressources créées. Le module ne crée aucune subscription ni canal de notification.

Exemple d'assemblage dans un module racine :

```hcl
module "observability" {
  source     = "../../modules/observability"
  project_id = var.project_id
  subscription_ids = {
    export      = module.delivery.export_subscription_id
    dead_letter = module.messaging.dead_letter_subscription
  }
  notification_channels = var.notification_channels
}
```
