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
// Le premier canal rc_<24 hex> rejoint par une connexion est celui du joueur. Présence tenue ici :
//  · connexion → rc__rt_here(canal) : en ligne tout de suite (+ message 'hello' à la connexion,
//    preuve pour l'appli que la chaîne marche) ;
//  · toutes les 30 s → rc__rt_alive(canaux connectés) : reste en ligne sans ping de l'appli ;
//  · 5 s après sa dernière connexion → rc__rt_gone(canal) : hors ligne tout de suite ;
//  · un spectateur quitte le canal d'une partie (ou se déconnecte) → rc__rt_unwatch(joueur, partie).
// Protection : 12 connexions max par IP, 40 messages max par connexion et par 10 s.
// ═══════════════════════════════════════════════════════════════════════════
'use strict';
const http = require('http');
const { WebSocketServer } = require('ws');
const { Client } = require('pg');

const PORT = Number(process.env.RT_PORT || 4000);
const DB = process.env.RT_DB || 'postgres://rc_rt:CHANGE_MOI@127.0.0.1:5432/postgres';
const KEY = process.env.RC_KEY || '';
const TOPIC_RE = /^realtime:rc_([0-9a-f]{24}|all)$/; // canal d'un joueur / d'une partie, ou canal commun rc_all
const GONE_MS = 5000; // délai avant « hors ligne » après la dernière connexion d'un joueur (rechargement de page)
const ALL = 'realtime:rc_all';
const MAX_PER_IP = 12; // connexions WebSocket ouvertes en même temps par adresse IP (plusieurs onglets / appareils d'une maison)
const MAX_MSG = 40; // messages reçus par connexion et par tranche de 10 s (au-delà : connexion coupée)

/** topic → ensemble des sockets abonnées */
const topics = new Map();

const bare = (t) => t.slice('realtime:'.length);

function sql(q, args) {
  if (!dbq) return;
  dbq.query(q, args).catch((e) => console.error('[pg]', q.split('(')[0], ':', e.message));
}

function leave(ws, topic, player = ws.player) {
  const set = topics.get(topic);
  if (set) {
    set.delete(ws);
    if (set.size === 0) topics.delete(topic);
  }
  ws.topics.delete(topic);
  if (ws.player === topic) {
    ws.player = null;
    gone(topic);
  } else if (player && topic !== ALL && topic !== player) {
    // canal d'une partie regardée : le spectateur part (s'il ne la regarde plus d'ailleurs)
    for (const o of set || []) if (o.player === player) return;
    sql('select public.rc__rt_unwatch($1, $2)', [bare(player), bare(topic)]);
  }
}

// ─── Joueur parti : plus aucune connexion sur son canal pendant GONE_MS ───
const goneTimers = new Map();
function gone(topic) {
  clearTimeout(goneTimers.get(topic));
  goneTimers.set(topic, setTimeout(() => {
    goneTimers.delete(topic);
    for (const ws of topics.get(topic) || []) if (ws.player === topic) return; // revenu entre-temps
    sql('select public.rc__rt_gone($1)', [bare(topic)]);
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

// adresse du client : X-Forwarded-For posé par Caddy (seule entrée, relais en 127.0.0.1)
const perIp = new Map();
function clientIp(req) {
  return String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
}

server.on('upgrade', (req, socket, head) => {
  const u = new URL(req.url, 'http://local');
  if (u.pathname !== '/realtime/v1/websocket' || (KEY && u.searchParams.get('apikey') !== KEY)) {
    socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    socket.destroy();
    return;
  }
  const ip = clientIp(req);
  if ((perIp.get(ip) || 0) >= MAX_PER_IP) {
    socket.write('HTTP/1.1 429 Too Many Requests\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    ws.ip = ip;
    perIp.set(ip, (perIp.get(ip) || 0) + 1);
    ws.on('close', () => {
      const n = (perIp.get(ip) || 1) - 1;
      if (n > 0) perIp.set(ip, n);
      else perIp.delete(ip);
    });
    wss.emit('connection', ws);
  });
});

wss.on('connection', (ws) => {
  ws.topics = new Set();
  ws.alive = true;
  ws.on('pong', () => (ws.alive = true));

  ws.msgs = 0;
  ws.on('message', (raw) => {
    if (++ws.msgs > MAX_MSG) return ws.terminate(); // trop de messages : client fou ou malveillant
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
        if (!ws.player && m.topic !== ALL) {
          ws.player = m.topic; // premier canal personnel = celui du joueur
          clearTimeout(goneTimers.get(m.topic));
          goneTimers.delete(m.topic);
          reply();
          sql('select public.rc__rt_here($1)', [bare(m.topic)]); // en ligne tout de suite
          ws.send(JSON.stringify({ topic: m.topic, event: 'broadcast', payload: { type: 'broadcast', event: 'hello', payload: {} }, ref: null }));
          return;
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
    const player = ws.player;
    for (const t of [...ws.topics]) leave(ws, t, player);
  });
});

// Joueurs connectés : restent « en ligne » (seen_at) sans ping de l'appli
setInterval(() => {
  const players = new Set();
  for (const ws of wss.clients) if (ws.player) players.add(bare(ws.player));
  if (players.size) sql('select public.rc__rt_alive($1)', [[...players]]);
}, 30000);

// Coupe les connexions mortes (pas de heartbeat ni de pong depuis 30 s)
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) {
      ws.terminate();
      continue;
    }
    ws.alive = false;
    ws.ping();
  }
}, 15000);

// remise à zéro du compteur de messages
setInterval(() => {
  for (const ws of wss.clients) ws.msgs = 0;
}, 10000);

function broadcast(topic, event, payload) {
  const set = topics.get('realtime:' + topic);
  if (!set) return;
  const msg = JSON.stringify({ topic: 'realtime:' + topic, event: 'broadcast', payload: { type: 'broadcast', event, payload }, ref: null });
  for (const ws of set) if (ws.readyState === 1) ws.send(msg);
}

// ─── Écoute de Postgres (reconnexion automatique) ─────────────────────────
let dbq = null; // connexion prête pour les requêtes (présence, spectateurs)
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
