// Producteur de positions fictives pour MoveNow.
// Publie des lots cadencés sur un topic Pub/Sub et écrit, pour chaque lot, la liste des événements
// attendus dans <dossier>/<lot>.jsonl : c'est la base de la réconciliation avec BigQuery.
//
//   node producteur.mjs --project mon-projet --topic positions --rate 10 --duration 60 --batch lot-01
//   node producteur.mjs --topic positions --rate 5 --duration 10 --batch lot-02 --invalid 3
//   node producteur.mjs --rate 2 --duration 3 --dry-run           essai sans GCP
//
// Sur GCP, l'authentification passe par ADC. Si PUBSUB_EMULATOR_HOST est défini, la bibliothèque
// Pub/Sub publie vers l'émulateur local à la place.
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';

const { values: options } = parseArgs({
  options: {
    topic: { type: 'string' },
    project: { type: 'string' },
    rate: { type: 'string', default: '10' },
    duration: { type: 'string', default: '60' },
    batch: { type: 'string', default: `lot-${new Date().toISOString().slice(0, 19).replace(/[-:T]/g, '')}` },
    invalid: { type: 'string', default: '0' },
    vehicles: { type: 'string', default: '20' },
    out: { type: 'string', default: '.' },
    loop: { type: 'boolean', default: false },
    'dry-run': { type: 'boolean', default: false },
  },
});

const rate = Number(options.rate);
const duration = Number(options.duration);
const invalid = Number(options.invalid);
const vehicles = Number(options.vehicles);
for (const [name, value, max] of [['rate', rate, 100], ['duration', duration, 600], ['invalid', invalid, 1000], ['vehicles', vehicles, 1000]]) {
  // Plafonds volontaires : ce script sert à des essais bornés, pas à reproduire le trafic métier.
  if (!Number.isInteger(value) || value < 0 || value > max) throw new Error(`--${name} doit être un entier entre 0 et ${max}`);
}
if (!/^[a-zA-Z0-9_-]+$/.test(options.batch)) throw new Error('--batch ne doit contenir que des lettres, chiffres, - et _');
if (!options['dry-run'] && !options.topic) throw new Error('--topic est requis, sauf avec --dry-run');
fs.mkdirSync(options.out, { recursive: true });

let topic = null;
if (!options['dry-run']) {
  const { PubSub } = await import('@google-cloud/pubsub');
  const projectId = options.project || process.env.GOOGLE_CLOUD_PROJECT || process.env.PUBSUB_PROJECT_ID;
  topic = new PubSub(projectId ? { projectId } : {}).topic(options.topic);
}

// Compteur global, écrit chaque seconde dans progression.json : en local, le tableau de bord s'en sert
// pour estimer le nombre de messages en attente.
let publiesTotal = 0;
const progression = (batch) => fs.writeFileSync(path.join(options.out, 'progression.json'), JSON.stringify({ lot: batch, publies: publiesTotal, maj: new Date().toISOString() }));

// Chaque véhicule part d'un point au hasard autour de Saint-Quentin, puis se déplace un peu à chaque position.
const flotte = Array.from({ length: vehicles }, () => ({ lat: 49.82 + Math.random() * 0.06, lon: 3.25 + Math.random() * 0.08 }));
function deplacer(n) {
  const v = flotte[n];
  v.lat = Math.min(49.88, Math.max(49.82, v.lat + (Math.random() - 0.5) * 0.002));
  v.lon = Math.min(3.33, Math.max(3.25, v.lon + (Math.random() - 0.5) * 0.003));
  return v;
}

async function publierLot(batch) {
  const total = rate * duration;
  // Les événements invalides sont répartis régulièrement dans le lot.
  const invalidCount = Math.min(invalid, total);
  const invalidAt = new Set(Array.from({ length: invalidCount }, (_, i) => 1 + Math.floor(((i + 0.5) * total) / invalidCount)));
  const records = [];
  const pending = [];
  const start = Date.now();
  let seq = 0;

  for (let second = 0; second < duration; second++) {
    for (let i = 0; i < rate; i++) {
      seq += 1;
      const n = seq % vehicles;
      const position = deplacer(n);
      const event = {
        event_id: `${batch}-${String(seq).padStart(6, '0')}`,
        vehicle_id: `vh-${String(n).padStart(4, '0')}`,
        event_time: new Date().toISOString(),
        latitude: Number(position.lat.toFixed(5)),
        longitude: Number(position.lon.toFixed(5)),
      };
      // Un message « invalide » est accepté par le topic mais ne respecte pas le schéma de la table :
      // sa latitude devient une chaîne de caractères.
      if (invalidAt.has(seq)) event.latitude = 'nord';
      const record = { event_id: event.event_id, invalide: invalidAt.has(seq), publie_le: event.event_time };
      records.push(record);
      publiesTotal += 1;
      if (topic) {
        pending.push(topic.publishMessage({ data: Buffer.from(JSON.stringify(event)) })
          .then((messageId) => { record.message_id = messageId; })
          .catch((error) => { record.erreur = error.message; }));
      } else if (seq <= 3) {
        console.log(JSON.stringify(event));
      }
    }
    if (topic) progression(batch);
    const wait = start + (second + 1) * 1000 - Date.now();
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
  }

  await Promise.all(pending);
  const file = path.join(options.out, `${batch}.jsonl`);
  fs.writeFileSync(file, records.map((record) => JSON.stringify(record)).join('\n') + '\n');
  const failed = records.filter((record) => record.erreur).length;
  console.log(`${batch} : ${records.length} événements, ${invalidAt.size} invalides, ${failed} échecs de publication${topic ? '' : ' (essai à blanc, rien publié)'}. Liste attendue : ${file}`);
  return failed;
}

if (options.loop) {
  // Mode continu pour la démonstration locale : un nouveau lot numéroté à la suite du précédent.
  for (let n = 1; ; n++) await publierLot(`${options.batch}-${String(n).padStart(3, '0')}`);
} else {
  process.exitCode = (await publierLot(options.batch)) ? 1 : 0;
}
