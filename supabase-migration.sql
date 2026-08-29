-- ============================================================
-- EUSES DIHEI – GEMEINSAME DATENBASIS
-- HomeDeluxe + MaxMio
-- ============================================================
-- Diese Migration ist wiederholbar. Sie löscht keine alten Tabellen.

create extension if not exists pgcrypto;

create table if not exists public.home_finder_properties (
  external_id text primary key,
  category text not null default 'maxmio'
    check (category in ('maxmio','homedeluxe')),
  entry_type text not null default 'listing'
    check (entry_type in ('listing','pipeline')),

  source text,
  source_listing_id text,
  source_url text,
  project_url text,
  project_name text,

  title text not null,
  description text,
  address text,
  zip text,
  city text,
  canton text,
  latitude double precision,
  longitude double precision,

  rooms numeric(4,1),
  living_area_m2 numeric(10,2),
  purchase_price_chf numeric(14,2),
  mandatory_parking_price_chf numeric(14,2),
  total_price_chf numeric(14,2),
  year_built integer,
  availability text,
  floor text,

  developer text,
  marketer text,
  project_status text,
  minergie boolean,
  building_right boolean not null default false,

  drive_minutes_duebendorf integer,
  drive_minutes_wohlen integer,
  drive_minutes_othmarsingen integer,

  ai_rating numeric(4,1),
  ai_summary text,
  ai_recommendation_reason text,
  advantages jsonb not null default '[]'::jsonb,
  disadvantages jsonb not null default '[]'::jsonb,

  discovered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.home_finder_state (
  external_id text primary key
    references public.home_finder_properties(external_id)
    on update cascade on delete cascade,
  status text not null default 'new'
    check (status in ('new','interesting','archive')),
  luca_vote smallint check (luca_vote in (-1,1)),
  gessi_vote smallint check (gessi_vote in (-1,1)),
  luca_favorite boolean not null default false,
  gessi_favorite boolean not null default false,
  luca_note text not null default '',
  gessi_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists home_finder_properties_category_idx
  on public.home_finder_properties(category);
create index if not exists home_finder_properties_discovered_idx
  on public.home_finder_properties(discovered_at desc);
create index if not exists home_finder_properties_city_idx
  on public.home_finder_properties(city);
create index if not exists home_finder_state_status_idx
  on public.home_finder_state(status);

create or replace function public.home_finder_set_category()
returns trigger
language plpgsql
as $$
begin
  if new.total_price_chf is not null then
    new.category := case
      when new.total_price_chf <= 1000000 then 'maxmio'
      else 'homedeluxe'
    end;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists home_finder_category_guard on public.home_finder_properties;
create trigger home_finder_category_guard
before insert or update on public.home_finder_properties
for each row execute function public.home_finder_set_category();

create or replace function public.home_finder_touch_state()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists home_finder_state_touch on public.home_finder_state;
create trigger home_finder_state_touch
before update on public.home_finder_state
for each row execute function public.home_finder_touch_state();

-- Die bestehende Website arbeitet wie bisher ohne Login mit dem Publishable Key.
alter table public.home_finder_properties enable row level security;
alter table public.home_finder_state enable row level security;

drop policy if exists "home_finder_properties_read" on public.home_finder_properties;
drop policy if exists "home_finder_properties_insert" on public.home_finder_properties;
drop policy if exists "home_finder_properties_update" on public.home_finder_properties;
drop policy if exists "home_finder_state_read" on public.home_finder_state;
drop policy if exists "home_finder_state_insert" on public.home_finder_state;
drop policy if exists "home_finder_state_update" on public.home_finder_state;

create policy "home_finder_properties_read"
  on public.home_finder_properties for select to anon, authenticated
  using (true);
create policy "home_finder_properties_insert"
  on public.home_finder_properties for insert to anon, authenticated
  with check (true);
create policy "home_finder_properties_update"
  on public.home_finder_properties for update to anon, authenticated
  using (true) with check (true);

create policy "home_finder_state_read"
  on public.home_finder_state for select to anon, authenticated
  using (true);
create policy "home_finder_state_insert"
  on public.home_finder_state for insert to anon, authenticated
  with check (true);
create policy "home_finder_state_update"
  on public.home_finder_state for update to anon, authenticated
  using (true) with check (true);

grant select,insert,update on public.home_finder_properties to anon,authenticated;
grant select,insert,update on public.home_finder_state to anon,authenticated;

-- ------------------------------------------------------------
-- Hilfsfunktionen für die einmalige Zusammenführung der drei
-- bisherigen Datenmodelle. Unterschiedliche Feldnamen werden
-- tolerant gelesen.
-- ------------------------------------------------------------

create or replace function public.hf_json_text(payload jsonb, keys text[])
returns text
language plpgsql immutable
as $$
declare key text; value text;
begin
  foreach key in array keys loop
    value := nullif(btrim(payload ->> key),'');
    if value is not null then return value; end if;
  end loop;
  return null;
end;
$$;

create or replace function public.hf_json_number(payload jsonb, keys text[])
returns numeric
language plpgsql immutable
as $$
declare key text; value text; cleaned text;
begin
  foreach key in array keys loop
    value := nullif(btrim(payload ->> key),'');
    if value is not null then
      cleaned := regexp_replace(replace(replace(value,'’',''),'''',''),'[^0-9,.-]','','g');
      cleaned := replace(cleaned,',','.');
      begin
        if cleaned not in ('','-','.', '-.') then return cleaned::numeric; end if;
      exception when others then null;
      end;
    end if;
  end loop;
  return null;
end;
$$;

create or replace function public.hf_json_boolean(payload jsonb, keys text[])
returns boolean
language plpgsql immutable
as $$
declare key text; value text;
begin
  foreach key in array keys loop
    value := lower(nullif(btrim(payload ->> key),''));
    if value in ('true','1','yes','ja') then return true; end if;
    if value in ('false','0','no','nein') then return false; end if;
  end loop;
  return false;
end;
$$;

create or replace function public.hf_json_array(payload jsonb, key_name text)
returns jsonb
language plpgsql immutable
as $$
declare value jsonb;
begin
  value := payload -> key_name;
  if jsonb_typeof(value) = 'array' then return value; end if;
  return '[]'::jsonb;
exception when others then return '[]'::jsonb;
end;
$$;

create or replace function public.hf_json_timestamp(payload jsonb, keys text[])
returns timestamptz
language plpgsql stable
as $$
declare key text; value text;
begin
  foreach key in array keys loop
    value := nullif(btrim(payload ->> key),'');
    if value is not null then
      begin return value::timestamptz;
      exception when others then null;
      end;
    end if;
  end loop;
  return now();
end;
$$;

create temp table if not exists hf_legacy_map (
  source_table text not null,
  legacy_id text not null,
  external_id text not null,
  primary key(source_table,legacy_id)
) on commit drop;

create or replace function public.hf_migrate_property_table(
  source_table text,
  category_hint text,
  type_hint text
)
returns void
language plpgsql
as $$
declare
  record_json jsonb;
  legacy_id text;
  external_key text;
  title_value text;
  city_value text;
  address_value text;
  source_url_value text;
  project_url_value text;
  purchase_value numeric;
  parking_value numeric;
  total_value numeric;
  rooms_value numeric;
  status_value text;
  archived_value boolean;
begin
  if to_regclass('public.' || quote_ident(source_table)) is null then return; end if;

  for record_json in execute format('select to_jsonb(t) from public.%I t',source_table) loop
    legacy_id := coalesce(public.hf_json_text(record_json,array['id']),md5(record_json::text));
    title_value := coalesce(public.hf_json_text(record_json,array['title','project_name']),case when type_hint='pipeline' then 'Kommendes Wohnprojekt' else 'Wohnung ohne Titel' end);
    city_value := public.hf_json_text(record_json,array['city','municipality','location','ort']);
    address_value := public.hf_json_text(record_json,array['address','adresse']);
    source_url_value := public.hf_json_text(record_json,array['source_url','listing_url','url','link']);
    project_url_value := public.hf_json_text(record_json,array['project_url']);
    external_key := coalesce(
      public.hf_json_text(record_json,array['external_id','source_listing_id','source_project_id']),
      'legacy-' || md5(coalesce(source_url_value,title_value || '-' || coalesce(city_value,'') || '-' || coalesce(address_value,'')))
    );

    purchase_value := public.hf_json_number(record_json,array['purchase_price_chf','estimated_price_from_chf','price']);
    parking_value := public.hf_json_number(record_json,array['mandatory_parking_price_chf','parking_price_chf']);
    -- In den bisherigen Tabellen enthält price_chf bereits den Gesamtpreis.
    total_value := public.hf_json_number(record_json,array['total_price_chf','price_chf']);
    if total_value is null then
      total_value := case when purchase_value is null then null else purchase_value + coalesce(parking_value,0) end;
    end if;
    rooms_value := public.hf_json_number(record_json,array['rooms','zimmer','expected_rooms']);
    status_value := lower(coalesce(public.hf_json_text(record_json,array['status']),'interesting'));
    archived_value := public.hf_json_boolean(record_json,array['is_archived']) or status_value in ('archived','rejected','archive');

    insert into public.home_finder_properties (
      external_id,category,entry_type,source,source_listing_id,source_url,project_url,project_name,
      title,description,address,zip,city,canton,latitude,longitude,rooms,living_area_m2,
      purchase_price_chf,mandatory_parking_price_chf,total_price_chf,year_built,availability,floor,
      developer,marketer,project_status,minergie,building_right,
      drive_minutes_duebendorf,drive_minutes_wohlen,drive_minutes_othmarsingen,
      ai_rating,ai_summary,ai_recommendation_reason,advantages,disadvantages,discovered_at,last_seen_at
    ) values (
      external_key,category_hint,type_hint,
      public.hf_json_text(record_json,array['source']),
      public.hf_json_text(record_json,array['source_listing_id','source_project_id']),
      source_url_value,coalesce(project_url_value,case when type_hint='pipeline' then source_url_value end),
      public.hf_json_text(record_json,array['project_name']),title_value,
      public.hf_json_text(record_json,array['description','status_details']),address_value,
      public.hf_json_text(record_json,array['zip','postal_code']),city_value,
      public.hf_json_text(record_json,array['canton']),
      public.hf_json_number(record_json,array['latitude','lat'])::double precision,
      public.hf_json_number(record_json,array['longitude','lng','lon'])::double precision,
      rooms_value,public.hf_json_number(record_json,array['living_area_m2','area_m2','expected_living_area_from_m2']),
      purchase_value,parking_value,total_value,
      public.hf_json_number(record_json,array['year_built','construction_year','baujahr','expected_construction_start'])::integer,
      public.hf_json_text(record_json,array['availability','move_in','expected_move_in']),
      public.hf_json_text(record_json,array['floor']),
      public.hf_json_text(record_json,array['developer']),public.hf_json_text(record_json,array['marketer']),
      public.hf_json_text(record_json,array['project_status']),
      public.hf_json_boolean(record_json,array['minergie']),
      public.hf_json_boolean(record_json,array['building_right','baurecht','leasehold']),
      public.hf_json_number(record_json,array['drive_minutes_duebendorf','duebendorf_minutes','travel_time_duebendorf_minutes','travel_time_gessi_minutes'])::integer,
      public.hf_json_number(record_json,array['drive_minutes_wohlen','wohlen_minutes','travel_time_wohlen_minutes'])::integer,
      public.hf_json_number(record_json,array['drive_minutes_othmarsingen','othmarsingen_minutes','travel_time_othmarsingen_minutes','travel_time_luca_minutes'])::integer,
      public.hf_json_number(record_json,array['ai_rating']),
      public.hf_json_text(record_json,array['ai_summary']),
      public.hf_json_text(record_json,array['ai_recommendation_reason','recommendation_reason']),
      public.hf_json_array(record_json,'advantages'),public.hf_json_array(record_json,'disadvantages'),
      public.hf_json_timestamp(record_json,array['discovered_at','imported_at','created_at']),
      public.hf_json_timestamp(record_json,array['last_seen_at','updated_at'])
    )
    on conflict (external_id) do update set
      source=coalesce(excluded.source,home_finder_properties.source),
      source_url=coalesce(excluded.source_url,home_finder_properties.source_url),
      project_url=coalesce(excluded.project_url,home_finder_properties.project_url),
      title=coalesce(excluded.title,home_finder_properties.title),
      description=coalesce(excluded.description,home_finder_properties.description),
      address=coalesce(excluded.address,home_finder_properties.address),
      zip=coalesce(excluded.zip,home_finder_properties.zip),
      city=coalesce(excluded.city,home_finder_properties.city),
      rooms=coalesce(excluded.rooms,home_finder_properties.rooms),
      living_area_m2=coalesce(excluded.living_area_m2,home_finder_properties.living_area_m2),
      total_price_chf=coalesce(excluded.total_price_chf,home_finder_properties.total_price_chf),
      year_built=coalesce(excluded.year_built,home_finder_properties.year_built),
      last_seen_at=greatest(excluded.last_seen_at,home_finder_properties.last_seen_at);

    insert into hf_legacy_map(source_table,legacy_id,external_id)
    values(source_table,legacy_id,external_key)
    on conflict (source_table,legacy_id) do update set external_id=excluded.external_id;

    insert into public.home_finder_state(external_id,status)
    values(external_key,case when archived_value then 'archive' else 'interesting' end)
    on conflict (external_id) do update set
      status=case when excluded.status='archive' then 'archive' else home_finder_state.status end;
  end loop;
end;
$$;

-- Bestehende Wohnungen und Pipeline-Projekte zusammenführen.
select public.hf_migrate_property_table('properties','homedeluxe','listing');
select public.hf_migrate_property_table('pipeline_projects','homedeluxe','pipeline');
select public.hf_migrate_property_table('properties_search2','maxmio','listing');
select public.hf_migrate_property_table('pipeline_projects_search2','maxmio','pipeline');
select public.hf_migrate_property_table('hf35_properties','maxmio','listing');
select public.hf_migrate_property_table('hf35_pipeline_projects','maxmio','pipeline');

create or replace function public.hf_migrate_votes(vote_table text,property_table text)
returns void language plpgsql as $$
declare row_json jsonb; mapped_id text; person_value text; vote_value integer;
begin
  if to_regclass('public.' || quote_ident(vote_table)) is null then return; end if;
  for row_json in execute format('select to_jsonb(t) from public.%I t',vote_table) loop
    select external_id into mapped_id from hf_legacy_map
      where source_table=property_table and legacy_id=public.hf_json_text(row_json,array['property_id','project_id']);
    if mapped_id is null then continue; end if;
    person_value := lower(coalesce(public.hf_json_text(row_json,array['person']),'luca'));
    vote_value := public.hf_json_number(row_json,array['vote'])::integer;
    if vote_value not in (-1,1) then continue; end if;
    if person_value='gessi' then update public.home_finder_state set gessi_vote=vote_value where external_id=mapped_id;
    else update public.home_finder_state set luca_vote=vote_value where external_id=mapped_id;
    end if;
  end loop;
end;
$$;

create or replace function public.hf_migrate_favorites(favorite_table text,property_table text)
returns void language plpgsql as $$
declare row_json jsonb; mapped_id text; person_value text;
begin
  if to_regclass('public.' || quote_ident(favorite_table)) is null then return; end if;
  for row_json in execute format('select to_jsonb(t) from public.%I t',favorite_table) loop
    select external_id into mapped_id from hf_legacy_map
      where source_table=property_table and legacy_id=public.hf_json_text(row_json,array['property_id','project_id']);
    if mapped_id is null then continue; end if;
    person_value := lower(coalesce(public.hf_json_text(row_json,array['person']),'luca'));
    if person_value='gessi' then update public.home_finder_state set gessi_favorite=true where external_id=mapped_id;
    else update public.home_finder_state set luca_favorite=true where external_id=mapped_id;
    end if;
  end loop;
end;
$$;

create or replace function public.hf_migrate_notes(note_table text,property_table text)
returns void language plpgsql as $$
declare row_json jsonb; mapped_id text; person_value text; note_value text;
begin
  if to_regclass('public.' || quote_ident(note_table)) is null then return; end if;
  for row_json in execute format('select to_jsonb(t) from public.%I t',note_table) loop
    select external_id into mapped_id from hf_legacy_map
      where source_table=property_table and legacy_id=public.hf_json_text(row_json,array['property_id','project_id']);
    if mapped_id is null then continue; end if;
    person_value := lower(coalesce(public.hf_json_text(row_json,array['person']),'luca'));
    note_value := coalesce(public.hf_json_text(row_json,array['note','comment']),'');
    if person_value='gessi' then update public.home_finder_state set gessi_note=note_value where external_id=mapped_id;
    else update public.home_finder_state set luca_note=note_value where external_id=mapped_id;
    end if;
  end loop;
end;
$$;

select public.hf_migrate_votes('property_votes','properties');
select public.hf_migrate_votes('property_votes_search2','properties_search2');
select public.hf_migrate_votes('hf35_property_votes','hf35_properties');

select public.hf_migrate_favorites('property_favorites','properties');
select public.hf_migrate_favorites('property_favorites_search2','properties_search2');
select public.hf_migrate_favorites('hf35_property_favorites','hf35_properties');

select public.hf_migrate_notes('property_notes','properties');
select public.hf_migrate_notes('property_notes_search2','properties_search2');
select public.hf_migrate_notes('hf35_property_notes','hf35_properties');
select public.hf_migrate_notes('pipeline_project_comments_search2','pipeline_projects_search2');

-- Abschliessende, harte Preiszuordnung. Genau CHF 1 Mio. gehört zu MaxMio.
update public.home_finder_properties
set category=case when total_price_chf <= 1000000 then 'maxmio' else 'homedeluxe' end
where total_price_chf is not null;

-- Neue Zustandszeilen werden bei Bedarf automatisch angelegt.
insert into public.home_finder_state(external_id,status)
select external_id,'new' from public.home_finder_properties
on conflict (external_id) do nothing;

-- Hilfsfunktionen bleiben absichtlich bestehen, damit die Migration gefahrlos
-- erneut ausgeführt werden kann, falls später noch alte Daten ergänzt werden.

-- Datenbankobjekte härten: deterministischer search_path, keine unnötigen RPCs
-- und RLS des Aufrufers auch für das bestehende Dashboard-View respektieren.
do $hardening$
declare
  function_signature text;
begin
  foreach function_signature in array array[
    'public.home_finder_touch_state()',
    'public.home_finder_set_category()',
    'public.hf_json_text(jsonb,text[])',
    'public.hf_json_number(jsonb,text[])',
    'public.hf_json_boolean(jsonb,text[])',
    'public.hf_json_array(jsonb,text)',
    'public.hf_json_timestamp(jsonb,text[])',
    'public.hf_migrate_property_table(text,text,text)',
    'public.hf_migrate_votes(text,text)',
    'public.hf_migrate_favorites(text,text)',
    'public.hf_migrate_notes(text,text)',
    'public.set_updated_at()',
    'public.set_property_archive_data()',
    'public.set_pipeline_projects_updated_at()',
    'public.record_property_price()'
  ] loop
    if to_regprocedure(function_signature) is not null then
      execute format('alter function %s set search_path = public, pg_temp', function_signature);
      execute format('revoke execute on function %s from public, anon, authenticated', function_signature);
    end if;
  end loop;

  if to_regclass('public.property_dashboard') is not null then
    execute 'alter view public.property_dashboard set (security_invoker = true)';
  end if;
end;
$hardening$;
