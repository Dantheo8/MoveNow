# Module analytics

## Responsabilité
Créer le dataset et la table BigQuery qui stockent les positions
des véhicules, avec leur schéma, leur partitionnement et leur expiration.

## Entrées prévues
- project_id : identifiant du projet GCP.
- location : emplacement du dataset.
- dataset_id : nom du dataset.
- table_id : nom de la table.
- schema : schéma JSON de la table.
- partition_field : champ utilisé pour le partitionnement.
- retention_days : durée de conservation des partitions en jours.
- labels : étiquettes des ressources.
- deletion_protection : empêche la suppression de la table par Terraform (true par défaut).

## Sorties prévues
- dataset_id : identifiant du dataset créé.
- table_id : identifiant de la table créée.
- table_full_id : nom complet au format projet.dataset.table.

## Dépendances
Le projet GCP doit exister et l’API BigQuery doit être activée.

## Intégration
Le module racine transmet table_full_id au module delivery,
qui configure l’alimentation de la table depuis Pub/Sub.