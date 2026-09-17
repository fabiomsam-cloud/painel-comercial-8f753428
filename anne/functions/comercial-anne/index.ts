// Painel de Inteligência Comercial — lado Anne (blwbbdcwdcwitsnskplk). Mesmo token ?k= da edge dashboard-comercial.
// Fase 1: esqueleto (contagens básicas). Fase 4 troca por rpc fn_comercial_anne(p_ini, p_fim).
import { createClient } from "jsr:@supabase/supabase-js@2";

const TOKEN = "com-sou-byMernuvTjwl28hb";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const url = new URL(req.url);
  if ((url.searchParams.get("k") ?? "") !== TOKEN) return json({ error: "unauthorized" }, 401);
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  try {
    // janela em dia Manaus (-04): [ini 00:00, fim 23:59:59]
    const ini = url.searchParams.get("ini") ?? "", fim = url.searchParams.get("fim") ?? "";
    const okYmd = (x: string) => /^\d{4}-\d{2}-\d{2}$/.test(x);
    const tIni = okYmd(ini) ? ini + "T04:00:00.000Z" : new Date(Date.now() - 45 * 86400e3).toISOString();
    const tFim = okYmd(fim) ? new Date(Date.parse(fim + "T04:00:00.000Z") + 86400e3 - 1).toISOString() : new Date().toISOString();
    const [conv, vend, sales] = await Promise.all([
      sb.from("conversations").select("status", { count: "exact", head: true }).eq("status", "humano_comercial"),
      sb.from("vendedores").select("id, nome, tipo, ativo").eq("ativo", true),
      // atribuição oficial da Anne (seção 5): quando existe linha em sales, ela vence o código do utm_term
      sb.from("sales").select("hubla_transaction_id, attribution, matched_by, agent_slug, paid_at, amount")
        .gte("paid_at", tIni).lte("paid_at", tFim).range(0, 4999),
    ]);
    if (vend.error) throw new Error(vend.error.message);
    if (sales.error) throw new Error(sales.error.message);
    return json({ generated_at: new Date().toISOString(), janela: { ini: tIni, fim: tFim },
      humano_comercial: conv.count ?? null, vendedores: vend.data ?? [], sales: sales.data ?? [] });
  } catch (e) { return json({ error: String(e) }, 500); }
});
