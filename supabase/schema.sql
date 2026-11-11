-- =====================================================================
-- KAFEL VENTAS · Esquema de base de datos v1 (Supabase / PostgreSQL)
-- Pégalo completo en: Supabase → SQL Editor → New query → Run.
-- Se puede ejecutar más de una vez (es re-ejecutable) sin duplicar datos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABLAS
-- ---------------------------------------------------------------------

-- Grupos (uno por coordinador). El código lo comparte con sus vendedores.
create table if not exists public.groups (
  id             uuid primary key default gen_random_uuid(),
  coordinator_id uuid not null unique,
  name           text not null,
  code           text not null unique,
  created_at     timestamptz not null default now()
);

-- Perfiles (1 por usuario de Supabase Auth)
create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  role              text not null check (role in ('vendedor','coordinador')),
  email             text not null,
  username          text not null,
  whatsapp          text not null,
  group_id          uuid references public.groups(id) on delete set null,
  status            text not null default 'pendiente'
                    check (status in ('pendiente','activo','rechazado','retirado')),
  monthly_goal      numeric(14,0) not null default 0 check (monthly_goal >= 0),
  terms_accepted_at timestamptz not null default now(),
  created_at        timestamptz not null default now()
);
create unique index if not exists profiles_username_uq on public.profiles (lower(username));
create index if not exists profiles_group_idx on public.profiles (group_id);

do $$ begin
  alter table public.groups
    add constraint groups_coordinator_fk
    foreign key (coordinator_id) references public.profiles(id) on delete cascade;
exception when duplicate_object then null; end $$;

-- Catálogo base (lo administras tú desde el SQL Editor; el coordinador NO lo puede cambiar)
create table if not exists public.catalog (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  kind        text not null check (kind in ('unica','mensualidad')),
  description text not null default '',
  benefits    text not null default '',          -- una ventaja por línea
  base_price  numeric(14,0) not null check (base_price >= 0),  -- precio base (o precio fijo de la mensualidad)
  seller_pct  numeric(5,2) not null default 20 check (seller_pct between 0 and 100), -- % del vendedor (solo mensualidades)
  active      boolean not null default true,
  sort        int not null default 0,
  created_at  timestamptz not null default now()
);

-- Precios por grupo (los pone el coordinador)
create table if not exists public.group_prices (
  group_id          uuid not null references public.groups(id) on delete cascade,
  catalog_id        uuid not null references public.catalog(id) on delete cascade,
  sale_price        numeric(14,0) not null check (sale_price >= 0),
  seller_commission numeric(14,0) not null default 0 check (seller_commission >= 0),
  updated_at        timestamptz not null default now(),
  primary key (group_id, catalog_id)
);

-- Clientes de cada vendedor
create table if not exists public.clients (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups(id) on delete cascade,
  seller_id     uuid not null references public.profiles(id) on delete cascade,
  name          text not null check (length(btrim(name)) >= 2),
  business      text not null default '',
  phone         text not null default '',
  city          text not null default '',
  notes         text not null default '',
  status        text not null default 'visitado'
                check (status in ('visitado','seguimiento','vendido','descartado')),
  next_followup date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists clients_seller_idx on public.clients (seller_id);
create index if not exists clients_group_idx  on public.clients (group_id);

-- Gestiones (llamadas, visitas, WhatsApp...) hechas por el vendedor sobre un cliente
create table if not exists public.activities (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups(id) on delete cascade,
  seller_id  uuid not null references public.profiles(id) on delete cascade,
  client_id  uuid not null references public.clients(id) on delete cascade,
  type       text not null check (type in ('llamada','whatsapp','visita','cotizacion','seguimiento','otro')),
  note       text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists activities_client_idx on public.activities (client_id);
create index if not exists activities_group_idx  on public.activities (group_id, created_at);

-- Ventas (cada una con su ticket)
create sequence if not exists public.ticket_seq;
create table if not exists public.sales (
  id                uuid primary key default gen_random_uuid(),
  ticket            text not null unique default ('KF-' || lpad(nextval('public.ticket_seq')::text, 5, '0')),
  group_id          uuid not null references public.groups(id) on delete cascade,
  seller_id         uuid not null references public.profiles(id) on delete cascade,
  client_id         uuid not null references public.clients(id) on delete restrict,
  catalog_id        uuid references public.catalog(id) on delete set null,
  product_name      text not null,
  kind              text not null check (kind in ('unica','mensualidad')),
  base_price        numeric(14,0) not null,
  sale_price        numeric(14,0) not null,
  seller_commission numeric(14,0) not null default 0,
  coordinator_profit numeric(14,0) not null default 0,
  sold_at           timestamptz not null default now(),
  delivery_status   text not null default 'pendiente'
                    check (delivery_status in ('pendiente','en_desarrollo','entregado')),
  payment_status    text not null default 'pendiente'
                    check (payment_status in ('pendiente','en_revision','pagado','rechazado','no_aplica')),
  paid_at           timestamptz,
  notes             text not null default ''
);
create index if not exists sales_group_idx  on public.sales (group_id, sold_at);
create index if not exists sales_seller_idx on public.sales (seller_id, sold_at);

-- Suscripciones (se crean al vender una mensualidad)
create table if not exists public.subscriptions (
  id                        uuid primary key default gen_random_uuid(),
  sale_id                   uuid not null unique references public.sales(id) on delete cascade,
  group_id                  uuid not null references public.groups(id) on delete cascade,
  seller_id                 uuid not null references public.profiles(id) on delete cascade,
  client_id                 uuid not null references public.clients(id) on delete cascade,
  catalog_id                uuid references public.catalog(id) on delete set null,
  plan_name                 text not null,
  monthly_price             numeric(14,0) not null,
  seller_pct                numeric(5,2) not null,
  seller_monthly_commission numeric(14,0) not null,
  status                    text not null default 'activa' check (status in ('activa','pausada','cancelada')),
  started_at                date not null default current_date,
  created_at                timestamptz not null default now()
);
create index if not exists subscriptions_group_idx  on public.subscriptions (group_id);
create index if not exists subscriptions_seller_idx on public.subscriptions (seller_id);

-- Pagos con comprobante (venta única o mes de una suscripción)
create table if not exists public.payments (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null references public.groups(id) on delete cascade,
  seller_id       uuid not null references public.profiles(id) on delete cascade,
  sale_id         uuid references public.sales(id) on delete cascade,
  subscription_id uuid references public.subscriptions(id) on delete cascade,
  period          date,
  amount          numeric(14,0) not null,
  receipt_path    text not null,
  note            text not null default '',
  status          text not null default 'en_revision' check (status in ('en_revision','aprobado','rechazado')),
  reviewed_by     uuid references public.profiles(id) on delete set null,
  reviewed_at     timestamptz,
  review_note     text not null default '',
  created_at      timestamptz not null default now(),
  check ((sale_id is not null) <> (subscription_id is not null)),
  check (subscription_id is null or period is not null)
);
create unique index if not exists payments_sale_uq on public.payments (sale_id)
  where sale_id is not null and status in ('en_revision','aprobado');
create unique index if not exists payments_sub_period_uq on public.payments (subscription_id, period)
  where subscription_id is not null and status in ('en_revision','aprobado');
create index if not exists payments_group_idx on public.payments (group_id, status);

-- Chat (recipient_id null = chat del grupo; con valor = mensaje directo)
create table if not exists public.messages (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  sender_id    uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid references public.profiles(id) on delete cascade,
  body         text not null check (length(btrim(body)) between 1 and 2000),
  created_at   timestamptz not null default now()
);
create index if not exists messages_group_idx on public.messages (group_id, created_at);

-- ---------------------------------------------------------------------
-- 2. FUNCIONES AUXILIARES
-- ---------------------------------------------------------------------

-- Grupo y rol del usuario actual (solo si su cuenta está activa)
create or replace function public.my_group() returns uuid
language sql stable security definer set search_path = public as $$
  select group_id from public.profiles where id = auth.uid() and status = 'activo'
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and status = 'activo'
$$;

create or replace function public.gen_group_code() returns text
language plpgsql as $$
declare chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; s text := ''; i int;
begin
  for i in 1..8 loop
    s := s || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  end loop;
  return substr(s, 1, 4) || '-' || substr(s, 5, 4);
end $$;

-- ¿Puedo escribirle a este usuario? (coordinador → sus vendedores; vendedor → su coordinador)
create or replace function public.can_message(p_recipient uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when p_recipient is null then my_group() is not null
    when my_role() = 'coordinador' then exists (
      select 1 from public.profiles p
      where p.id = p_recipient and p.group_id = my_group() and p.role = 'vendedor' and p.status = 'activo')
    when my_role() = 'vendedor' then exists (
      select 1 from public.profiles p
      where p.id = p_recipient and p.group_id = my_group() and p.role = 'coordinador')
    else false end
$$;

-- Disponibles antes de iniciar sesión (formulario de registro)
create or replace function public.check_group_code(p_code text) returns text
language sql stable security definer set search_path = public as $$
  select g.name from public.groups g
  where replace(g.code, '-', '') = regexp_replace(upper(coalesce(p_code, '')), '[^A-Z0-9]', '', 'g')
  limit 1
$$;

create or replace function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where lower(username) = lower(btrim(coalesce(p_username, ''))))
$$;

-- ---------------------------------------------------------------------
-- 3. ALTA DE USUARIOS (se ejecuta al crear la cuenta en Supabase Auth)
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role text := m->>'rol';
  v_user text := btrim(coalesce(m->>'username', ''));
  v_wa   text := regexp_replace(coalesce(m->>'whatsapp', ''), '\D', '', 'g');
  v_code text := regexp_replace(upper(coalesce(m->>'code', '')), '[^A-Z0-9]', '', 'g');
  v_group public.groups%rowtype;
  v_new_code text;
begin
  if v_role is null or v_role not in ('vendedor','coordinador') then raise exception 'Rol inválido'; end if;
  if length(v_user) < 3 or length(v_user) > 30 then raise exception 'Nombre de usuario inválido'; end if;
  if length(v_wa) < 7 or length(v_wa) > 15 then raise exception 'Número de WhatsApp inválido'; end if;
  if coalesce(m->>'terms', '') <> 'true' then raise exception 'Debes aceptar el tratamiento de datos personales'; end if;

  if v_role = 'vendedor' then
    select * into v_group from public.groups where replace(code, '-', '') = v_code;
    if not found then raise exception 'Código de grupo inválido'; end if;
    insert into public.profiles (id, role, email, username, whatsapp, group_id, status)
    values (new.id, 'vendedor', new.email, v_user, v_wa, v_group.id, 'pendiente');
  else
    insert into public.profiles (id, role, email, username, whatsapp, status)
    values (new.id, 'coordinador', new.email, v_user, v_wa, 'activo');
    loop
      v_new_code := public.gen_group_code();
      exit when not exists (select 1 from public.groups where code = v_new_code);
    end loop;
    insert into public.groups (coordinator_id, name, code)
    values (new.id, 'Grupo de ' || v_user, v_new_code) returning * into v_group;
    update public.profiles set group_id = v_group.id where id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 4. TRIGGERS DE INTEGRIDAD
-- ---------------------------------------------------------------------

-- Precios del grupo: valida reglas (el coordinador no puede vender bajo el precio base)
create or replace function public.group_prices_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.catalog%rowtype;
begin
  select * into c from public.catalog where id = new.catalog_id;
  if c.kind = 'mensualidad' then
    -- Mensualidades: precio fijo y comisión fija (no editables)
    new.sale_price := c.base_price;
    new.seller_commission := round(c.base_price * c.seller_pct / 100);
  else
    if new.sale_price < c.base_price then
      raise exception 'El precio de venta no puede ser menor al precio base (%)', c.base_price;
    end if;
    if new.seller_commission > new.sale_price - c.base_price then
      raise exception 'La comisión del vendedor no puede superar el excedente (%)', new.sale_price - c.base_price;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists group_prices_guard_t on public.group_prices;
create trigger group_prices_guard_t before insert or update on public.group_prices
  for each row execute function public.group_prices_guard();

-- Al crear un grupo, se le asignan todos los productos del catálogo
create or replace function public.seed_group_prices() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.group_prices (group_id, catalog_id, sale_price, seller_commission)
  select new.id, c.id, c.base_price, 0 from public.catalog c
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists seed_group_prices_t on public.groups;
create trigger seed_group_prices_t after insert on public.groups
  for each row execute function public.seed_group_prices();

-- Al agregar un producto al catálogo, se asigna a todos los grupos
create or replace function public.catalog_to_groups() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.group_prices (group_id, catalog_id, sale_price, seller_commission)
  select g.id, new.id, new.base_price, 0 from public.groups g
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists catalog_to_groups_t on public.catalog;
create trigger catalog_to_groups_t after insert on public.catalog
  for each row execute function public.catalog_to_groups();

-- Si cambias el precio base del catálogo, se reajustan los precios de los grupos
create or replace function public.catalog_price_changed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.base_price is distinct from old.base_price or new.seller_pct is distinct from old.seller_pct then
    update public.group_prices gp set
      sale_price = greatest(gp.sale_price, new.base_price),
      seller_commission = least(gp.seller_commission, greatest(gp.sale_price, new.base_price) - new.base_price)
    where gp.catalog_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists catalog_price_changed_t on public.catalog;
create trigger catalog_price_changed_t after update on public.catalog
  for each row execute function public.catalog_price_changed();

-- Propietario automático (nadie puede falsificar de quién es un registro)
create or replace function public.set_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.group_id := public.my_group();
  new.seller_id := auth.uid();
  if new.group_id is null then raise exception 'Tu cuenta no está activa en un grupo'; end if;
  return new;
end $$;
drop trigger if exists clients_owner_t on public.clients;
create trigger clients_owner_t before insert on public.clients
  for each row execute function public.set_owner();
drop trigger if exists activities_owner_t on public.activities;
create trigger activities_owner_t before insert on public.activities
  for each row execute function public.set_owner();

create or replace function public.set_message_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.group_id := public.my_group();
  new.sender_id := auth.uid();
  if new.group_id is null then raise exception 'Tu cuenta no está activa en un grupo'; end if;
  return new;
end $$;
drop trigger if exists messages_owner_t on public.messages;
create trigger messages_owner_t before insert on public.messages
  for each row execute function public.set_message_owner();

-- Un cliente solo pasa a "vendido" registrando una venta; y no vuelve atrás
create or replace function public.clients_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status = 'vendido' and old.status <> 'vendido'
     and coalesce(current_setting('app.in_sale', true), 'off') <> 'on' then
    raise exception 'Para marcar un cliente como vendido registra la venta';
  end if;
  if old.status = 'vendido' and new.status <> 'vendido' then
    raise exception 'Un cliente con venta no puede volver a otro estado';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists clients_guard_t on public.clients;
create trigger clients_guard_t before update on public.clients
  for each row execute function public.clients_guard();

-- La gestión solo puede registrarse sobre clientes propios
create or replace function public.activities_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.clients c where c.id = new.client_id and c.seller_id = auth.uid()) then
    raise exception 'Cliente no encontrado';
  end if;
  return new;
end $$;
drop trigger if exists activities_guard_t on public.activities;
create trigger activities_guard_t before insert on public.activities
  for each row execute function public.activities_guard();

-- ---------------------------------------------------------------------
-- 5. FUNCIONES DE NEGOCIO (RPC)
-- ---------------------------------------------------------------------

-- Coordinador: aprobar / rechazar / retirar vendedores
create or replace function public.set_member_status(p_seller uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_role() is distinct from 'coordinador' then raise exception 'Solo el coordinador puede hacer esto'; end if;
  if p_status not in ('activo','rechazado','retirado') then raise exception 'Estado inválido'; end if;
  update public.profiles set status = p_status
  where id = p_seller and group_id = my_group() and role = 'vendedor';
  if not found then raise exception 'Vendedor no encontrado en tu grupo'; end if;
end $$;

-- Coordinador: meta mensual de un vendedor
create or replace function public.set_goal(p_seller uuid, p_amount numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_role() is distinct from 'coordinador' then raise exception 'Solo el coordinador puede hacer esto'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'Meta inválida'; end if;
  update public.profiles set monthly_goal = round(p_amount)
  where id = p_seller and group_id = my_group() and role = 'vendedor';
  if not found then raise exception 'Vendedor no encontrado en tu grupo'; end if;
end $$;

-- Vendedor: registrar una venta (los precios los toma el servidor, no el navegador)
create or replace function public.create_sale(p_client uuid, p_catalog uuid, p_notes text default '')
returns public.sales
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_group uuid := my_group();
  c public.clients%rowtype; cat public.catalog%rowtype; gp public.group_prices%rowtype; s public.sales%rowtype;
begin
  if my_role() is distinct from 'vendedor' then raise exception 'Solo los vendedores registran ventas'; end if;
  select * into c from public.clients where id = p_client and seller_id = v_uid and group_id = v_group;
  if not found then raise exception 'Cliente no encontrado'; end if;
  select * into cat from public.catalog where id = p_catalog and active;
  if not found then raise exception 'Producto no disponible'; end if;
  select * into gp from public.group_prices where group_id = v_group and catalog_id = p_catalog;
  if not found then raise exception 'El producto no tiene precio en tu grupo'; end if;

  perform set_config('app.in_sale', 'on', true);
  update public.clients set status = 'vendido' where id = c.id;
  perform set_config('app.in_sale', 'off', true);

  if cat.kind = 'unica' then
    insert into public.sales (group_id, seller_id, client_id, catalog_id, product_name, kind,
                              base_price, sale_price, seller_commission, coordinator_profit, payment_status, notes)
    values (v_group, v_uid, c.id, cat.id, cat.name, 'unica',
            cat.base_price, gp.sale_price, gp.seller_commission,
            gp.sale_price - cat.base_price - gp.seller_commission, 'pendiente', coalesce(p_notes, ''))
    returning * into s;
  else
    insert into public.sales (group_id, seller_id, client_id, catalog_id, product_name, kind,
                              base_price, sale_price, seller_commission, coordinator_profit, payment_status, notes)
    values (v_group, v_uid, c.id, cat.id, cat.name, 'mensualidad',
            cat.base_price, gp.sale_price, 0, 0, 'no_aplica', coalesce(p_notes, ''))
    returning * into s;
    insert into public.subscriptions (sale_id, group_id, seller_id, client_id, catalog_id, plan_name,
                                      monthly_price, seller_pct, seller_monthly_commission)
    values (s.id, v_group, v_uid, c.id, cat.id, cat.name,
            gp.sale_price, cat.seller_pct, round(gp.sale_price * cat.seller_pct / 100));
  end if;
  return s;
end $$;

-- Vendedor: subir comprobante (venta única o mes de una suscripción)
create or replace function public.submit_payment(
  p_sale uuid, p_subscription uuid, p_period date, p_path text, p_note text default '')
returns public.payments
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_group uuid := my_group();
  s public.sales%rowtype; sub public.subscriptions%rowtype; pay public.payments%rowtype; v_period date;
begin
  if my_role() is distinct from 'vendedor' then raise exception 'Solo los vendedores suben comprobantes'; end if;
  if (p_sale is null) = (p_subscription is null) then raise exception 'Indica una venta o una suscripción'; end if;
  if p_path is null or p_path not like (v_group::text || '/' || v_uid::text || '/%') then
    raise exception 'Ruta de comprobante inválida';
  end if;

  begin
    if p_sale is not null then
      select * into s from public.sales where id = p_sale and seller_id = v_uid and group_id = v_group and kind = 'unica';
      if not found then raise exception 'Venta no encontrada'; end if;
      if s.payment_status not in ('pendiente','rechazado') then
        raise exception 'Esta venta ya tiene un comprobante en revisión o aprobado';
      end if;
      insert into public.payments (group_id, seller_id, sale_id, amount, receipt_path, note)
      values (v_group, v_uid, s.id, s.sale_price, p_path, coalesce(p_note, '')) returning * into pay;
      update public.sales set payment_status = 'en_revision' where id = s.id;
    else
      select * into sub from public.subscriptions where id = p_subscription and seller_id = v_uid and group_id = v_group;
      if not found then raise exception 'Suscripción no encontrada'; end if;
      if sub.status <> 'activa' then raise exception 'La suscripción no está activa'; end if;
      v_period := date_trunc('month', coalesce(p_period, current_date))::date;
      if v_period > date_trunc('month', current_date)::date or v_period < date_trunc('month', sub.started_at)::date then
        raise exception 'Mes inválido para esta suscripción';
      end if;
      insert into public.payments (group_id, seller_id, subscription_id, period, amount, receipt_path, note)
      values (v_group, v_uid, sub.id, v_period, sub.monthly_price, p_path, coalesce(p_note, '')) returning * into pay;
    end if;
  exception when unique_violation then
    raise exception 'Ya existe un comprobante en revisión o aprobado para este pago';
  end;
  return pay;
end $$;

-- Coordinador: aprobar o rechazar un comprobante
create or replace function public.review_payment(p_payment uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare pay public.payments%rowtype;
begin
  if my_role() is distinct from 'coordinador' then raise exception 'Solo el coordinador puede revisar pagos'; end if;
  select * into pay from public.payments where id = p_payment and group_id = my_group() and status = 'en_revision' for update;
  if not found then raise exception 'Pago no encontrado o ya revisado'; end if;
  update public.payments set
    status = case when p_approve then 'aprobado' else 'rechazado' end,
    reviewed_by = auth.uid(), reviewed_at = now(), review_note = coalesce(p_note, '')
  where id = pay.id;
  if pay.sale_id is not null then
    update public.sales set
      payment_status = case when p_approve then 'pagado' else 'rechazado' end,
      paid_at = case when p_approve then now() else null end
    where id = pay.sale_id;
  end if;
end $$;

-- Coordinador: estado de entrega de una venta
create or replace function public.set_delivery(p_sale uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_role() is distinct from 'coordinador' then raise exception 'Solo el coordinador puede hacer esto'; end if;
  if p_status not in ('pendiente','en_desarrollo','entregado') then raise exception 'Estado inválido'; end if;
  update public.sales set delivery_status = p_status where id = p_sale and group_id = my_group();
  if not found then raise exception 'Venta no encontrada'; end if;
end $$;

-- Coordinador: pausar / cancelar / reactivar una suscripción
create or replace function public.set_subscription_status(p_sub uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_role() is distinct from 'coordinador' then raise exception 'Solo el coordinador puede hacer esto'; end if;
  if p_status not in ('activa','pausada','cancelada') then raise exception 'Estado inválido'; end if;
  update public.subscriptions set status = p_status where id = p_sub and group_id = my_group();
  if not found then raise exception 'Suscripción no encontrada'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 6. SEGURIDAD (RLS): cada quien ve solo lo de su grupo / lo suyo
-- ---------------------------------------------------------------------
alter table public.groups        enable row level security;
alter table public.profiles      enable row level security;
alter table public.catalog       enable row level security;
alter table public.group_prices  enable row level security;
alter table public.clients       enable row level security;
alter table public.activities    enable row level security;
alter table public.sales         enable row level security;
alter table public.subscriptions enable row level security;
alter table public.payments      enable row level security;
alter table public.messages      enable row level security;

drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups for select to authenticated
  using (coordinator_id = auth.uid() or id = my_group());

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid()
         or (group_id is not null and group_id = my_group()
             and (status = 'activo' or my_role() = 'coordinador')));
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists catalog_select on public.catalog;
create policy catalog_select on public.catalog for select to authenticated using (active);

drop policy if exists group_prices_select on public.group_prices;
create policy group_prices_select on public.group_prices for select to authenticated
  using (group_id = my_group());
drop policy if exists group_prices_update on public.group_prices;
create policy group_prices_update on public.group_prices for update to authenticated
  using (group_id = my_group() and my_role() = 'coordinador')
  with check (group_id = my_group() and my_role() = 'coordinador');

drop policy if exists clients_select on public.clients;
create policy clients_select on public.clients for select to authenticated
  using (group_id = my_group() and (my_role() = 'coordinador' or seller_id = auth.uid()));
drop policy if exists clients_insert on public.clients;
create policy clients_insert on public.clients for insert to authenticated
  with check (my_role() = 'vendedor' and group_id = my_group() and seller_id = auth.uid());
drop policy if exists clients_update on public.clients;
create policy clients_update on public.clients for update to authenticated
  using (my_role() = 'vendedor' and seller_id = auth.uid() and group_id = my_group())
  with check (my_role() = 'vendedor' and seller_id = auth.uid() and group_id = my_group());

drop policy if exists activities_select on public.activities;
create policy activities_select on public.activities for select to authenticated
  using (group_id = my_group() and (my_role() = 'coordinador' or seller_id = auth.uid()));
drop policy if exists activities_insert on public.activities;
create policy activities_insert on public.activities for insert to authenticated
  with check (my_role() = 'vendedor' and group_id = my_group() and seller_id = auth.uid());

drop policy if exists sales_select on public.sales;
create policy sales_select on public.sales for select to authenticated
  using (group_id = my_group() and (my_role() = 'coordinador' or seller_id = auth.uid()));
drop policy if exists subscriptions_select on public.subscriptions;
create policy subscriptions_select on public.subscriptions for select to authenticated
  using (group_id = my_group() and (my_role() = 'coordinador' or seller_id = auth.uid()));
drop policy if exists payments_select on public.payments;
create policy payments_select on public.payments for select to authenticated
  using (group_id = my_group() and (my_role() = 'coordinador' or seller_id = auth.uid()));

drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages for select to authenticated
  using (group_id = my_group()
         and (recipient_id is null or recipient_id = auth.uid() or sender_id = auth.uid()));
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert to authenticated
  with check (group_id = my_group() and sender_id = auth.uid() and can_message(recipient_id));

-- ---------------------------------------------------------------------
-- 7. PERMISOS (principio de mínimo privilegio)
-- ---------------------------------------------------------------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

grant select on public.groups, public.profiles, public.catalog, public.group_prices, public.clients,
                public.activities, public.sales, public.subscriptions, public.payments, public.messages
  to authenticated;
grant update (username, whatsapp) on public.profiles to authenticated;
grant update (sale_price, seller_commission) on public.group_prices to authenticated;
grant insert (name, business, phone, city, notes, next_followup) on public.clients to authenticated;
grant update (name, business, phone, city, notes, status, next_followup) on public.clients to authenticated;
grant insert (client_id, type, note) on public.activities to authenticated;
grant insert (recipient_id, body) on public.messages to authenticated;

grant execute on function public.my_group(), public.my_role(), public.can_message(uuid),
  public.set_member_status(uuid, text), public.set_goal(uuid, numeric),
  public.create_sale(uuid, uuid, text), public.submit_payment(uuid, uuid, date, text, text),
  public.review_payment(uuid, boolean, text), public.set_delivery(uuid, text),
  public.set_subscription_status(uuid, text)
  to authenticated;
grant execute on function public.check_group_code(text), public.username_available(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 8. COMPROBANTES (Storage privado) Y TIEMPO REAL
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprobantes', 'comprobantes', false, 5242880,
        array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists comprobantes_insert on storage.objects;
create policy comprobantes_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'comprobantes' and my_role() = 'vendedor'
              and (storage.foldername(name))[1] = my_group()::text
              and (storage.foldername(name))[2] = auth.uid()::text);
drop policy if exists comprobantes_select on storage.objects;
create policy comprobantes_select on storage.objects for select to authenticated
  using (bucket_id = 'comprobantes' and (storage.foldername(name))[1] = my_group()::text
         and (my_role() = 'coordinador' or (storage.foldername(name))[2] = auth.uid()::text));

do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['messages','group_prices','profiles','payments','sales','subscriptions'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 9. CATÁLOGO DE EJEMPLO  ← REEMPLAZA CON TUS PRODUCTOS REALES
--    (solo se inserta si el catálogo está vacío)
-- ---------------------------------------------------------------------
insert into public.catalog (name, kind, description, benefits, base_price, seller_pct, sort)
select * from (values
  ('Catálogo digital (EJEMPLO)', 'unica',
   'Catálogo web de un solo archivo con pedidos por WhatsApp.',
   E'Pedidos directo a WhatsApp\nPanel de administración oculto\nFunciona en celular', 150000, 0, 1),
  ('Página web de servicios (EJEMPLO)', 'unica',
   'Página web profesional para presentar el negocio.',
   E'Diseño a la medida\nBotón de WhatsApp\nListo para publicar', 300000, 0, 2),
  ('Mensualidad soporte (EJEMPLO)', 'mensualidad',
   'Mantenimiento y actualizaciones mes a mes.',
   E'Cambios de precios y fotos\nSoporte por WhatsApp\nCopias de seguridad', 20000, 20, 3)
) as v(name, kind, description, benefits, base_price, seller_pct, sort)
where not exists (select 1 from public.catalog);
