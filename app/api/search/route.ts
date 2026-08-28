import { NextResponse } from "next/server";
import { isConfigured, searchMedia } from "@/lib/tmdb";
import { isKidsMedia } from "@/lib/media";
import { catalogLocale } from "@/lib/catalog-locale";

/** Keeps the TMDB credential server-side; the client only sees results. */
export async function GET(request: Request) {
  const query = new URL(request.url).searchParams.get("q")?.trim() ?? "";
  const params = new URL(request.url).searchParams;
  const kidsOnly = params.get("kids") === "1";
  const locale = catalogLocale(params.get("lang"));
  if (!isConfigured()) {
    return NextResponse.json({ results: [], error: "TMDB_API_KEY is not set." }, { status: 503 });
  }
  if (!query) return NextResponse.json({ results: [] });

  const results = await searchMedia(query, locale.tmdbLanguage);
  return NextResponse.json({ results: kidsOnly ? results.filter(isKidsMedia) : results });
}
