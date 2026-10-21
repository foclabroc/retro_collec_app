-- Pixel Trade maison : supprime les tables / fonctions de Rétro Jump et Rétro Jet copiées pour rien.
-- Rétro Jump / Rétro Jet restent sur Supabase : rien n'y est touché.
-- Tout ou rien : si un objet rc_* en dépend, erreur et rien n'est supprimé (pas de CASCADE).
-- Relançable (if exists).
\set ON_ERROR_STOP on
begin;

drop function if exists
  public.jet_awards_refresh(),
  public.jet_general(integer, integer),
  public.jet_general_board(),
  public.jet_general_rank(text),
  public.jet_player_card(text, text),
  public.jet_rank_watch(text, text, integer, integer),
  public.jet_top_ghost(text, text),
  public.jet_week_board(date),
  public.jet_week_medals(integer, integer),
  public.jet_week_medals_rank(text),
  public.jump_awards_refresh(),
  public.jump_chat_filter(text),
  public.jump_chat_norm(text),
  public.jump_claim_name(text, text, boolean),
  public.jump_clean_name(text),
  public.jump_cups_sync(text),
  public.jump_general(integer, integer),
  public.jump_general_board(),
  public.jump_general_rank(text),
  public.jump_overtakes_get(text, text),
  public.jump_player_card(text, text),
  public.jump_rank(text, text, text),
  public.jump_rank_watch(text, text, integer, integer),
  public.jump_top_ghost(text, text),
  public.jump_week_board(date),
  public.jump_week_medals(integer, integer),
  public.jump_week_medals_rank(text);

drop table if exists
  public.jet_award_days, public.jet_award_weeks, public.jet_awards,
  public.jet_day_awards, public.jet_ghosts,
  public.jump_award_days, public.jump_award_weeks, public.jump_awards,
  public.jump_chat, public.jump_chat_bans, public.jump_chat_reports,
  public.jump_chat_words, public.jump_day_awards, public.jump_ghosts,
  public.jump_overtakes, public.jump_players, public.jump_scores;

commit;

\echo '== Reste (doit être 0) =='
select count(*) as reste
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and (c.relname like 'jump\_%' or c.relname like 'jet\_%');
select count(*) as reste_fonctions
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and (p.proname like 'jump\_%' or p.proname like 'jet\_%');

-- PostgREST doit oublier ces RPC
notify pgrst, 'reload schema';
