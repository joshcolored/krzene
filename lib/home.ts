/**
 * Assembles the home screen catalog.
 *
 * Metadata and artwork come from TMDB; every play button resolves to a VidSrc
 * embed URL. The VidSrc `vapi` listing endpoints are also queried — they are
 * documented but currently retired, so that rail only appears if a mirror
 * answers.
 */

import type { HomeData, Media, MediaRail } from "./media";
import { catalogLocale } from "./catalog-locale";
import { fetchDeepList, fetchDetail, fetchList, genreMap, isConfigured } from "./tmdb";
import { vidsrcList } from "./vidsrc";

/** Japanese animation, for the Anime tab. */
const ANIME_PARAMS = {
  with_genres: 16,
  with_original_language: "ja",
  sort_by: "popularity.desc",
  "vote_count.gte": 50,
};

export async function getHomeData(localeCode?: string | null): Promise<HomeData> {
  if (!isConfigured()) {
    return { configured: false, reason: "TMDB_API_KEY is not set." };
  }

  const locale = catalogLocale(localeCode);
  const genres = await genreMap(locale.tmdbLanguage);
  const deepList = (
    path: string,
    kind: "movie" | "tv",
    params: Record<string, string | number> = {},
  ) => fetchDeepList(path, kind, genres, { ...params, language: locale.tmdbLanguage });
  const list = (
    path: string,
    kind: "movie" | "tv",
    params: Record<string, string | number> = {},
  ) => fetchList(path, kind, genres, { ...params, language: locale.tmdbLanguage });

  const [
    trending,
    trendingMovies,
    trendingShows,
    popularMovies,
    topMovies,
    upcoming,
    popularShows,
    onTheAir,
    topShows,
    anime,
    regionalMovies,
    kidsMovies,
    kidsShows,
    kidsAnimation,
    vidsrcMovies,
    vidsrcShows,
  ] = await Promise.all([
    deepList("/trending/all/week", "movie"),
    deepList("/trending/movie/day", "movie"),
    deepList("/trending/tv/day", "tv"),
    deepList("/movie/popular", "movie", { region: locale.countryCode }),
    deepList("/movie/top_rated", "movie", { region: locale.countryCode }),
    list("/movie/upcoming", "movie", { region: locale.countryCode }),
    deepList("/tv/popular", "tv"),
    list("/tv/on_the_air", "tv"),
    deepList("/tv/top_rated", "tv"),
    deepList("/discover/tv", "tv", ANIME_PARAMS),
    deepList("/discover/movie", "movie", {
      with_origin_country: locale.countryCode,
      with_original_language: locale.originalLanguage,
      region: locale.countryCode,
      include_adult: "false",
      sort_by: "popularity.desc",
    }),
    deepList("/discover/movie", "movie", {
      with_genres: 10751,
      include_adult: "false",
      sort_by: "popularity.desc",
    }),
    deepList("/discover/tv", "tv", {
      with_genres: "10762|10751",
      include_adult: "false",
      sort_by: "popularity.desc",
    }),
    deepList("/discover/tv", "tv", {
      with_genres: "16,10762",
      include_adult: "false",
      sort_by: "popularity.desc",
    }),
    vidsrcList("movie", "add"),
    vidsrcList("tv", "add"),
  ]);

  if (!trending.length && !popularMovies.length && !popularShows.length) {
    return {
      configured: false,
      reason: "TMDB rejected the key, or the request could not be reached.",
    };
  }

  // The hero needs a full-width backdrop and a tagline, so pull its detail.
  const candidates = [...trending, ...popularMovies, ...popularShows];
  const lead = candidates.find((item) => item.backdrop) ?? candidates[0];
  const hero =
    (await fetchDetail(lead.kind, lead.tmdbId, locale.tmdbLanguage)) ??
    { ...lead, imdbId: null, runtime: "", tagline: "", seasons: [], recommendations: [] };

  const rails: MediaRail[] = [
    { id: "trending", kicker: "JUST FOR YOU", heading: "Trending this week", kind: "mixed", items: trending },
    { id: "regional-popular", kicker: `${locale.label.toUpperCase()} STORIES`, heading: `Popular in ${locale.country}`, kind: "movie", items: regionalMovies },
    { id: "trending-movies", kicker: "TRENDING TODAY", heading: "Movies everyone is watching", kind: "movie", items: trendingMovies },
    { id: "trending-shows", kicker: "TRENDING TODAY", heading: "Series everyone is watching", kind: "tv", items: trendingShows },
    { id: "movies-popular", kicker: "MOVIES", heading: "Popular movies", kind: "movie", items: popularMovies },
    { id: "movies-top", kicker: "MOVIES", heading: "Highest rated of all time", kind: "movie", items: topMovies },
    { id: "movies-upcoming", kicker: "MOVIES", heading: "Coming soon", kind: "movie", items: upcoming },
    { id: "tv-popular", kicker: "TV SHOWS", heading: "Popular series", kind: "tv", items: popularShows },
    { id: "tv-air", kicker: "TV SHOWS", heading: "On the air now", kind: "tv", items: onTheAir },
    { id: "tv-top", kicker: "TV SHOWS", heading: "Highest rated series", kind: "tv", items: topShows },
    { id: "anime", kicker: "ANIME", heading: "Anime & animation", kind: "tv", items: anime },
    { id: "kids-trending", kicker: "KIDS", heading: "Popular for kids", kind: "mixed", items: [...kidsMovies.slice(0, 20), ...kidsShows.slice(0, 20)] },
    { id: "kids-movies", kicker: "FAMILY MOVIES", heading: "Movies for everyone", kind: "movie", items: kidsMovies },
    { id: "kids-shows", kicker: "KIDS TV", heading: "Shows made for kids", kind: "tv", items: kidsShows },
    { id: "kids-animation", kicker: "ANIMATION", heading: "Animated adventures", kind: "tv", items: kidsAnimation },
  ];

  // Only rendered when VidSrc's listing API is actually alive.
  const freshOnVidsrc = mergeVidsrc(vidsrcMovies?.items, vidsrcShows?.items, [
    ...trending,
    ...popularMovies,
    ...popularShows,
    ...topMovies,
    ...topShows,
  ]);
  if (freshOnVidsrc.length) {
    rails.splice(1, 0, {
      id: "vidsrc-fresh",
      kicker: "VIDSRC",
      heading: "Just added to VidSrc",
      kind: "mixed",
      items: freshOnVidsrc,
    });
  }

  return {
    configured: true,
    hero,
    rails: rails.filter((rail) => rail.items.length > 0),
    vidsrcMirror: vidsrcMovies?.mirror ?? vidsrcShows?.mirror ?? null,
    localeCode: locale.code,
  };
}

/**
 * VidSrc list items carry ids and a title but no artwork, so they are only
 * usable once matched against a TMDB record we already hold.
 */
function mergeVidsrc(
  movies: { tmdbId: string | null; title: string }[] | undefined,
  shows: { tmdbId: string | null; title: string }[] | undefined,
  known: Media[],
): Media[] {
  const listed = [...(movies ?? []), ...(shows ?? [])];
  if (!listed.length) return [];

  const byId = new Map(known.map((item) => [String(item.tmdbId), item]));
  const byTitle = new Map(known.map((item) => [item.title.toLowerCase(), item]));

  const matched: Media[] = [];
  const seen = new Set<string>();
  for (const entry of listed) {
    const hit = (entry.tmdbId ? byId.get(entry.tmdbId) : undefined) ?? byTitle.get(entry.title.toLowerCase());
    if (hit && !seen.has(hit.key)) {
      seen.add(hit.key);
      matched.push(hit);
    }
  }
  return matched.slice(0, 20);
}
