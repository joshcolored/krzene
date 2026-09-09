/** Supported playback providers. Catalog IDs are TMDB unless explicitly AniList. */
export type PlaybackSource = {
  id: "cinesrc" | "zoryva";
  name: string;
  region: string;
  host: string;
  provider: "cinesrc" | "zoryva";
};

export const PLAYBACK_SOURCES: PlaybackSource[] = [
  { id: "cinesrc", name: "CineSrc", region: "Global", host: "https://cinesrc.st", provider: "cinesrc" },
  { id: "zoryva", name: "Zoryva", region: "Global", host: "https://zoryva.me", provider: "zoryva" },
];
export const DEFAULT_MIRROR = PLAYBACK_SOURCES[0];

export type EmbedOptions = {
  host?: string;
  provider?: PlaybackSource["provider"];
  autoplay?: boolean;
  startAt?: number;
  /** Only a verified AniList ID may select Zoryva's anime endpoint. */
  anilistId?: number | null;
};

function positiveId(id: string | number): string {
  if (!/^\d+$/.test(String(id)) || !Number.isSafeInteger(Number(id)) || Number(id) < 1) {
    throw new Error("Playback requires a positive numeric media ID.");
  }
  return String(id);
}

export function embedUrl(
  kind: "movie" | "tv",
  id: string | number,
  season?: number | null,
  episode?: number | null,
  options: EmbedOptions = {},
): string {
  const provider = options.provider ?? DEFAULT_MIRROR.provider;
  const host = options.host ?? PLAYBACK_SOURCES.find((source) => source.provider === provider)!.host;
  const selectedSeason = positiveId(season ?? 1);
  const selectedEpisode = positiveId(episode ?? 1);
  if (provider === "zoryva") {
    const path = options.anilistId != null
      ? `/embed/anime/${positiveId(options.anilistId)}/${selectedSeason}/${selectedEpisode}`
      : kind === "movie"
        ? `/embed/movie/${positiveId(id)}`
        : `/embed/tv/${positiveId(id)}/${selectedSeason}/${selectedEpisode}`;
    const url = new URL(path, host);
    url.searchParams.set("color", "#e50914");
    return url.toString();
  }
  const url = new URL(`/embed/${kind}/${positiveId(id)}`, host);
  if (kind === "tv") {
    url.searchParams.set("s", selectedSeason);
    url.searchParams.set("e", selectedEpisode);
  }
  if (options.autoplay) url.searchParams.set("autoplay", "true");
  if (options.startAt && Number.isFinite(options.startAt) && options.startAt > 0) {
    url.searchParams.set("t", String(Math.floor(options.startAt)));
  }
  return url.toString();
}
