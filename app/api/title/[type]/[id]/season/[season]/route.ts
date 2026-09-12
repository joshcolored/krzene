import { NextResponse } from "next/server";
import { catalogLocale } from "@/lib/catalog-locale";
import { fetchSeasonEpisodes } from "@/lib/tmdb";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ type: string; id: string; season: string }> },
) {
  const { type, id, season } = await params;
  const tmdbId = Number(id);
  const seasonNumber = Number(season);
  if (type !== "tv" || !Number.isInteger(tmdbId) || tmdbId <= 0 || !Number.isInteger(seasonNumber) || seasonNumber <= 0) {
    return NextResponse.json({ error: "Invalid TV season." }, { status: 400 });
  }
  const locale = catalogLocale(new URL(request.url).searchParams.get("lang"));
  const episodes = await fetchSeasonEpisodes(tmdbId, seasonNumber, locale.tmdbLanguage);
  if (!episodes) return NextResponse.json({ error: "Season unavailable." }, { status: 503 });
  return NextResponse.json({ episodes });
}
