const $ = (selector) => document.querySelector(selector);
const SVG = 'http://www.w3.org/2000/svg';
// Cadre de la carte : la zone où le producteur invente ses positions, autour de Saint-Quentin.
const zone = { latMin: 49.82, latMax: 49.88, lonMin: 3.25, lonMax: 3.33 };
const traces = new Map();
let attendusFichier = null;
let repriseFin = 0;

const nombre = (n) => (n === null || n === undefined ? 'n/d' : n.toLocaleString('fr-FR'));
const heure = (iso) => (iso ? new Date(iso).toLocaleTimeString('fr-FR') : '');
// Angle d'or : des identifiants voisins reçoivent des teintes bien distinctes.
const couleur = (id) => `hsl(${([...id].reduce((h, c) => (h * 31 + c.charCodeAt(0)) % 997, 7) * 137.5) % 360} 75% 60%)`;

async function api(path, options) {
  const res = await fetch(path, { cache: 'no-store', ...options });
  const body = await res.json();
  if (!res.ok) throw new Error(body.erreur || `HTTP ${res.status}`);
  return body;
}

function alerte(texte) {
  $('#alert').hidden = !texte;
  $('#alert').textContent = texte || '';
}

async function etat() {
  try {
    const data = await api('/api/etat');
    $('#env').innerHTML = `<b>${data.libelle}</b> / ${data.plateforme}`;
    alerte(data.erreur ? `Lecture impossible : ${data.erreur}` : data.pret ? '' : 'La source démarre…');
    const c = data.compteurs;
    $('#c-recus').textContent = nombre(c.recus);
    $('#c-dl').textContent = nombre(c.dead_letter);
    $('#c-attente').textContent = c.en_attente === null ? 'voir Monitoring' : nombre(c.en_attente);
    dessinerDebit(data.debit, data.pas_secondes || 2);
    const t = data.transfert;
    $('#t-couper').disabled = !t.pilotable || !t.actif;
    $('#t-retablir').disabled = !t.pilotable || t.actif;
    if (!t.pilotable) {
      $('#t-etat').className = 'badge';
      $('#t-etat').textContent = 'géré par GCP';
      $('#t-texte').textContent = 'Sur GCP, la BigQuery subscription fait le transfert.';
    } else {
      $('#t-etat').className = `badge ${t.actif ? 'ok' : 'warn'}`;
      $('#t-etat').textContent = t.actif ? 'actif' : 'coupé';
      const reste = Math.round((repriseFin - Date.now()) / 1000);
      $('#t-texte').textContent = t.actif ? 'Les messages sont écrits au fil de l’eau.' : `Les messages s’accumulent.${reste > 0 ? ` Rétablissement automatique dans ${reste} s (démo publique).` : ''}`;
    }
  } catch (error) {
    alerte(`Le tableau de bord ne répond pas : ${error.message}`);
  }
}

function dessinerDebit(points, pas) {
  const svg = $('#debit');
  const max = Math.max(1, ...points.map((p) => p.n));
  const largeur = 300 / Math.max(points.length, 30);
  svg.replaceChildren(...points.map((p, i) => {
    const rect = document.createElementNS(SVG, 'rect');
    const h = (p.n / max) * 86;
    rect.setAttribute('x', i * largeur);
    rect.setAttribute('y', 90 - h);
    rect.setAttribute('width', Math.max(1, largeur - 1));
    rect.setAttribute('height', h);
    return rect;
  }));
  const dernier = points.at(-1);
  $('#c-debit').textContent = dernier ? `${(dernier.n / pas).toFixed(1)} /s` : '…';
  $('#debit-legende').textContent = `Un point toutes les ${pas} secondes, maximum ${max} par point.`;
}

function projeter(lat, lon) {
  return [((lon - zone.lonMin) / (zone.lonMax - zone.lonMin)) * 600, (1 - (lat - zone.latMin) / (zone.latMax - zone.latMin)) * 380];
}

async function carte() {
  try {
    const positions = await api('/api/positions');
    const svg = $('#carte');
    const grille = document.createElementNS(SVG, 'g');
    grille.setAttribute('class', 'grille');
    for (let x = 0; x <= 600; x += 60) grille.insertAdjacentHTML('beforeend', `<line x1="${x}" y1="0" x2="${x}" y2="380"/>`);
    for (let y = 0; y <= 380; y += 38) grille.insertAdjacentHTML('beforeend', `<line x1="0" y1="${y}" x2="600" y2="${y}"/>`);
    const elements = [grille];
    for (const p of positions) {
      const trace = traces.get(p.vehicle_id) || [];
      const point = projeter(p.latitude, p.longitude);
      if (!trace.length || trace.at(-1).join() !== point.join()) trace.push(point);
      if (trace.length > 8) trace.shift();
      traces.set(p.vehicle_id, trace);
      const c = couleur(p.vehicle_id);
      const ligne = document.createElementNS(SVG, 'polyline');
      ligne.setAttribute('class', 'trace');
      ligne.setAttribute('stroke', c);
      ligne.setAttribute('points', trace.map((xy) => xy.join(',')).join(' '));
      const cercle = document.createElementNS(SVG, 'circle');
      cercle.setAttribute('cx', point[0]);
      cercle.setAttribute('cy', point[1]);
      cercle.setAttribute('r', 5);
      cercle.setAttribute('fill', c);
      const titre = document.createElementNS(SVG, 'title');
      titre.textContent = `${p.vehicle_id}, ${heure(p.event_time)}`;
      cercle.append(titre);
      elements.push(ligne, cercle);
    }
    const legende = document.createElementNS(SVG, 'text');
    legende.setAttribute('x', 10);
    legende.setAttribute('y', 370);
    legende.textContent = `Saint-Quentin, positions fictives, ${positions.length} véhicules`;
    elements.push(legende);
    svg.replaceChildren(...elements);
  } catch {}
}

async function listes() {
  try {
    const evenements = await api('/api/evenements');
    $('#evenements').replaceChildren(...evenements.map((e) => ligne([e.event_id, e.vehicle_id, heure(e.event_time)])));
    const dl = await api('/api/dead-letter');
    if (dl.length) $('#dead-letter').replaceChildren(...dl.map((d) => ligne([d.event_id || 'illisible', d.erreur, d.tentatives ?? ''], 'badge err', 1)));
  } catch {}
}

function ligne(cellules, classe = '', index = -1) {
  const tr = document.createElement('tr');
  cellules.forEach((valeur, i) => {
    const td = document.createElement('td');
    if (i === 0) td.className = 'mono';
    if (i === index) {
      const badge = document.createElement('span');
      badge.className = classe;
      badge.textContent = valeur;
      td.append(badge);
    } else {
      td.textContent = valeur;
    }
    tr.append(td);
  });
  return tr;
}

async function lots() {
  try {
    const liste = await api('/api/lots');
    const choix = $('#lot').value;
    $('#lot').replaceChildren(...liste.map((lot) => new Option(lot.attendus ? `${lot.nom} (${lot.attendus} attendus)` : lot.nom, lot.nom)));
    if (choix) $('#lot').value = choix;
  } catch {}
}

async function reconcilier() {
  const nom = $('#lot').value;
  if (!nom) return;
  const lot = await api(`/api/lots/${encodeURIComponent(nom)}`);
  const attendus = attendusFichier?.filter((a) => a.event_id.startsWith(`${nom}-`)) || lot.attendus;
  const dl = new Set(lot.dead_letter);
  const ecrits = Object.keys(lot.recus).length;
  const doublons = Object.values(lot.recus).filter((n) => n > 1).length;
  $('#resultat').hidden = false;
  $('#r-ecrits').textContent = nombre(ecrits);
  $('#r-doublons').textContent = nombre(doublons);
  $('#r-dl').textContent = nombre(dl.size);
  if (!attendus) {
    $('#r-attendus').textContent = 'n/d';
    $('#r-manquants').textContent = 'n/d';
    $('#r-note').textContent = 'Chargez le fichier .jsonl écrit par le producteur pour connaître les manquants.';
    $('#r-ids').textContent = '';
    return;
  }
  const manquants = attendus.filter((a) => !lot.recus[a.event_id] && !dl.has(a.event_id));
  $('#r-attendus').textContent = nombre(attendus.length);
  $('#r-manquants').textContent = nombre(manquants.length);
  const invalides = attendus.filter((a) => a.invalide).length;
  $('#r-note').textContent = `${invalides} message(s) invalide(s) prévu(s) dans ce lot : ils doivent finir en dead-letter, pas dans la table. Un manquant peut aussi être encore en attente.`;
  $('#r-ids').textContent = manquants.length ? `Manquants : ${manquants.map((a) => a.event_id).join(', ')}` : 'Aucun manquant.';
}

$('#fichier').addEventListener('change', async (event) => {
  const texte = await event.target.files[0]?.text();
  attendusFichier = texte ? texte.trim().split('\n').map((l) => JSON.parse(l)) : null;
  const nom = attendusFichier?.[0]?.event_id.replace(/-\d{6}$/, '');
  if (nom && ![...$('#lot').options].some((o) => o.value === nom)) $('#lot').add(new Option(nom, nom));
  if (nom) $('#lot').value = nom;
});
$('#reconcilier').addEventListener('click', () => reconcilier().catch((error) => alerte(error.message)));
$('#t-couper').addEventListener('click', () => api('/api/transfert', { method: 'POST', body: JSON.stringify({ actif: false }) }).then((r) => {
  repriseFin = r.reprise_auto_s ? Date.now() + r.reprise_auto_s * 1000 : 0;
  etat();
}));
$('#t-retablir').addEventListener('click', () => api('/api/transfert', { method: 'POST', body: JSON.stringify({ actif: true }) }).then(etat));

async function deploiement() {
  try {
    const { blocs } = await api('/api/deploiement');
    Carte.rendre($('#deploiement'), [
      { titre: 'Production', ids: ['producteur', 'topic'] },
      { titre: 'Livraison', ids: ['subscription', 'deadletter', 'inspection'] },
      { titre: 'Analyse', ids: ['table', 'run', 'identite'] },
      { titre: 'Exploitation', ids: ['obs'] },
    ], blocs);
  } catch {}
}

function boucle() {
  etat();
  carte();
  listes();
}
boucle();
lots();
deploiement();
setInterval(boucle, 2000);
setInterval(lots, 10000);
setInterval(deploiement, 15000);
