/** Episode mappings from https://github.com/anibridge/anibridge-mappings (v3).
 * No title matching: ambiguous or non-1:1 mappings fall back to TMDB playback.
 */
export type AnimeMapping = {
  season: number;
  anilistId: number;
  firstEpisode: number;
  lastEpisode: number | null;
  anilistFirstEpisode: number;
};

type Dataset = Record<string, unknown>;
const DATA_URL = "https://github.com/anibridge/anibridge-mappings/releases/download/v3/mappings.min.json";
let cached: Dataset = {};
let expiresAt = 0;
let pending: Promise<Dataset> | undefined;

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

async function dataset(): Promise<Dataset> {
  if (Date.now() < expiresAt) return cached;
  if (pending) return pending;
  pending = (async () => {
    try {
      const response = await fetch(DATA_URL, { cache: "no-store", signal: AbortSignal.timeout(8000) });
      if (!response.ok) throw new Error("Mapping dataset unavailable");
      const data: unknown = await response.json();
      if (!object(data)) throw new Error("Invalid mapping dataset");
      // Keep only TMDB → AniList entries in the process cache.
      cached = Object.fromEntries(Object.entries(data)
        .filter(([key, value]) => /^tmdb_(show|movie):/.test(key) && object(value))
        .map(([key, value]) => [key, Object.fromEntries(Object.entries(value as Dataset)
          .filter(([target]) => /^anilist:\d+$/.test(target)))]));
      expiresAt = Date.now() + 24 * 60 * 60 * 1000;
    } catch {
      // Do not block playback or hammer an unavailable mapping service.
      expiresAt = Date.now() + 60_000;
    }
    return cached;
  })();
  try { return await pending; } finally { pending = undefined; }
}

function range(text: string): [number, number] | null {
  const match = /^(\d+)(?:-(\d*))?$/.exec(text);
  if (!match) return null;
  const start = Number(match[1]);
  const end = match[2] === undefined ? start : match[2] === "" ? Infinity : Number(match[2]);
  return Number.isSafeInteger(start) && start > 0 && end >= start &&
    (end === Infinity || Number.isSafeInteger(end)) ? [start, end] : null;
}

export function mappingsFromDataset(data: Dataset, kind: "movie" | "tv", id: number): AnimeMapping[] {
  const prefix = kind === "movie" ? `tmdb_movie:${id}` : `tmdb_show:${id}:s`;
  const result: AnimeMapping[] = [];
  for (const [key, targets] of Object.entries(data)) {
    if (kind === "movie" ? key !== prefix : !key.startsWith(prefix)) continue;
    const season = kind === "movie" ? 1 : Number(key.slice(prefix.length));
    if (!Number.isSafeInteger(season) || season < 1 || !object(targets)) continue;
    for (const [target, episodes] of Object.entries(targets)) {
      if (!/^anilist:\d+$/.test(target) || !object(episodes)) continue;
      const anilistId = Number(target.slice(8));
      if (!Number.isSafeInteger(anilistId) || anilistId < 1) continue;
      // An empty relationship alone doesn't establish episode correspondence.
      for (const [source, destination] of Object.entries(episodes)) {
        if (typeof destination !== "string") continue;
        const [segments, ratio, extra] = destination.split("|");
        if (extra !== undefined || (ratio !== undefined && ratio !== "1")) continue;
        const sourceRange = range(source);
        const targetRanges = segments.split(",").map(range);
        if (!sourceRange || targetRanges.some((entry) => entry === null)) continue;
        const ranges = targetRanges as [number, number][];
        const count = ranges.reduce((sum, [first, last]) => sum + last - first + 1, 0);
        if (count !== sourceRange[1] - sourceRange[0] + 1) continue;
        let cursor = sourceRange[0];
        for (const [first, last] of ranges) {
          const end = cursor + last - first;
          result.push({ season, anilistId, firstEpisode: cursor,
            lastEpisode: Number.isFinite(end) ? end : null, anilistFirstEpisode: first });
          cursor = end + 1;
        }
      }
    }
  }
  return result;
}

export async function animeMappings(kind: "movie" | "tv", id: number): Promise<AnimeMapping[]> {
  return mappingsFromDataset(await dataset(), kind, id);
}

export function resolveAnimeEpisode(mappings: AnimeMapping[], season: number, episode: number) {
  const matches = mappings.filter((mapping) => mapping.season === season &&
    episode >= mapping.firstEpisode && (mapping.lastEpisode === null || episode <= mapping.lastEpisode));
  const unique = new Map(matches.map((mapping) => {
    const result = { anilistId: mapping.anilistId, episode: mapping.anilistFirstEpisode + episode - mapping.firstEpisode };
    return [`${result.anilistId}:${result.episode}`, result];
  }));
  return unique.size === 1 ? [...unique.values()][0] : null;
}
