import "server-only";

import type { MediaKind, StreamingOffer } from "@/lib/media";

const API_ROOT = "https://api.watchmode.com/v1";

type SearchResult = {
  id?: unknown;
  tmdb_id?: unknown;
  tmdb_type?: unknown;
};

type SourceResult = {
  source_id?: unknown;
  name?: unknown;
  type?: unknown;
  region?: unknown;
  format?: unknown;
  price?: unknown;
  web_url?: unknown;
};

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function number(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function externalUrl(value: unknown): string | null {
  const raw = text(value);
  if (!raw) return null;
  try {
    const url = new URL(raw);
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function offerType(value: unknown): StreamingOffer["type"] {
  switch (text(value)?.toLowerCase()) {
    case "sub": return "subscription";
    case "free": return "free";
    case "rent": return "rent";
    case "buy": return "buy";
    default: return "other";
  }
}

async function watchmode<T>(path: string, apiKey: string): Promise<T | null> {
  try {
    const response = await fetch(`${API_ROOT}${path}`, {
      headers: { Accept: "application/json", "X-API-Key": apiKey },
      signal: AbortSignal.timeout(8000),
      next: { revalidate: 21600 },
    });
    if (!response.ok) {
      console.error(`Watchmode ${path} returned ${response.status}`);
      return null;
    }
    return await response.json() as T;
  } catch (error) {
    console.error(`Watchmode ${path} failed`, error);
    return null;
  }
}

export async function fetchWatchmodeOffers(kind: MediaKind, tmdbId: number): Promise<StreamingOffer[]> {
  const apiKey = process.env.WATCHMODE_API_KEY?.trim();
  if (!apiKey) return [];

  const searchField = kind === "movie" ? "tmdb_movie_id" : "tmdb_tv_id";
  const search = await watchmode<{ title_results?: SearchResult[] }>(
    `/search/?search_field=${searchField}&search_value=${tmdbId}&types=${kind === "movie" ? "movie" : "tv"}`,
    apiKey,
  );
  const match = search?.title_results?.find((item) => number(item.tmdb_id) === tmdbId) ?? search?.title_results?.[0];
  const watchmodeId = number(match?.id);
  if (!watchmodeId) return [];

  const region = process.env.WATCHMODE_REGION?.trim().toUpperCase() || "PH";
  const sources = await watchmode<SourceResult[]>(
    `/title/${watchmodeId}/sources/?regions=${encodeURIComponent(region)}`,
    apiKey,
  );
  if (!Array.isArray(sources)) return [];

  const seen = new Set<string>();
  return sources.flatMap((source) => {
    const provider = text(source.name);
    const url = externalUrl(source.web_url);
    if (!provider || !url) return [];
    const type = offerType(source.type);
    const sourceRegion = text(source.region)?.toUpperCase() || region;
    const key = `${provider.toLowerCase()}|${type}|${sourceRegion}|${url}`;
    if (seen.has(key)) return [];
    seen.add(key);
    return [{
      id: `${number(source.source_id) ?? provider}-${type}-${seen.size}`,
      provider,
      type,
      region: sourceRegion,
      format: text(source.format),
      price: number(source.price),
      url,
    } satisfies StreamingOffer];
  }).slice(0, 12);
}
