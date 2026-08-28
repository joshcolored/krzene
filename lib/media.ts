/** Shared media shape used by every UI surface. */

export type MediaKind = "movie" | "tv";

export type Media = {
  /** Stable UI key and watchlist id, e.g. "movie-603692". */
  key: string;
  kind: MediaKind;
  tmdbId: number;
  title: string;
  year: number | null;
  overview: string;
  poster: string | null;
  backdrop: string | null;
  /** TMDB vote average, 0–10. */
  score: number;
  genres: string[];
  accent: string;
};

export type MediaRail = {
  id: string;
  kicker: string;
  heading: string;
  kind: MediaKind | "mixed";
  items: Media[];
};

export type SeasonSummary = {
  number: number;
  name: string;
  episodeCount: number;
};

export type MediaDetail = Media & {
  imdbId: string | null;
  /** "2h 11m" for movies, "3 seasons · 62 episodes" for shows. */
  runtime: string;
  tagline: string;
  seasons: SeasonSummary[];
  recommendations: Media[];
};

export type StreamingOffer = {
  id: string;
  provider: string;
  type: "subscription" | "free" | "rent" | "buy" | "other";
  region: string;
  format: string | null;
  price: number | null;
  url: string;
};

export type HomeData =
  | { configured: true; hero: MediaDetail; rails: MediaRail[]; vidsrcMirror: string | null; localeCode: string }
  | { configured: false; reason: string };

/**
 * Deliberately conservative: TMDB's adult flag does not mean a title is
 * suitable for children. Kids profiles only receive titles explicitly filed
 * under Kids or Family; animation alone can still be adult-oriented.
 */
export function isKidsMedia(media: Pick<Media, "genres">): boolean {
  return media.genres.some((genre) => {
    const normalized = genre.trim().toLowerCase();
    return normalized === "kids" || normalized === "family";
  });
}

const ACCENTS = [
  "#e36f34",
  "#845eff",
  "#ef3b63",
  "#2cbf89",
  "#2778ff",
  "#9f2549",
  "#7ba6c8",
  "#f044d0",
  "#df9a32",
  "#388ed0",
];

/** Deterministic so server and client render identical markup. */
export function accentFor(tmdbId: number): string {
  return ACCENTS[Math.abs(tmdbId) % ACCENTS.length];
}

export function watchHref(media: Pick<Media, "kind" | "tmdbId">): string {
  return `/watch/${media.kind}/${media.tmdbId}`;
}
