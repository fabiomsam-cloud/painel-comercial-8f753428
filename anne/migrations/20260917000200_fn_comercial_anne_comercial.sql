-- Painel Comercial (lado Anne): seções 9A/9B/9C, motivos de perda (ref. B) e disparos (seção 11), num único jsonb.
create or replace function public.fn_comercial_anne_comercial(p_ini date, p_fim date) returns jsonb language sql stable as $$
  with t as (
    select (p_ini::timestamp at time zone 'America/Manaus') as t_ini, ((p_fim + 1)::timestamp at time zone 'America/Manaus') as t_fim
  ),
  -- 9A: produtividade por vendedor (coorte = leads recebidos no período; ligações registradas no período)
  vend as (
    select v.id, v.nome, v.email, v.tipo, v.ativo,
      (select count(*) from public.atividades_comercial a, t where a.vendedor_id = v.id and a.tipo like 'ligacao%' and a.created_at >= t.t_ini and a.created_at < t.t_fim) as ligacoes,
      (select count(*) from public.atividades_comercial a, t where a.vendedor_id = v.id and a.tipo = 'whatsapp' and a.created_at >= t.t_ini and a.created_at < t.t_fim) as whatsapp,
      (select count(*) from public.atividades_comercial a, t where a.vendedor_id = v.id and a.tipo = 'nota' and a.created_at >= t.t_ini and a.created_at < t.t_fim) as notas,
      (select count(*) from public.lead_assignments la, t where la.vendedor_id = v.id and la.assigned_at >= t.t_ini and la.assigned_at < t.t_fim) as recebidos,
      (select count(*) from public.lead_assignments la, t where la.vendedor_id = v.id and la.assigned_at >= t.t_ini and la.assigned_at < t.t_fim and la.status = 'devolvido') as devolvidos,
      (select count(*) from public.lead_assignments la, t where la.vendedor_id = v.id and la.assigned_at >= t.t_ini and la.assigned_at < t.t_fim and la.status = 'expirado') as expirados,
      (select count(*) from public.lead_assignments la, t where la.vendedor_id = v.id and la.assigned_at >= t.t_ini and la.assigned_at < t.t_fim and la.status = 'ativo') as em_posse,
      (select count(*) from public.lead_assignments la, t where la.vendedor_id = v.id and la.assigned_at >= t.t_ini and la.assigned_at < t.t_fim and la.status = 'matriculado') as matriculados,
      (select coalesce(sum(la.venda_valor),0) from public.lead_assignments la, t where la.vendedor_id = v.id and la.assigned_at >= t.t_ini and la.assigned_at < t.t_fim and la.status = 'matriculado') as venda_valor
    from public.vendedores v
  ),
  -- 9B: conversas com troca real (≥2 msgs do lead) e atividade do lead no período, que nunca tiveram posse no comercial humano
  fora as (
    select cv.status, count(*) as convs,
           count(*) filter (where m.n >= 6) as m6, count(*) filter (where m.n >= 10) as m10
    from public.conversations cv
    join lateral (select count(*) as n from public.messages m where m.conversation_id = cv.id and m.from_type = 'user') m on true, t
    where cv.last_user_message_at >= t.t_ini and cv.last_user_message_at < t.t_fim
      and m.n >= 2
      and not exists (select 1 from public.lead_assignments la where la.conversation_id = cv.id)
    group by cv.status
  ),
  -- 9C: quem assume — a única fonte é escalations.claimed_by (conversations.current_agent_slug é sempre o agente de IA)
  esc as (
    select e.claimed_by, e.conversation_id, e.claimed_at, e.created_at,
      exists (select 1 from public.messages m where m.conversation_id = e.conversation_id and m.from_type = 'user' and m.created_at > coalesce(e.claimed_at, e.created_at)) as engajou,
      (exists (select 1 from public.conversations cv where cv.id = e.conversation_id and cv.won_at > coalesce(e.claimed_at, e.created_at))
       or exists (select 1 from public.sales s where s.conversation_id = e.conversation_id and s.paid_at > coalesce(e.claimed_at, e.created_at) and s.attribution in ('anne_ia','anne_humano','anne_blindado'))) as converteu
    from public.escalations e, t
    where e.created_at >= t.t_ini and e.created_at < t.t_fim
  ),
  esc_agg as (
    select claimed_by, count(*) as assumiu, count(distinct conversation_id) as conversas,
           count(distinct conversation_id) filter (where engajou) as engajou, count(distinct conversation_id) filter (where converteu) as converteu
    from esc where claimed_by is not null group by claimed_by
  ),
  -- Ref. B: motivos de perda das posses encerradas no período
  perda as (
    select coalesce(split_part(la.motivo_perda, ' — ', 1), case when la.status = 'expirado' then 'expirado_sem_resultado' end) as motivo, count(*) as n
    from public.lead_assignments la, t
    where la.status in ('devolvido','expirado') and coalesce(la.closed_at, la.expires_at) >= t.t_ini and coalesce(la.closed_at, la.expires_at) < t.t_fim
    group by 1
  ),
  -- Seção 11: disparos do período + vendas até 10 dias após receber um disparo (correlação temporal, não causa)
  bc as (
    select b.campaign_id, b.name, b.agent_slug, b.status, b.created_at, b.total, b.enviados, b.respostas
    from public.vw_broadcast_stats b, t where b.created_at >= t.t_ini and b.created_at < t.t_fim
  ),
  pos_disparo as (
    select count(*) as vendas, count(*) filter (where s.attribution in ('anne_ia','anne_humano','anne_blindado')) as vendas_anne, count(*) filter (where s.attribution = 'anne_disparo') as vendas_disparo_attr
    from public.sales s join public.contacts c on c.id = s.contact_id, t
    where s.paid_at >= t.t_ini and s.paid_at < t.t_fim
      and exists (select 1 from public.broadcast_recipients r where r.phone_norm = c.phone_norm and r.status = 'sent' and r.sent_at between s.paid_at - interval '10 days' and s.paid_at)
  )
  select jsonb_build_object(
    'vendedores', (select coalesce(jsonb_agg(to_jsonb(vend) order by vend.nome), '[]'::jsonb) from vend),
    'fora_pipeline', (select coalesce(jsonb_agg(to_jsonb(fora) order by fora.convs desc), '[]'::jsonb) from fora),
    'escalacoes', (select coalesce(jsonb_agg(to_jsonb(esc_agg) order by esc_agg.assumiu desc), '[]'::jsonb) from esc_agg),
    'escalacoes_total', (select count(*) from esc),
    'escalacoes_sem_claim', (select count(*) from esc where claimed_by is null),
    'motivos_perda', (select coalesce(jsonb_agg(to_jsonb(perda) order by perda.n desc), '[]'::jsonb) from perda),
    'broadcast', (select coalesce(jsonb_agg(to_jsonb(bc) order by bc.enviados desc), '[]'::jsonb) from bc),
    'pos_disparo', (select to_jsonb(pos_disparo) from pos_disparo),
    'humano_comercial_agora', (select count(*) from public.conversations where status = 'humano_comercial')
  )
$$;
revoke all on function public.fn_comercial_anne_comercial(date,date) from anon, authenticated;
