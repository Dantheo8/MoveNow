// Tableau de bord MoveNow : carte des véhicules, débit, dead-letter et réconciliation des lots.
// En local, il imite aussi le transfert vers BigQuery (voir sources.mjs). Sur GCP, il se déploie
// sur Cloud Run en lecture seule, avec SOURCE=bigquery.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import { creerSource } from './sources.mjs';

const here = new URL('.', import.meta.url);
const plateforme = process.env.K_SERVICE ? 'Cloud Run' : 'local';
const assets = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/kit.css': ['kit.css', 'text/css; charset=utf-8'],
  '/carte.js': ['carte.js', 'text/javascript; charset=utf-8'],
};
// Démo publique : un transfert coupé par un visiteur se rétablit seul au bout d'une minute.
const demoPublique = process.env.DEMO_PUBLIQUE === 'true';
let reprise = null;

const source = await creerSource(process.env);
let pret = false;
source.pret.then(() => { pret = true; }, (error) => console.log(JSON.stringify({ severity: 'ERROR', message: `source indisponible : ${error.message}` })));

function send(res, status, body, type = 'application/json; charset=utf-8') {
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(type.startsWith('application/json') ? JSON.stringify(body) : body);
}

async function lireJson(req) {
  let body = '';
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 1000) throw Object.assign(new Error('requête trop longue'), { http: 413 });
  }
  return JSON.parse(body || '{}');
}

const server = http.createServer(async (req, res) => {
  const { pathname } = new URL(req.url, 'http://localhost');
  try {
    if (req.method === 'GET' && assets[pathname]) {
      const [file, type] = assets[pathname];
      return send(res, 200, fs.readFileSync(new URL(`public/${file}`, here)), type);
    }
    if (pathname === '/healthz') return send(res, pret ? 200 : 503, { statut: pret ? 'ok' : 'démarrage' });
    if (pathname === '/api/etat') {
      return send(res, 200, { mode: source.mode, libelle: source.libelle, plateforme, instance: process.env.K_REVISION || os.hostname(), pret, ...(await source.etat()) });
    }
    if (pathname === '/api/deploiement') return send(res, 200, await source.deploiement());
    if (pathname === '/api/positions') return send(res, 200, await source.positions());
    if (pathname === '/api/evenements') return send(res, 200, await source.evenements());
    if (pathname === '/api/dead-letter') return send(res, 200, await source.deadLetter());
    if (pathname === '/api/lots') return send(res, 200, await source.lots());
    const lot = pathname.match(/^\/api\/lots\/([\w-]{1,80})$/);
    if (lot) return send(res, 200, await source.lot(lot[1]));
    if (pathname === '/api/transfert' && req.method === 'POST') {
      const { actif } = await lireJson(req);
      const etat = await source.piloter(Boolean(actif));
      clearTimeout(reprise);
      if (demoPublique && !actif) reprise = setTimeout(() => source.piloter(true), 60_000);
      return send(res, 200, { ...etat, reprise_auto_s: demoPublique && !actif ? 60 : null });
    }
    send(res, 404, { erreur: 'route inconnue' });
  } catch (error) {
    if (error.http) return send(res, error.http, { erreur: error.message });
    console.log(JSON.stringify({ severity: 'ERROR', message: error.message }));
    send(res, 500, { erreur: error.message });
  }
});

server.listen(Number(process.env.PORT || 8080), () => {
  console.log(JSON.stringify({ severity: 'INFO', message: `tableau de bord prêt sur le port ${server.address().port}, mode ${source.mode}` }));
});
process.on('SIGTERM', () => server.close(() => process.exit(0)));
