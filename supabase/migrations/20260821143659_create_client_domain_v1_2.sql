begin;

-- Client domain V1.2.
-- This structural migration deliberately leaves public.app_users empty.
-- William's exact Auth UUID belongs to the later, separately authorized
-- application step for ERP_CLIENT.
-- Search is limited to Clients, Contacts and their contact methods.
-- Direct Client and Contact deletion remains unavailable in this isolated
-- migration; the 72-hour Project rule and the protected-data workflow belong
-- to their future, separately authorized migrations.
-- No personal-data JSON history is created here. Production opening remains
-- conditional on the transversal Journal, anonymization and retention work.

create schema if not exists extensions;
create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;

grant usage on schema extensions to authenticated;

do $extension_schema_check$
begin
  if exists (
    select 1
    from pg_catalog.pg_extension as ext
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = ext.extnamespace
    where ext.extname in ('unaccent', 'pg_trgm')
      and namespace.nspname <> 'extensions'
  ) then
    raise exception
      'The unaccent and pg_trgm extensions must be installed in the extensions schema.';
  end if;
end;
$extension_schema_check$;

create table public.app_users (
  user_id uuid primary key,
  is_active boolean not null default false,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  constraint app_users_user_id_fkey
    foreign key (user_id)
    references auth.users (id)
    on delete restrict
);

create table public.clients (
  id bigint generated always as identity
    (sequence name public.clients_id_seq)
    primary key,
  owner_user_id uuid not null default auth.uid(),
  category text not null,
  person_last_name text,
  person_first_name text,
  entity_name text,
  status text not null default 'active',
  address_line_1 text,
  address_line_2 text,
  address_postal_code text,
  address_city text,
  address_country_code text,
  search_name text not null,
  first_project_created_at timestamptz,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  constraint clients_owner_user_id_fkey
    foreign key (owner_user_id)
    references public.app_users (user_id)
    on delete restrict,
  constraint clients_category_check
    check (
      category in (
        'particulier',
        'professionnel',
        'association',
        'collectivite'
      )
    ),
  constraint clients_status_check
    check (status in ('active', 'inactive')),
  constraint clients_identity_by_category_check
    check (
      (
        category = 'particulier'
        and person_last_name is not null
        and btrim(person_last_name) <> ''
        and (person_first_name is null or btrim(person_first_name) <> '')
        and entity_name is null
      )
      or
      (
        category in ('professionnel', 'association', 'collectivite')
        and entity_name is not null
        and btrim(entity_name) <> ''
        and person_last_name is null
        and person_first_name is null
      )
    ),
  constraint clients_address_line_1_check
    check (address_line_1 is null or btrim(address_line_1) <> ''),
  constraint clients_address_line_2_check
    check (address_line_2 is null or btrim(address_line_2) <> ''),
  constraint clients_address_postal_code_check
    check (address_postal_code is null or btrim(address_postal_code) <> ''),
  constraint clients_address_city_check
    check (address_city is null or btrim(address_city) <> ''),
  constraint clients_address_country_code_check
    check (
      address_country_code is null
      or address_country_code ~ '^[A-Z]{2}$'
    ),
  constraint clients_search_name_check
    check (btrim(search_name) <> ''),
  constraint clients_first_project_created_at_check
    check (
      first_project_created_at is null
      or first_project_created_at >= created_at
    ),
  constraint clients_id_owner_user_id_key
    unique (id, owner_user_id)
);

create table public.contacts (
  id bigint generated always as identity
    (sequence name public.contacts_id_seq)
    primary key,
  owner_user_id uuid not null default auth.uid(),
  client_id bigint not null,
  last_name text not null,
  first_name text,
  is_external_contact boolean not null default false,
  external_organization_name text,
  job_title text,
  department text,
  status text not null default 'active',
  search_name text not null,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  constraint contacts_owner_user_id_fkey
    foreign key (owner_user_id)
    references public.app_users (user_id)
    on delete restrict,
  constraint contacts_client_owner_fkey
    foreign key (client_id, owner_user_id)
    references public.clients (id, owner_user_id)
    on delete cascade,
  constraint contacts_last_name_check
    check (btrim(last_name) <> ''),
  constraint contacts_first_name_check
    check (first_name is null or btrim(first_name) <> ''),
  constraint contacts_external_organization_name_check
    check (
      external_organization_name is null
      or (
        is_external_contact
        and btrim(external_organization_name) <> ''
      )
    ),
  constraint contacts_job_title_check
    check (job_title is null or btrim(job_title) <> ''),
  constraint contacts_department_check
    check (department is null or btrim(department) <> ''),
  constraint contacts_status_check
    check (status in ('active', 'inactive')),
  constraint contacts_search_name_check
    check (btrim(search_name) <> ''),
  constraint contacts_id_owner_user_id_key
    unique (id, owner_user_id)
);

create table public.contact_methods (
  id bigint generated always as identity
    (sequence name public.contact_methods_id_seq)
    primary key,
  owner_user_id uuid not null default auth.uid(),
  client_id bigint,
  contact_id bigint,
  kind text not null,
  label text not null,
  value text not null,
  normalized_value text not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  constraint contact_methods_owner_user_id_fkey
    foreign key (owner_user_id)
    references public.app_users (user_id)
    on delete restrict,
  constraint contact_methods_client_owner_fkey
    foreign key (client_id, owner_user_id)
    references public.clients (id, owner_user_id)
    on delete cascade,
  constraint contact_methods_contact_owner_fkey
    foreign key (contact_id, owner_user_id)
    references public.contacts (id, owner_user_id)
    on delete cascade,
  constraint contact_methods_subject_check
    check ((client_id is not null) <> (contact_id is not null)),
  constraint contact_methods_kind_check
    check (kind in ('email', 'phone')),
  constraint contact_methods_label_check
    check (btrim(label) <> ''),
  constraint contact_methods_value_check
    check (btrim(value) <> ''),
  constraint contact_methods_normalized_value_check
    check (btrim(normalized_value) <> '')
);

create function private.normalize_search_text(p_value text)
returns text
language sql
stable
security invoker
set search_path = ''
as $function$
  select btrim(
    regexp_replace(
      regexp_replace(
        lower(extensions.unaccent(coalesce(p_value, ''))),
        '[^[:alnum:]]+',
        ' ',
        'g'
      ),
      '[[:space:]]+',
      ' ',
      'g'
    )
  );
$function$;

create function private.normalize_email(p_value text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select lower(
    regexp_replace(
      btrim(coalesce(p_value, '')),
      '[[:space:]]+',
      '',
      'g'
    )
  );
$function$;

create function private.normalize_phone(p_value text)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $function$
declare
  normalized text;
begin
  normalized := regexp_replace(
    coalesce(p_value, ''),
    '[^0-9+]+',
    '',
    'g'
  );

  if normalized ~ '^0[1-9][0-9]{8}$' then
    return '+33' || substr(normalized, 2);
  elsif normalized ~ '^0033[1-9][0-9]{8}$' then
    return '+33' || substr(normalized, 5);
  elsif normalized ~ '^00330[1-9][0-9]{8}$' then
    return '+33' || substr(normalized, 6);
  elsif normalized ~ '^\+330[1-9][0-9]{8}$' then
    return '+33' || substr(normalized, 5);
  elsif normalized ~ '^\+33[1-9][0-9]{8}$' then
    return normalized;
  elsif normalized ~ '^00[1-9][0-9]{7,14}$' then
    return '+' || substr(normalized, 3);
  elsif normalized ~ '^\+[1-9][0-9]{7,14}$' then
    return normalized;
  end if;

  return '';
end;
$function$;

create function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.updated_at := statement_timestamp();
  return new;
end;
$function$;

create function private.clients_compute_search_name_biu()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.category := lower(btrim(new.category));
  new.status := lower(btrim(new.status));
  new.person_last_name := nullif(btrim(new.person_last_name), '');
  new.person_first_name := nullif(btrim(new.person_first_name), '');
  new.entity_name := nullif(btrim(new.entity_name), '');
  new.address_line_1 := nullif(btrim(new.address_line_1), '');
  new.address_line_2 := nullif(btrim(new.address_line_2), '');
  new.address_postal_code := nullif(btrim(new.address_postal_code), '');
  new.address_city := nullif(btrim(new.address_city), '');
  new.address_country_code := upper(
    nullif(btrim(new.address_country_code), '')
  );

  new.search_name := private.normalize_search_text(
    concat_ws(
      ' ',
      new.person_first_name,
      new.person_last_name,
      new.entity_name,
      new.address_line_1,
      new.address_line_2,
      new.address_postal_code,
      new.address_city,
      new.address_country_code
    )
  );

  return new;
end;
$function$;

create function private.contacts_compute_search_name_biu()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.last_name := btrim(new.last_name);
  new.first_name := nullif(btrim(new.first_name), '');
  new.external_organization_name := nullif(
    btrim(new.external_organization_name),
    ''
  );
  new.job_title := nullif(btrim(new.job_title), '');
  new.department := nullif(btrim(new.department), '');
  new.status := lower(btrim(new.status));

  new.search_name := private.normalize_search_text(
    concat_ws(
      ' ',
      new.first_name,
      new.last_name,
      new.external_organization_name,
      new.job_title,
      new.department
    )
  );

  return new;
end;
$function$;

create function private.contact_methods_normalize_biu()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.kind := lower(btrim(new.kind));
  new.label := btrim(new.label);
  new.value := btrim(new.value);

  if new.kind = 'email' then
    new.normalized_value := private.normalize_email(new.value);
  elsif new.kind = 'phone' then
    new.normalized_value := private.normalize_phone(new.value);
  else
    raise exception using
      errcode = '23514',
      message = 'Unsupported contact method kind.';
  end if;

  if new.normalized_value = '' then
    raise exception using
      errcode = '23514',
      message = 'The normalized contact method value cannot be empty.';
  end if;

  return new;
end;
$function$;

create function private.contacts_validate_professional_context_biu()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  client_category text;
begin
  select client.category
    into client_category
  from public.clients as client
  where client.id = new.client_id
    and client.owner_user_id = new.owner_user_id
  for update;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'The owning client is unavailable.';
  end if;

  if new.external_organization_name is not null
    and not (
      new.is_external_contact
      and client_category = 'particulier'
    )
  then
    raise exception using
      errcode = '23514',
      message = 'An external organization is allowed only for an external contact of a particulier client.';
  end if;

  return new;
end;
$function$;

create function private.clients_validate_contact_category_bu()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if old.category is distinct from new.category
    and new.category <> 'particulier'
    and exists (
      select 1
      from public.contacts as contact
      where contact.client_id = new.id
        and contact.owner_user_id = new.owner_user_id
        and contact.external_organization_name is not null
    )
  then
    raise exception using
      errcode = '23514',
      message = 'Clear external contact organizations before changing the client category.';
  end if;

  return new;
end;
$function$;

create function private.contact_methods_assign_first_primary_bi()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.client_id is not null then
    perform 1
    from public.clients as client
    where client.id = new.client_id
      and client.owner_user_id = new.owner_user_id
    for update;

    if not found then
      raise exception using
        errcode = '23503',
        message = 'The owning client is unavailable.';
    end if;

    select not exists (
      select 1
      from public.contact_methods as method
      where method.owner_user_id = new.owner_user_id
        and method.client_id = new.client_id
        and method.kind = new.kind
    )
      into new.is_primary;
  else
    perform 1
    from public.contacts as contact
    where contact.id = new.contact_id
      and contact.owner_user_id = new.owner_user_id
    for update;

    if not found then
      raise exception using
        errcode = '23503',
        message = 'The owning contact is unavailable.';
    end if;

    select not exists (
      select 1
      from public.contact_methods as method
      where method.owner_user_id = new.owner_user_id
        and method.contact_id = new.contact_id
        and method.kind = new.kind
    )
      into new.is_primary;
  end if;

  return new;
end;
$function$;

create function private.contact_methods_primary_required_ct()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  method_count bigint;
  primary_count bigint;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    if old.client_id is not null then
      if exists (
        select 1
        from public.clients as client
        where client.id = old.client_id
          and client.owner_user_id = old.owner_user_id
      ) then
        select
          count(*),
          count(*) filter (where method.is_primary)
          into method_count, primary_count
        from public.contact_methods as method
        where method.owner_user_id = old.owner_user_id
          and method.client_id = old.client_id
          and method.kind = old.kind;

        if method_count > 0 and primary_count <> 1 then
          raise exception using
            errcode = '23514',
            message = 'A client contact method group must have exactly one primary method.';
        end if;
      end if;
    elsif exists (
      select 1
      from public.contacts as contact
      where contact.id = old.contact_id
        and contact.owner_user_id = old.owner_user_id
    ) then
      select
        count(*),
        count(*) filter (where method.is_primary)
        into method_count, primary_count
      from public.contact_methods as method
      where method.owner_user_id = old.owner_user_id
        and method.contact_id = old.contact_id
        and method.kind = old.kind;

      if method_count > 0 and primary_count <> 1 then
        raise exception using
          errcode = '23514',
          message = 'A contact method group must have exactly one primary method.';
      end if;
    end if;
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    if new.client_id is not null then
      if exists (
        select 1
        from public.clients as client
        where client.id = new.client_id
          and client.owner_user_id = new.owner_user_id
      ) then
        select
          count(*),
          count(*) filter (where method.is_primary)
          into method_count, primary_count
        from public.contact_methods as method
        where method.owner_user_id = new.owner_user_id
          and method.client_id = new.client_id
          and method.kind = new.kind;

        if method_count > 0 and primary_count <> 1 then
          raise exception using
            errcode = '23514',
            message = 'A client contact method group must have exactly one primary method.';
        end if;
      end if;
    elsif exists (
      select 1
      from public.contacts as contact
      where contact.id = new.contact_id
        and contact.owner_user_id = new.owner_user_id
    ) then
      select
        count(*),
        count(*) filter (where method.is_primary)
        into method_count, primary_count
      from public.contact_methods as method
      where method.owner_user_id = new.owner_user_id
        and method.contact_id = new.contact_id
        and method.kind = new.kind;

      if method_count > 0 and primary_count <> 1 then
        raise exception using
          errcode = '23514',
          message = 'A contact method group must have exactly one primary method.';
      end if;
    end if;
  end if;

  return null;
end;
$function$;

create function private.set_primary_contact_method_impl(p_method_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_client_id bigint;
  target_contact_id bigint;
  target_kind text;
begin
  caller_user_id := auth.uid();

  if caller_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'An authenticated identity is required.';
  end if;

  if not exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = caller_user_id
      and app_user.is_active
  ) then
    raise exception using
      errcode = '42501',
      message = 'The application user is unavailable or inactive.';
  end if;

  select
    method.client_id,
    method.contact_id,
    method.kind
    into target_client_id, target_contact_id, target_kind
  from public.contact_methods as method
  where method.id = p_method_id
    and method.owner_user_id = caller_user_id;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'The contact method is unavailable.';
  end if;

  if target_client_id is not null then
    perform 1
    from public.clients as client
    where client.id = target_client_id
      and client.owner_user_id = caller_user_id
    for update;

    if not found then
      raise exception using
        errcode = '42501',
        message = 'The owning client is unavailable.';
    end if;

    update public.contact_methods as method
    set is_primary = false
    where method.owner_user_id = caller_user_id
      and method.client_id = target_client_id
      and method.kind = target_kind
      and method.is_primary;
  else
    perform 1
    from public.contacts as contact
    where contact.id = target_contact_id
      and contact.owner_user_id = caller_user_id
    for update;

    if not found then
      raise exception using
        errcode = '42501',
        message = 'The owning contact is unavailable.';
    end if;

    update public.contact_methods as method
    set is_primary = false
    where method.owner_user_id = caller_user_id
      and method.contact_id = target_contact_id
      and method.kind = target_kind
      and method.is_primary;
  end if;

  update public.contact_methods as method
  set is_primary = true
  where method.id = p_method_id
    and method.owner_user_id = caller_user_id;
end;
$function$;

create function public.set_primary_contact_method(p_method_id bigint)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.set_primary_contact_method_impl(p_method_id);
$function$;

create function public.search_client_domain(p_query text)
returns table (
  result_type text,
  result_id bigint,
  client_id bigint,
  contact_id bigint,
  display_name text,
  matched_kind text,
  matched_value text,
  rank real
)
language sql
stable
security invoker
set search_path = ''
as $function$
  with query_forms as (
    select
      private.normalize_search_text(p_query) as search_text,
      private.normalize_email(p_query) as email_value,
      private.normalize_phone(p_query) as phone_value
  ),
  matches as (
    select
      'client'::text as result_type,
      client.id as result_id,
      client.id as client_id,
      null::bigint as contact_id,
      case
        when client.category = 'particulier'
          then concat_ws(' ', client.person_first_name, client.person_last_name)
        else client.entity_name
      end as display_name,
      'identity'::text as matched_kind,
      case
        when client.category = 'particulier'
          then concat_ws(' ', client.person_first_name, client.person_last_name)
        else client.entity_name
      end as matched_value,
      extensions.similarity(client.search_name, query.search_text) as rank
    from public.clients as client
    cross join query_forms as query
    where query.search_text <> ''
      and client.search_name like '%' || query.search_text || '%'

    union all

    select
      'contact'::text,
      contact.id,
      contact.client_id,
      contact.id,
      concat_ws(' ', contact.first_name, contact.last_name),
      'identity'::text,
      concat_ws(' ', contact.first_name, contact.last_name),
      extensions.similarity(contact.search_name, query.search_text)
    from public.contacts as contact
    cross join query_forms as query
    where query.search_text <> ''
      and contact.search_name like '%' || query.search_text || '%'

    union all

    select
      'client_contact_method'::text,
      method.id,
      method.client_id,
      null::bigint,
      case
        when client.category = 'particulier'
          then concat_ws(' ', client.person_first_name, client.person_last_name)
        else client.entity_name
      end,
      method.kind,
      method.value,
      case
        when method.kind = 'email'
          and method.normalized_value = query.email_value then 1.0::real
        when method.kind = 'phone'
          and method.normalized_value = query.phone_value then 1.0::real
        else 0.5::real
      end
    from public.contact_methods as method
    join public.clients as client
      on client.id = method.client_id
      and client.owner_user_id = method.owner_user_id
    cross join query_forms as query
    where method.client_id is not null
      and (
        (
          method.kind = 'email'
          and query.email_value <> ''
          and position(query.email_value in method.normalized_value) > 0
        )
        or
        (
          method.kind = 'phone'
          and query.phone_value <> ''
          and position(query.phone_value in method.normalized_value) > 0
        )
      )

    union all

    select
      'contact_contact_method'::text,
      method.id,
      contact.client_id,
      contact.id,
      concat_ws(' ', contact.first_name, contact.last_name),
      method.kind,
      method.value,
      case
        when method.kind = 'email'
          and method.normalized_value = query.email_value then 1.0::real
        when method.kind = 'phone'
          and method.normalized_value = query.phone_value then 1.0::real
        else 0.5::real
      end
    from public.contact_methods as method
    join public.contacts as contact
      on contact.id = method.contact_id
      and contact.owner_user_id = method.owner_user_id
    cross join query_forms as query
    where method.contact_id is not null
      and (
        (
          method.kind = 'email'
          and query.email_value <> ''
          and position(query.email_value in method.normalized_value) > 0
        )
        or
        (
          method.kind = 'phone'
          and query.phone_value <> ''
          and position(query.phone_value in method.normalized_value) > 0
        )
      )
  )
  select
    matches.result_type,
    matches.result_id,
    matches.client_id,
    matches.contact_id,
    matches.display_name,
    matches.matched_kind,
    matches.matched_value,
    matches.rank
  from matches
  order by
    matches.rank desc,
    matches.display_name,
    matches.result_type,
    matches.result_id;
$function$;

create trigger app_users_99_set_updated_at_bu
before update on public.app_users
for each row
execute function private.set_updated_at();

create trigger clients_01_compute_search_name_biu
before insert or update of
  category,
  person_last_name,
  person_first_name,
  entity_name,
  status,
  address_line_1,
  address_line_2,
  address_postal_code,
  address_city,
  address_country_code
on public.clients
for each row
execute function private.clients_compute_search_name_biu();

create trigger clients_02_validate_contact_category_bu
before update of category on public.clients
for each row
execute function private.clients_validate_contact_category_bu();

create trigger clients_99_set_updated_at_bu
before update on public.clients
for each row
execute function private.set_updated_at();

create trigger contacts_01_compute_search_name_biu
before insert or update of
  last_name,
  first_name,
  external_organization_name,
  job_title,
  department,
  status
on public.contacts
for each row
execute function private.contacts_compute_search_name_biu();

create trigger contacts_02_validate_professional_context_biu
before insert or update of
  owner_user_id,
  client_id,
  is_external_contact,
  external_organization_name
on public.contacts
for each row
execute function private.contacts_validate_professional_context_biu();

create trigger contacts_99_set_updated_at_bu
before update on public.contacts
for each row
execute function private.set_updated_at();

create trigger contact_methods_01_normalize_biu
before insert or update of kind, label, value
on public.contact_methods
for each row
execute function private.contact_methods_normalize_biu();

create trigger contact_methods_02_assign_first_primary_bi
before insert on public.contact_methods
for each row
execute function private.contact_methods_assign_first_primary_bi();

create trigger contact_methods_99_set_updated_at_bu
before update on public.contact_methods
for each row
execute function private.set_updated_at();

create constraint trigger contact_methods_primary_required_ct
after insert or update or delete on public.contact_methods
deferrable initially deferred
for each row
execute function private.contact_methods_primary_required_ct();

create index clients_owner_user_id_idx
  on public.clients (owner_user_id);

create index contacts_owner_user_id_idx
  on public.contacts (owner_user_id);

create index contact_methods_owner_user_id_idx
  on public.contact_methods (owner_user_id);

create index contacts_client_owner_idx
  on public.contacts (client_id, owner_user_id);

create index contact_methods_client_owner_idx
  on public.contact_methods (client_id, owner_user_id)
  where client_id is not null;

create index contact_methods_contact_owner_idx
  on public.contact_methods (contact_id, owner_user_id)
  where contact_id is not null;

create index clients_owner_status_idx
  on public.clients (owner_user_id, status);

create index contacts_owner_status_idx
  on public.contacts (owner_user_id, status);

create index clients_orphan_candidate_idx
  on public.clients (owner_user_id, created_at)
  where first_project_created_at is null;

create index clients_search_name_trgm_idx
  on public.clients
  using gin (search_name extensions.gin_trgm_ops);

create index contacts_search_name_trgm_idx
  on public.contacts
  using gin (search_name extensions.gin_trgm_ops);

create index contact_methods_owner_kind_normalized_value_idx
  on public.contact_methods (owner_user_id, kind, normalized_value);

create unique index contact_methods_one_primary_per_client_kind_uidx
  on public.contact_methods (owner_user_id, client_id, kind)
  where client_id is not null and is_primary;

create unique index contact_methods_one_primary_per_contact_kind_uidx
  on public.contact_methods (owner_user_id, contact_id, kind)
  where contact_id is not null and is_primary;

alter table public.app_users enable row level security;
alter table public.app_users force row level security;
alter table public.clients enable row level security;
alter table public.clients force row level security;
alter table public.contacts enable row level security;
alter table public.contacts force row level security;
alter table public.contact_methods enable row level security;
alter table public.contact_methods force row level security;

-- FORCE ROW LEVEL SECURITY does not neutralize superusers or BYPASSRLS roles.
-- The private SECURITY DEFINER core therefore performs explicit identity,
-- active-user and ownership checks before every privileged update.

create policy app_users_select_self_active
on public.app_users
for select
to authenticated
using (
  user_id = (select auth.uid())
  and is_active
);

create policy clients_select_owned_active_user
on public.clients
for select
to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy clients_insert_owned_active_user
on public.clients
for insert
to authenticated
with check (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy clients_update_owned_active_user
on public.clients
for update
to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
)
with check (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy contacts_select_owned_active_user
on public.contacts
for select
to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy contacts_insert_owned_active_user
on public.contacts
for insert
to authenticated
with check (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy contacts_update_owned_active_user
on public.contacts
for update
to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
)
with check (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy contact_methods_select_owned_active_user
on public.contact_methods
for select
to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy contact_methods_insert_owned_active_user
on public.contact_methods
for insert
to authenticated
with check (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy contact_methods_update_owned_active_user
on public.contact_methods
for update
to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
)
with check (
  owner_user_id = (select auth.uid())
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

create policy contact_methods_delete_non_primary_owned_active_user
on public.contact_methods
for delete
to authenticated
using (
  owner_user_id = (select auth.uid())
  and not is_primary
  and exists (
    select 1
    from public.app_users as app_user
    where app_user.user_id = (select auth.uid())
      and app_user.is_active
  )
);

revoke all on table
  public.app_users,
  public.clients,
  public.contacts,
  public.contact_methods
from public, anon, authenticated;

revoke all on sequence
  public.clients_id_seq,
  public.contacts_id_seq,
  public.contact_methods_id_seq
from public, anon, authenticated;

revoke all on function private.normalize_search_text(text)
  from public, anon, authenticated;
revoke all on function private.normalize_email(text)
  from public, anon, authenticated;
revoke all on function private.normalize_phone(text)
  from public, anon, authenticated;
revoke all on function private.set_updated_at()
  from public, anon, authenticated;
revoke all on function private.clients_compute_search_name_biu()
  from public, anon, authenticated;
revoke all on function private.contacts_compute_search_name_biu()
  from public, anon, authenticated;
revoke all on function private.contact_methods_normalize_biu()
  from public, anon, authenticated;
revoke all on function private.contacts_validate_professional_context_biu()
  from public, anon, authenticated;
revoke all on function private.clients_validate_contact_category_bu()
  from public, anon, authenticated;
revoke all on function private.contact_methods_assign_first_primary_bi()
  from public, anon, authenticated;
revoke all on function private.contact_methods_primary_required_ct()
  from public, anon, authenticated;
revoke all on function private.set_primary_contact_method_impl(bigint)
  from public, anon, authenticated;
revoke all on function public.set_primary_contact_method(bigint)
  from public, anon, authenticated;
revoke all on function public.search_client_domain(text)
  from public, anon, authenticated;

grant usage on schema public to authenticated;

grant select on table public.app_users to authenticated;

grant select on table public.clients to authenticated;
grant insert (
  category,
  person_last_name,
  person_first_name,
  entity_name,
  status,
  address_line_1,
  address_line_2,
  address_postal_code,
  address_city,
  address_country_code
) on public.clients to authenticated;
grant update (
  category,
  person_last_name,
  person_first_name,
  entity_name,
  status,
  address_line_1,
  address_line_2,
  address_postal_code,
  address_city,
  address_country_code
) on public.clients to authenticated;

grant select on table public.contacts to authenticated;
grant insert (
  client_id,
  last_name,
  first_name,
  is_external_contact,
  external_organization_name,
  job_title,
  department,
  status
) on public.contacts to authenticated;
grant update (
  last_name,
  first_name,
  is_external_contact,
  external_organization_name,
  job_title,
  department,
  status
) on public.contacts to authenticated;

grant select on table public.contact_methods to authenticated;
grant insert (
  client_id,
  contact_id,
  kind,
  label,
  value
) on public.contact_methods to authenticated;
grant update (
  label,
  value
) on public.contact_methods to authenticated;
grant delete on table public.contact_methods to authenticated;

grant usage on sequence
  public.clients_id_seq,
  public.contacts_id_seq,
  public.contact_methods_id_seq
to authenticated;

grant execute on function private.normalize_search_text(text)
  to authenticated;
grant execute on function private.normalize_email(text)
  to authenticated;
grant execute on function private.normalize_phone(text)
  to authenticated;
grant execute on function private.set_primary_contact_method_impl(bigint)
  to authenticated;
grant execute on function public.set_primary_contact_method(bigint)
  to authenticated;
grant execute on function public.search_client_domain(text)
  to authenticated;

commit;
