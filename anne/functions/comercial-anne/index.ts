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
    const [conv, vend] = await Promise.all([
      sb.from("conversations").select("status", { count: "exact", head: true }).eq("status", "humano_comercial"),
      sb.from("vendedores").select("id, nome, tipo, ativo").eq("ativo", true),
    ]);
    if (vend.error) throw new Error(vend.error.message);
    return json({ generated_at: new Date().toISOString(), humano_comercial: conv.count ?? null, vendedores: vend.data ?? [] });
  } catch (e) { return json({ error: String(e) }, 500); }
});
