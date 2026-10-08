# Observability

Ce module crée un seul dashboard Cloud Monitoring pour le lab : positions publiées sur le topic, requêtes BigQuery du projet, backlog et état de l'export, transferts en dead-letter, file d'inspection et journaux d'erreur BigQuery. Le graphique de publications compte les messages, même lorsque le producteur les publie en lots. Les requêtes BigQuery et leurs erreurs ne mesurent pas les écritures de positions ; elles peuvent aussi provenir des vérifications manuelles. Le bucket GCS contient l'état Terraform, pas les positions, et n'est donc pas affiché ici.

Une courbe dead-letter sans série signifie qu'aucun transfert n'a été observé sur la période choisie. La file d'inspection à zéro signifie qu'aucun message n'y attend actuellement. Après un essai avec un message invalide, attendre les tentatives de livraison puis quelques minutes pour la remontée des métriques Monitoring.

Il crée quatre alertes : backlog et retard persistants pendant 5 minutes, état d'export non actif, et au moins un transfert dead-letter sur 5 minutes. Les seuils sont des valeurs de départ à ajuster après vos essais. Les canaux de notification doivent déjà exister ; une liste vide crée les incidents sans envoyer de notification.

## Entrées

- `project_id` : projet GCP.
- `topic_id` : sortie `topic_id` de `messaging`.
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
  topic_id   = module.messaging.topic_id
  subscription_ids = {
    export      = module.delivery.export_subscription_id
    dead_letter = module.messaging.dead_letter_subscription
  }
  notification_channels = var.notification_channels
}
```
