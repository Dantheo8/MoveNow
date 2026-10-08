# MoveNow, kit de démarrage

Un producteur de positions fictives et un tableau de bord qui montre ce que le pipeline a vraiment écrit : la carte des véhicules, le débit, la dead-letter et la réconciliation des lots. Le kit est un démonstrateur : il sert à vérifier votre infrastructure, il n’est pas évalué.

## Ce qu’il contient

```text
producteur/           Publie des lots cadencés sur Pub/Sub et écrit la liste des événements attendus
tableau/              Tableau de bord, déployable sur Cloud Run en lecture seule
  server.mjs          Routes de l’API et de l’interface
  sources.mjs         Démo en mémoire, émulateur Pub/Sub local ou BigQuery réel
  public/             Interface : carte, débit, flux, dead-letter, réconciliation
docker-compose.yml    Émulateur Pub/Sub, tableau et producteur en continu
```

## Lancer en local

Le plus rapide, sans Docker, sans GCP et sans rien installer : un flux simulé entièrement en mémoire.

```sh
cd tableau
node server.mjs
```

Avec Docker, le flux passe par le vrai émulateur Pub/Sub de Google. Le premier lancement télécharge son image, qui est volumineuse.

```sh
docker compose up --build
```

Ouvrez ensuite http://localhost:8080. Les véhicules bougent sur la carte, quelques messages invalides partent en dead-letter après cinq tentatives. Le bouton « Couper le transfert » imite le retrait du droit d’écriture : la file d’attente grossit, puis se résorbe quand vous rétablissez.

| Rôle | En local | Sur GCP |
| --- | --- | --- |
| Topic et subscriptions | émulateur Pub/Sub | Pub/Sub |
| Transfert vers la table | imité par le tableau (`sources.mjs`) | BigQuery subscription |
| Table analytique | mémoire du tableau | table BigQuery partitionnée sur `event_time` |
| Dead-letter | imitée : cinq essais, puis publication sur le topic d’échec | dead-letter policy de la subscription |
| Listes attendues | volume partagé `lots` | fichiers `.jsonl` à charger dans l’interface |

L’émulateur ne connaît ni IAM, ni les BigQuery subscriptions, ni les métriques de Monitoring. Ce que vous observez en local montre le principe, pas le comportement exact de GCP.

## Passer sur GCP

### Le producteur

Il tourne depuis votre poste ou Cloud Shell, avec ADC. Son identité n’a besoin que de publier sur le topic.

```sh
cd producteur
npm install
node producteur.mjs --project votre-projet --topic positions --rate 1 --duration 10 --batch lot-01
node producteur.mjs --project votre-projet --topic positions --rate 5 --duration 10 --batch lot-02 --invalid 3
```

Chaque lot laisse un fichier `lot-XX.jsonl` : la liste des identifiants attendus. Le débit est plafonné à 100 événements par seconde et la durée à 10 minutes par lot.

### Le contrat de la table

Le producteur envoie du JSON avec ces champs, qui doivent correspondre au schéma de la table quand la subscription écrit avec `use_table_schema` :

| Champ | Type |
| --- | --- |
| `event_id` | STRING |
| `vehicle_id` | STRING |
| `event_time` | TIMESTAMP |
| `latitude` | FLOAT |
| `longitude` | FLOAT |

L’option `--invalid` remplace la latitude par du texte : le topic accepte le message, la table le refuse.

### Le tableau de bord

Il se déploie sur Cloud Run et lit la table en lecture seule. Son identité a besoin de lire la table et de lancer des requêtes, et de s’abonner à la subscription d’inspection si vous voulez voir la dead-letter.

```sh
REGION=europe-west9
PROJECT_ID=votre-projet
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/movenow/tableau:v1"
gcloud builds submit --tag "$IMAGE" tableau
```

| Variable | Rôle |
| --- | --- |
| `SOURCE` | `bigquery` pour lire la vraie table. |
| `BQ_TABLE` | `projet.dataset.table`. |
| `BQ_LOCATION` | La localisation du dataset, par exemple `europe-west9`. |
| `GOOGLE_CLOUD_PROJECT` | Le projet, utile pour les noms courts. |
| `DEAD_LETTER_SUBSCRIPTION` | Facultatif. La subscription d’inspection, lue sans acquitter les messages. |
| `REFRESH_SECONDS` | Intervalle de rafraîchissement, 20 secondes par défaut. |

Chaque rafraîchissement lance quelques petites requêtes filtrées sur la partition. C’est peu, mais pas gratuit : fermez le tableau de bord après la démonstration. Le nombre de messages en attente ne se lit pas dans la table ; sur GCP, regardez `num_undelivered_messages` dans Monitoring.

## La carte du déploiement

En haut de l’interface, l’architecture cible est dessinée bloc par bloc. Chaque bloc s’allume selon ce que l’application constate elle-même, avec la preuve affichée dessous :

| Couleur | Sens |
| --- | --- |
| vert, « prouvé » | l’application l’a vérifié elle-même |
| orange, « à revoir » | ça fonctionne, mais c’est un anti-pattern connu |
| rouge, « en échec » | l’application a essayé et ça ne marche pas |
| pointillés, « pas encore détecté » | rien de visible pour l’instant |
| gris, « à prouver vous-même » | invisible depuis l’application : montrez-le dans la console |
| violet, « simulé en local » | l’équivalent local, en attendant le déploiement |

La carte constate, elle ne note pas : un bloc vert ne dit pas que votre choix est le bon, seulement qu’il est en place.

Pour MoveNow, en mode `bigquery`, le tableau de bord lit :

| Bloc | Comment | Droit nécessaire |
| --- | --- | --- |
| Producteur | positions écrites dans la dernière heure | `roles/bigquery.dataViewer` et `roles/bigquery.jobUser`, déjà nécessaires |
| Table BigQuery | partitionnement et comparaison du schéma au contrat du producteur | idem |
| Topic, BigQuery subscription, dead-letter | configuration de la subscription donnée par `SUBSCRIPTION` | `roles/pubsub.viewer` sur la subscription, facultatif |
| Subscription d’inspection | lecture sans acquittement | `roles/pubsub.subscriber` sur elle |

| Variable | Rôle |
| --- | --- |
| `SUBSCRIPTION` | Facultatif. La subscription de transfert, pour afficher sa configuration sur la carte. |
| `DEMO_PUBLIQUE` | `true` pour les démos hébergées : un transfert coupé se rétablit seul au bout d’une minute. |
