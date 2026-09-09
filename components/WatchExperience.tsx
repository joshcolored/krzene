"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { isKidsMedia, watchHref, type Media, type MediaDetail, type StreamingOffer } from "@/lib/media";
import { DEFAULT_MIRROR, PLAYBACK_SOURCES, embedUrl, type PlaybackSource } from "@/lib/playback";
import { usePlaybackBridge } from "@/lib/playback-bridge";
import { useAuth } from "./AuthProvider";
import { resolveAnimeEpisode } from "@/lib/anime-mappings";

type WatchMenu = "servers" | "episodes" | "subtitles";

type WatchTransitionOrigin = {
  left: number;
  top: number;
  width: number;
  height: number;
  viewportWidth: number;
  viewportHeight: number;
  createdAt: number;
};

const TOOL_BUTTON =
  "inline-flex min-h-10 cursor-pointer items-center justify-center gap-2 rounded-lg border border-white/12 bg-[#171717] px-3.5 text-xs font-bold text-[#d8d4ce] transition hover:border-white/25 hover:bg-[#232323] hover:text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#f5ad12]";

export function WatchExperience({
  detail,
  notice,
  streamingOffers = [],
}: {
  detail: MediaDetail;
  notice?: string;
  streamingOffers?: StreamingOffer[];
}) {
  const searchParams = useSearchParams();
  const requestedSeason = Number(searchParams.get("season"));
  const requestedEpisode = Number(searchParams.get("episode"));
  const resumeAt = Number(searchParams.get("t"));
  const initialSeason = detail.seasons.some((entry) => entry.number === requestedSeason)
    ? requestedSeason
    : detail.seasons[0]?.number ?? 1;
  const [mirror, setMirror] = useState<PlaybackSource>(DEFAULT_MIRROR);
  const [season, setSeason] = useState(initialSeason);
  const [episode, setEpisode] = useState(Number.isInteger(requestedEpisode) && requestedEpisode > 0 ? requestedEpisode : 1);
  const [openMenu, setOpenMenu] = useState<WatchMenu | null>(null);
  const [sourceNotice, setSourceNotice] = useState("");
  const [transitionOrigin, setTransitionOrigin] = useState<WatchTransitionOrigin | null>(null);
  const [transitionReady, setTransitionReady] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const frameRef = useRef<HTMLIFrameElement>(null);
  const mirrorRef = useRef(mirror);
  const attemptedSourcesRef = useRef(new Set<string>());
  const loadTimeoutRef = useRef<number | null>(null);
  const noticeTimeoutRef = useRef<number | null>(null);
  const { ready: authReady, user, activeProfile, library, toggleLibrary, saveWatchProgress } = useAuth();
  const saved = library.some((item) => item.key === detail.key);

  mirrorRef.current = mirror;

  useEffect(() => {
    let origin: WatchTransitionOrigin | null = null;
    try {
      const stored = sessionStorage.getItem("krzene:watch-transition");
      if (stored) {
        const parsed = JSON.parse(stored) as WatchTransitionOrigin;
        const valid =
          Number.isFinite(parsed.left) &&
          Number.isFinite(parsed.top) &&
          parsed.width > 0 &&
          parsed.viewportWidth > 0 &&
          Date.now() - parsed.createdAt < 60_000;
        if (valid) origin = parsed;
      }
    } catch {
      // A direct page entrance simply uses the normal fade.
    }
    setTransitionOrigin(origin);
    setTransitionReady(true);
  }, []);

  const isSeries = detail.kind === "tv";
  const seasons = detail.seasons;
  const activeSeason = seasons.find((entry) => entry.number === season) ?? seasons[0];
  const embedId = detail.tmdbId;
  const animeEpisode = resolveAnimeEpisode(detail.animeMappings ?? [], season, episode);

  const sourceUrl = useMemo(
    () =>
      embedUrl(detail.kind, embedId,
        mirror.provider === "zoryva" && animeEpisode ? 1 : isSeries ? season : null,
        mirror.provider === "zoryva" && animeEpisode ? animeEpisode.episode : isSeries ? episode : null, {
        host: mirror.host,
        provider: mirror.provider,
        anilistId: animeEpisode?.anilistId,
        autoplay: true,
        startAt: Number.isFinite(resumeAt) && resumeAt > 0 ? resumeAt : undefined,
      }),
    [detail.kind, animeEpisode?.anilistId, animeEpisode?.episode, embedId, episode, isSeries, mirror.host, mirror.provider, resumeAt, season],
  );
  // These providers use native player controls; no undocumented remote commands.
  const [playback, remote] = usePlaybackBridge(frameRef, sourceUrl, false);
  const resumeSent = useRef(false);
  const playbackRef = useRef(playback);
  playbackRef.current = playback;
  const progressBucket = Math.floor(playback.position / 10);

  const clearLoadTimeout = useCallback(() => {
    if (loadTimeoutRef.current == null) return;
    window.clearTimeout(loadTimeoutRef.current);
    loadTimeoutRef.current = null;
  }, []);

  const tryNextSource = useCallback((failedSourceId?: string) => {
    const current = mirrorRef.current;
    attemptedSourcesRef.current.add(failedSourceId ?? current.id);
    const currentIndex = PLAYBACK_SOURCES.findIndex((source) => source.id === current.id);
    const next = PLAYBACK_SOURCES.slice(currentIndex + 1).find(
      (source) => !attemptedSourcesRef.current.has(source.id),
    );

    clearLoadTimeout();
    if (!next) {
      setSourceNotice("No other playback source is available.");
      return;
    }

    setOpenMenu(null);
    setSourceNotice("Trying other sources...");
    setMirror(next);
  }, [clearLoadTimeout]);

  useEffect(() => {
    attemptedSourcesRef.current.clear();
    setSourceNotice("");
  }, [detail.key, episode, season]);

  useEffect(() => {
    clearLoadTimeout();
    loadTimeoutRef.current = window.setTimeout(() => {
      tryNextSource(mirrorRef.current.id);
    }, 20_000);
    return clearLoadTimeout;
  }, [clearLoadTimeout, sourceUrl, tryNextSource]);

  useEffect(() => {
    const onProviderMessage = (event: MessageEvent) => {
      const frame = frameRef.current;
      if (!frame?.contentWindow || event.source !== frame.contentWindow) return;

      let text = "";
      try {
        text = typeof event.data === "string" ? event.data : JSON.stringify(event.data);
      } catch {
        return;
      }

      if (!/(no (?:media|video|stream|source)|not found|unavailable|cannot be played|can't be played|playback error|error[_ -]loading|file not found)/i.test(text)) return;
      tryNextSource(mirrorRef.current.id);
    };

    window.addEventListener("message", onProviderMessage);
    return () => window.removeEventListener("message", onProviderMessage);
  }, [tryNextSource]);

  useEffect(() => () => {
    clearLoadTimeout();
    if (noticeTimeoutRef.current != null) window.clearTimeout(noticeTimeoutRef.current);
  }, [clearLoadTimeout]);

  const handleFrameLoad = () => {
    clearLoadTimeout();
    if (!sourceNotice) return;
    if (noticeTimeoutRef.current != null) window.clearTimeout(noticeTimeoutRef.current);
    noticeTimeoutRef.current = window.setTimeout(() => setSourceNotice(""), 3000);
  };

  useEffect(() => {
    if (resumeSent.current || !playback.connected || !Number.isFinite(resumeAt) || resumeAt < 5) return;
    resumeSent.current = true;
    remote.seekTo(resumeAt);
  }, [playback.connected, remote, resumeAt]);

  useEffect(() => {
    if (progressBucket < 1) return;
    const current = playbackRef.current;
    void saveWatchProgress(
      stripDetail(detail),
      current.position,
      current.duration,
      isSeries ? season : null,
      isSeries ? episode : null,
    );
  }, [detail, episode, isSeries, progressBucket, saveWatchProgress, season]);

  const sourcePath = (() => {
    try {
      const parsed = new URL(sourceUrl);
      return `${parsed.pathname}${parsed.search}`;
    } catch {
      return sourceUrl;
    }
  })();
  const runtime =
    playback.duration > 0
      ? `${clock(playback.position)} / ${clock(playback.duration)}`
      : detail.runtime || "Runtime unavailable";
  const endsAt =
    playback.duration > 0
      ? new Date(
          Date.now() + Math.max(playback.duration - playback.position, 0) * 1000,
        ).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
      : "";

  const chooseSeason = (nextSeason: number) => {
    setSeason(nextSeason);
    setEpisode(1);
  };

  const toggleMenu = (menu: WatchMenu) => {
    setOpenMenu((current) => (current === menu ? null : menu));
  };

  const returnToCatalog = useCallback(() => {
    if (leaving) return;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (!transitionOrigin || reduceMotion) {
      window.location.assign("/");
      return;
    }

    setLeaving(true);
    window.setTimeout(() => window.history.back(), 460);
  }, [leaving, transitionOrigin]);

  useEffect(() => {
    const onRemoteKey = (event: KeyboardEvent) => {
      const legacyCode = event.keyCode;
      const isTextControl = (event.target as HTMLElement | null)?.matches?.("input, textarea, select, [contenteditable='true']");
      if (isTextControl) return;

      if (event.key === "MediaPlayPause" || legacyCode === 10252) {
        event.preventDefault();
        playbackRef.current.playing ? remote.pause() : remote.play();
      } else if (event.key === "MediaPlay" || legacyCode === 415) {
        event.preventDefault();
        remote.play();
      } else if (event.key === "MediaPause" || legacyCode === 19 || legacyCode === 413) {
        event.preventDefault();
        remote.pause();
      } else if (event.key === "MediaRewind" || legacyCode === 412) {
        event.preventDefault();
        remote.seekBy(-10);
      } else if (event.key === "MediaFastForward" || legacyCode === 417) {
        event.preventDefault();
        remote.seekBy(10);
      } else if (event.key === "AudioVolumeMute") {
        event.preventDefault();
        remote.setMuted(!playbackRef.current.muted);
      } else if (event.key === "Escape") {
        if (openMenu) {
          event.preventDefault();
          setOpenMenu(null);
        }
      } else if (event.key === "BrowserBack" || event.key === "GoBack" || legacyCode === 10009 || legacyCode === 461) {
        event.preventDefault();
        if (openMenu) setOpenMenu(null);
        else returnToCatalog();
      }
    };

    window.addEventListener("keydown", onRemoteKey);
    return () => window.removeEventListener("keydown", onRemoteKey);
  }, [openMenu, remote, returnToCatalog]);

  if (!authReady) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#040404] text-white">
        <span className="h-9 w-9 animate-spin rounded-full border-2 border-white/20 border-t-[#f5ad12]" aria-label="Loading profile" />
      </main>
    );
  }

  if (activeProfile?.isKids && !isKidsMedia(detail)) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[radial-gradient(circle_at_50%_35%,#172522,#040404_62%)] px-5 text-center text-white">
        <section className="max-w-md rounded-3xl border border-white/10 bg-black/35 px-8 py-10 shadow-2xl backdrop-blur-xl">
          <span className="mb-5 inline-flex rounded-full bg-[#d9edf5] px-3 py-1 text-xs font-extrabold tracking-wider text-[#16242a]">KIDS PROFILE</span>
          <h1 className="font-display text-3xl font-extrabold">This title isn&apos;t available here</h1>
          <p className="mt-3 text-sm leading-relaxed text-[#aaa6a0]">Switch to a standard profile to watch it, or return to the kids catalog.</p>
          <Link href="/" className="mt-7 inline-flex min-h-12 items-center justify-center rounded-xl bg-white px-6 font-extrabold text-black">Back to Kids</Link>
        </section>
      </main>
    );
  }

  const transitionStyle = transitionOrigin
    ? ({
        "--watch-origin-x": `${transitionOrigin.left + transitionOrigin.width / 2 - transitionOrigin.viewportWidth / 2}px`,
        "--watch-origin-y": `${transitionOrigin.top}px`,
        "--watch-origin-scale": String(
          Math.min(Math.max(transitionOrigin.width / transitionOrigin.viewportWidth, 0.12), 0.62),
        ),
      } as React.CSSProperties)
    : undefined;

  return (
    <main
      className={`pwa-safe-bottom min-h-screen bg-[#040404] pb-[90px] text-white ${!transitionReady ? "opacity-0" : leaving ? "ui-watch-page-exit" : transitionOrigin ? "ui-watch-page-enter" : "ui-modal-enter"}`}
      style={transitionStyle}
    >
      <section className="pwa-watch-shell px-[max(26px,calc((100vw_-_1720px)/2))] pt-5">
        <header className="mb-4 flex min-w-0 items-center gap-3">
          <Link
            href="/"
            className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-[#171717] text-xl text-white transition hover:bg-[#292929] focus-visible:outline-2 focus-visible:outline-[#f5ad12]"
            aria-label="Back to browse"
            onClick={(event) => {
              event.preventDefault();
              returnToCatalog();
            }}
          >
            ‹
          </Link>
          <div className="min-w-0">
            <h1 className="truncate bg-[linear-gradient(180deg,#ffd463,#e79a08)] bg-clip-text font-display text-[clamp(20px,2.4vw,34px)] leading-none font-extrabold text-transparent uppercase">
              {detail.title}
            </h1>
            <p className="mt-1 text-[10px] font-bold tracking-[.18em] text-[#817c75] uppercase">
              {isSeries ? `Series · S${season} · E${episode}` : "Movie"}
            </p>
          </div>
        </header>

        <div className="relative aspect-video w-full overflow-hidden rounded-lg bg-black max-[760px]:rounded-md">
          <iframe
            key={sourceUrl}
            ref={frameRef}
            className="block h-full w-full border-0 bg-black"
            src={sourceUrl}
            title={`${detail.title} — ${mirror.name}`}
            allow="autoplay; fullscreen; picture-in-picture; encrypted-media"
            allowFullScreen
            referrerPolicy="origin"
            tabIndex={-1}
            onLoad={handleFrameLoad}
            onError={() => tryNextSource(mirror.id)}
          />
          {sourceNotice && (
            <div className="pointer-events-none absolute inset-x-0 top-3 z-10 flex justify-center px-3" role="status" aria-live="polite">
              <span className="rounded-full border border-white/15 bg-black/85 px-4 py-2 text-xs font-bold text-white shadow-xl backdrop-blur-md">
                {sourceNotice}
              </span>
            </div>
          )}
        </div>

        <div className="relative border-b border-white/10 py-3">
          <div className="flex items-center justify-between gap-3 max-[640px]:flex-col max-[640px]:items-stretch">
            <div className="flex min-w-0 items-center gap-3 pl-1 text-xs tabular-nums">
              <time className="shrink-0 font-semibold text-[#f2efea]">{runtime}</time>
              {endsAt && <span className="truncate text-[#8f8a83]">Ends at {endsAt}</span>}
            </div>

            <div className="flex shrink-0 flex-wrap justify-end gap-2 max-[640px]:justify-start">
              {isSeries && seasons.length > 0 && (
                <button
                  type="button"
                  className={`${TOOL_BUTTON} ${openMenu === "episodes" ? "border-white/30 bg-white/12 text-white" : ""}`}
                  onClick={() => toggleMenu("episodes")}
                  aria-expanded={openMenu === "episodes"}
                >
                  Episodes <span className="text-[#8f8a83]">S{season} E{episode}</span>
                </button>
              )}
              <button
                type="button"
                className={`${TOOL_BUTTON} ${openMenu === "subtitles" ? "border-white/30 bg-white/12 text-white" : ""}`}
                onClick={() => toggleMenu("subtitles")}
                aria-expanded={openMenu === "subtitles"}
              >
                Subtitles
              </button>
              <button
                type="button"
                className={`${TOOL_BUTTON} ${openMenu === "servers" ? "border-white/30 bg-white/12 text-white" : ""}`}
                onClick={() => toggleMenu("servers")}
                aria-expanded={openMenu === "servers"}
              >
                Servers <span className="text-[#8f8a83]">{mirror.name}</span>
              </button>
            </div>
          </div>

          {openMenu && (
            <div className="ui-menu-enter mt-3 ml-auto max-h-[min(52vh,430px)] w-[min(460px,100%)] origin-top-right overflow-auto rounded-xl border border-white/12 bg-[#111] p-3 shadow-[0_22px_60px_rgba(0,0,0,.55)]">
              {openMenu === "episodes" && isSeries && (
                <div>
                  <label className="mb-3 flex items-center gap-3">
                    <span className="text-[10px] font-bold tracking-[.12em] text-[#817c75] uppercase">Season</span>
                    <select
                      className="min-w-0 flex-1 cursor-pointer rounded-lg border border-white/10 bg-[#242321] px-3 py-2 text-xs font-semibold text-white outline-none"
                      value={season}
                      onChange={(event) => chooseSeason(Number(event.target.value))}
                    >
                      {seasons.map((entry) => (
                        <option key={entry.number} value={entry.number}>{entry.name}</option>
                      ))}
                    </select>
                  </label>
                  <div className="grid grid-cols-8 gap-1.5 max-[640px]:grid-cols-6">
                    {Array.from({ length: activeSeason?.episodeCount ?? 0 }, (_, index) => index + 1).map((number) => (
                      <button
                        key={number}
                        type="button"
                        className={`cursor-pointer rounded-lg border py-2 text-[11px] font-bold transition ${episode === number ? "border-[#f2f0ec] bg-[#f2f0ec] text-[#111]" : "border-white/8 bg-[#20201f] text-[#aaa59e] hover:bg-[#2b2a29] hover:text-white"}`}
                        onClick={() => {
                          setEpisode(number);
                          setOpenMenu(null);
                        }}
                      >
                        {number}
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {openMenu === "subtitles" && (
                <p className="p-2 text-sm text-[#aaa59e]">
                  Use {mirror.name}&apos;s settings inside the video to choose available subtitles.
                </p>
              )}

              {openMenu === "servers" && (
                <div className="flex flex-col gap-1">
                  {PLAYBACK_SOURCES.map((item) => (
                    <button
                      key={item.id}
                      type="button"
                      className={`flex cursor-pointer items-center gap-2 rounded-lg px-3 py-2.5 text-left transition ${mirror.id === item.id ? "bg-white/13 text-white" : "text-[#aaa59e] hover:bg-white/8 hover:text-white"}`}
                      onClick={() => {
                        attemptedSourcesRef.current.clear();
                        setSourceNotice("");
                        setMirror(item);
                        setOpenMenu(null);
                      }}
                    >
                      <b className="text-xs">{item.name}</b>
                      <span className="text-[11px] text-[#817c75]">{item.region}</span>
                      {mirror.id === item.id && <span className="ml-auto text-[#f5ad12]">✓</span>}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </section>

      <section className="grid grid-cols-[minmax(0,1fr)_minmax(280px,340px)] gap-11 px-[max(26px,calc((100vw_-_1720px)/2))] pt-[46px] max-[1080px]:grid-cols-1 max-[1080px]:gap-[30px] max-[760px]:px-[18px]">
        <div>
          {notice && (
            <p className="mb-[14px] rounded-xl border border-[rgba(224,160,74,.32)] bg-[rgba(224,160,74,.1)] px-[15px] py-3 text-xs leading-[1.6] text-[#e5b878]" role="status">
              {notice}
            </p>
          )}
          <p className="text-xs font-bold tracking-[.06em] text-[#47c98d] uppercase">Now watching</p>
          <h2 className="my-[14px] mb-5 font-display text-[clamp(30px,3.1vw,50px)] leading-none font-extrabold tracking-[-.045em]">{detail.title}</h2>
          <div className="flex flex-wrap items-center gap-[10px]">
            {detail.score > 0 && <span className="text-[#47c98d]">★ {detail.score.toFixed(1)}</span>}
            {detail.year && <b className="rounded-md border border-white/18 px-[7px] py-1 text-[11px] text-[#d4d1cc]">{detail.year}</b>}
            {detail.runtime && <b className="rounded-md border border-white/18 px-[7px] py-1 text-[11px] text-[#d4d1cc]">{detail.runtime}</b>}
            {isSeries && <b className="rounded-md border border-white/18 px-[7px] py-1 text-[11px] text-[#d4d1cc]">S{season} · E{episode}</b>}
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
          {user && activeProfile && (
            <button className="w-full cursor-pointer rounded-xl border-0 bg-[#f2f0ec] px-[18px] py-[14px] font-extrabold text-[#111]" onClick={() => void toggleLibrary(stripDetail(detail))}>
              {saved ? "✓ Saved to my list" : "+ Add to my list"}
            </button>
          )}
          <div className="mt-7 border-t border-white/9 pt-[22px]">
            <b className="text-[13px]">Source</b>
            <p className="text-xs leading-relaxed text-[#77736e]">
              {sourcePath} on {new URL(mirror.host).host}. {mirror.name}&apos;s native settings control subtitles and playback quality, including 1080p when the selected stream provides it.
            </p>
          </div>
          <div className="mt-5 border-t border-white/9 pt-[22px]">
            <b className="text-[13px]">TV remote</b>
            <p className="text-xs leading-relaxed text-[#77736e]">
              Use the D-pad to move, OK to select, Back to close, and your remote&apos;s media keys to play, pause, rewind, or fast-forward.
            </p>
          </div>
          {streamingOffers.length > 0 && (
            <div className="mt-5 border-t border-white/9 pt-[22px]">
              <div className="flex items-center justify-between gap-3">
                <b className="text-[13px]">Where to watch</b>
                <a href="https://www.watchmode.com/" target="_blank" rel="noopener noreferrer nofollow" className="text-[10px] font-bold tracking-[.1em] text-[#77736e] uppercase transition hover:text-white">Watchmode</a>
              </div>
              <p className="mt-1 text-xs leading-relaxed text-[#77736e]">Legal availability in {streamingOffers[0]?.region}.</p>
              <div className="mt-3 flex flex-col gap-2">
                {streamingOffers.map((offer) => (
                  <a
                    key={offer.id}
                    href={offer.url}
                    target="_blank"
                    rel="noopener noreferrer nofollow"
                    className="flex min-h-11 items-center gap-3 rounded-lg border border-white/9 bg-[#151515] px-3 text-xs transition hover:border-white/20 hover:bg-[#202020] focus-visible:outline-2 focus-visible:outline-[#f5ad12]"
                  >
                    <b className="min-w-0 flex-1 truncate text-[#eeeae4]">{offer.provider}</b>
                    {offer.format && <span className="text-[#8f8a83]">{offer.format}</span>}
                    <span className="rounded-full bg-white/8 px-2 py-1 text-[9px] font-extrabold tracking-[.08em] text-[#bdb8b0] uppercase">{offer.type}</span>
                    <span aria-hidden="true" className="text-[#f5ad12]">↗</span>
                  </a>
                ))}
              </div>
            </div>
          )}
        </aside>
      </section>

      {(activeProfile?.isKids ? detail.recommendations.filter(isKidsMedia) : detail.recommendations).length > 0 && (
        <section className="mt-[62px] px-[max(26px,calc((100vw_-_1720px)/2))] max-[760px]:px-[18px]">
          <h2 className="font-display text-[21px] font-bold">Recommended next</h2>
          <div className="grid grid-cols-4 gap-[14px] max-[1080px]:grid-cols-2 max-[760px]:flex max-[760px]:overflow-x-auto">
            {(activeProfile?.isKids ? detail.recommendations.filter(isKidsMedia) : detail.recommendations).map((item) => (
              <Link className="overflow-hidden rounded-[13px] bg-[#121212] max-[760px]:shrink-0 max-[760px]:basis-[72vw]" href={watchHref(item)} key={item.key}>
                {item.backdrop || item.poster ? (
                  <img className="block aspect-[1.65] w-full object-cover" src={item.backdrop ?? item.poster!} alt="" loading="lazy" />
                ) : (
                  <span className="flex aspect-[1.65] w-full items-center justify-center bg-[linear-gradient(140deg,#1d1d1d,#121212)]" />
                )}
                <span className="flex flex-col p-[11px]">
                  <b>{item.title}</b>
                  <small className="mt-1 text-[#77736e]">{item.year ?? "—"} • {item.genres[0] ?? (item.kind === "tv" ? "Series" : "Film")}</small>
                </span>
              </Link>
            ))}
          </div>
        </section>
      )}
    </main>
  );
}

function clock(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";
  const whole = Math.floor(seconds);
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  const secs = whole % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`
    : `${minutes}:${String(secs).padStart(2, "0")}`;
}

function stripDetail(detail: MediaDetail): Media {
  const { key, kind, tmdbId, title, year, overview, poster, backdrop, score, genres, accent } = detail;
  return { key, kind, tmdbId, title, year, overview, poster, backdrop, score, genres, accent };
}
