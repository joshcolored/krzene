import { createHmac, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

type EventPayload = {
  data?: {
    id?: string;
    type?: string;
    data?: {
      id?: string;
      attributes?: { reference_number?: string };
    };
    attributes?: {
      type?: string;
      livemode?: boolean;
      data?: {
        id?: string;
        attributes?: { reference_number?: string };
      };
    };
  };
};

function safeEqualHex(left: string, right: string) {
  if (!left || !right || left.length !== right.length) return false;
  return timingSafeEqual(Buffer.from(left, "utf8"), Buffer.from(right, "utf8"));
}

function verifySignature(rawBody: string, header: string, secret: string) {
  const parts = Object.fromEntries(header.split(",").map((part) => {
    const [key, ...value] = part.trim().split("=");
    return [key, value.join("=")];
  }));
  const timestamp = parts.t;
  if (!timestamp) return false;

  const expected = createHmac("sha256", secret).update(`${timestamp}.${rawBody}`).digest("hex");
  return safeEqualHex(expected, parts.te || "") || safeEqualHex(expected, parts.li || "");
}

export async function POST(request: Request) {
  const rawBody = await request.text();
  const signature = request.headers.get("paymongo-signature") || request.headers.get("x-paymongo-signature") || "";
  const webhookSecret = process.env.PAYMONGO_WEBHOOK_SECRET?.trim();
  const admin = createAdminClient();

  if (!webhookSecret || !admin) {
    return NextResponse.json({ error: "Webhook is not configured." }, { status: 503 });
  }
  if (!verifySignature(rawBody, signature, webhookSecret)) {
    return NextResponse.json({ error: "Invalid signature." }, { status: 401 });
  }

  let payload: EventPayload;
  try {
    payload = JSON.parse(rawBody) as EventPayload;
  } catch {
    return NextResponse.json({ error: "Invalid JSON." }, { status: 400 });
  }

  const eventId = payload.data?.id;
  const attributes = payload.data?.attributes;
  const eventType = attributes?.type || payload.data?.type;
  if (!eventId || !eventType) return NextResponse.json({ received: true });
  if (eventType !== "checkout_session.payment.paid") return NextResponse.json({ received: true });

  const session = attributes?.data || payload.data?.data;
  const sessionId = session?.id;
  const referenceNumber = session?.attributes?.reference_number;
  if (!sessionId && !referenceNumber) return NextResponse.json({ received: true });

  const { error: eventError } = await admin.from("paymongo_webhook_events").insert({
    event_id: eventId,
    event_type: eventType,
    livemode: Boolean(attributes?.livemode),
  });
  if (eventError?.code === "23505") return NextResponse.json({ received: true, duplicate: true });
  if (eventError) {
    console.error("Could not record PayMongo event", eventError.code);
    return NextResponse.json({ error: "Event could not be recorded." }, { status: 500 });
  }

  let checkoutQuery = admin.from("premium_checkout_sessions").select("id,owner_id,status,access_days");
  checkoutQuery = sessionId
    ? checkoutQuery.eq("paymongo_checkout_session_id", sessionId)
    : checkoutQuery.eq("reference_number", referenceNumber!);
  const { data: checkout, error: checkoutError } = await checkoutQuery.single();

  if (checkoutError || !checkout) {
    console.error("Paid checkout was not found", sessionId || referenceNumber);
    await admin.from("paymongo_webhook_events").delete().eq("event_id", eventId);
    return NextResponse.json({ error: "Checkout was not found." }, { status: 500 });
  }
  if (checkout.status === "paid") return NextResponse.json({ received: true, duplicate: true });

  const now = new Date();
  const { data: current } = await admin
    .from("premium_subscriptions")
    .select("current_period_end")
    .eq("owner_id", checkout.owner_id)
    .maybeSingle();
  const currentEnd = current?.current_period_end ? new Date(current.current_period_end) : null;
  const startsAt = currentEnd && currentEnd > now ? currentEnd : now;
  const endsAt = new Date(startsAt);
  endsAt.setUTCDate(endsAt.getUTCDate() + checkout.access_days);

  const { error: premiumError } = await admin.from("premium_subscriptions").upsert({
    owner_id: checkout.owner_id,
    status: "active",
    current_period_start: now.toISOString(),
    current_period_end: endsAt.toISOString(),
    updated_at: now.toISOString(),
  }, { onConflict: "owner_id" });
  if (premiumError) {
    console.error("Premium access could not be activated", premiumError.code);
    await admin.from("paymongo_webhook_events").delete().eq("event_id", eventId);
    return NextResponse.json({ error: "Premium could not be activated." }, { status: 500 });
  }

  await admin.from("premium_checkout_sessions").update({
    status: "paid",
    paid_at: now.toISOString(),
  }).eq("id", checkout.id);

  return NextResponse.json({ received: true });
}
