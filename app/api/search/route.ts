import { NextResponse } from "next/server";
import { isConfigured, searchMedia } from "@/lib/tmdb";

/** Keeps the TMDB credential server-side; the client only sees results. */
export async function GET(request: Request) {
  const query = new URL(request.url).searchParams.get("q")?.trim() ?? "";
  if (!isConfigured()) {
    return NextResponse.json({ results: [], error: "TMDB_API_KEY is not set." }, { status: 503 });
  }
  if (!query) return NextResponse.json({ results: [] });

  return NextResponse.json({ results: await searchMedia(query) });
}
