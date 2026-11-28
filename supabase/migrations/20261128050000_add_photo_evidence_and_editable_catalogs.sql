-- Evidencia fotográfica privada y catálogos administrables de QUALYX.
alter table public.muestreos_anden
  add column if not exists fotos_json jsonb not null default '[]'::jsonb;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidencias-muestreos', 'evidencias-muestreos', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false, file_size_limit=10485760,
  allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create policy "evidencias_insert_propias"
on storage.objects for insert to authenticated
with check (bucket_id='evidencias-muestreos' and (storage.foldername(name))[1]=(select auth.uid())::text);

create policy "evidencias_select_propias_o_admin"
on storage.objects for select to authenticated
using (bucket_id='evidencias-muestreos' and (
  (storage.foldername(name))[1]=(select auth.uid())::text or public.cb_is_admin()
));

create table if not exists public.cb_catalogs (
  id smallint primary key default 1 check (id=1),
  ranchos text[] not null default array['ALEGRE 1','ALEGRE 3','ALEGRE 4','NOGAL','DERRAMADERO','BLANCO','CATARINA'],
  variedades text[] not null default array['MYA','MARILYN','FRYDA'],
  updated_at timestamptz not null default now()
);
insert into public.cb_catalogs(id) values(1) on conflict(id) do nothing;
alter table public.cb_catalogs enable row level security;
create policy "cb_catalogs_read_authenticated" on public.cb_catalogs
  for select to authenticated using (true);
create policy "cb_catalogs_admin_update" on public.cb_catalogs
  for update to authenticated using (public.cb_is_admin()) with check (public.cb_is_admin());
grant select, update on public.cb_catalogs to authenticated;
