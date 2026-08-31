import { NextResponse } from "next/server";
import { catalogLocale } from "@/lib/catalog-locale";
import { fetchDetailOutcome } from "@/lib/tmdb";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ type: string; id: string }> },
) {
  const { type, id } = await params;
  if (type !== "movie" && type !== "tv") {
    return NextResponse.json({ error: "Unsupported media type." }, { status: 400 });
  }
  const tmdbId = Number(id);
  if (!Number.isInteger(tmdbId) || tmdbId <= 0) {
    return NextResponse.json({ error: "Invalid TMDB id." }, { status: 400 });
  }

  const locale = catalogLocale(new URL(request.url).searchParams.get("lang"));
  const outcome = await fetchDetailOutcome(type, tmdbId, locale.tmdbLanguage);
  if (outcome.status === "missing") {
    return NextResponse.json({ error: "Title not found." }, { status: 404 });
  }
  if (outcome.status === "unavailable") {
    return NextResponse.json({ error: "Title metadata is temporarily unavailable." }, { status: 503 });
  }
  return NextResponse.json({ detail: outcome.detail });
}
