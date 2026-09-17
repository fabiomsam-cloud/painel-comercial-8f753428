-- Seção 10: uso de cupons nos 90 dias que terminam em p_fim (dia Manaus), faturas pagas
create or replace function public.fn_comercial_cupons_90d(p_fim date)
returns table (total bigint, com_cupom bigint, desconto_total numeric, desconto_medio numeric, top jsonb)
language sql stable as $$
  with f as (
    select coupon, discount_value from public.hubla_invoices
    where status = 'Paga' and (paid_at at time zone 'America/Manaus')::date between p_fim - 89 and p_fim
  ), t as (
    select coupon, count(*) n, round(sum(coalesce(discount_value,0)),2) desconto
    from f where coupon is not null and coupon <> '' group by coupon order by n desc limit 8
  )
  select count(*), count(*) filter (where coupon is not null and coupon <> ''),
         round(sum(coalesce(discount_value,0)) filter (where coupon is not null and coupon <> ''),2),
         round(avg(coalesce(discount_value,0)) filter (where coupon is not null and coupon <> ''),2),
         coalesce((select jsonb_agg(jsonb_build_object('coupon', coupon, 'n', n, 'desconto', desconto)) from t), '[]'::jsonb)
  from f
$$;
revoke all on function public.fn_comercial_cupons_90d(date) from anon, authenticated;
