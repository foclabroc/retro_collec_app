CREATE OR REPLACE FUNCTION public.rc__chat_clean(p text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  tok text; k text; res text := ''; bad boolean;
begin
  p := regexp_replace(trim(p), '\s+', ' ', 'g');
  -- liens
  p := regexp_replace(p, '(https?://\S+|www\.\S+|\S+\.(com|fr|net|org|io|be|ch|ca|gg|ly|me|tv|xyz|ru|de|uk|eu|info|app)(/\S*)?)', '[lien]', 'gi');
  -- numéros de téléphone (8 chiffres ou plus, séparés ou non)
  p := regexp_replace(p, '\+?\d([\s.\-]?\d){7,}', '[numéro]', 'g');
  foreach tok in array string_to_array(p, ' ') loop
    k := public.rc__chat_key(tok);
    bad := k <> '' and exists (select 1 from public.rc_chat_words w where public.rc__chat_key(w.word) = k);
    res := res || case when res = '' then '' else ' ' end
               || case when bad then repeat('*', greatest(3, least(char_length(tok), 8))) else tok end;
  end loop;
  return res;
end $function$
