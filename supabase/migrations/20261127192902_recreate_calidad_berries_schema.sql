create table public.cb_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 email text not null,
 display_name text not null,
 puesto text not null default 'Trabajador',
 role text not null default 'trabajador' check (role in ('admin','trabajador')),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.cb_invitations (
 code text primary key,
 created_by uuid not null references auth.users(id),
 used_by uuid unique references auth.users(id),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now() + interval '7 days')
);
create table public.cb_app_config (
 key text primary key,
 value jsonb not null,
 updated_at timestamptz not null default now()
);
create table public.muestreos_anden (
 uuid text primary key,
 owner_id uuid not null default auth.uid() references auth.users(id),
 cultivo text not null, rancho text not null, sector text not null,
 variedad text not null, presentacion text not null, cuadrilla text not null,
 cajas_recibidas integer not null, canastos integer not null, fruta_muestra integer not null,
 licencia text not null, grados_brix double precision, peso double precision,
 frutos_larva integer not null default 0, evaluador text not null default '',
 muestreados text not null default '', defectos_json jsonb not null,
 pct_condicion double precision not null, pct_apariencia double precision not null,
 puntos_condicion integer not null, puntos_apariencia integer not null,
 puntos_total integer not null, disposicion text not null, motivo text not null default '',
 fecha timestamptz not null, usuario_email text not null, usuario_nombre text not null,
 usuario_puesto text not null
);
create index muestreos_anden_owner_id_fecha_idx on public.muestreos_anden(owner_id, fecha desc);
create table public.muestreos_proceso (
 uuid text primary key,
 owner_id uuid not null default auth.uid() references auth.users(id),
 cultivo text not null, frutos_muestra integer, rancho text not null default '',
 cajas integer, taras integer, pct_proceso double precision, defectos_json jsonb not null,
 area_agronomia double precision not null, area_poscosecha double precision not null,
 area_cosecha double precision not null, area_actividades double precision not null,
 area_inocuidad double precision not null, total_defectos double precision not null,
 potencial_empacable double precision not null, fecha timestamptz not null,
 usuario_email text not null, usuario_nombre text not null, usuario_puesto text not null
);
create index muestreos_proceso_owner_id_fecha_idx on public.muestreos_proceso(owner_id, fecha desc);
create table public.semaforo (
 uuid text primary key,
 owner_id uuid not null default auth.uid() references auth.users(id),
 cultivo text not null, categoria text not null, nivel text not null, nota text,
 fecha timestamptz not null, usuario_email text not null, usuario_nombre text not null,
 usuario_puesto text not null
);
create index semaforo_owner_id_fecha_idx on public.semaforo(owner_id, fecha desc);

create or replace function public.cb_is_admin()
returns boolean language sql stable security definer set search_path=''
as $function$ select exists(select 1 from public.cb_profiles p where p.user_id=auth.uid() and p.role='admin' and p.active=true) $function$;

create or replace function public.cb_redeem_invitation(p_code text, p_name text, p_puesto text)
returns boolean language plpgsql security definer set search_path=''
as $function$
declare v_email text; v_updated int;
begin
 if auth.uid() is null then raise exception 'Autenticación requerida'; end if;
 select lower(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'Confirma tu correo antes de continuar'; end if;
 if exists(select 1 from public.cb_profiles where user_id=auth.uid()) then raise exception 'Esta cuenta ya está registrada'; end if;
 if length(trim(p_name))<2 or length(trim(p_puesto))<2 then raise exception 'Nombre y puesto obligatorios'; end if;
 update public.cb_invitations i set used_by=auth.uid()
 where i.code=upper(trim(p_code)) and i.used_by is null and i.expires_at>now()
 and exists(select 1 from public.cb_profiles p where p.user_id=i.created_by and p.role='admin' and p.active=true);
 get diagnostics v_updated=row_count;
 if v_updated<>1 then return false; end if;
 insert into public.cb_profiles(user_id,email,display_name,puesto,role,active)
 values(auth.uid(),v_email,left(trim(p_name),120),left(trim(p_puesto),100),'trabajador',true);
 return true;
end $function$;

create or replace function public.cb_owner_verified_profile()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
 if new.email_confirmed_at is not null
 and lower(new.email) in ('fernanda.var.pre@gmail.com','yamilethklunder@gmail.com')
 and (old.email_confirmed_at is null or old.email_confirmed_at is distinct from new.email_confirmed_at) then
  insert into public.cb_profiles(user_id,email,display_name,puesto,role,active)
  values(new.id,lower(new.email),
   case when lower(new.email)='yamilethklunder@gmail.com' then 'Yamileth Klunder' else 'Fernanda' end,
   case when lower(new.email)='yamilethklunder@gmail.com' then 'Administradora' else 'Dueña' end,
   'admin',true)
  on conflict(user_id) do update set role='admin',active=true,email=excluded.email;
 end if;
 return new;
end $function$;

create trigger cb_owner_verified after update of email_confirmed_at on auth.users
for each row execute function public.cb_owner_verified_profile();

alter table public.cb_profiles enable row level security;
alter table public.cb_invitations enable row level security;
alter table public.cb_app_config enable row level security;
alter table public.muestreos_anden enable row level security;
alter table public.muestreos_proceso enable row level security;
alter table public.semaforo enable row level security;

create policy cb_app_config_read on public.cb_app_config for select to authenticated using (true);
create policy cb_invitation_admin_insert on public.cb_invitations for insert to authenticated
with check (public.cb_is_admin() and created_by=auth.uid() and used_by is null and expires_at>now());
create policy cb_invitation_admin_select on public.cb_invitations for select to authenticated
using (public.cb_is_admin() and created_by=auth.uid());
create policy cb_profiles_admin_read on public.cb_profiles for select to authenticated using (public.cb_is_admin());
create policy cb_profiles_self_read on public.cb_profiles for select to authenticated using (user_id=auth.uid());

create policy cb_admin_anden_read on public.muestreos_anden for select to authenticated using (public.cb_is_admin());
create policy cb_admin_anden_update on public.muestreos_anden for update to authenticated using (public.cb_is_admin()) with check (public.cb_is_admin());
create policy muestreos_anden_insert_own on public.muestreos_anden for insert to authenticated
with check (owner_id=(select auth.uid()) and exists(select 1 from public.cb_profiles p where p.user_id=(select auth.uid()) and p.active));
create policy muestreos_anden_read_own on public.muestreos_anden for select to authenticated using (owner_id=(select auth.uid()));
create policy muestreos_anden_update_own on public.muestreos_anden for update to authenticated using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()));

create policy cb_admin_proceso_read on public.muestreos_proceso for select to authenticated using (public.cb_is_admin());
create policy cb_admin_proceso_update on public.muestreos_proceso for update to authenticated using (public.cb_is_admin()) with check (public.cb_is_admin());
create policy muestreos_proceso_insert_own on public.muestreos_proceso for insert to authenticated
with check (owner_id=(select auth.uid()) and exists(select 1 from public.cb_profiles p where p.user_id=(select auth.uid()) and p.active));
create policy muestreos_proceso_read_own on public.muestreos_proceso for select to authenticated using (owner_id=(select auth.uid()));
create policy muestreos_proceso_update_own on public.muestreos_proceso for update to authenticated using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()));

create policy cb_admin_semaforo_read on public.semaforo for select to authenticated using (public.cb_is_admin());
create policy semaforo_insert_own on public.semaforo for insert to authenticated
with check (owner_id=(select auth.uid()) and exists(select 1 from public.cb_profiles p where p.user_id=(select auth.uid()) and p.active));
create policy semaforo_read_own on public.semaforo for select to authenticated using (owner_id=(select auth.uid()));

grant usage on schema public to authenticated, anon;
grant select on public.cb_app_config to authenticated;
grant select on public.cb_profiles to authenticated;
grant select,insert on public.cb_invitations to authenticated;
grant select,insert,update on public.muestreos_anden, public.muestreos_proceso to authenticated;
grant select,insert on public.semaforo to authenticated;
revoke all on function public.cb_is_admin() from public;
grant execute on function public.cb_is_admin() to authenticated;
revoke all on function public.cb_redeem_invitation(text,text,text) from public;
grant execute on function public.cb_redeem_invitation(text,text,text) to authenticated;
