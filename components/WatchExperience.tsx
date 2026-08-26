"use client";

import Link from "next/link";
import { useCallback, useMemo, useState } from "react";
import { PlayerChrome, type PlayerPanel, type PlayerSource } from "./PlayerChrome";
import { watchHref, type Media, type MediaDetail } from "@/lib/media";
import { DEFAULT_MIRROR, VIDSRC_MIRRORS, embedUrl, type VidSrcMirror } from "@/lib/vidsrc";
import { useAuth } from "./AuthProvider";

/** VidSrc takes a two-letter code on `ds_lang`; "" leaves the player default. */
const SUBTITLE_LANGUAGES = [
  { code: "", label: "Player default" },
  { code: "en", label: "English" },
  { code: "es", label: "Spanish" },
  { code: "fr", label: "French" },
  { code: "de", label: "German" },
  { code: "pt", label: "Portuguese" },
  { code: "it", label: "Italian" },
  { code: "tl", label: "Filipino" },
  { code: "ja", label: "Japanese" },
  { code: "ko", label: "Korean" },
  { code: "zh", label: "Chinese" },
  { code: "hi", label: "Hindi" },
  { code: "ar", label: "Arabic" },
];

export function WatchExperience({ detail, notice }: { detail: MediaDetail; notice?: string }) {
  const [mirror, setMirror] = useState<VidSrcMirror>(DEFAULT_MIRROR);
  const [season, setSeason] = useState(detail.seasons[0]?.number ?? 1);
  const [episode, setEpisode] = useState(1);
  const [subtitle, setSubtitle] = useState("");
  const { library, toggleLibrary } = useAuth();
  const saved = library.some((item) => item.key === detail.key);

  const isSeries = detail.kind === "tv";
  const seasons = detail.seasons;
  const seasonIndex = seasons.findIndex((entry) => entry.number === season);
  const activeSeason = seasons[seasonIndex] ?? seasons[0];

  // VidSrc keys off the IMDb id where we have one; the TMDB id is the fallback.
  const embedId = detail.imdbId ?? detail.tmdbId;

  const source: PlayerSource = useMemo(
    () => ({
      kind: "embed",
      label: mirror.name,
      url: embedUrl(detail.kind, embedId, isSeries ? season : null, isSeries ? episode : null, {
        host: mirror.host,
        subtitleLanguage: subtitle || undefined,
        autoplay: true,
      }),
    }),
    [detail.kind, embedId, isSeries, season, episode, mirror.host, mirror.name, subtitle],
  );

  const toggleSaved = () => void toggleLibrary(stripDetail(detail));

  const chooseSeason = (nextSeason: number) => {
    setSeason(nextSeason);
    setEpisode(1);
  };

  /** Walks episode order, rolling over into the neighbouring season. */
  const step = useCallback(
    (delta: number) => {
      const current = seasons[seasonIndex];
      if (!current) return;
      const next = episode + delta;
      if (next >= 1 && next <= current.episodeCount) {
        setEpisode(next);
        return;
      }
      const target = seasons[seasonIndex + delta];
      if (!target) return;
      setSeason(target.number);
      setEpisode(delta > 0 ? 1 : target.episodeCount);
    },
    [episode, seasonIndex, seasons],
  );

  const canStepBack = isSeries && (episode > 1 || seasonIndex > 0);
  const canStepForward =
    isSeries &&
    ((activeSeason ? episode < activeSeason.episodeCount : false) || seasonIndex < seasons.length - 1);

  const sourcePath = isSeries
    ? `embed/tv/${embedId}/${season}/${episode}`
    : `embed/movie/${embedId}`;

  const panels: PlayerPanel[] = [];

  if (isSeries && seasons.length > 0) {
    panels.push({
      id: "episodes",
      icon: "screen",
      label: "Episodes",
      content: (
        <div className="panel-episodes">
          <label className="panel-field">
            <span>Season</span>
            <select value={season} onChange={(event) => chooseSeason(Number(event.target.value))}>
              {seasons.map((entry) => (
                <option key={entry.number} value={entry.number}>
                  {entry.name}
                </option>
              ))}
            </select>
          </label>
          <div className="panel-episode-grid">
            {Array.from({ length: activeSeason?.episodeCount ?? 0 }, (_, index) => index + 1).map(
              (number) => (
                <button
                  key={number}
                  type="button"
                  className={episode === number ? "is-active" : ""}
                  onClick={() => setEpisode(number)}
                  aria-label={`Season ${season}, episode ${number}`}
                >
                  {number}
                </button>
              ),
            )}
          </div>
        </div>
      ),
    });
  }

  panels.push({
    id: "subtitles",
    icon: "captions",
    label: "Subtitles",
    content: (
      <div className="panel-list">
        {SUBTITLE_LANGUAGES.map((language) => (
          <button
            key={language.code || "default"}
            type="button"
            className={subtitle === language.code ? "is-active" : ""}
            onClick={() => setSubtitle(language.code)}
          >
            <b>{language.label}</b>
            {subtitle === language.code && <i>✓</i>}
          </button>
        ))}
        <p className="panel-note">
          Asks {mirror.name} to preselect that track. Coverage depends on what the mirror has for
          this title.
        </p>
      </div>
    ),
  });

  panels.push({
    id: "servers",
    icon: "settings",
    label: "Servers",
    content: (
      <div className="panel-list">
        {VIDSRC_MIRRORS.map((item) => (
          <button
            key={item.id}
            type="button"
            className={mirror.id === item.id ? "is-active" : ""}
            onClick={() => setMirror(item)}
          >
            <b>{item.name}</b>
            <span>{item.region}</span>
            {mirror.id === item.id && <i>✓</i>}
          </button>
        ))}
        <p className="panel-note">
          {sourcePath} on {new URL(mirror.host).host}. If one server won&apos;t load, switch.
        </p>
      </div>
    ),
  });

  return (
    <main className="watch-root">
      <PlayerChrome
        title={detail.title}
        kicker={isSeries ? "Series" : "Movie"}
        overview={detail.overview}
        backdrop={detail.backdrop ?? detail.poster}
        runtimeLabel={detail.runtime}
        source={source}
        panels={panels}
        backHref="/"
        nowPlaying={isSeries ? `S${season} · E${episode}` : undefined}
        onStep={isSeries ? step : undefined}
        canStepBack={canStepBack}
        canStepForward={canStepForward}
      />

      <section className="watch-below">
        <div className="watch-below-main">
          {notice && (
            <p className="watch-notice" role="status">
              {notice}
            </p>
          )}
          <p className="eyebrow">
            <span>Now watching</span>
          </p>
          <h1 className="watch-below-title">{detail.title}</h1>
          <div className="hero-meta">
            {detail.score > 0 && <span>★ {detail.score.toFixed(1)}</span>}
            {detail.year && <b>{detail.year}</b>}
            {detail.runtime && <b>{detail.runtime}</b>}
            {isSeries && (
              <b>
                S{season} · E{episode}
              </b>
            )}
            <b>{mirror.name}</b>
          </div>
          {detail.tagline && <p className="watch-tagline">“{detail.tagline}”</p>}
          <p className="watch-below-overview">
            {detail.overview || "No synopsis available for this title."}
          </p>
          <div className="genre-list">
            {detail.genres.map((genre) => (
              <span key={genre}>{genre}</span>
            ))}
          </div>
        </div>

        <aside className="watch-below-side">
          <button className="wide-save" onClick={toggleSaved}>
            {saved ? "✓ Saved to my list" : "+ Add to my list"}
          </button>
          <div className="watch-note">
            <b>Source</b>
            <p>
              {sourcePath} on {new URL(mirror.host).host}. Servers, subtitles and episodes are in the
              player&apos;s control bar.
            </p>
          </div>
          <div className="watch-note">
            <b>Shortcuts</b>
            <p>
              <kbd>F</kbd> fullscreen · <kbd>Space</kbd> play/pause · <kbd>←</kbd> <kbd>→</kbd> skip
              10s · <kbd>M</kbd> mute · <kbd>Esc</kbd> close a panel
            </p>
          </div>
        </aside>
      </section>

      {detail.recommendations.length > 0 && (
        <section className="watch-recommendations">
          <h2>Recommended next</h2>
          <div>
            {detail.recommendations.map((item) => (
              <Link href={watchHref(item)} key={item.key}>
                {item.backdrop || item.poster ? (
                  <img src={item.backdrop ?? item.poster!} alt="" loading="lazy" />
                ) : (
                  <span className="art-fallback" />
                )}
                <span>
                  <b>{item.title}</b>
                  <small>
                    {item.year ?? "—"} • {item.genres[0] ?? (item.kind === "tv" ? "Series" : "Film")}
                  </small>
                </span>
              </Link>
            ))}
          </div>
        </section>
      )}
    </main>
  );
}

/** Watchlist entries only need the card fields, not the full detail payload. */
function stripDetail(detail: MediaDetail): Media {
  const { key, kind, tmdbId, title, year, overview, poster, backdrop, score, genres, accent } = detail;
  return { key, kind, tmdbId, title, year, overview, poster, backdrop, score, genres, accent };
}
