import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const supabase = await createClient();
  const admin = createAdminClient();
  const secretKey = process.env.PAYMONGO_SECRET_KEY?.trim();

  if (!supabase) {
    return NextResponse.json({ error: "Premium checkout cannot reach Supabase authentication." }, { status: 503 });
  }
  if (!admin) {
    console.error("Premium checkout is missing SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY.");
    return NextResponse.json({ error: "Premium checkout needs its server database key." }, { status: 503 });
  }
  if (!secretKey) {
    console.error("Premium checkout is missing PAYMONGO_SECRET_KEY.");
    return NextResponse.json({ error: "Premium checkout needs its PayMongo server key." }, { status: 503 });
  }

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in before purchasing Premium." }, { status: 401 });

  const { data: plan, error: planError } = await admin
    .from("premium_plans")
    .select("id,name,price_centavos,currency,access_days")
    .eq("id", "standard")
    .eq("active", true)
    .maybeSingle();
  if (planError || !plan) {
    console.error("Premium checkout could not load the active database plan", planError?.code);
    return NextResponse.json({ error: "Premium plan is unavailable. Apply the latest Supabase migration." }, { status: 503 });
  }

  const configuredUrl = process.env.APP_URL?.trim();
  const appUrl = (configuredUrl || new URL(request.url).origin).replace(/\/$/, "");
  const referenceNumber = `KRZ-${user.id.slice(0, 8)}-${Date.now()}`;
  const idempotencyKey = randomUUID();
  const paymentMethods = (process.env.PAYMONGO_PAYMENT_METHODS || "qrph")
    .split(",")
    .map((method) => method.trim())
    .filter(Boolean);

  const response = await fetch("https://api.paymongo.com/v2/checkout_sessions", {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${secretKey}:`).toString("base64")}`,
      "Content-Type": "application/json",
      "Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify({
      data: {
        attributes: {
          billing: user.email ? { email: user.email, name: user.user_metadata?.full_name || user.email } : undefined,
          cancel_url: `${appUrl}/?premium=cancelled`,
          description: `${plan.access_days} days of ${plan.name} with an ad-free catalog experience and 1080p access where available.`,
          line_items: [{
            amount: plan.price_centavos,
            currency: plan.currency,
            description: `Ad-free access for ${plan.access_days} days`,
            name: plan.name,
            quantity: 1,
          }],
          metadata: { owner_id: user.id, plan_id: plan.id, access_days: String(plan.access_days) },
          payment_method_types: paymentMethods,
          reference_number: referenceNumber,
          send_email_receipt: true,
          show_description: true,
          show_line_items: true,
          success_url: `${appUrl}/?premium=success`,
        },
      },
    }),
    cache: "no-store",
  });

  const payload = await response.json() as {
    data?: { id?: string; attributes?: { checkout_url?: string } };
    errors?: Array<{ detail?: string }>;
  };
  const sessionId = payload.data?.id;
  const checkoutUrl = payload.data?.attributes?.checkout_url;

  if (!response.ok || !sessionId || !checkoutUrl) {
    console.error("PayMongo checkout creation failed", response.status, payload.errors?.map((error) => error.detail));
    return NextResponse.json({ error: "PayMongo could not start checkout. Try again shortly." }, { status: 502 });
  }

  const { error } = await admin.from("premium_checkout_sessions").insert({
    owner_id: user.id,
    paymongo_checkout_session_id: sessionId,
    reference_number: referenceNumber,
    plan_id: plan.id,
    amount: plan.price_centavos,
    currency: plan.currency,
    access_days: plan.access_days,
  });

  if (error) {
    console.error("Premium checkout could not be recorded", error.code);
    return NextResponse.json({ error: "Checkout could not be recorded safely." }, { status: 500 });
  }

  return NextResponse.json({ checkoutUrl });
}
