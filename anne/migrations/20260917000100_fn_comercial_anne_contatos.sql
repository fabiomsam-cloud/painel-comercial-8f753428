-- Painel Comercial (lado Anne): contatos ligados aos leads do período + sinais de conversa real.
-- Escopo: contatos cujo lead nasceu no período (source_first.lead_criado_em) OU criados no período ainda sem lead (inbound novo).
create or replace function public.fn_comercial_anne_contatos(p_ini date, p_fim date)
returns table (lead_id uuid, contact_id uuid, phone_norm text, status text, agent_slug text,
               msg_user int, msg_user_periodo int, last_user_message_at timestamptz, won_at timestamptz, contact_created_at timestamptz)
language sql stable as $$
  with t as (
    select (p_ini::timestamp at time zone 'America/Manaus') as t_ini, ((p_fim + 1)::timestamp at time zone 'America/Manaus') as t_fim
  ), c as (
    select ct.id, ct.phone_norm, ct.created_at,
           case when (ct.source_first->>'lead_id') ~ '^[0-9a-f-]{36}$' then (ct.source_first->>'lead_id')::uuid end as lead_id,
           cv.id as conversation_id, cv.status, cv.current_agent_slug, cv.last_user_message_at, cv.won_at
    from public.contacts ct
    left join public.conversations cv on cv.contact_id = ct.id, t
    where ((ct.source_first->>'lead_criado_em') is not null
           and (ct.source_first->>'lead_criado_em')::timestamptz >= t.t_ini and (ct.source_first->>'lead_criado_em')::timestamptz < t.t_fim)
       or (ct.created_at >= t.t_ini and ct.created_at < t.t_fim and not (ct.source_first ? 'lead_id'))
  )
  select c.lead_id, c.id, c.phone_norm, c.status, c.current_agent_slug,
         coalesce((select count(*)::int from public.messages m where m.conversation_id = c.conversation_id and m.from_type = 'user'), 0),
         coalesce((select count(*)::int from public.messages m, t where m.conversation_id = c.conversation_id and m.from_type = 'user' and m.created_at >= t.t_ini and m.created_at < t.t_fim), 0),
         c.last_user_message_at, c.won_at, c.created_at
  from c
$$;
revoke all on function public.fn_comercial_anne_contatos(date,date) from anon, authenticated;
create index if not exists ix_contacts_lead_criado_em on public.contacts (((source_first->>'lead_criado_em')));
create index if not exists ix_contacts_created_at on public.contacts (created_at);
create index if not exists ix_conversations_last_user_msg on public.conversations (last_user_message_at);
