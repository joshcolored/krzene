import { notFound } from "next/navigation";
import { WatchExperience } from "@/components/WatchExperience";
import { fetchDetailOutcome } from "@/lib/tmdb";
import { accentFor, type MediaDetail, type MediaKind } from "@/lib/media";
import { fetchWatchmodeOffers } from "@/lib/watchmode";

/**
 * Env and TMDB availability are per-request concerns, so never prerender this.
 */
export const dynamic = "force-dynamic";

/**
 * Movie and TV playback providers accept TMDB IDs.
 * So when TMDB metadata is unavailable (no key, rate limit, network blip) the
 * player still works; only the surrounding copy degrades. A 404 is reserved
 * for a genuinely malformed URL.
 */
function placeholderDetail(kind: MediaKind, tmdbId: number): MediaDetail {
  return {
    key: `${kind}-${tmdbId}`,
    kind,
    tmdbId,
    title: kind === "tv" ? `Series #${tmdbId}` : `Movie #${tmdbId}`,
    year: null,
    overview: "",
    poster: null,
    backdrop: null,
    score: 0,
    genres: [],
    accent: accentFor(tmdbId),
    imdbId: null,
    runtime: "",
    tagline: "",
    // Without metadata we cannot know the real season list; offer season 1 so
    // the episode picker still drives embed/tv/{id}/{season}/{episode}.
    seasons: kind === "tv" ? [{ number: 1, name: "Season 1", episodeCount: 24 }] : [],
    recommendations: [],
  };
}

export default async function WatchPage({
  params,
}: {
  params: Promise<{ type: string; id: string }>;
}) {
  const { type, id } = await params;

  // Only a malformed route is a real 404.
  if (type !== "movie" && type !== "tv") notFound();
  const tmdbId = Number(id);
  if (!Number.isInteger(tmdbId) || tmdbId <= 0) notFound();

  const kind = type as MediaKind;
  const [outcome, streamingOffers] = await Promise.all([
    fetchDetailOutcome(kind, tmdbId),
    fetchWatchmodeOffers(kind, tmdbId),
  ]);

  // TMDB confirmed there is no such title — that is a genuine 404.
  if (outcome.status === "missing") notFound();

  if (outcome.status === "ok") return <WatchExperience detail={outcome.detail} streamingOffers={streamingOffers} />;

  return (
    <WatchExperience
      detail={placeholderDetail(kind, tmdbId)}
      streamingOffers={streamingOffers}
      notice="Couldn't reach TMDB for this title's details, so the synopsis and episode list are unavailable. You can still try playback using the TMDB ID."
    />
  );
}
