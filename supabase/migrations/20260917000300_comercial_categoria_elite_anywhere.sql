-- "Extensão - Elite PRF" conta como Elite no protótipo (2025: 221 = 204 + 17, R$ 244.559,28 exato) → ELITE em qualquer posição do nome
create or replace function public.fn_comercial_categoria_nome(p_name text) returns text
language sql immutable as $$
  select case
    when p_name ~* 'DIAMANTE' then 'upsell'
    when p_name ~* 'ELITE' then 'elite'
    when p_name ~* 'PLAY ?PASSEI|SOU QUEST|^\s*PÓS GRADUAÇÃO' then 'recorrente'
    else 'outros' end
$$;
update public.comercial_produto_categoria set categoria = public.fn_comercial_categoria_nome(product_name), updated_at = now()
where origem = 'regex' and validado = false and categoria <> public.fn_comercial_categoria_nome(product_name);
