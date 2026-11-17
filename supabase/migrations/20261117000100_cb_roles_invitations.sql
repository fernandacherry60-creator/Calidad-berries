-- Calidad Berries: identidades compartidas entre dispositivos.
-- Ejecutar únicamente en el proyecto Supabase correcto tras respaldo.
-- No altera tablas de muestreos ni usuarios locales existentes.
create table if not exists public.cb_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  puesto text not null default 'Trabajador',
  role text not null default 'trabajador' check (role in ('admin','trabajador')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.cb_invitations (
  code text primary key,
  role text not null default 'trabajador' check (role = 'trabajador'),
  created_by uuid not null references auth.users(id),
  used_by uuid unique references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days')
);
create index if not exists cb_invitations_creator_idx on public.cb_invitations(created_by);
alter table public.cb_profiles enable row level security;
alter table public.cb_invitations enable row level security;
revoke all on public.cb_profiles, public.cb_invitations from anon;
grant select on public.cb_profiles to authenticated;
grant select, insert on public.cb_invitations to authenticated;
create or replace function public.cb_is_admin()
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (select 1 from public.cb_profiles p
  where p.user_id = (select auth.uid()) and p.role = 'admin' and p.active);
$$;
revoke all on function public.cb_is_admin() from public, anon;
grant execute on function public.cb_is_admin() to authenticated;
drop policy if exists cb_profiles_select on public.cb_profiles;
create policy cb_profiles_select on public.cb_profiles for select to authenticated
using (user_id = (select auth.uid()) or public.cb_is_admin());
drop policy if exists cb_invitations_select on public.cb_invitations;
create policy cb_invitations_select on public.cb_invitations for select to authenticated
using (created_by = (select auth.uid()) and public.cb_is_admin());
drop policy if exists cb_invitations_insert on public.cb_invitations;
create policy cb_invitations_insert on public.cb_invitations for insert to authenticated
with check (created_by = (select auth.uid()) and role = 'trabajador'
and used_by is null and public.cb_is_admin());
-- El canje es atómico y comprueba la invitación sin exponer su lectura.
create or replace function public.cb_redeem_invitation(
  p_code text, p_display_name text, p_puesto text
) returns boolean language plpgsql security definer
set search_path = '' as $$
declare v_inv public.cb_invitations%rowtype; v_email text;
begin
  if auth.uid() is null or length(trim(p_display_name)) < 3 then return false; end if;
  select email into v_email from auth.users where id = auth.uid();
  if v_email is null then return false; end if;
  select * into v_inv from public.cb_invitations
    where code = upper(trim(p_code)) and used_by is null and expires_at > now()
    for update;
  if not found then return false; end if;
  if exists (select 1 from public.cb_profiles where user_id = auth.uid()) then return false; end if;
  insert into public.cb_profiles(user_id,email,display_name,puesto,role)
    values(auth.uid(),v_email,trim(p_display_name),trim(p_puesto),'trabajador');
  update public.cb_invitations set used_by = auth.uid() where code = v_inv.code;
  return true;
end;
$$;
revoke all on function public.cb_redeem_invitation(text,text,text) from public, anon;
grant execute on function public.cb_redeem_invitation(text,text,text) to authenticated;
-- IMPORTANTE: crear primero la cuenta del dueño en Supabase Auth y luego
-- asignarle el rol con SQL ejecutado desde el panel SQL, NO desde Flutter:
-- insert into public.cb_profiles(user_id,email,display_name,puesto,role)
-- select id,email,'Dueño','Administrador','admin' from auth.users
-- where email = 'CORREO_REAL_DEL_DUENO';
-- Nunca agregar una service_role key a la aplicación.
