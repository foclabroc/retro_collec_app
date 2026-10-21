# Pixel Trade à la maison (Windows, sans Docker)

Remplace Supabase par 3 programmes natifs derrière le Caddy déjà en place pour Jellyfin.
L'appli ne change que d'adresse : les RPC et le temps réel parlent le même langage qu'avant.

| Rôle | Programme | Port local |
|---|---|---|
| Base de données | PostgreSQL 17 (service Windows) | 5432 |
| API des RPC (`/rest/v1/rpc/…`) | PostgREST (`postgrest.exe`) | 3000 |
| Temps réel des duels (`/realtime/v1/websocket`) | `rc-realtime` (Node.js, ce dossier) | 4000 |
| HTTPS public | Caddy (déjà installé) | 443 |

Mémoire totale : environ 300 à 500 Mo. Seul Caddy est ouvert sur Internet.

## 1. Installer (une fois)

1. **PostgreSQL 17** : installeur Windows officiel (EDB). Retenir le mot de passe `postgres`.
   - Dans `postgresql.conf` (dossier `data`) : `listen_addresses = 'localhost'`, puis redémarrer le service.
   - Ne jamais ouvrir le port 5432 sur la box.
2. **PostgREST** : télécharger `postgrest-…-windows-x64.zip` (GitHub, releases de PostgREST), dézipper dans `C:\pixeltrade\postgrest\` avec `postgrest.conf`.
3. **Node.js LTS** : installeur Windows. Copier le dossier `rc-realtime` dans `C:\pixeltrade\rc-realtime\`, puis dans ce dossier : `npm install`.
4. **NSSM** (pour lancer en service) : `nssm.exe` dans `C:\pixeltrade\`.

## 2. Préparer la base

1. Remplacer les mots de passe `CHANGE_MOI_…` dans `01_avant_import.sql`, `postgrest.conf` et la variable `RT_DB` plus bas (les mêmes partout).
2. `psql -U postgres -d postgres -f 01_avant_import.sql`

## 3. Copier la base Supabase

Mettre d'abord le jeu en maintenance (page admin → Maintenance) pour que plus rien ne bouge.

1. Supabase → **Connect** → « Session pooler » : copier l'adresse `postgresql://postgres.wwyxfcdubdnwokeanigk:…@….pooler.supabase.com:5432/postgres`.
2. Sauvegarde du schéma `public` (tables, données, fonctions, droits) :
   ```
   pg_dump "ADRESSE_COPIÉE" -n public --no-owner -f rc_public.sql
   ```
3. Import à la maison :
   ```
   psql -U postgres -d postgres -f rc_public.sql
   ```
   Les erreurs « already exists » sur le schéma `public` sont normales.
4. `psql -U postgres -d postgres -f 02_apres_import.sql` → doit afficher `fonctions_internes_ouvertes = 0`.

## 4. Lancer les services

```
nssm install pixeltrade-api C:\pixeltrade\postgrest\postgrest.exe C:\pixeltrade\postgrest\postgrest.conf
nssm install pixeltrade-rt "C:\Program Files\nodejs\node.exe" C:\pixeltrade\rc-realtime\server.js
nssm set pixeltrade-rt AppEnvironmentExtra RT_PORT=4000 RT_DB=postgres://rc_rt:MOT_DE_PASSE@127.0.0.1:5432/postgres RC_KEY=sb_publishable_M1Rdee-lSEzCfq81zjYq5Q_NgJ0a35z
nssm start pixeltrade-api
nssm start pixeltrade-rt
```

Puis ajouter `Caddyfile.extrait` au Caddyfile (avec le bon sous-domaine) et recharger Caddy.

Tests rapides :
- `http://127.0.0.1:4000` dans le navigateur du PC → « rc-realtime ok ».
- Une requête vers `https://api.mondomaine.fr/rest/v1/rpc/…` sans clé `apikey` → 401 (normal : la clé est obligatoire).

## 5. Basculer l'appli

Dans `lib/server.dart`, `kRcUrl` passe à `https://api.mondomaine.fr` (la clé `kRcKey` ne change pas), nouvelle version, push (web) puis APK.
Les anciennes APK visent encore Supabase : y laisser la maintenance avec un message « mets à jour » et monter la version minimale.
Avec un sous-domaine à toi, un futur déménagement ne demandera plus de nouvelle APK : il suffira de changer le DNS.

## 6. Sauvegardes (indispensable)

Tâche planifiée Windows chaque nuit :
```
pg_dump -U postgres -d postgres -n public -Fc -f D:\sauvegardes\rc_%DATE:~6,4%%DATE:~3,2%%DATE:~0,2%.dump
```
Garder plusieurs jours, idéalement sur un autre disque.

## Comment marche le temps réel

Les déclencheurs des duels (`rc_c4_rt`, `rc_bs_rt`) appellent `rc__rt_duel`, qui envoie `pg_notify('rc_rt', …)`.
`rc-realtime` écoute ce canal et transmet le message aux joueurs abonnés, avec le même protocole Phoenix que Supabase Realtime.
`lib/live_link.dart` ne voit aucune différence. Si le relais tombe, le polling de secours prend le relais comme avant.
