/**
 * VidSrc client — endpoints exactly as published in the VidSrc API docs
 * (see vidsrc-api.png in the project root).
 *
 *   Playback (working):
 *     embed/movie/{id}
 *     embed/tv/{id}
 *     embed/tv/{id}/{season}
 *     embed/tv/{id}/{season}/{episode}
 *
 *   Listing (documented, but the namespace currently 404s on every mirror):
 *     vapi/movie/{type}/{page}      type = "new" | "add"
 *     vapi/tv/{type}/{page}         type = "new" | "add"
 *     vapi/episode/latest/{page}
 *
 * {id} accepts an IMDb id (tt-prefixed) or a TMDB id. IMDb ids resolve more
 * reliably, so callers should prefer them and fall back to the TMDB id.
 */

export type VidSrcMirror = {
  id: string;
  name: string;
  region: string;
  host: string;
};

/** Ordered by observed reliability — the first entry is the default. */
export const VIDSRC_MIRRORS: VidSrcMirror[] = [
  { id: "vidsrc-me", name: "VidSrc", region: "Global", host: "https://vidsrc.me" },
  { id: "vidsrc-to", name: "VidSrc To", region: "EU", host: "https://vidsrc.to" },
  { id: "vidsrc-net", name: "VidSrc Net", region: "US", host: "https://vidsrc.net" },
  { id: "vidsrc-xyz", name: "VidSrc XYZ", region: "Backup", host: "https://vidsrc.xyz" },
];

export const DEFAULT_MIRROR = VIDSRC_MIRRORS[0];

export type EmbedOptions = {
  /** Mirror host, e.g. "https://vidsrc.me". Defaults to the primary mirror. */
  host?: string;
  /** Preferred subtitle language, ISO 639-1 (VidSrc `ds_lang`). */
  subtitleLanguage?: string;
  /** Absolute URL to a custom .vtt/.srt track (VidSrc `sub_url`). */
  subtitleUrl?: string;
  /** Start playback immediately where the mirror allows it. */
  autoplay?: boolean;
};

function withParams(url: string, options: EmbedOptions): string {
  const params = new URLSearchParams();
  if (options.subtitleLanguage) params.set("ds_lang", options.subtitleLanguage);
  if (options.subtitleUrl) params.set("sub_url", options.subtitleUrl);
  if (options.autoplay) params.set("autoplay", "1");
  const query = params.toString();
  return query ? `${url}?${query}` : url;
}

/** embed/movie/{id} */
export function movieEmbedUrl(id: string | number, options: EmbedOptions = {}): string {
  const host = options.host ?? DEFAULT_MIRROR.host;
  return withParams(`${host}/embed/movie/${id}`, options);
}

/**
 * embed/tv/{id} · embed/tv/{id}/{season} · embed/tv/{id}/{season}/{episode}
 * Season and episode are appended only when supplied, matching the three
 * separate TV endpoints in the docs.
 */
export function tvEmbedUrl(
  id: string | number,
  season?: number | null,
  episode?: number | null,
  options: EmbedOptions = {},
): string {
  const host = options.host ?? DEFAULT_MIRROR.host;
  let path = `${host}/embed/tv/${id}`;
  if (season != null) {
    path += `/${season}`;
    if (episode != null) path += `/${episode}`;
  }
  return withParams(path, options);
}

/** Builds the right embed URL for either media kind. */
export function embedUrl(
  kind: "movie" | "tv",
  id: string | number,
  season?: number | null,
  episode?: number | null,
  options: EmbedOptions = {},
): string {
  return kind === "movie" ? movieEmbedUrl(id, options) : tvEmbedUrl(id, season, episode, options);
}

/* ------------------------------------------------------------------ *
 * vapi listing endpoints
 * ------------------------------------------------------------------ */

export type VidSrcListItem = {
  imdbId: string | null;
  tmdbId: string | null;
  title: string;
  quality: string | null;
  kind: "movie" | "tv";
  season: number | null;
  episode: number | null;
};

export type VidSrcListResult = {
  items: VidSrcListItem[];
  /** Mirror that answered, for display/debugging. */
  mirror: string;
  pages: number | null;
};

type RawItem = Record<string, unknown>;

function str(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (typeof value === "number") return String(value);
  return null;
}

function num(value: unknown): number | null {
  const parsed = Number(str(value));
  return Number.isFinite(parsed) ? parsed : null;
}

/** VidSrc has shipped a few response shapes over time; accept all of them. */
function extractItems(payload: unknown): RawItem[] {
  if (Array.isArray(payload)) return payload as RawItem[];
  if (!payload || typeof payload !== "object") return [];
  const root = payload as Record<string, unknown>;
  const candidates = [root.result, root.results, root.items, root.data];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) return candidate as RawItem[];
    if (candidate && typeof candidate === "object") {
      const nested = (candidate as Record<string, unknown>).items;
      if (Array.isArray(nested)) return nested as RawItem[];
    }
  }
  return [];
}

function normalizeItem(raw: RawItem, kind: "movie" | "tv"): VidSrcListItem {
  return {
    imdbId: str(raw.imdb_id ?? raw.imdb ?? raw.imdbId),
    tmdbId: str(raw.tmdb_id ?? raw.tmdb ?? raw.tmdbId),
    title: str(raw.title ?? raw.name ?? raw.show_title) ?? "Untitled",
    quality: str(raw.quality),
    kind,
    season: num(raw.season ?? raw.season_number),
    episode: num(raw.episode ?? raw.episode_number),
  };
}

/**
 * Calls a vapi listing endpoint, trying each mirror in turn.
 *
 * Returns `null` when no mirror answers with usable JSON — which is the
 * current state of the API, so every caller must treat this as expected and
 * degrade rather than throw.
 */
export async function vidsrcList(
  resource: "movie" | "tv" | "episode",
  type: "new" | "add" | "latest",
  page = 1,
): Promise<VidSrcListResult | null> {
  const path = resource === "episode" ? `vapi/episode/latest/${page}` : `vapi/${resource}/${type}/${page}`;
  const kind: "movie" | "tv" = resource === "movie" ? "movie" : "tv";

  for (const mirror of VIDSRC_MIRRORS) {
    try {
      const response = await fetch(`${mirror.host}/${path}`, {
        headers: { accept: "application/json" },
        signal: AbortSignal.timeout(3500),
        next: { revalidate: 1800 },
      });
      if (!response.ok) continue;
      if (!(response.headers.get("content-type") ?? "").includes("json")) continue;

      const items = extractItems(await response.json()).map((raw) => normalizeItem(raw, kind));
      if (!items.length) continue;
      return { items, mirror: mirror.host, pages: null };
    } catch {
      // Mirror unreachable, blocked, or too slow — move to the next one.
    }
  }
  return null;
}
