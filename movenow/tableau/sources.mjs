// Sources de données du tableau de bord MoveNow. Trois modes :
//   demo        aucune variable : un flux simulé en mémoire, sans GCP ni Docker
//   emulateur   PUBSUB_EMULATOR_HOST défini : l'émulateur Pub/Sub local, avec une imitation
//               de la BigQuery subscription et de la dead-letter policy
//   bigquery    SOURCE=bigquery : lecture de la vraie table BigQuery sur GCP
import fs from 'node:fs';
import path from 'node:path';
import { bloc, blocCloudRun, blocIdentite, enCache } from './gcp.mjs';

const MAX_TENTATIVES = Number(process.env.MAX_DELIVERY_ATTEMPTS || 5);
const log = (severity, message, extra = {}) => console.log(JSON.stringify({ severity, message, ...extra }));

// Le contrat de la table : les mêmes contrôles que BigQuery quand la subscription écrit avec use_table_schema.
export function valider(data) {
  let event;
  try {
    event = JSON.parse(data);
  } catch {
    return { erreur: 'JSON illisible' };
  }
  if (!event || typeof event !== 'object') return { erreur: 'message vide' };
  if (typeof event.event_id !== 'string' || !event.event_id) return { erreur: 'event_id manquant' };
  if (typeof event.vehicle_id !== 'string' || !event.vehicle_id) return { erreur: 'vehicle_id manquant', event };
  if (typeof event.event_time !== 'string' || Number.isNaN(Date.parse(event.event_time))) return { erreur: 'event_time n’est pas un TIMESTAMP', event };
  for (const champ of ['latitude', 'longitude']) {
    if (typeof event[champ] !== 'number' || !Number.isFinite(event[champ])) return { erreur: `${champ} n’est pas un FLOAT`, event };
  }
  return { event };
}

const lireJson = (texte) => { try { return JSON.parse(texte); } catch { return null; } };

// Une « table » en mémoire, partagée par les modes demo et emulateur.
class TableLocale {
  constructor() {
    this.lignes = [];
    this.parId = new Map();
    this.derniers = new Map();
    this.deadLetter = [];
    this.idsDeadLetter = new Set();
    this.recus = 0;
    this.debit = [];
    this.depuisDernierPoint = 0;
    setInterval(() => {
      this.debit.push({ t: Date.now(), n: this.depuisDernierPoint });
      this.depuisDernierPoint = 0;
      if (this.debit.length > 60) this.debit.shift();
    }, 2000).unref();
  }
  ecrire(event) {
    const ligne = { ...event, ingere_le: new Date().toISOString() };
    this.lignes.push(ligne);
    if (this.lignes.length > 20000) this.lignes.splice(0, this.lignes.length - 20000);
    this.parId.set(event.event_id, (this.parId.get(event.event_id) || 0) + 1);
    this.derniers.set(event.vehicle_id, ligne);
    this.recus += 1;
    this.depuisDernierPoint += 1;
  }
  mettreDeCote(entree) {
    this.deadLetter.unshift(entree);
    if (this.deadLetter.length > 200) this.deadLetter.pop();
    if (entree.event_id) this.idsDeadLetter.add(entree.event_id);
  }
  positions() {
    return [...this.derniers.values()].map(({ vehicle_id, latitude, longitude, event_time }) => ({ vehicle_id, latitude, longitude, event_time }));
  }
  evenements() {
    return this.lignes.slice(-25).reverse();
  }
  lot(nom) {
    const prefixe = `${nom}-`;
    const recus = {};
    for (const [id, n] of this.parId) if (id.startsWith(prefixe)) recus[id] = n;
    return { recus, dead_letter: [...this.idsDeadLetter].filter((id) => id.startsWith(prefixe)) };
  }
  nomsDeLots() {
    const noms = new Set();
    for (const id of this.parId.keys()) noms.add(id.replace(/-\d{6}$/, ''));
    return [...noms].reverse().slice(0, 20);
  }
}

// Mode demo : un producteur et une imitation du transfert, tout en mémoire.
function sourceDemo() {
  const table = new TableLocale();
  const file = [];
  const lots = new Map();
  let actif = true;
  let publies = 0;
  let numeroLot = 0;
  let lot = null;
  const flotte = Array.from({ length: 20 }, () => ({ lat: 49.82 + Math.random() * 0.06, lon: 3.25 + Math.random() * 0.08 }));

  // Cinq événements par seconde, par lots d'une minute, avec un message invalide par lot.
  setInterval(() => {
    if (!lot || lot.seq >= 300) {
      numeroLot += 1;
      lot = { nom: `lot-demo-${String(numeroLot).padStart(3, '0')}`, seq: 0, attendus: [], invalide: 1 + Math.floor(Math.random() * 300) };
      lots.set(lot.nom, lot.attendus);
      if (lots.size > 10) lots.delete(lots.keys().next().value);
    }
    lot.seq += 1;
    const n = lot.seq % flotte.length;
    const v = flotte[n];
    v.lat = Math.min(49.88, Math.max(49.82, v.lat + (Math.random() - 0.5) * 0.002));
    v.lon = Math.min(3.33, Math.max(3.25, v.lon + (Math.random() - 0.5) * 0.003));
    const event = {
      event_id: `${lot.nom}-${String(lot.seq).padStart(6, '0')}`,
      vehicle_id: `vh-${String(n).padStart(4, '0')}`,
      event_time: new Date().toISOString(),
      latitude: Number(v.lat.toFixed(5)),
      longitude: Number(v.lon.toFixed(5)),
    };
    const invalide = lot.seq === lot.invalide;
    if (invalide) event.latitude = 'nord';
    lot.attendus.push({ event_id: event.event_id, invalide });
    file.push({ data: JSON.stringify(event), tentatives: 0 });
    publies += 1;
  }, 200).unref();

  // Le transfert traite au plus vingt messages toutes les 200 ms : le rattrapage reste visible.
  setInterval(() => {
    if (!actif) return;
    for (let i = 0; i < 20 && file.length; i++) {
      const message = file.shift();
      const resultat = valider(message.data);
      if (!resultat.erreur) { table.ecrire(resultat.event); continue; }
      message.tentatives += 1;
      if (message.tentatives < MAX_TENTATIVES) { file.push(message); continue; }
      table.mettreDeCote({ event_id: resultat.event?.event_id || null, erreur: resultat.erreur, tentatives: message.tentatives, recu_le: new Date().toISOString(), extrait: message.data.slice(0, 160) });
    }
  }, 200).unref();

  return {
    mode: 'demo',
    libelle: 'Démo en mémoire',
    pret: Promise.resolve(),
    async etat() {
      return { compteurs: { recus: table.recus, dead_letter: table.deadLetter.length, en_attente: file.length, publies }, debit: table.debit, pas_secondes: 2, transfert: { pilotable: true, actif } };
    },
    async positions() { return table.positions(); },
    async evenements() { return table.evenements(); },
    async deadLetter() { return table.deadLetter.slice(0, 30); },
    async lots() { return [...lots.keys()].reverse().map((nom) => ({ nom, attendus: lots.get(nom).length })); },
    async lot(nom) { return { nom, attendus: lots.get(nom) || null, ...table.lot(nom) }; },
    async piloter(etat) { actif = etat; return { actif }; },
    async deploiement() {
      return { plateforme: 'local', blocs: [
        bloc('producteur', 'Producteur', 'simule', 'producteur intégré au tableau, cinq positions par seconde'),
        bloc('topic', 'Topic Pub/Sub', 'simule', 'file en mémoire'),
        bloc('subscription', 'Transfert vers la table', 'simule', actif ? 'transfert imité, actif' : 'transfert imité, coupé'),
        bloc('deadletter', 'Dead-letter', 'simule', `${table.deadLetter.length} message(s) mis de côté après ${MAX_TENTATIVES} essais`),
        bloc('inspection', 'Subscription d’inspection', 'simule', 'liste affichée dans le tableau'),
        bloc('table', 'Table BigQuery', 'simule', `${table.recus} positions en mémoire`),
        blocCloudRun('Tableau de bord sur Cloud Run'),
        bloc('identite', 'Identité du tableau', 'simule', 'pas de compte de service en local'),
        bloc('obs', 'Monitoring et alertes', 'manuel', 'backlog, âge du plus ancien message et alertes : à montrer dans Monitoring'),
      ] };
    },
  };
}

// Mode emulateur : vrai Pub/Sub local. L'émulateur ne sait pas écrire dans BigQuery ni appliquer
// une dead-letter policy : ce module les imite, pour que le flux se comporte comme sur GCP.
async function sourceEmulateur(env) {
  const { PubSub } = await import('@google-cloud/pubsub');
  const pubsub = new PubSub({ projectId: env.PUBSUB_PROJECT_ID || 'movenow-local' });
  const noms = {
    topic: env.TOPIC || 'positions',
    subscription: env.SUBSCRIPTION || 'positions-vers-bigquery',
    deadLetterTopic: env.DEAD_LETTER_TOPIC || 'positions-dead-letter',
    inspection: env.DEAD_LETTER_SUBSCRIPTION || 'positions-dead-letter-inspection',
  };
  const dossierLots = env.LOTS_DIR || '/lots';
  const table = new TableLocale();
  const tentatives = new Map();
  let abonnement = null;

  // Crée les ressources si elles n'existent pas encore (code 6 : ALREADY_EXISTS).
  const assurer = async (creer) => { try { await creer(); } catch (error) { if (error.code !== 6) throw error; } };
  async function initialiser() {
    await assurer(() => pubsub.createTopic(noms.topic));
    await assurer(() => pubsub.createTopic(noms.deadLetterTopic));
    await assurer(() => pubsub.topic(noms.topic).createSubscription(noms.subscription, { ackDeadlineSeconds: 10 }));
    await assurer(() => pubsub.topic(noms.deadLetterTopic).createSubscription(noms.inspection));
    ouvrir();
    pubsub.subscription(noms.inspection).on('message', (message) => {
      const event = lireJson(message.data.toString());
      table.mettreDeCote({
        event_id: event?.event_id || null,
        erreur: message.attributes.erreur || 'inconnue',
        tentatives: Number(message.attributes.tentatives) || null,
        recu_le: new Date().toISOString(),
        extrait: message.data.toString().slice(0, 160),
      });
      message.ack();
    });
    log('INFO', 'topics et subscriptions prêts dans l’émulateur', noms);
  }
  // L'émulateur peut mettre quelques secondes à répondre : on réessaie pendant une minute.
  const pret = (async () => {
    for (let essai = 1; ; essai++) {
      try {
        return await initialiser();
      } catch (error) {
        if (essai >= 30) throw error;
        log('WARNING', `émulateur pas encore prêt : ${error.message}`);
        await new Promise((resolve) => setTimeout(resolve, 2000));
      }
    }
  })();

  function ouvrir() {
    const deadLetterTopic = pubsub.topic(noms.deadLetterTopic);
    abonnement = pubsub.subscription(noms.subscription, { flowControl: { maxMessages: 500 } });
    abonnement.on('message', async (message) => {
      const resultat = valider(message.data.toString());
      if (!resultat.erreur) {
        table.ecrire(resultat.event);
        tentatives.delete(message.id);
        message.ack();
        return;
      }
      const n = (tentatives.get(message.id) || 0) + 1;
      tentatives.set(message.id, n);
      if (n < MAX_TENTATIVES) { message.nack(); return; }
      tentatives.delete(message.id);
      await deadLetterTopic.publishMessage({ data: message.data, attributes: { erreur: resultat.erreur, tentatives: String(n), source: noms.subscription } });
      message.ack();
    });
    abonnement.on('error', (error) => log('ERROR', error.message, { code: error.code }));
  }

  function lireAttendus(nom) {
    const fichier = path.join(dossierLots, `${nom}.jsonl`);
    if (!/^[\w-]+$/.test(nom) || !fs.existsSync(fichier)) return null;
    return fs.readFileSync(fichier, 'utf8').trim().split('\n').map(lireJson).filter(Boolean).map(({ event_id, invalide }) => ({ event_id, invalide }));
  }

  return {
    mode: 'emulateur',
    libelle: 'Émulateur Pub/Sub local',
    pret,
    async etat() {
      const progression = fs.existsSync(path.join(dossierLots, 'progression.json')) ? lireJson(fs.readFileSync(path.join(dossierLots, 'progression.json'), 'utf8')) : null;
      const publies = progression?.publies ?? null;
      const enAttente = publies === null ? null : Math.max(0, publies - table.recus - table.deadLetter.length);
      return { compteurs: { recus: table.recus, dead_letter: table.deadLetter.length, en_attente: enAttente, publies }, debit: table.debit, pas_secondes: 2, transfert: { pilotable: true, actif: Boolean(abonnement) } };
    },
    async positions() { return table.positions(); },
    async evenements() { return table.evenements(); },
    async deadLetter() { return table.deadLetter.slice(0, 30); },
    async lots() {
      const fichiers = fs.existsSync(dossierLots) ? fs.readdirSync(dossierLots).filter((f) => f.endsWith('.jsonl')).map((f) => f.slice(0, -6)) : [];
      const noms = [...new Set([...table.nomsDeLots(), ...fichiers])].sort().reverse().slice(0, 20);
      return noms.map((nom) => ({ nom, attendus: lireAttendus(nom)?.length ?? null }));
    },
    async lot(nom) { return { nom, attendus: lireAttendus(nom), ...table.lot(nom) }; },
    async deploiement() {
      const progression = fs.existsSync(path.join(dossierLots, 'progression.json')) ? lireJson(fs.readFileSync(path.join(dossierLots, 'progression.json'), 'utf8')) : null;
      const recent = progression && Date.now() - Date.parse(progression.maj) < 10000;
      return { plateforme: 'local', blocs: [
        bloc('producteur', 'Producteur', 'simule', recent ? `conteneur producteur actif, lot ${progression.lot}` : 'aucune publication récente du conteneur producteur'),
        bloc('topic', 'Topic Pub/Sub', 'simule', `émulateur Pub/Sub, topic ${noms.topic}`),
        bloc('subscription', 'Transfert vers la table', 'simule', `subscription ${noms.subscription}, transfert imité ${abonnement ? 'actif' : 'coupé'}`),
        bloc('deadletter', 'Dead-letter', 'simule', `topic ${noms.deadLetterTopic}, ${MAX_TENTATIVES} essais imités`),
        bloc('inspection', 'Subscription d’inspection', 'simule', `${noms.inspection}, ${table.deadLetter.length} message(s) reçu(s)`),
        bloc('table', 'Table BigQuery', 'simule', `${table.recus} positions en mémoire`),
        blocCloudRun('Tableau de bord sur Cloud Run'),
        bloc('identite', 'Identité du tableau', 'simule', 'pas de compte de service en local'),
        bloc('obs', 'Monitoring et alertes', 'manuel', 'backlog, âge du plus ancien message et alertes : à montrer dans Monitoring'),
      ] };
    },
    // Couper le transfert imite le retrait du droit d'écriture : les messages s'accumulent dans Pub/Sub.
    async piloter(actif) {
      if (actif && !abonnement) ouvrir();
      if (!actif && abonnement) { await abonnement.close(); abonnement = null; }
      return { actif: Boolean(abonnement) };
    },
  };
}

// Mode bigquery : lecture seule de la table réelle, rafraîchie toutes les REFRESH_SECONDS secondes.
// Chaque rafraîchissement lance quelques petites requêtes filtrées sur la partition.
async function sourceBigQuery(env) {
  const { BigQuery } = await import('@google-cloud/bigquery');
  if (!/^[\w-]+\.[\w-]+\.[\w-]+$/.test(env.BQ_TABLE || '')) throw new Error('BQ_TABLE doit être de la forme projet.dataset.table');
  const bigquery = new BigQuery(env.GOOGLE_CLOUD_PROJECT ? { projectId: env.GOOGLE_CLOUD_PROJECT } : {});
  const table = `\`${env.BQ_TABLE}\``;
  const requete = async (query, params = {}) => (await bigquery.query({ query, params, location: env.BQ_LOCATION || undefined }))[0];
  const valeur = (v) => (v && typeof v === 'object' && 'value' in v ? v.value : v);
  const cache = { compteurs: { recus: 0, dead_letter: null, en_attente: null, publies: null }, debit: [], positions: [], evenements: [], deadLetter: [], erreur: null };

  let lireDeadLetter = async () => [];
  if (env.DEAD_LETTER_SUBSCRIPTION) {
    // Lecture sans acquittement : les messages sont aussitôt rendus à la subscription d'inspection.
    const { v1 } = await import('@google-cloud/pubsub');
    const client = new v1.SubscriberClient();
    const subscription = env.DEAD_LETTER_SUBSCRIPTION.includes('/') ? env.DEAD_LETTER_SUBSCRIPTION : `projects/${env.GOOGLE_CLOUD_PROJECT}/subscriptions/${env.DEAD_LETTER_SUBSCRIPTION}`;
    lireDeadLetter = async () => {
      const [reponse] = await client.pull({ subscription, maxMessages: 20 });
      const messages = reponse.receivedMessages || [];
      if (messages.length) await client.modifyAckDeadline({ subscription, ackIds: messages.map((m) => m.ackId), ackDeadlineSeconds: 0 });
      return messages.map(({ message }) => {
        const data = Buffer.from(message.data || '').toString();
        return {
          event_id: lireJson(data)?.event_id || null,
          erreur: 'voir les journaux de la subscription',
          tentatives: Number(message.attributes?.CloudPubSubDeadLetterSourceDeliveryCount) || null,
          recu_le: message.publishTime ? new Date(Number(message.publishTime.seconds) * 1000).toISOString() : null,
          extrait: data.slice(0, 160),
        };
      });
    };
  }

  async function rafraichir() {
    try {
      const [compte] = await requete(`SELECT COUNT(*) AS recus FROM ${table} WHERE event_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)`);
      const debit = await requete(`SELECT UNIX_SECONDS(TIMESTAMP_TRUNC(event_time, MINUTE)) AS t, COUNT(*) AS n FROM ${table}
        WHERE event_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 MINUTE) GROUP BY t ORDER BY t`);
      const positions = await requete(`SELECT vehicle_id, latitude, longitude, event_time FROM ${table}
        WHERE event_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
        QUALIFY ROW_NUMBER() OVER (PARTITION BY vehicle_id ORDER BY event_time DESC) = 1`);
      const evenements = await requete(`SELECT event_id, vehicle_id, event_time, latitude, longitude FROM ${table}
        WHERE event_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) ORDER BY event_time DESC LIMIT 25`);
      try {
        cache.deadLetter = await lireDeadLetter();
        cache.erreurDeadLetter = null;
      } catch (error) {
        cache.erreurDeadLetter = error.message;
      }
      cache.compteurs = { recus: compte.recus, dead_letter: env.DEAD_LETTER_SUBSCRIPTION ? cache.deadLetter.length : null, en_attente: null, publies: null };
      cache.debit = debit.map(({ t, n }) => ({ t: t * 1000, n }));
      cache.positions = positions.map((p) => ({ ...p, event_time: valeur(p.event_time) }));
      cache.evenements = evenements.map((e) => ({ ...e, event_time: valeur(e.event_time) }));
      cache.erreur = null;
    } catch (error) {
      cache.erreur = error.message;
      log('ERROR', error.message);
    }
  }
  const pret = rafraichir();
  setInterval(rafraichir, Number(env.REFRESH_SECONDS || 20) * 1000).unref();

  return {
    mode: 'bigquery',
    libelle: `BigQuery, ${env.BQ_TABLE}`,
    pret,
    async etat() { return { compteurs: cache.compteurs, debit: cache.debit, transfert: { pilotable: false, actif: null }, erreur: cache.erreur, pas_secondes: 60 }; },
    async positions() { return cache.positions; },
    async evenements() { return cache.evenements; },
    async deadLetter() { return cache.deadLetter; },
    async lots() {
      const lignes = await requete(`SELECT REGEXP_EXTRACT(event_id, r'^(.*)-[0-9]{6}$') AS nom, COUNT(*) AS n FROM ${table}
        WHERE event_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY) GROUP BY nom ORDER BY MAX(event_time) DESC LIMIT 20`);
      return lignes.filter((l) => l.nom).map((l) => ({ nom: l.nom, attendus: null }));
    },
    async lot(nom) {
      const lignes = await requete(`SELECT event_id, COUNT(*) AS n FROM ${table}
        WHERE STARTS_WITH(event_id, @prefixe) AND event_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 DAY) GROUP BY event_id`, { prefixe: `${nom}-` });
      return { nom, attendus: null, recus: Object.fromEntries(lignes.map((l) => [l.event_id, l.n])), dead_letter: cache.deadLetter.map((d) => d.event_id).filter((id) => id?.startsWith(`${nom}-`)) };
    },
    async piloter() { throw Object.assign(new Error('sur GCP, coupez le transfert en retirant le droit d’écriture du service agent'), { http: 409 }); },
    deploiement: enCache(() => carteBigQuery(env, bigquery, cache), 20),
  };
}

// Carte du déploiement sur GCP. La table se lit avec bigquery.dataViewer, déjà nécessaire au tableau.
// La configuration de la subscription demande roles/pubsub.viewer sur elle, ce qui reste facultatif.
const contrat = { event_id: 'STRING', vehicle_id: 'STRING', event_time: 'TIMESTAMP', latitude: 'FLOAT', longitude: 'FLOAT' };
async function carteBigQuery(env, bigquery, cache) {
  const blocs = [blocCloudRun('Tableau de bord sur Cloud Run'), await blocIdentite()];
  const recus = cache.compteurs.recus;
  blocs.push(recus > 0
    ? bloc('producteur', 'Producteur', 'ok', `${recus} position(s) écrite(s) dans la dernière heure`, 'requête sur la table')
    : bloc('producteur', 'Producteur', 'inconnu', 'aucune position récente dans la table : producteur lancé, transfert configuré ?'));

  const [projet, dataset, nomTable] = env.BQ_TABLE.split('.');
  try {
    const [meta] = await bigquery.dataset(dataset, { projectId: projet }).table(nomTable).getMetadata();
    const champs = Object.fromEntries((meta.schema?.fields || []).map((f) => [f.name, f.type === 'FLOAT64' ? 'FLOAT' : f.type]));
    const ecarts = Object.entries(contrat).filter(([nom, type]) => champs[nom] !== type).map(([nom, type]) => `${nom} : ${champs[nom] || 'absent'} au lieu de ${type}`);
    const partition = meta.timePartitioning?.field ? `partitionnée sur ${meta.timePartitioning.field}` : meta.timePartitioning ? 'partitionnée par date d’ingestion' : 'non partitionnée';
    const filtre = meta.requirePartitionFilter ? ', filtre de partition exigé' : '';
    blocs.push(ecarts.length
      ? bloc('table', 'Table BigQuery', 'alerte', `schéma différent du contrat du producteur : ${ecarts.join(', ')}`, env.BQ_TABLE)
      : bloc('table', 'Table BigQuery', 'ok', `${partition}${filtre}, schéma conforme au contrat du producteur`, env.BQ_TABLE));
  } catch (error) {
    blocs.push(bloc('table', 'Table BigQuery', 'echec', 'métadonnées de la table illisibles', error.message));
  }

  if (!env.SUBSCRIPTION) {
    blocs.push(bloc('topic', 'Topic Pub/Sub', 'inconnu', 'renseignez SUBSCRIPTION pour afficher ce bloc'), bloc('subscription', 'BigQuery subscription', 'inconnu', 'renseignez SUBSCRIPTION pour afficher ce bloc'), bloc('deadletter', 'Dead-letter', 'inconnu', 'renseignez SUBSCRIPTION pour afficher ce bloc'));
  } else {
    try {
      const { PubSub } = await import('@google-cloud/pubsub');
      const [sub] = await new PubSub(env.GOOGLE_CLOUD_PROJECT ? { projectId: env.GOOGLE_CLOUD_PROJECT } : {}).subscription(env.SUBSCRIPTION).getMetadata();
      const court = (nom = '') => nom.split('/').pop();
      blocs.push(bloc('topic', 'Topic Pub/Sub', 'ok', `topic ${court(sub.topic)}`, sub.topic));
      blocs.push(sub.bigqueryConfig?.table
        ? bloc('subscription', 'BigQuery subscription', 'ok', `écrit dans ${sub.bigqueryConfig.table}, use_table_schema ${sub.bigqueryConfig.useTableSchema ? 'oui' : 'non'}`, court(sub.name))
        : bloc('subscription', 'Transfert vers la table', 'ok', 'subscription sans export BigQuery : un consommateur fait le transfert', court(sub.name)));
      blocs.push(sub.deadLetterPolicy?.deadLetterTopic
        ? bloc('deadletter', 'Dead-letter', 'ok', `vers ${court(sub.deadLetterPolicy.deadLetterTopic)}, ${sub.deadLetterPolicy.maxDeliveryAttempts} tentatives au plus`, 'deadLetterPolicy')
        : bloc('deadletter', 'Dead-letter', 'inconnu', 'pas de dead-letter policy sur la subscription'));
    } catch (error) {
      const droit = error.code === 7 ? 'pour afficher ce bloc, donnez au tableau roles/pubsub.viewer sur la subscription (facultatif)' : 'configuration de la subscription illisible';
      blocs.push(bloc('topic', 'Topic Pub/Sub', 'inconnu', droit), bloc('subscription', 'BigQuery subscription', 'inconnu', droit, error.message), bloc('deadletter', 'Dead-letter', 'inconnu', droit));
    }
  }

  blocs.push(!env.DEAD_LETTER_SUBSCRIPTION
    ? bloc('inspection', 'Subscription d’inspection', 'inconnu', 'renseignez DEAD_LETTER_SUBSCRIPTION pour afficher ce bloc')
    : cache.erreurDeadLetter
      ? bloc('inspection', 'Subscription d’inspection', 'inconnu', 'lecture impossible : roles/pubsub.subscriber sur la subscription d’inspection ?', cache.erreurDeadLetter)
      : bloc('inspection', 'Subscription d’inspection', 'ok', `lisible, ${cache.deadLetter.length} message(s) visible(s)`, env.DEAD_LETTER_SUBSCRIPTION));
  blocs.push(bloc('obs', 'Monitoring et alertes', 'manuel', 'backlog, âge du plus ancien message et alertes : à montrer dans Monitoring'));
  return { plateforme: process.env.K_SERVICE ? 'Cloud Run' : 'local', blocs };
}

export async function creerSource(env = process.env) {
  if (env.SOURCE === 'bigquery') return sourceBigQuery(env);
  if (env.PUBSUB_EMULATOR_HOST) return sourceEmulateur(env);
  return sourceDemo();
}
