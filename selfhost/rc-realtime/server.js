// ═══════════════════════════════════════════════════════════════════════════
// rc-realtime : petit relais temps réel pour Pixel Trade auto-hébergé.
// Remplace Supabase Realtime en parlant le même protocole que lib/live_link.dart
// (Phoenix vsn 1.0.0 : phx_join, heartbeat, broadcast) : l'appli ne change pas.
//
// Postgres → pg_notify('rc_rt', {topic, event, payload}) (voir 02_apres_import.sql)
// → ce relais → les WebSockets abonnées à « realtime:<topic> ».
//
// Variables d'environnement :
//   RT_PORT  port d'écoute local (défaut 4000, derrière Caddy)
//   RT_DB    connexion Postgres (rôle rc_rt, qui n'a besoin que de se connecter)
//   RC_KEY   clé publique de l'appli (paramètre apikey), vide = pas de contrôle
//
// Canaux acceptés : realtime:rc_<24 hex> (un joueur, ou une partie regardée) et realtime:rc_all.
// Le premier canal rc_<24 hex> rejoint par une connexion est celui du joueur : 10 s après
// qu'il n'a plus aucune connexion, le relais appelle rc__rt_gone(canal) → le joueur passe
// hors ligne tout de suite (au lieu d'attendre 75 s).
// ═══════════════════════════════════════════════════════════════════════════
'use strict';
const http = require('http');
const { WebSocketServer } = require('ws');
const { Client } = require('pg');

const PORT = Number(process.env.RT_PORT || 4000);
const DB = process.env.RT_DB || 'postgres://rc_rt:CHANGE_MOI@127.0.0.1:5432/postgres';
const KEY = process.env.RC_KEY || '';
const TOPIC_RE = /^realtime:rc_([0-9a-f]{24}|all)$/; // canal d'un joueur / d'une partie, ou canal commun rc_all
const GONE_MS = 10000; // délai avant « hors ligne » après la dernière connexion d'un joueur

/** topic → ensemble des sockets abonnées */
const topics = new Map();

function leave(ws, topic) {
  const set = topics.get(topic);
  if (set) {
    set.delete(ws);
    if (set.size === 0) topics.delete(topic);
  }
  ws.topics.delete(topic);
  if (ws.player === topic) {
    ws.player = null;
    gone(topic);
  }
}

// ─── Joueur parti : plus aucune connexion sur son canal pendant GONE_MS ───
const goneTimers = new Map();
function gone(topic) {
  clearTimeout(goneTimers.get(topic));
  goneTimers.set(topic, setTimeout(() => {
    goneTimers.delete(topic);
    for (const ws of topics.get(topic) || []) if (ws.player === topic) return; // revenu entre-temps
    if (!dbq) return;
    dbq.query('select public.rc__rt_gone($1)', [topic.slice('realtime:'.length)]).catch((e) => console.error('[pg] rc__rt_gone :', e.message));
  }, GONE_MS));
}

// ─── Serveur HTTP + WebSocket ──────────────────────────────────────────────
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end(`rc-realtime ok, ${countSockets()} connexions\n`);
});
const wss = new WebSocketServer({ noServer: true, maxPayload: 16 * 1024 });

function countSockets() {
  return wss.clients.size;
}

server.on('upgrade', (req, socket, head) => {
  const u = new URL(req.url, 'http://local');
  if (u.pathname !== '/realtime/v1/websocket' || (KEY && u.searchParams.get('apikey') !== KEY)) {
    socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws));
});

wss.on('connection', (ws) => {
  ws.topics = new Set();
  ws.alive = true;
  ws.on('pong', () => (ws.alive = true));

  ws.on('message', (raw) => {
    let m;
    try {
      m = JSON.parse(raw);
    } catch {
      return;
    }
    if (!m || typeof m !== 'object') return;
    ws.alive = true;
    const reply = (status = 'ok', response = {}) =>
      ws.send(JSON.stringify({ topic: m.topic, event: 'phx_reply', payload: { status, response }, ref: m.ref ?? null, join_ref: m.join_ref ?? null }));

    switch (m.event) {
      case 'heartbeat':
        return reply();
      case 'phx_join':
        if (typeof m.topic !== 'string' || !TOPIC_RE.test(m.topic) || ws.topics.size >= 4) return reply('error', { reason: 'refusé' });
        if (!topics.has(m.topic)) topics.set(m.topic, new Set());
        topics.get(m.topic).add(ws);
        ws.topics.add(m.topic);
        if (!ws.player && m.topic !== 'realtime:rc_all') {
          ws.player = m.topic; // premier canal personnel = celui du joueur
          clearTimeout(goneTimers.get(m.topic));
          goneTimers.delete(m.topic);
        }
        return reply();
      case 'phx_leave':
        leave(ws, m.topic);
        return reply();
      default:
        return reply('error', { reason: 'inconnu' });
    }
  });

  ws.on('close', () => {
    for (const t of [...ws.topics]) leave(ws, t);
  });
});

// Coupe les connexions mortes (pas de heartbeat ni de pong depuis 60 s)
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) {
      ws.terminate();
      continue;
    }
    ws.alive = false;
    ws.ping();
  }
}, 30000);

function broadcast(topic, event, payload) {
  const set = topics.get('realtime:' + topic);
  if (!set) return;
  const msg = JSON.stringify({ topic: 'realtime:' + topic, event: 'broadcast', payload: { type: 'broadcast', event, payload }, ref: null });
  for (const ws of set) if (ws.readyState === 1) ws.send(msg);
}

// ─── Écoute de Postgres (reconnexion automatique) ─────────────────────────
let dbq = null; // connexion prête pour les requêtes (rc__rt_gone)
async function listen() {
  const db = new Client({ connectionString: DB });
  db.on('error', (e) => console.error('[pg] erreur :', e.message));
  db.on('end', () => {
    if (dbq === db) dbq = null;
    console.error('[pg] connexion perdue, nouvel essai dans 3 s');
    setTimeout(listen, 3000);
  });
  db.on('notification', (n) => {
    try {
      const { topic, event, payload } = JSON.parse(n.payload);
      if (typeof topic === 'string' && typeof event === 'string') broadcast(topic, event, payload ?? {});
    } catch (e) {
      console.error('[pg] message illisible :', e.message);
    }
  });
  try {
    await db.connect();
    await db.query('LISTEN rc_rt');
    dbq = db;
    console.log('[pg] à l\'écoute du canal rc_rt');
  } catch (e) {
    console.error('[pg] connexion impossible :', e.message);
    db.removeAllListeners('end');
    setTimeout(listen, 3000);
  }
}

server.listen(PORT, '127.0.0.1', () => console.log(`[rt] relais sur 127.0.0.1:${PORT}`));
listen();
