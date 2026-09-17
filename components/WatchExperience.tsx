"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { isKidsMedia, watchHref, type EpisodeSummary, type Media, type MediaDetail, type StreamingOffer } from "@/lib/media";
import { DEFAULT_MIRROR, PLAYBACK_SOURCES, embedUrl, type PlaybackSource } from "@/lib/playback";
import { usePlaybackBridge } from "@/lib/playback-bridge";
import {
  parseSubtitle,
  readBrowserSubtitle,
  subtitleStorageKey,
  subtitleTextAt,
  writeBrowserSubtitle,
  type BrowserSubtitle,
} from "@/lib/browser-subtitles";
import { useAuth } from "./AuthProvider";
import { resolveAnimeEpisode } from "@/lib/anime-mappings";

type WatchMenu = "servers" | "settings";

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

const DEFAULT_SUBTITLE_STYLE: BrowserSubtitle = {
  name: "Subtitle preview",
  source: "",
  enabled: true,
  offset: 0,
  speed: 1,
  fontSize: 22,
  background: 0.68,
  backgroundColor: "#000000",
  color: "#ffffff",
};

function FullscreenMenuPortal({
  active,
  container,
  children,
}: {
  active: boolean;
  container: HTMLElement | null;
  children: ReactNode;
}) {
  return active && container ? createPortal(children, container) : children;
}

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
  const [resumePosition, setResumePosition] = useState(Number.isFinite(resumeAt) && resumeAt > 0 ? resumeAt : 0);
  const [episodes, setEpisodes] = useState<EpisodeSummary[]>([]);
  const [episodesLoading, setEpisodesLoading] = useState(false);
  const [openMenu, setOpenMenu] = useState<WatchMenu | null>(null);
  const [quality, setQuality] = useState<string | null>(null);
  const [controlsVisible, setControlsVisible] = useState(true);
  const [scrubPosition, setScrubPosition] = useState<number | null>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [subtitle, setSubtitle] = useState<BrowserSubtitle | null>(null);
  const [subtitleNotice, setSubtitleNotice] = useState("");
  const [findingSubtitle, setFindingSubtitle] = useState(false);
  const [sourceNotice, setSourceNotice] = useState("");
  const [transitionOrigin, setTransitionOrigin] = useState<WatchTransitionOrigin | null>(null);
  const [transitionReady, setTransitionReady] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const frameRef = useRef<HTMLIFrameElement>(null);
  const playerShellRef = useRef<HTMLDivElement>(null);
  const subtitleInputRef = useRef<HTMLInputElement>(null);
  const controlsTimeoutRef = useRef<number | null>(null);
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
        startAt: resumePosition > 0 ? resumePosition : undefined,
        customControls: mirror.provider === "cinesrc",
        quality,
      }),
    [detail.kind, animeEpisode?.anilistId, animeEpisode?.episode, embedId, episode, isSeries, mirror.host, mirror.provider, quality, resumePosition, season],
  );
  const customPlayer = mirror.provider === "cinesrc";
  const [playback, remote] = usePlaybackBridge(frameRef, sourceUrl, customPlayer);
  const resumeSent = useRef(false);
  const playbackRef = useRef(playback);
  playbackRef.current = playback;
  const progressBucket = Math.floor(playback.position / 10);
  const subtitleKey = subtitleStorageKey(
    detail.key,
    isSeries ? season : 0,
    isSeries ? episode : 0,
  );
  const subtitleCues = useMemo(() => {
    if (!subtitle) return [];
    try {
      return parseSubtitle(subtitle.source);
    } catch {
      return [];
    }
  }, [subtitle]);
  const shownPosition = scrubPosition ?? playback.position;
  const subtitleStyle = subtitle ?? DEFAULT_SUBTITLE_STYLE;
  const visibleSubtitle =
    subtitle?.enabled && subtitleCues.length
      ? subtitleTextAt(
          subtitleCues,
          shownPosition,
          subtitle.offset,
          subtitle.speed,
        )
      : null;

  const commitSubtitle = useCallback(
    (next: BrowserSubtitle | null) => {
      setSubtitle(next);
      try {
        writeBrowserSubtitle(subtitleKey, next);
      } catch {
        setSubtitleNotice("The subtitle works now, but this browser could not save it locally.");
      }
    },
    [subtitleKey],
  );

  useEffect(() => {
    setSubtitle(readBrowserSubtitle(subtitleKey));
    setSubtitleNotice("");
  }, [subtitleKey]);

  useEffect(() => {
    const onFullscreen = () =>
      setIsFullscreen(document.fullscreenElement === playerShellRef.current);
    document.addEventListener("fullscreenchange", onFullscreen);
    return () => document.removeEventListener("fullscreenchange", onFullscreen);
  }, []);

  const revealControls = useCallback(() => {
    setControlsVisible(true);
    if (controlsTimeoutRef.current != null) {
      window.clearTimeout(controlsTimeoutRef.current);
    }
    controlsTimeoutRef.current = window.setTimeout(() => {
      if (playbackRef.current.playing && !playbackRef.current.buffering) {
        setControlsVisible(false);
      }
    }, 3500);
  }, []);

  useEffect(() => {
    if (!customPlayer || !playback.playing || playback.buffering) {
      setControlsVisible(true);
      return;
    }
    revealControls();
  }, [customPlayer, playback.buffering, playback.playing, revealControls]);

  useEffect(
    () => () => {
      if (controlsTimeoutRef.current != null) {
        window.clearTimeout(controlsTimeoutRef.current);
      }
    },
    [],
  );

  const handleSubtitleFile = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    try {
      const source = await file.text();
      const cues = parseSubtitle(source);
      commitSubtitle({
        name: file.name,
        source,
        enabled: true,
        offset: 0,
        speed: 1,
        fontSize: 22,
        background: 0.68,
        backgroundColor: "#000000",
        color: "#ffffff",
      });
      setSubtitleNotice(`${file.name} loaded with ${cues.length} cues.`);
    } catch (error) {
      setSubtitleNotice(
        error instanceof Error ? error.message : "That subtitle file could not be read.",
      );
    }
  };

  const findSubtitleAutomatically = async () => {
    if (findingSubtitle) return;
    setFindingSubtitle(true);
    setSubtitleNotice("");
    const query = new URLSearchParams({
      type: isSeries ? "tv" : "movie",
      id: String(detail.tmdbId),
      lang: navigator.language.split(/[-_]/)[0] || "en",
    });
    if (isSeries) {
      query.set("season", String(season));
      query.set("episode", String(episode));
    }
    try {
      const response = await fetch(`/api/subtitles?${query}`);
      const payload = (await response.json()) as {
        content?: string;
        name?: string;
        error?: string;
      };
      if (!response.ok || !payload.content) {
        throw new Error(payload.error || "No automatic subtitle was found.");
      }
      const cues = parseSubtitle(payload.content);
      commitSubtitle({
        name: payload.name || `${detail.title}.srt`,
        source: payload.content,
        enabled: true,
        offset: 0,
        speed: 1,
        fontSize: 22,
        background: 0.68,
        backgroundColor: "#000000",
        color: "#ffffff",
      });
      setSubtitleNotice(`Subtitle loaded with ${cues.length} cues.`);
    } catch (error) {
      setSubtitleNotice(
        error instanceof Error ? error.message : "Automatic subtitle search failed.",
      );
    } finally {
      setFindingSubtitle(false);
    }
  };

  const subtitleCatUrl = `https://www.subtitlecat.com/index.php?${new URLSearchParams({
    search: [
      detail.title,
      detail.year || "",
      isSeries ? `S${String(season).padStart(2, "0")}` : "",
      isSeries ? `E${String(episode).padStart(2, "0")}` : "",
    ]
      .filter(Boolean)
      .join(" "),
  })}`;

  const updateSubtitle = (changes: Partial<BrowserSubtitle>) => {
    if (!subtitle) return;
    commitSubtitle({ ...subtitle, ...changes });
  };

  const changeQuality = (next: string | null) => {
    if (next === quality) return;
    setResumePosition(playback.position);
    resumeSent.current = false;
    setQuality(next);
  };

  const toggleFullscreen = async () => {
    if (!playerShellRef.current) return;
    if (document.fullscreenElement) await document.exitFullscreen();
    else await playerShellRef.current.requestFullscreen();
  };

  useEffect(() => {
    if (!isSeries) return;
    let cancelled = false;
    setEpisodesLoading(true);
    fetch(`/api/title/tv/${detail.tmdbId}/season/${season}`)
      .then((response) => response.ok ? response.json() : Promise.reject())
      .then((payload) => { if (!cancelled) setEpisodes(payload.episodes ?? []); })
      .catch(() => { if (!cancelled) setEpisodes([]); })
      .finally(() => { if (!cancelled) setEpisodesLoading(false); });
    return () => { cancelled = true; };
  }, [detail.tmdbId, isSeries, season]);

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
    if (resumeSent.current || !playback.connected || resumePosition < 5) return;
    resumeSent.current = true;
    remote.seekTo(resumePosition);
  }, [playback.connected, remote, resumePosition]);

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

  const selectEpisode = (nextSeason: number, nextEpisode: number) => {
    setSeason(nextSeason);
    setEpisode(nextEpisode);
    setResumePosition(0);
    resumeSent.current = false;
    const url = new URL(window.location.href);
    url.searchParams.set("season", String(nextSeason));
    url.searchParams.set("episode", String(nextEpisode));
    url.searchParams.delete("t");
    window.history.replaceState(window.history.state, "", url);
    void saveWatchProgress(stripDetail(detail), 0, 0, nextSeason, nextEpisode);
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

        <div
          ref={playerShellRef}
          className="group relative aspect-video w-full overflow-hidden rounded-lg bg-black max-[760px]:rounded-md"
          onMouseMove={customPlayer ? revealControls : undefined}
          onPointerDown={customPlayer ? revealControls : undefined}
        >
          <iframe
            key={sourceUrl}
            ref={frameRef}
            className={`block h-full w-full border-0 bg-black ${customPlayer ? "pointer-events-none" : ""}`}
            src={sourceUrl}
            title={`${detail.title} — ${mirror.name}`}
            allow="autoplay; fullscreen; picture-in-picture; encrypted-media"
            allowFullScreen
            referrerPolicy="origin"
            tabIndex={-1}
            onLoad={handleFrameLoad}
            onError={() => tryNextSource(mirror.id)}
          />
          {customPlayer && (
            <div
              className="absolute inset-0 z-[2] select-none"
              onClick={revealControls}
              onDoubleClick={(event) => {
                const bounds = event.currentTarget.getBoundingClientRect();
                remote.seekBy(event.clientX - bounds.left < bounds.width / 2 ? -10 : 10);
                revealControls();
              }}
            >
              <div
                className={`pointer-events-none absolute inset-0 bg-[linear-gradient(180deg,rgba(0,0,0,.72),transparent_36%,rgba(0,0,0,.86))] transition-opacity duration-200 ${controlsVisible ? "opacity-100" : "opacity-0"}`}
              />
              <div
                className={`pointer-events-none absolute inset-x-0 top-0 flex items-center justify-between p-4 transition-opacity duration-200 ${controlsVisible ? "opacity-100" : "opacity-0"}`}
              >
                <div className="min-w-0">
                  <b className="block truncate text-sm drop-shadow-lg">{detail.title}</b>
                  <small className="text-white/60">
                    {isSeries ? `S${season} · E${episode}` : "Movie"}
                  </small>
                </div>
                <span className="rounded-full bg-[#e21927] px-2.5 py-1 text-[10px] font-black tracking-wider uppercase">
                  Krzene
                </span>
              </div>

              <div className="pointer-events-none absolute inset-0 grid place-items-center">
                {(!playback.connected || playback.buffering) && (
                  <span
                    className="h-12 w-12 animate-spin rounded-full border-[3px] border-white/25 border-t-[#e21927]"
                    aria-label="Buffering"
                  />
                )}
                {playback.connected && !playback.buffering && controlsVisible && (
                  <div className="pointer-events-auto flex items-center gap-5 max-[640px]:gap-3" onClick={(event) => event.stopPropagation()}>
                    <button
                      type="button"
                      className="grid h-12 w-12 cursor-pointer place-items-center rounded-full bg-black/55 text-sm font-black backdrop-blur-md transition hover:scale-105 hover:bg-black/75"
                      onClick={() => remote.seekBy(-10)}
                      aria-label="Rewind 10 seconds"
                    >
                      ↶10
                    </button>
                    <button
                      type="button"
                      className="grid h-16 w-16 cursor-pointer place-items-center rounded-full bg-white text-3xl text-black shadow-2xl transition hover:scale-105"
                      onClick={() => (playback.playing ? remote.pause() : remote.play())}
                      aria-label={playback.playing ? "Pause" : "Play"}
                    >
                      {playback.playing ? "Ⅱ" : "▶"}
                    </button>
                    <button
                      type="button"
                      className="grid h-12 w-12 cursor-pointer place-items-center rounded-full bg-black/55 text-sm font-black backdrop-blur-md transition hover:scale-105 hover:bg-black/75"
                      onClick={() => remote.seekBy(10)}
                      aria-label="Forward 10 seconds"
                    >
                      10↷
                    </button>
                  </div>
                )}
              </div>

              {visibleSubtitle && (
                <div
                  className="pointer-events-none absolute inset-x-[8%] bottom-[19%] z-[3] text-center font-semibold whitespace-pre-line text-shadow-lg"
                  style={{
                    color: subtitle?.color,
                    fontSize: `clamp(14px, ${subtitle?.fontSize ?? 22}px, 3.2vw)`,
                  }}
                >
                  <span
                    className="box-decoration-clone rounded-md px-2 py-1 leading-[1.45]"
                    style={{
                      backgroundColor: hexWithOpacity(
                        subtitle?.backgroundColor ?? "#000000",
                        subtitle?.background ?? 0.68,
                      ),
                    }}
                  >
                    {visibleSubtitle}
                  </span>
                </div>
              )}

              <div
                className={`pointer-events-auto absolute inset-x-0 bottom-0 p-4 transition-opacity duration-200 ${controlsVisible ? "opacity-100" : "pointer-events-none opacity-0"}`}
                onClick={(event) => event.stopPropagation()}
              >
                <input
                  aria-label="Playback position"
                  className="block h-1.5 w-full cursor-pointer accent-[#e21927]"
                  type="range"
                  min={0}
                  max={Math.max(playback.duration, 1)}
                  step="0.1"
                  value={Math.min(shownPosition, Math.max(playback.duration, 1))}
                  onChange={(event) => setScrubPosition(Number(event.target.value))}
                  onPointerUp={(event) => {
                    remote.seekTo(Number(event.currentTarget.value));
                    setScrubPosition(null);
                  }}
                  onKeyUp={(event) => {
                    remote.seekTo(Number(event.currentTarget.value));
                    setScrubPosition(null);
                  }}
                />
                <div className="mt-2 flex items-center gap-2 text-xs tabular-nums">
                  <time>{clock(shownPosition)}</time>
                  <span className="text-white/45">/ {clock(playback.duration)}</span>
                  <button
                    type="button"
                    className="ml-2 cursor-pointer rounded-lg px-2 py-1 text-base hover:bg-white/12"
                    onClick={() => remote.setMuted(!playback.muted)}
                    aria-label={playback.muted ? "Unmute" : "Mute"}
                  >
                    {playback.muted ? "🔇" : "🔊"}
                  </button>
                  <button
                    type="button"
                    className="ml-auto cursor-pointer rounded-lg px-2 py-1 font-bold hover:bg-white/12"
                    onClick={() => toggleMenu("settings")}
                  >
                    Settings
                  </button>
                  <button
                    type="button"
                    className="cursor-pointer rounded-lg px-2 py-1 text-base hover:bg-white/12"
                    onClick={() => void toggleFullscreen()}
                    aria-label={isFullscreen ? "Exit fullscreen" : "Fullscreen"}
                  >
                    {isFullscreen ? "↙" : "⛶"}
                  </button>
                </div>
              </div>
            </div>
          )}
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
              {customPlayer && (
                <button
                  type="button"
                  className={`${TOOL_BUTTON} ${openMenu === "settings" ? "border-[#e21927] bg-[#e21927]/15 text-white" : ""}`}
                  onClick={() => toggleMenu("settings")}
                  aria-expanded={openMenu === "settings"}
                >
                  Playback settings
                </button>
              )}
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
            <FullscreenMenuPortal
              active={isFullscreen}
              container={playerShellRef.current}
            >
            <div
              className={`ui-menu-enter origin-top-right overflow-auto rounded-2xl border border-[#e21927]/45 bg-[#0d0d0f] p-4 shadow-[0_22px_60px_rgba(0,0,0,.65)] ${
                isFullscreen
                  ? "absolute right-4 bottom-16 z-30 max-h-[calc(100%-5rem)] w-[min(560px,calc(100%-2rem))]"
                  : "mt-3 ml-auto max-h-[min(72vh,680px)] w-[min(560px,100%)]"
              }`}
              onClick={(event) => event.stopPropagation()}
            >
              {openMenu === "settings" && (
                <div className="space-y-6">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <p className="text-[10px] font-black tracking-[.15em] text-[#e21927] uppercase">Krzene player</p>
                      <h3 className="mt-1 text-xl font-black">Playback settings</h3>
                    </div>
                    <button
                      type="button"
                      className="grid h-9 w-9 shrink-0 cursor-pointer place-items-center rounded-full bg-white/8 text-lg hover:bg-white/15"
                      onClick={() => setOpenMenu(null)}
                      aria-label="Close playback settings"
                    >
                      ×
                    </button>
                  </div>

                  <fieldset>
                    <legend className="mb-2 text-xs font-bold text-[#aaa59e]">Speed</legend>
                    <div className="flex flex-wrap gap-2">
                      {[0.5, 0.75, 1, 1.25, 1.5, 2].map((rate) => (
                        <button
                          key={rate}
                          type="button"
                          className={`cursor-pointer rounded-full border px-3 py-2 text-xs font-bold ${playback.playbackRate === rate ? "border-[#e21927] bg-[#e21927] text-white" : "border-white/12 bg-[#171719] text-[#bbb]"}`}
                          onClick={() => remote.setPlaybackRate(rate)}
                        >
                          {rate === 1 ? "Normal" : `${rate}x`}
                        </button>
                      ))}
                    </div>
                  </fieldset>

                  <fieldset>
                    <legend className="mb-2 text-xs font-bold text-[#aaa59e]">Preferred quality</legend>
                    <div className="flex flex-wrap gap-2">
                      {[null, "1080", "720", "480"].map((option) => (
                        <button
                          key={option ?? "auto"}
                          type="button"
                          className={`cursor-pointer rounded-full border px-3 py-2 text-xs font-bold ${quality === option ? "border-[#e21927] bg-[#e21927] text-white" : "border-white/12 bg-[#171719] text-[#bbb]"}`}
                          onClick={() => changeQuality(option)}
                        >
                          {option ? `${option}p` : "Auto"}
                        </button>
                      ))}
                    </div>
                  </fieldset>

                  <label className="block text-xs font-bold text-[#aaa59e]">
                    <span className="mb-2 flex justify-between"><span>Volume</span><span>{Math.round(playback.volume * 100)}%</span></span>
                    <input
                      className="w-full cursor-pointer accent-[#e21927]"
                      type="range"
                      min={0}
                      max={1}
                      step={0.05}
                      value={playback.volume}
                      onChange={(event) => remote.setVolume(Number(event.target.value))}
                    />
                  </label>
                  <p className="-mt-4 text-[11px] leading-relaxed text-white/35">
                    Web embeds are limited by browser security to 100%. The mobile app can apply Krzene&apos;s 300% Web Audio gain when the stream permits it.
                  </p>

                  <div className="rounded-2xl border border-white/10 bg-[#161618] p-4">
                    <div className="flex items-start gap-3">
                      <span className="text-xl text-[#e21927]">CC</span>
                      <div className="min-w-0 flex-1">
                        <b className="block">Krzene subtitles</b>
                        <small className="block truncate text-white/45">{subtitle?.name || "No external subtitle loaded"}</small>
                      </div>
                      <input
                        type="checkbox"
                        className="h-5 w-5 accent-[#e21927]"
                        checked={subtitle?.enabled === true}
                        disabled={!subtitle}
                        onChange={(event) => updateSubtitle({ enabled: event.target.checked })}
                        aria-label="Show imported subtitles"
                      />
                    </div>
                    <p className="mt-2 text-center text-[11px] text-white/35">Stored only in this browser</p>
                    <div className="mt-3 grid grid-cols-2 gap-2 max-[520px]:grid-cols-1">
                      <button
                        type="button"
                        className="min-h-11 cursor-pointer rounded-xl bg-[#e21927] px-3 text-sm font-bold text-white disabled:opacity-50"
                        disabled={findingSubtitle}
                        onClick={() => void findSubtitleAutomatically()}
                      >
                        {findingSubtitle ? "Finding…" : "Auto find (free)"}
                      </button>
                      <button
                        type="button"
                        className="min-h-11 cursor-pointer rounded-xl border border-white/15 px-3 text-sm font-bold"
                        onClick={() => subtitleInputRef.current?.click()}
                      >
                        Choose subtitle file
                      </button>
                    </div>
                    <input
                      ref={subtitleInputRef}
                      className="hidden"
                      type="file"
                      accept=".srt,.vtt,application/x-subrip,text/vtt,text/plain"
                      onChange={(event) => void handleSubtitleFile(event)}
                    />
                    <a
                      href={subtitleCatUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="mt-3 flex min-h-10 items-center justify-between rounded-lg px-2 text-sm text-[#ddd] hover:bg-white/5"
                    >
                      <span><b>Find on Subtitle Cat</b><small className="block text-white/40">Download an SRT, then choose it here</small></span>
                      <span>↗</span>
                    </a>
                    <p className="mt-2 text-[11px] leading-relaxed text-white/35">OpenSubtitles developer consumers can allow up to 100 test downloads per day. No VIP plan is required.</p>
                    {subtitleNotice && <p className="mt-3 rounded-lg bg-black/35 p-2 text-xs text-[#ddd]" role="status">{subtitleNotice}</p>}

                    <div className="mt-5 border-t border-white/8 pt-4">
                      <b className="text-sm">Subtitle customization</b>
                      {!subtitle && <p className="mt-1 text-[11px] text-white/35">Choose or auto-find a subtitle to activate these controls.</p>}
                      <fieldset disabled={!subtitle} className={`mt-4 space-y-4 ${subtitle ? "" : "opacity-40"}`}>
                        <label className="block text-xs text-[#aaa59e]">
                          <span className="mb-1 flex justify-between"><b>Subtitle timing</b><span>{subtitleStyle.offset >= 0 ? "+" : ""}{subtitleStyle.offset.toFixed(1)}s</span></span>
                          <input className="w-full accent-[#e21927]" type="range" min={-10} max={10} step={0.5} value={subtitleStyle.offset} onChange={(event) => updateSubtitle({ offset: Number(event.target.value) })} />
                        </label>
                        <label className="block text-xs text-[#aaa59e]">
                          <span className="mb-1 flex justify-between"><b>Subtitle speed</b><span>{subtitleStyle.speed.toFixed(2)}x</span></span>
                          <input className="w-full accent-[#e21927]" type="range" min={0.8} max={1.2} step={0.025} value={subtitleStyle.speed} onChange={(event) => updateSubtitle({ speed: Number(event.target.value) })} />
                        </label>
                        <label className="block text-xs text-[#aaa59e]">
                          <span className="mb-1 flex justify-between"><b>Text size</b><span>{subtitleStyle.fontSize}px</span></span>
                          <input className="w-full accent-[#e21927]" type="range" min={14} max={34} step={2} value={subtitleStyle.fontSize} onChange={(event) => updateSubtitle({ fontSize: Number(event.target.value) })} />
                        </label>
                        <label className="block text-xs text-[#aaa59e]">
                          <span className="mb-1 flex justify-between"><b>Background opacity</b><span>{Math.round(subtitleStyle.background * 100)}%</span></span>
                          <input className="w-full accent-[#e21927]" type="range" min={0} max={1} step={0.1} value={subtitleStyle.background} onChange={(event) => updateSubtitle({ background: Number(event.target.value) })} />
                        </label>
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="mr-1 text-xs font-bold text-[#aaa59e]">Background color</span>
                          {["#000000", "#5b0b13", "#10243c"].map((backgroundColor) => (
                            <button key={backgroundColor} type="button" className={`h-8 w-8 cursor-pointer rounded-full border-2 ${subtitleStyle.backgroundColor === backgroundColor ? "border-[#e21927]" : "border-white/15"}`} style={{ background: backgroundColor }} onClick={() => updateSubtitle({ backgroundColor })} aria-label={`Use ${backgroundColor} subtitle background`} />
                          ))}
                        </div>
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="mr-1 text-xs font-bold text-[#aaa59e]">Text color</span>
                          {["#ffffff", "#ffdf45", "#47c98d"].map((color) => (
                            <button key={color} type="button" className={`h-8 w-8 cursor-pointer rounded-full border-2 ${subtitleStyle.color === color ? "border-[#e21927]" : "border-white/15"}`} style={{ background: color }} onClick={() => updateSubtitle({ color })} aria-label={`Use ${color} subtitles`} />
                          ))}
                          {subtitle && <button type="button" className="ml-auto cursor-pointer text-xs font-bold text-[#e21927]" onClick={() => commitSubtitle(null)}>Remove subtitle</button>}
                        </div>
                      </fieldset>
                    </div>
                  </div>
                </div>
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
            </FullscreenMenuPortal>
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
          <div className="border-t border-white/9 pt-[22px]">
            <b className="text-[13px]">Source</b>
            <p className="text-xs leading-relaxed text-[#77736e]">
              {sourcePath} on {new URL(mirror.host).host}. {customPlayer
                ? "Krzene controls playback, quality, and locally stored subtitles."
                : `${mirror.name}'s native player controls playback for this fallback source.`}
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

      {isSeries && seasons.length > 0 && (
        <section className="mt-12 px-[max(26px,calc((100vw_-_1720px)/2))] max-[760px]:px-[18px]">
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <h2 className="font-display text-[clamp(26px,3vw,42px)] font-extrabold">Episodes</h2>
              <p className="mt-1 text-sm text-[#817c75]">{activeSeason?.name ?? `Season ${season}`} · {activeSeason?.episodeCount ?? episodes.length} episodes</p>
            </div>
            <div className="flex max-w-full gap-2 overflow-x-auto pb-1">
              {seasons.map((entry) => (
                <button key={entry.number} type="button" onClick={() => selectEpisode(entry.number, 1)} className={`shrink-0 rounded-full px-5 py-3 text-sm font-bold transition ${entry.number === season ? "bg-white text-black" : "bg-[#141414] text-[#aaa6a0] hover:bg-[#222] hover:text-white"}`}>{entry.name}</button>
              ))}
            </div>
          </div>
          {episodesLoading ? <div className="mt-7 h-36 animate-pulse rounded-2xl bg-white/5" /> : (
            <div className="mt-7 grid grid-cols-2 gap-4 max-[760px]:grid-cols-1">
              {episodes.map((item) => (
                <button key={item.id} type="button" onClick={() => selectEpisode(item.seasonNumber, item.episodeNumber)} className={`group overflow-hidden rounded-2xl border text-left transition ${episode === item.episodeNumber ? "border-[#f5ad12] bg-[#1b1811]" : "border-white/8 bg-[#151515] hover:border-white/20"}`}>
                  <span className="relative block aspect-[1.9] overflow-hidden bg-[#202020]">
                    {item.still && <img src={item.still} alt="" loading="lazy" className="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]" />}
                    <b className="absolute top-3 left-3 rounded-full bg-black/75 px-3 py-1.5 text-xs">S{item.seasonNumber} E{item.episodeNumber}</b>
                    {episode === item.episodeNumber && <span className="absolute inset-0 grid place-items-center bg-black/25 text-4xl" aria-hidden="true">▶</span>}
                  </span>
                  <span className="block p-4"><b className="text-base">{item.name}</b><small className="mt-1 block text-[#817c75]">{item.airDate ?? "Air date unavailable"}{item.runtime ? ` · ${item.runtime}m` : ""}</small>{item.overview && <span className="mt-3 block line-clamp-3 text-sm leading-relaxed text-[#aaa6a0]">{item.overview}</span>}</span>
                </button>
              ))}
            </div>
          )}
        </section>
      )}

      {user && activeProfile && (
        <section className="mt-10 px-[max(26px,calc((100vw_-_1720px)/2))] max-[760px]:px-[18px]">
          <button
            className="w-full cursor-pointer rounded-xl border-0 bg-[#f2f0ec] px-[18px] py-[14px] font-extrabold text-[#111] transition hover:bg-white"
            onClick={() => void toggleLibrary(stripDetail(detail))}
          >
            {saved ? "✓ Saved to my list" : "+ Add to my list"}
          </button>
        </section>
      )}

      {detail.cast.length > 0 && (
        <section className="mt-14 px-[max(26px,calc((100vw_-_1720px)/2))] max-[760px]:px-[18px]">
          <h2 className="font-display text-[clamp(24px,2.5vw,36px)] font-extrabold">Cast</h2>
          <div className="mt-6 grid grid-cols-6 gap-5 max-[1080px]:grid-cols-4 max-[640px]:grid-cols-3">
            {detail.cast.map((person) => <div key={person.id} className="min-w-0 text-center">{person.profile ? <img src={person.profile} alt="" loading="lazy" className="mx-auto aspect-square w-full max-w-40 rounded-full border border-white/10 object-cover" /> : <div className="mx-auto grid aspect-square w-full max-w-40 place-items-center rounded-full bg-[#1c1c1c] text-3xl text-[#777]">{person.name.slice(0, 1)}</div>}<b className="mt-3 block truncate text-sm">{person.name}</b><small className="mt-1 block truncate text-[#817c75]">{person.character}</small></div>)}
          </div>
        </section>
      )}

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

function hexWithOpacity(hex: string, opacity: number): string {
  const match = /^#([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i.exec(hex);
  if (!match) return `rgba(0,0,0,${opacity})`;
  return `rgba(${Number.parseInt(match[1], 16)},${Number.parseInt(match[2], 16)},${Number.parseInt(match[3], 16)},${Math.max(0, Math.min(1, opacity))})`;
}

function stripDetail(detail: MediaDetail): Media {
  const { key, kind, tmdbId, title, year, overview, poster, backdrop, score, genres, accent } = detail;
  return { key, kind, tmdbId, title, year, overview, poster, backdrop, score, genres, accent };
}
