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
rem PostgREST a besoin des DLL de PostgreSQL (sinon code 3221225781 = DLL introuvable)
nssm set pixeltrade-api AppEnvironmentExtra "PATH=C:\Program Files\PostgreSQL\17\bin;C:\Windows\system32;C:\Windows"
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

Script `sauvegarde.ps1` : `pg_dump -Fc` du schéma `public` dans `D:\pixeltrade\sauvegardes\rc_AAAA-MM-JJ_HHMM.dump`, vérifié par `pg_restore -l`, garde 7 jours, journal `D:\pixeltrade\sauvegarde.log`.

1. Copier `sauvegarde.ps1` dans `D:\pixeltrade\`.
2. Créer `D:\pixeltrade\pgpass.conf` (une ligne, mot de passe de `postgres`) :
   ```
   127.0.0.1:5432:*:postgres:MOT_DE_PASSE
   ```
3. Tester à la main (PowerShell admin) puis vérifier le journal et `D:\pixeltrade\sauvegardes` :
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File D:\pixeltrade\sauvegarde.ps1
   ```
4. Tâche planifiée chaque nuit à 4 h 17 (compte SYSTEM, pas besoin d'être connecté) :
   ```
   schtasks /Create /TN "PixelTrade-Sauvegarde" /SC DAILY /ST 04:17 /RU SYSTEM /RL HIGHEST /F /TR "powershell -NoProfile -ExecutionPolicy Bypass -File D:\pixeltrade\sauvegarde.ps1"
   schtasks /Run /TN "PixelTrade-Sauvegarde"
   ```

Restaurer (base vide préparée avec `01_avant_import.sql`) :
```
pg_restore -U postgres -d postgres --no-owner --clean --if-exists D:\pixeltrade\sauvegardes\rc_….dump
```
puis `02_apres_import.sql` et `05_securite.sql` (propriétaire `rc_owner`, droits de l'API). Idéalement, copier aussi de temps en temps un `.dump` sur un autre disque ou une clé.

## Comment marche le temps réel

Les déclencheurs des duels (`rc_c4_rt`, `rc_bs_rt`) appellent `rc__rt_duel`, qui envoie `pg_notify('rc_rt', …)`.
`rc-realtime` écoute ce canal et transmet le message aux joueurs abonnés, avec le même protocole Phoenix que Supabase Realtime.
`lib/live_link.dart` ne voit aucune différence. Si le relais tombe, le polling de secours prend le relais comme avant.
