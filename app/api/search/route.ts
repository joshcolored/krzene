import { NextResponse } from "next/server";
import { isConfigured, searchMedia } from "@/lib/tmdb";
import { isKidsMedia } from "@/lib/media";

/** Keeps the TMDB credential server-side; the client only sees results. */
export async function GET(request: Request) {
  const query = new URL(request.url).searchParams.get("q")?.trim() ?? "";
  const kidsOnly = new URL(request.url).searchParams.get("kids") === "1";
  if (!isConfigured()) {
    return NextResponse.json({ results: [], error: "TMDB_API_KEY is not set." }, { status: 503 });
  }
  if (!query) return NextResponse.json({ results: [] });

  const results = await searchMedia(query);
  return NextResponse.json({ results: kidsOnly ? results.filter(isKidsMedia) : results });
}
