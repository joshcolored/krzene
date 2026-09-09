/**
 * TMDB client (server-only).
 *
 * TMDB supplies the catalog metadata — titles, artwork, genres, seasons, and
 * the IMDb id for reference. Playback providers are defined in lib/playback.ts.
 *
 * Set TMDB_API_KEY in .env.local. Both credential types are accepted:
 *   - v3 API key (32 hex chars)      → sent as ?api_key=
 *   - v4 read access token (JWT)     → sent as Authorization: Bearer
 */

import { animeMappings } from "./anime-mappings";
import {
  accentFor,
  type Media,
  type MediaDetail,
  type MediaKind,
  type SeasonSummary,
} from "./media";

const API = "https://api.themoviedb.org/3";
const IMAGE = "https://image.tmdb.org/t/p";
const REVALIDATE = 3600;

function credential(): string | null {
  const key = process.env.TMDB_API_KEY?.trim();
  return key ? key : null;
}

export function isConfigured(): boolean {
  return credential() !== null;
}

/** v4 read tokens are JWTs and are far longer than a v3 key. */
function isBearerToken(key: string): boolean {
  return key.startsWith("ey") || key.length > 40;
}

/**
 * Raw call that preserves *why* a request failed, so callers can tell
 * "this title does not exist" (404) from "TMDB was unreachable".
 */
async function tmdbRaw<T>(
  path: string,
  params: Record<string, string | number> = {},
): Promise<{ data: T | null; missing: boolean }> {
  const key = credential();
  if (!key) return { data: null, missing: false };

  const url = new URL(`${API}${path}`);
  url.searchParams.set("language", "en-US");
  for (const [name, value] of Object.entries(params)) url.searchParams.set(name, String(value));

  const headers: Record<string, string> = { accept: "application/json" };
  if (isBearerToken(key)) headers.authorization = `Bearer ${key}`;
  else url.searchParams.set("api_key", key);

  // No AbortSignal here on purpose: Next.js treats a fetch carrying a signal as
  // uncacheable, which would silently defeat the revalidate window below.
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await fetch(url, { headers, next: { revalidate: REVALIDATE } });
      if (response.ok) return { data: (await response.json()) as T, missing: false };

      // 401/404 are verdicts, not blips — retrying cannot change them.
      if (response.status === 401 || response.status === 404) {
        console.error(`TMDB ${path} → ${response.status}`);
        return { data: null, missing: response.status === 404 };
      }
      console.error(`TMDB ${path} → ${response.status}${attempt === 0 ? " (retrying)" : ""}`);
    } catch (error) {
      console.error(`TMDB ${path} failed${attempt === 0 ? " (retrying)" : ""}`, error);
    }
  }
  return { data: null, missing: false };
}

async function tmdb<T>(path: string, params: Record<string, string | number> = {}): Promise<T | null> {
  return (await tmdbRaw<T>(path, params)).data;
}

/* ------------------------------------------------------------------ *
 * Raw TMDB shapes (only the fields actually consumed)
 * ------------------------------------------------------------------ */

type TmdbItem = {
  original_language?: string;
  id: number;
  media_type?: string;
  title?: string;
  name?: string;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  vote_average?: number;
  release_date?: string;
  first_air_date?: string;
  genre_ids?: number[];
  genres?: { id: number; name: string }[];
};

type TmdbPage = { results?: TmdbItem[]; total_pages?: number };

type TmdbDetail = TmdbItem & {
  tagline?: string;
  imdb_id?: string | null;
  runtime?: number | null;
  episode_run_time?: number[];
  number_of_seasons?: number;
  number_of_episodes?: number;
  seasons?: { season_number: number; name?: string; episode_count?: number }[];
  external_ids?: { imdb_id?: string | null };
  recommendations?: TmdbPage;
  similar?: TmdbPage;
};

/* ------------------------------------------------------------------ *
 * Normalization
 * ------------------------------------------------------------------ */

export function imageUrl(path: string | null | undefined, size: string): string | null {
  return path ? `${IMAGE}/${size}${path}` : null;
}

function yearOf(item: TmdbItem): number | null {
  const date = item.release_date || item.first_air_date;
  const year = date ? Number(date.slice(0, 4)) : NaN;
  return Number.isFinite(year) && year > 1800 ? year : null;
}

/** Genre id → name, fetched once per revalidation window. */
export async function genreMap(language = "en-US"): Promise<Map<number, string>> {
  const [movies, shows] = await Promise.all([
    tmdb<{ genres?: { id: number; name: string }[] }>("/genre/movie/list", { language }),
    tmdb<{ genres?: { id: number; name: string }[] }>("/genre/tv/list", { language }),
  ]);
  const map = new Map<number, string>();
  for (const genre of [...(movies?.genres ?? []), ...(shows?.genres ?? [])]) map.set(genre.id, genre.name);
  return map;
}

function toMedia(item: TmdbItem, fallbackKind: MediaKind, genres: Map<number, string>): Media | null {
  const kind: MediaKind =
    item.media_type === "movie" || item.media_type === "tv" ? item.media_type : fallbackKind;
  const title = item.title ?? item.name;
  if (!item.id || !title) return null;

  const names = item.genres?.length
    ? item.genres.map((genre) => genre.name)
    : (item.genre_ids ?? []).map((id) => genres.get(id)).filter((name): name is string => Boolean(name));

  return {
    key: `${kind}-${item.id}`,
    kind,
    tmdbId: item.id,
    title,
    year: yearOf(item),
    overview: item.overview?.trim() ?? "",
    poster: imageUrl(item.poster_path, "w500"),
    backdrop: imageUrl(item.backdrop_path, "w780"),
    score: Math.round((item.vote_average ?? 0) * 10) / 10,
    genres: names.slice(0, 3),
    accent: accentFor(item.id),
  };
}

function normalizeList(
  page: TmdbPage | null,
  fallbackKind: MediaKind,
  genres: Map<number, string>,
): Media[] {
  return (page?.results ?? [])
    .map((item) => toMedia(item, fallbackKind, genres))
    .filter((media): media is Media => media !== null)
    // A card with no artwork at all is a hole in the rail.
    .filter((media) => media.backdrop || media.poster);
}

/** Drops repeats so a title never appears twice in one rail. */
function dedupe(items: Media[]): Media[] {
  const seen = new Set<string>();
  return items.filter((item) => (seen.has(item.key) ? false : (seen.add(item.key), true)));
}

/* ------------------------------------------------------------------ *
 * Catalog queries
 * ------------------------------------------------------------------ */

export async function fetchList(
  path: string,
  fallbackKind: MediaKind,
  genres: Map<number, string>,
  params: Record<string, string | number> = {},
): Promise<Media[]> {
  return normalizeList(await tmdb<TmdbPage>(path, params), fallbackKind, genres);
}

/** Two pages back to back, for the rails that should feel deep. */
export async function fetchDeepList(
  path: string,
  fallbackKind: MediaKind,
  genres: Map<number, string>,
  params: Record<string, string | number> = {},
): Promise<Media[]> {
  const [first, second] = await Promise.all([
    fetchList(path, fallbackKind, genres, { ...params, page: 1 }),
    fetchList(path, fallbackKind, genres, { ...params, page: 2 }),
  ]);
  return dedupe([...first, ...second]);
}

export async function searchMedia(query: string, language = "en-US"): Promise<Media[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];
  const genres = await genreMap(language);
  const page = await tmdb<TmdbPage>("/search/multi", {
    query: trimmed,
    include_adult: "false",
    language,
  });
  const results = (page?.results ?? []).filter(
    (item) => item.media_type === "movie" || item.media_type === "tv",
  );
  return dedupe(normalizeList({ results }, "movie", genres));
}

function runtimeLabel(detail: TmdbDetail, kind: MediaKind): string {
  if (kind === "movie") {
    const minutes = detail.runtime ?? 0;
    if (!minutes) return "Runtime unavailable";
    return `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, "0")}m`;
  }
  const seasons = detail.number_of_seasons ?? 0;
  const episodes = detail.number_of_episodes ?? 0;
  const parts: string[] = [];
  if (seasons) parts.push(`${seasons} season${seasons === 1 ? "" : "s"}`);
  if (episodes) parts.push(`${episodes} episode${episodes === 1 ? "" : "s"}`);
  return parts.join(" · ") || "Ongoing series";
}

function seasonSummaries(detail: TmdbDetail): SeasonSummary[] {
  return (detail.seasons ?? [])
    // Keep the season picker focused on regular episodes.
    .filter((season) => season.season_number > 0 && (season.episode_count ?? 0) > 0)
    .map((season) => ({
      number: season.season_number,
      name: season.name?.trim() || `Season ${season.season_number}`,
      episodeCount: season.episode_count ?? 1,
    }))
    .sort((a, b) => a.number - b.number);
}

/**
 * Outcome-aware detail fetch:
 *   ok          — metadata loaded
 *   missing     — TMDB says no such title; the caller should 404
 *   unavailable — no key / rate limited / unreachable; playback can still work
 */
export type DetailOutcome =
  | { status: "ok"; detail: MediaDetail }
  | { status: "missing" }
  | { status: "unavailable" };

export async function fetchDetailOutcome(
  kind: MediaKind,
  tmdbId: number,
  language = "en-US",
): Promise<DetailOutcome> {
  const genres = await genreMap(language);
  const { data: detail, missing } = await tmdbRaw<TmdbDetail>(`/${kind}/${tmdbId}`, {
    append_to_response: "external_ids,recommendations,similar",
    language,
  });
  if (!detail) return missing ? { status: "missing" } : { status: "unavailable" };

  const base = toMedia({ ...detail, media_type: kind }, kind, genres);
  if (!base) return { status: "missing" };

  const related = dedupe([
    ...normalizeList(detail.recommendations ?? null, kind, genres),
    ...normalizeList(detail.similar ?? null, kind, genres),
  ]).filter((item) => item.key !== base.key);

  return {
    status: "ok",
    detail: {
      ...base,
      animeMappings: detail.original_language === "ja" && detail.genres?.some((genre) => genre.id === 16)
        ? await animeMappings(kind, tmdbId) : [],
      backdrop: imageUrl(detail.backdrop_path, "original"),
      imdbId: detail.imdb_id ?? detail.external_ids?.imdb_id ?? null,
      runtime: runtimeLabel(detail, kind),
      tagline: detail.tagline?.trim() ?? "",
      seasons: kind === "tv" ? seasonSummaries(detail) : [],
      recommendations: related.slice(0, 8),
    },
  };
}

export async function fetchDetail(
  kind: MediaKind,
  tmdbId: number,
  language = "en-US",
): Promise<MediaDetail | null> {
  const outcome = await fetchDetailOutcome(kind, tmdbId, language);
  return outcome.status === "ok" ? outcome.detail : null;
}

/** Hero needs a wide backdrop and a tagline, so it gets its own detail call. */
export async function fetchHero(kind: MediaKind, tmdbId: number): Promise<MediaDetail | null> {
  return fetchDetail(kind, tmdbId);
}
