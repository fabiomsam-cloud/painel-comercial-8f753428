-- De-para produto Hubla → concurso (para o filtro de concurso alcançar as seções de receita). Seed por regex; editável.
update public.comercial_produto_categoria set contest_code = case
  when product_name ~* 'TRIBUNAL DE JUSTI|TJ-?AM' then 'TJAM'
  when product_name ~* 'SEDUC[ -]?PA' then 'SEDUC_PA'
  when product_name ~* 'SEDUC' then 'seduc_amazonas'
  when product_name ~* 'MANAUS ?PREV' then 'MANAUSPREV'
  when product_name ~* 'SEMSA|SES[ -]AM|SES \+' then 'ses_e_semsa_manaus'
  when product_name ~* 'POL[IÍ]CIA CIVIL AMAZONAS|PC-?AM' then 'PCAM'
  when product_name ~* 'GUARDA MUNICIPAL' then 'GUARDA_MANAUS'
  when product_name ~* 'INSS' then 'INSS'
  when product_name ~* 'SEMED' then 'SEMED'
  when product_name ~* 'ALEAM' then 'ALEAM'
  when product_name ~* 'PRF' then 'PRF'
  when product_name ~* 'ELITE FEDERAL|ELITE DELTA' then 'policia_federal'
  when product_name ~* 'ELITE POLICIAL' then 'PCIVIL'
  when product_name ~* 'PLAY ?PASSEI|SPOTFABIO' then 'PLAYPASSEI'
  when product_name ~* 'TRIBUNAIS' then 'carreiras_tribunais'
  else null end
where contest_code is null;
