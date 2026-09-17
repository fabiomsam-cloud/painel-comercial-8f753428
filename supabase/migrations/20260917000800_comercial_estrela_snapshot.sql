-- Ref. A: segmentação por estrela — snapshot diário (base histórica inteira, 769k lead_interests → não roda ao vivo).
-- Dedup POR LEAD: maior score por (lead, concurso). Faixas: ★★★★★ 91–100 · ★★★★ 71–90 · ★★★ 51–70 · ★★ 21–50 · ★ 1–20. score=0 = nunca pontuado.
create or replace function public.fn_comercial_estrela_refresh() returns int language plpgsql security definer as $$
declare v_ts timestamptz := now(); v_n int;
begin
  insert into public.comercial_estrela_snapshot (gerado_em, contest_code, total_leads, score_pos, faixa5, faixa4, faixa3, faixa2, faixa1)
  with s as (select li.lead_id, c.code, max(li.score) score from public.lead_interests li join public.contests c on c.id = li.contest_id group by 1,2)
  select v_ts, code, count(*), count(*) filter (where score > 0),
         count(*) filter (where score > 90), count(*) filter (where score > 70 and score <= 90),
         count(*) filter (where score > 50 and score <= 70), count(*) filter (where score > 20 and score <= 50),
         count(*) filter (where score > 0 and score <= 20)
  from s group by code;
  get diagnostics v_n = row_count;
  delete from public.comercial_estrela_snapshot where gerado_em < v_ts - interval '90 days';
  return v_n;
end $$;
revoke all on function public.fn_comercial_estrela_refresh() from anon, authenticated, public;

create or replace function public.fn_comercial_estrela()
returns table (gerado_em timestamptz, contest_code text, total_leads bigint, score_pos bigint, faixa5 bigint, faixa4 bigint, faixa3 bigint, faixa2 bigint, faixa1 bigint)
language sql stable as $$
  select gerado_em, contest_code, total_leads, score_pos, faixa5, faixa4, faixa3, faixa2, faixa1
  from public.comercial_estrela_snapshot where gerado_em = (select max(gerado_em) from public.comercial_estrela_snapshot)
  order by total_leads desc
$$;
revoke all on function public.fn_comercial_estrela() from anon, authenticated;

select public.fn_comercial_estrela_refresh();
-- 03:00 Manaus = 07:00 UTC
select cron.schedule('comercial-estrela-diario', '0 7 * * *', $$select public.fn_comercial_estrela_refresh()$$);
