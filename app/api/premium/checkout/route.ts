import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

const PREMIUM_PRICE_CENTAVOS = 5000;

export async function POST(request: Request) {
  const supabase = await createClient();
  const admin = createAdminClient();
  const secretKey = process.env.PAYMONGO_SECRET_KEY?.trim();

  if (!supabase || !admin || !secretKey) {
    return NextResponse.json({ error: "Premium checkout is not configured yet." }, { status: 503 });
  }

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in before purchasing Premium." }, { status: 401 });

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
          description: "30 days of Krzene Premium with an ad-free catalog experience.",
          line_items: [{
            amount: PREMIUM_PRICE_CENTAVOS,
            currency: "PHP",
            description: "Ad-free access for 30 days",
            name: "Krzene Premium",
            quantity: 1,
          }],
          metadata: { owner_id: user.id, access_days: "30" },
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
    amount: PREMIUM_PRICE_CENTAVOS,
  });

  if (error) {
    console.error("Premium checkout could not be recorded", error.code);
    return NextResponse.json({ error: "Checkout could not be recorded safely." }, { status: 500 });
  }

  return NextResponse.json({ checkoutUrl });
}
