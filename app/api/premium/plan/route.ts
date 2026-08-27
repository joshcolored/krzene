import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET() {
  const supabase = await createClient();
  if (!supabase) {
    return NextResponse.json({ error: "Premium plans cannot reach Supabase." }, { status: 503 });
  }

  const { data, error } = await supabase
    .from("premium_plans")
    .select("id,name,price_centavos,currency,access_days")
    .eq("id", "standard")
    .eq("active", true)
    .maybeSingle();

  if (error || !data) {
    return NextResponse.json({ error: "The Premium plan is not available." }, { status: 503 });
  }

  return NextResponse.json({
    plan: {
      id: data.id,
      name: data.name,
      priceCentavos: data.price_centavos,
      currency: data.currency,
      accessDays: data.access_days,
    },
  }, { headers: { "Cache-Control": "no-store, max-age=0" } });
}
