create or replace function public.rc__lot_day()
 returns boolean
 language sql
 stable
as $function$ select public.rc__saturday() or public.rc__effect('lot_free') is not null $function$;
