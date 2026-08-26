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
  // English is selected up front so supported tracks are visible immediately.
  const [subtitle, setSubtitle] = useState("en");
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
        <div>
          <label className="mb-3 flex items-center gap-[10px]">
            <span className="w-[52px] text-[10px] font-bold tracking-[.1em] text-[#817c75] uppercase">Season</span>
            <select className="min-w-0 flex-1 cursor-pointer appearance-none rounded-[9px] border border-white/10 bg-[#242321] px-[10px] py-[9px] text-xs font-semibold text-white outline-none" value={season} onChange={(event) => chooseSeason(Number(event.target.value))}>
              {seasons.map((entry) => (
                <option key={entry.number} value={entry.number}>
                  {entry.name}
                </option>
              ))}
            </select>
          </label>
          <div className="grid grid-cols-6 gap-[6px] max-[760px]:grid-cols-5">
            {Array.from({ length: activeSeason?.episodeCount ?? 0 }, (_, index) => index + 1).map(
              (number) => (
                <button
                  key={number}
                  type="button"
                  className={`cursor-pointer rounded-lg border px-0 py-[9px] text-[11px] font-bold transition ${episode === number ? "border-[#f2f0ec] bg-[#f2f0ec] text-[#111]" : "border-white/8 bg-[#20201f] text-[#a9a49d] hover:bg-[#2b2a29] hover:text-white"}`}
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
      <div className="flex flex-col gap-[2px]">
        {SUBTITLE_LANGUAGES.map((language) => (
          <button
            key={language.code || "default"}
            type="button"
            className={`flex cursor-pointer items-center gap-[10px] rounded-lg border-0 px-[10px] py-[9px] text-left transition ${subtitle === language.code ? "bg-white/13 text-white" : "bg-transparent text-[#aaa59e] hover:bg-white/8 hover:text-white"}`}
            onClick={() => setSubtitle(language.code)}
          >
            <b className="text-[13px] font-semibold">{language.label}</b>
            {subtitle === language.code && <i className="ml-auto text-[#f5ad12] not-italic">✓</i>}
          </button>
        ))}
        <p className="mx-1 mt-3 mb-[2px] text-[11px] leading-[1.6] text-[#77726c]">
          Reloads the player with this preferred track. If a title has no matching subtitle,
          use the player&apos;s CC menu to choose another available track.
        </p>
      </div>
    ),
  });

  panels.push({
    id: "servers",
    icon: "settings",
    label: "Servers",
    content: (
      <div className="flex flex-col gap-[2px]">
        {VIDSRC_MIRRORS.map((item) => (
          <button
            key={item.id}
            type="button"
            className={`flex cursor-pointer items-center gap-[10px] rounded-lg border-0 px-[10px] py-[9px] text-left transition ${mirror.id === item.id ? "bg-white/13 text-white" : "bg-transparent text-[#aaa59e] hover:bg-white/8 hover:text-white"}`}
            onClick={() => setMirror(item)}
          >
            <b className="text-[13px] font-semibold">{item.name}</b>
            <span className="text-[11px] text-[#86817b]">{item.region}</span>
            {mirror.id === item.id && <i className="ml-auto text-[#f5ad12] not-italic">✓</i>}
          </button>
        ))}
        <p className="mx-1 mt-3 mb-[2px] text-[11px] leading-[1.6] text-[#77726c]">
          {sourcePath} on {new URL(mirror.host).host}. If one server won&apos;t load, switch.
        </p>
      </div>
    ),
  });

  return (
    <main className="min-h-screen bg-[#040404] pb-[90px]">
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

      <section className="grid grid-cols-[minmax(0,1fr)_minmax(280px,340px)] gap-11 px-[max(26px,calc((100vw_-_1720px)/2))] pt-[46px] max-[1080px]:grid-cols-[minmax(0,1fr)] max-[1080px]:gap-[30px] max-[760px]:px-[18px]">
        <div>
          {notice && (
            <p className="mb-[14px] rounded-xl border border-[rgba(224,160,74,.32)] bg-[rgba(224,160,74,.1)] px-[15px] py-3 text-xs leading-[1.6] text-[#e5b878]" role="status">
              {notice}
            </p>
          )}
          <p className="text-xs font-bold tracking-[.06em] text-[#47c98d] uppercase">
            <span>Now watching</span>
          </p>
          <h1 className="my-[14px] mb-5 font-display text-[clamp(30px,3.1vw,50px)] leading-none font-extrabold tracking-[-.045em]">{detail.title}</h1>
          <div className="flex flex-wrap items-center gap-[10px]">
            {detail.score > 0 && <span className="text-[#47c98d]">★ {detail.score.toFixed(1)}</span>}
            {detail.year && <b className="rounded-md border border-white/18 px-[7px] py-1 text-[11px] text-[#d4d1cc]">{detail.year}</b>}
            {detail.runtime && <b className="rounded-md border border-white/18 px-[7px] py-1 text-[11px] text-[#d4d1cc]">{detail.runtime}</b>}
            {isSeries && (
              <b className="rounded-md border border-white/18 px-[7px] py-1 text-[11px] text-[#d4d1cc]">
                S{season} · E{episode}
              </b>
            )}
            <b className="rounded-md border border-white/18 px-[7px] py-1 text-[11px] text-[#d4d1cc]">{mirror.name}</b>
          </div>
          {detail.tagline && <p className="mb-[14px] text-[#d8d4ce] italic">“{detail.tagline}”</p>}
          <p className="m-0 max-w-[74ch] text-[15px] leading-[1.68] text-[#aaa6a0]">
            {detail.overview || "No synopsis available for this title."}
          </p>
          <div className="my-6 flex flex-wrap gap-2">
            {detail.genres.map((genre) => (
              <span className="rounded-[20px] border border-white/9 bg-[#181818] px-[11px] py-[7px] text-[11px] text-[#bbb7b0]" key={genre}>{genre}</span>
            ))}
          </div>
        </div>

        <aside className="flex flex-col pt-[30px] max-[1080px]:pt-0">
          <button className="w-full cursor-pointer rounded-xl border-0 bg-[#f2f0ec] px-[18px] py-[14px] font-extrabold text-[#111]" onClick={toggleSaved}>
            {saved ? "✓ Saved to my list" : "+ Add to my list"}
          </button>
          <div className="mt-7 border-t border-white/9 pt-[22px]">
            <b className="text-[13px]">Source</b>
            <p className="text-xs text-[#77736e]">
              {sourcePath} on {new URL(mirror.host).host}. Servers, subtitles and episodes are in the
              player&apos;s control bar.
            </p>
          </div>
          <div className="mt-7 border-t border-white/9 pt-[22px]">
            <b className="text-[13px]">Shortcuts</b>
            <p className="text-xs text-[#77736e] [&_kbd]:rounded-[5px] [&_kbd]:border [&_kbd]:border-white/13 [&_kbd]:bg-[#1d1d1c] [&_kbd]:px-[6px] [&_kbd]:py-[2px] [&_kbd]:font-sans [&_kbd]:text-[10px]">
              <kbd>F</kbd> fullscreen · <kbd>Space</kbd> play/pause · <kbd>←</kbd> <kbd>→</kbd> skip
              10s · <kbd>M</kbd> mute · <kbd>Esc</kbd> close a panel
            </p>
          </div>
        </aside>
      </section>

      {detail.recommendations.length > 0 && (
        <section className="mt-[62px] px-[max(26px,calc((100vw_-_1720px)/2))] max-[760px]:px-[18px]">
          <h2 className="font-display text-[21px] font-bold">Recommended next</h2>
          <div className="grid grid-cols-4 gap-[14px] max-[1080px]:grid-cols-2 max-[760px]:flex max-[760px]:overflow-x-auto">
            {detail.recommendations.map((item) => (
              <Link className="overflow-hidden rounded-[13px] bg-[#121212] max-[760px]:shrink-0 max-[760px]:basis-[72vw]" href={watchHref(item)} key={item.key}>
                {item.backdrop || item.poster ? (
                  <img className="block aspect-[1.65] w-full object-cover" src={item.backdrop ?? item.poster!} alt="" loading="lazy" />
                ) : (
                  <span className="flex aspect-[1.65] w-full items-center justify-center bg-[linear-gradient(140deg,#1d1d1d,#121212)]" />
                )}
                <span className="flex flex-col p-[11px]">
                  <b>{item.title}</b>
                  <small className="mt-1 text-[#77736e]">
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
