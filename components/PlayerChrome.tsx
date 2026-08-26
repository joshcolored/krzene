"use client";

/**
 * The Krzene player chrome.
 *
 * Two source kinds share one set of controls:
 *
 *   native — a direct video file. Everything is live off the <video> element.
 *
 *   embed  — a provider iframe (VidSrc). The frame is cross-origin, but its
 *            nested layers relay postMessages both ways, so playback can be
 *            both read and driven: see lib/vidsrc-bridge.ts. Once that bridge
 *            connects, the transport here is real — scrub, play/pause, ±10s,
 *            mute, elapsed/duration, "ends at" — and the provider's own title
 *            strip and control bar are sealed off as duplicates: pointer events
 *            no longer reach the frame (so its chrome cannot be woken) and the
 *            band it draws on load is masked until it auto-hides.
 *            A mirror without the relay never connects; the transport then
 *            degrades to an inert rule and the provider keeps its own chrome,
 *            which is the only thing the viewer could use.
 *
 * Fullscreen is owned by this component in BOTH modes: it requests fullscreen
 * on the page root, so the chrome comes along and the button works even when
 * the provider's own fullscreen button is blocked inside its nested frame.
 */

import Link from "next/link";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from "react";
import { useVidSrcBridge } from "@/lib/vidsrc-bridge";

const CHROME_BUTTON = "chrome-button inline-flex h-[38px] min-w-[38px] shrink-0 cursor-pointer items-center justify-center rounded-[10px] border-0 bg-transparent p-0 text-[#cbc7c1] transition hover:bg-white/14 hover:text-white disabled:cursor-default disabled:opacity-30 disabled:hover:bg-transparent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#f5ad12] [&_svg]:h-[21px] [&_svg]:w-[21px]";
const ROUND_CHROME_BUTTON = `${CHROME_BUTTON} is-round h-10 min-w-10 rounded-full bg-white/7`;

/* ------------------------------------------------------------------ *
 * Types
 * ------------------------------------------------------------------ */

export type PlayerSource =
  | { kind: "embed"; url: string; label: string }
  | { kind: "native"; url: string; label: string };

export type PlayerPanel = {
  id: string;
  /** Which control-bar button opens this panel. */
  icon: "screen" | "captions" | "settings";
  label: string;
  content: ReactNode;
};

export type PlayerChromeProps = {
  title: string;
  /** Small uppercase line under the wordmark — "MOVIE", "SERIES". */
  kicker: string;
  overview: string;
  backdrop: string | null;
  /** Human runtime for the start card, e.g. "1h 34m". */
  runtimeLabel: string;
  source: PlayerSource;
  panels?: PlayerPanel[];
  backHref: string;
  /** Extra line in the start card and control bar, e.g. "S1 · E4". */
  nowPlaying?: string;
  /** Episode stepping for embed sources; omit to hide the buttons. */
  onStep?: (delta: number) => void;
  canStepBack?: boolean;
  canStepForward?: boolean;
};

/* ------------------------------------------------------------------ *
 * Vendor-prefixed fullscreen / PiP surfaces
 * ------------------------------------------------------------------ */

type FullscreenDocument = Document & {
  webkitFullscreenElement?: Element | null;
  webkitExitFullscreen?: () => Promise<void> | void;
};

type FullscreenElement = HTMLElement & {
  webkitRequestFullscreen?: () => Promise<void> | void;
};

type MobileVideoElement = HTMLVideoElement & {
  webkitEnterFullscreen?: () => void;
};

function fullscreenElement(): Element | null {
  const doc = document as FullscreenDocument;
  return doc.fullscreenElement ?? doc.webkitFullscreenElement ?? null;
}

/* ------------------------------------------------------------------ *
 * Time helpers
 * ------------------------------------------------------------------ */

function clock(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return "0:00";
  const total = Math.floor(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  const pad = (value: number) => String(value).padStart(2, "0");
  return hours > 0 ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${minutes}:${pad(secs)}`;
}

/* ------------------------------------------------------------------ *
 * Glyphs
 * ------------------------------------------------------------------ */

type GlyphName =
  | "back"
  | "people"
  | "cast"
  | "help"
  | "play"
  | "pause"
  | "back10"
  | "forward10"
  | "volume"
  | "mute"
  | "screen"
  | "captions"
  | "settings"
  | "pip"
  | "expand"
  | "collapse"
  | "popout"
  | "prev"
  | "next";

function Glyph({ name }: { name: GlyphName }) {
  const common = {
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.7,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
    focusable: false,
  };

  switch (name) {
    case "back":
      return (
        <svg {...common}>
          <path d="m14 5-7 7 7 7" />
        </svg>
      );
    case "people":
      return (
        <svg {...common}>
          <path d="M15 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-4A3.5 3.5 0 0 0 4 18.5V20" />
          <circle cx="9.5" cy="8.5" r="3" />
          <path d="M20 20v-1.5a3.5 3.5 0 0 0-2.6-3.4M15.5 6a3 3 0 0 1 0 5.6" />
        </svg>
      );
    case "cast":
      return (
        <svg {...common}>
          <path d="M2 16.1A5 5 0 0 1 5.9 20M2 12.05A9 9 0 0 1 9.95 20" />
          <path d="M2 9V6a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-6" />
        </svg>
      );
    case "help":
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="9" />
          <path d="M9.3 9.3a2.8 2.8 0 0 1 5.4.9c0 1.9-2.7 2.4-2.7 4" />
          <path d="M12 17.4h.01" strokeWidth={2.2} />
        </svg>
      );
    case "play":
      return (
        <svg {...common} fill="currentColor" stroke="none">
          <path d="M8 4.8 19.2 12 8 19.2z" />
        </svg>
      );
    case "pause":
      return (
        <svg {...common} fill="currentColor" stroke="none">
          <rect x="6.4" y="4.6" width="3.6" height="14.8" rx="1.1" />
          <rect x="14" y="4.6" width="3.6" height="14.8" rx="1.1" />
        </svg>
      );
    case "back10":
      return (
        <svg {...common}>
          <path d="M12 5.4A7.4 7.4 0 1 1 4.7 14" />
          <path d="M12 2.4 8.7 5.4 12 8.4" />
          <text
            x="12"
            y="16.4"
            textAnchor="middle"
            fontSize="7.4"
            fontWeight="700"
            fill="currentColor"
            stroke="none"
          >
            10
          </text>
        </svg>
      );
    case "forward10":
      return (
        <svg {...common}>
          <path d="M12 5.4A7.4 7.4 0 1 0 19.3 14" />
          <path d="M12 2.4l3.3 3-3.3 3" />
          <text
            x="12"
            y="16.4"
            textAnchor="middle"
            fontSize="7.4"
            fontWeight="700"
            fill="currentColor"
            stroke="none"
          >
            10
          </text>
        </svg>
      );
    case "volume":
      return (
        <svg {...common}>
          <path d="M11 4.8 6.4 8.6H3v6.8h3.4L11 19.2z" fill="currentColor" stroke="none" />
          <path d="M15 9.4a3.6 3.6 0 0 1 0 5.2M17.7 6.7a7.4 7.4 0 0 1 0 10.6" />
        </svg>
      );
    case "mute":
      return (
        <svg {...common}>
          <path d="M11 4.8 6.4 8.6H3v6.8h3.4L11 19.2z" fill="currentColor" stroke="none" />
          <path d="m15.4 9.6 5 5M20.4 9.6l-5 5" />
        </svg>
      );
    case "screen":
      return (
        <svg {...common}>
          <rect x="2.6" y="4.6" width="18.8" height="12.4" rx="2.4" />
          <path d="M9 20.2h6" />
        </svg>
      );
    case "captions":
      return (
        <svg {...common}>
          <rect x="2.6" y="5" width="18.8" height="14" rx="3" />
          <path d="M7 11.4h4.4M7 14.8h8.6M14.4 11.4h2.6" />
        </svg>
      );
    case "settings":
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="3.1" />
          <path d="M12 2.6v2.6M12 18.8v2.6M4.4 4.4l1.9 1.9M17.7 17.7l1.9 1.9M2.6 12h2.6M18.8 12h2.6M4.4 19.6l1.9-1.9M17.7 6.3l1.9-1.9" />
        </svg>
      );
    case "pip":
      return (
        <svg {...common}>
          <rect x="2.6" y="4.6" width="18.8" height="14.8" rx="2.4" />
          <rect x="11.8" y="11.6" width="8" height="6" rx="1.4" fill="currentColor" stroke="none" />
        </svg>
      );
    case "expand":
      return (
        <svg {...common}>
          <path d="M8.6 3.4H5.4a2 2 0 0 0-2 2v3.2M15.4 3.4h3.2a2 2 0 0 1 2 2v3.2M8.6 20.6H5.4a2 2 0 0 1-2-2v-3.2M15.4 20.6h3.2a2 2 0 0 0 2-2v-3.2" />
        </svg>
      );
    case "collapse":
      return (
        <svg {...common}>
          <path d="M3.4 8.6h3.2a2 2 0 0 0 2-2V3.4M20.6 8.6h-3.2a2 2 0 0 1-2-2V3.4M3.4 15.4h3.2a2 2 0 0 1 2 2v3.2M20.6 15.4h-3.2a2 2 0 0 0-2 2v3.2" />
        </svg>
      );
    case "popout":
      return (
        <svg {...common}>
          <path d="M14.6 3.6h5.8v5.8M20.4 3.6 14 10" />
          <rect x="3.6" y="10" width="10.4" height="10.4" rx="2" />
        </svg>
      );
    case "prev":
      return (
        <svg {...common} fill="currentColor" stroke="none">
          <path d="M17.4 5.2v13.6L8.2 12z" />
          <rect x="5.2" y="5.2" width="2.4" height="13.6" rx="1" />
        </svg>
      );
    case "next":
      return (
        <svg {...common} fill="currentColor" stroke="none">
          <path d="M6.6 5.2v13.6L15.8 12z" />
          <rect x="16.4" y="5.2" width="2.4" height="13.6" rx="1" />
        </svg>
      );
  }
}

/* ------------------------------------------------------------------ *
 * Component
 * ------------------------------------------------------------------ */

export function PlayerChrome({
  title,
  kicker,
  overview,
  backdrop,
  runtimeLabel,
  source,
  panels = [],
  backHref,
  nowPlaying,
  onStep,
  canStepBack = false,
  canStepForward = false,
}: PlayerChromeProps) {
  const isNative = source.kind === "native";

  const pageRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const frameRef = useRef<HTMLIFrameElement>(null);
  const idleTimer = useRef<number | null>(null);
  const seekTimer = useRef<number | null>(null);

  /** Has the viewer dismissed the start card? Doubles as the paused overlay. */
  const [started, setStarted] = useState(false);
  const [loading, setLoading] = useState(true);
  const [playing, setPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [muted, setMuted] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isWide, setIsWide] = useState(false);
  const [openPanel, setOpenPanel] = useState<string | null>(null);
  const [idle, setIdle] = useState(false);
  /** Scrub position while the viewer is dragging, before the seek is sent. */
  const [scrubbing, setScrubbing] = useState<number | null>(null);

  const [bridge, remote] = useVidSrcBridge(frameRef, source.url, !isNative);

  /* ---------------------------------------------------------------------- *
   * One transport, two back ends. `live` is the switch: true when the
   * controls actually move the picture, false only for an embed whose mirror
   * never answered the bridge.
   * ---------------------------------------------------------------------- */
  const bridged = !isNative && bridge.connected;
  const live = isNative || bridged;

  const position = isNative ? currentTime : bridge.position;
  const total = isNative ? duration : bridge.duration;
  const isPlaying = isNative ? playing : bridge.playing;
  const isMuted = isNative ? muted : bridge.muted;

  /* -------- the overlay is showing whenever playback is not running ------- */
  // Before the bridge connects the provider owns the pre-roll (its own poster
  // and play button), so the overlay steps aside once the frame is mounted.
  const overlayVisible = isNative ? !playing : bridged ? !bridge.playing : !started;

  /** The provider is drawing chrome of its own that ours duplicates. */
  const providerTop = bridged && (bridge.barVisible || bridge.chromeVisible);
  const providerBottom = bridged && bridge.chromeVisible;

  /* ------------------------------ fullscreen ----------------------------- */

  useEffect(() => {
    const sync = () => setIsFullscreen(fullscreenElement() === pageRef.current);
    document.addEventListener("fullscreenchange", sync);
    document.addEventListener("webkitfullscreenchange", sync);
    sync();
    return () => {
      document.removeEventListener("fullscreenchange", sync);
      document.removeEventListener("webkitfullscreenchange", sync);
    };
  }, []);

  const toggleFullscreen = useCallback(() => {
    const node = pageRef.current as FullscreenElement | null;
    if (!node) return;
    const doc = document as FullscreenDocument;

    // iPhone Safari exposes fullscreen on <video>, not arbitrary page nodes.
    if (!fullscreenElement() && !node.requestFullscreen && !node.webkitRequestFullscreen && isNative) {
      (videoRef.current as MobileVideoElement | null)?.webkitEnterFullscreen?.();
      return;
    }

    // Fullscreen the page root, not the iframe: a cross-origin provider frame
    // may refuse its own request, but ours always applies — and taking the
    // root along keeps the chrome on screen.
    const run = fullscreenElement()
      ? (doc.exitFullscreen?.() ?? doc.webkitExitFullscreen?.())
      : (node.requestFullscreen?.({ navigationUI: "hide" }) ?? node.webkitRequestFullscreen?.());

    Promise.resolve(run).catch(() => {
      /* The browser declined (no user gesture, or policy). Nothing to do. */
    });
  }, [isNative]);

  /* ------------------------------- transport ----------------------------- */

  const togglePlay = useCallback(() => {
    if (!isNative) {
      // Until the bridge answers, the start card is the only gate we own.
      if (!bridge.connected) {
        setStarted(true);
        return;
      }
      if (bridge.playing) remote.pause();
      else remote.play();
      return;
    }
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) void video.play().catch(() => setPlaying(false));
    else video.pause();
  }, [bridge.connected, bridge.playing, isNative, remote]);

  const seekBy = useCallback(
    (delta: number) => {
      if (!isNative) {
        if (bridge.connected) remote.seekBy(delta);
        return;
      }
      const video = videoRef.current;
      if (!video || !Number.isFinite(video.duration)) return;
      video.currentTime = Math.min(Math.max(video.currentTime + delta, 0), video.duration);
    },
    [bridge.connected, isNative, remote],
  );

  const seekTo = useCallback(
    (value: number) => {
      if (!isNative) {
        if (bridge.connected) remote.seekTo(value);
        return;
      }
      const video = videoRef.current;
      if (!video) return;
      video.currentTime = value;
      setCurrentTime(value);
    },
    [bridge.connected, isNative, remote],
  );

  /**
   * Range inputs fire on every step, and each embed seek is a postMessage
   * round trip — so the thumb moves immediately and the seek lands once the
   * viewer settles. Debouncing also covers keyboard and touch identically,
   * with no pointer bookkeeping.
   */
  const previewSeek = useCallback(
    (value: number) => {
      setScrubbing(value);
      if (seekTimer.current) window.clearTimeout(seekTimer.current);
      seekTimer.current = window.setTimeout(() => {
        seekTo(value);
        setScrubbing(null);
      }, 160);
    },
    [seekTo],
  );

  useEffect(
    () => () => {
      if (seekTimer.current) window.clearTimeout(seekTimer.current);
    },
    [],
  );

  const toggleMute = useCallback(() => {
    if (!isNative) {
      // The player accepts mute/unmute but reports no volume level, so a
      // slider would be a guess — the toggle is all we can state honestly.
      if (bridge.connected) remote.setMuted(!bridge.muted);
      return;
    }
    const video = videoRef.current;
    const next = !muted;
    setMuted(next);
    if (video) video.muted = next;
  }, [bridge.connected, bridge.muted, isNative, muted, remote]);

  const togglePip = useCallback(() => {
    const video = videoRef.current;
    if (!isNative || !video) {
      // No PiP for a cross-origin frame — widen the stage instead.
      setIsWide((wide) => !wide);
      return;
    }
    if (document.pictureInPictureElement) void document.exitPictureInPicture().catch(() => {});
    else void video.requestPictureInPicture().catch(() => setIsWide((wide) => !wide));
  }, [isNative]);

  /* ------------------------- reset on source change ---------------------- */

  useEffect(() => {
    setLoading(true);
    setCurrentTime(0);
    setDuration(0);
  }, [source.url]);

  /* ----------------------------- chrome idling --------------------------- */

  const wake = useCallback(() => {
    setIdle(false);
    if (idleTimer.current) window.clearTimeout(idleTimer.current);
    idleTimer.current = window.setTimeout(() => setIdle(true), 3200);
  }, []);

  useEffect(() => {
    // Pointer events do not cross into a cross-origin frame. A native <video>
    // reports them directly; a bridged embed reports them through the catcher
    // laid over the frame. Without either, the wake handler would never fire
    // over the picture and hiding the chrome would strand the controls.
    if (!live || overlayVisible || openPanel) {
      setIdle(false);
      if (idleTimer.current) window.clearTimeout(idleTimer.current);
      return;
    }
    wake();
    return () => {
      if (idleTimer.current) window.clearTimeout(idleTimer.current);
    };
  }, [live, overlayVisible, openPanel, wake]);

  /* ------------------------------- keyboard ------------------------------ */

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && /^(INPUT|SELECT|TEXTAREA)$/.test(target.tagName)) return;
      if (event.metaKey || event.ctrlKey || event.altKey) return;

      switch (event.key) {
        case "f":
        case "F":
          event.preventDefault();
          toggleFullscreen();
          break;
        case "Escape":
          setOpenPanel(null);
          break;
        case " ":
        case "k":
        case "K":
          event.preventDefault();
          togglePlay();
          break;
        case "m":
        case "M":
          if (live) toggleMute();
          break;
        case "ArrowLeft":
          if (live) {
            event.preventDefault();
            seekBy(-10);
          }
          break;
        case "ArrowRight":
          if (live) {
            event.preventDefault();
            seekBy(10);
          }
          break;
        default:
          break;
      }
      wake();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [live, seekBy, toggleFullscreen, toggleMute, togglePlay, wake]);

  /* ------------------------------- derived ------------------------------- */

  /** What the scrub thumb sits on: the drag, or the real position. */
  const shown = scrubbing ?? position;
  const progress = total > 0 ? Math.min(shown / total, 1) : 0;

  /** "Ends at 10:39 PM" — client-only, so it never mismatches SSR output. */
  const endsAt = useMemo(() => {
    if (!live || total <= 0) return "";
    const remaining = Math.max(total - position, 0);
    const at = new Date(Date.now() + remaining * 1000);
    return at.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    // position is intentionally a dependency: the estimate drifts with pauses.
  }, [live, total, position]);

  const resumeLabel = live
    ? total > 0
      ? `${clock(position)} of ${clock(total)}`
      : "Loading…"
    : [nowPlaying, runtimeLabel].filter(Boolean).join(" · ");

  const activePanel = panels.find((panel) => panel.id === openPanel) ?? null;

  const panelButton = (panel: PlayerPanel) => (
    <button
      key={panel.id}
      type="button"
      className={`${CHROME_BUTTON}${openPanel === panel.id ? " is-active bg-white/20 text-white" : ""}`}
      aria-label={panel.label}
      aria-haspopup="dialog"
      aria-expanded={openPanel === panel.id}
      title={panel.label}
      onClick={() => setOpenPanel((current) => (current === panel.id ? null : panel.id))}
    >
      <Glyph name={panel.icon} />
    </button>
  );

  return (
    <div
      ref={pageRef}
      className={[
        "watch-page relative flex flex-col bg-[#040404]",
        isNative ? "is-native" : "is-embed",
        // Marks a transport that actually moves the picture — a native video or
        // a connected bridge. Fullscreen floats the bars only in that case.
        live ? "is-live" : "",
        isFullscreen ? "is-fullscreen" : "",
        isWide ? "is-wide" : "",
        idle ? "is-idle" : "",
        overlayVisible ? "is-paused" : "is-playing",
      ]
        .filter(Boolean)
        .join(" ")}
      onPointerMove={wake}
      onPointerLeave={() => live && !overlayVisible && !openPanel && setIdle(true)}
    >
      {/* ------------------------------ top bar ------------------------------ */}
      <header className="watch-topbar flex items-start gap-[18px] px-[max(26px,calc((100vw_-_1720px)/2))] pt-[22px] pb-4 transition-opacity duration-250 max-[760px]:px-[18px] max-[760px]:pt-4 max-[760px]:pb-3">
        <Link href={backHref} className={ROUND_CHROME_BUTTON} aria-label="Back to browse">
          <Glyph name="back" />
        </Link>

        <div className="flex min-w-0 flex-col gap-[5px] pt-0.5" hidden={overlayVisible}>
          <strong className="overflow-hidden bg-[linear-gradient(180deg,#ffd463_0%,#f5ad12_55%,#d98908_100%)] bg-clip-text font-display text-[clamp(24px,2.3vw,34px)] leading-none font-extrabold tracking-[-.02em] text-ellipsis whitespace-nowrap text-transparent uppercase">{title}</strong>
          <span className="text-[10px] font-bold tracking-[.19em] text-[#8a857e] uppercase">{nowPlaying ? `${kicker} · ${nowPlaying}` : kicker}</span>
        </div>

        <div className="ml-auto flex gap-2 pt-0.5 max-[760px]:[&_button:not(:last-child)]:hidden" hidden={overlayVisible}>
          <button type="button" className={ROUND_CHROME_BUTTON} aria-label="Watch party" title="Watch party">
            <Glyph name="people" />
          </button>
          <button type="button" className={ROUND_CHROME_BUTTON} aria-label="Cast to device" title="Cast to device">
            <Glyph name="cast" />
          </button>
          <button type="button" className={ROUND_CHROME_BUTTON} aria-label="Playback help" title="Playback help">
            <Glyph name="help" />
          </button>
        </div>
      </header>

      {/* ------------------------------- stage ------------------------------- */}
      <div className={`watch-stage-wrap relative px-[max(26px,calc((100vw_-_1720px)/2))] max-[760px]:px-[18px] ${isWide ? "px-0 max-[760px]:px-0" : ""}`}>
        <div className={`watch-stage relative mx-auto aspect-video w-full overflow-hidden bg-black ${isWide ? "max-h-[calc(100vh_-_200px)] rounded-none" : "max-h-[calc(100vh_-_232px)] rounded-lg max-[1080px]:max-h-none"}`}>
          {isNative ? (
            <video
              ref={videoRef}
              className="absolute inset-0 h-full w-full cursor-pointer bg-black object-contain"
              src={source.url}
              playsInline
              preload="metadata"
              poster={backdrop ?? undefined}
              onClick={togglePlay}
              onLoadedMetadata={(event) => {
                setDuration(event.currentTarget.duration || 0);
                setLoading(false);
              }}
              onTimeUpdate={(event) => setCurrentTime(event.currentTarget.currentTime)}
              onPlay={() => {
                setPlaying(true);
                setStarted(true);
              }}
              onPause={() => setPlaying(false)}
              onWaiting={() => setLoading(true)}
              onPlaying={() => setLoading(false)}
              onVolumeChange={(event) => setMuted(event.currentTarget.muted)}
            />
          ) : (
            started && (
              <iframe
                key={source.url}
                ref={frameRef}
                className={`absolute inset-0 z-[1] block h-full w-full border-0 bg-black ${bridged ? "pointer-events-none" : ""}`}
                src={source.url}
                title={`${title} — ${source.label}`}
                // `fullscreen` here is what lets the provider's own control work
                // at all; ours works regardless because it targets the page root.
                allow="autoplay; fullscreen; picture-in-picture; encrypted-media"
                allowFullScreen
                referrerPolicy="origin"
                onLoad={() => setLoading(false)}
              />
            )
          )}

          {/* The seal. Once the bridge is driving playback, pointer events stop
              at this layer instead of reaching the frame — so the provider's
              own pointermove/pointerdown handlers never wake its title strip or
              control bar, and clicking the picture plays/pauses through us. */}
          {bridged && <div className="absolute inset-0 z-[2] cursor-pointer" onClick={togglePlay} aria-hidden />}

          {providerTop && <div className="absolute inset-x-0 top-0 z-[3] h-[max(58px,13%)] bg-black pointer-events-none" aria-hidden />}
          {providerBottom && <div className="absolute inset-x-0 bottom-0 z-[3] h-[max(66px,16%)] bg-black pointer-events-none" aria-hidden />}

          {/* Only before the first play — once running, a native pause should
              show the frozen frame, not artwork over the top of it. */}
          {backdrop && overlayVisible && !started && (
            <img className="absolute inset-0 h-full w-full object-cover opacity-55" src={backdrop} alt="" aria-hidden />
          )}

          {loading && started && (
            <div className="absolute inset-0 z-[3] flex flex-col items-center justify-center gap-3 pointer-events-none [&_b]:text-xs [&_b]:text-[#aaa6a0]" role="status">
              <span className="h-[30px] w-[30px] animate-spin rounded-full border-2 border-white/18 border-t-white" />
              <b>Loading {source.label}…</b>
            </div>
          )}

          {/* ------------------- start / paused overlay ------------------- */}
          {overlayVisible && (
            <div className="absolute inset-0 z-[4] flex flex-col items-start justify-end bg-[linear-gradient(90deg,rgba(0,0,0,.93)_0%,rgba(0,0,0,.72)_34%,rgba(0,0,0,.18)_68%,transparent_100%),linear-gradient(0deg,rgba(0,0,0,.86)_0%,transparent_62%)] pb-[clamp(18px,4vh,46px)] pl-[clamp(20px,3vw,44px)]">
              <p className="mb-3 text-[11px] font-bold tracking-[.2em] text-[#98938c] uppercase">You&apos;re watching</p>
              <strong className="block max-w-[15ch] bg-[linear-gradient(180deg,#ffd463_0%,#f5ad12_52%,#cf8106_100%)] bg-clip-text font-display text-[clamp(38px,5.4vw,92px)] leading-[.9] font-extrabold tracking-[-.045em] text-transparent uppercase">{title}</strong>
              <p className="mt-3.5 text-[11px] font-bold tracking-[.19em] text-[#8f8a83] uppercase">{nowPlaying ? `${kicker} · ${nowPlaying}` : kicker}</p>
              {overview && <p className="mt-3.5 line-clamp-3 max-w-[590px] text-sm leading-[1.62] text-[#c6c1ba]">{overview}</p>}
              <div className="mt-[26px] flex flex-wrap items-center gap-4">
                <button type="button" className="inline-flex cursor-pointer items-center gap-2.5 rounded-[10px] border-0 bg-[#f7f5f1] py-[13px] pr-[26px] pl-5 text-[15px] font-bold text-[#111] transition hover:-translate-y-px hover:bg-white focus-visible:outline-2 focus-visible:outline-offset-3 focus-visible:outline-[#f5ad12] [&_svg]:h-[17px] [&_svg]:w-[17px]" onClick={togglePlay}>
                  <Glyph name="play" />
                  <span>{live && position > 1 ? "Resume" : "Play"}</span>
                </button>
                {resumeLabel && <span className="text-xs text-[#a39e97] tabular-nums">{resumeLabel}</span>}
              </div>
              <div
                className="mt-[26px] h-0.5 w-[520px] max-w-full rounded-sm bg-[linear-gradient(90deg,#f7f5f1_var(--progress),rgba(255,255,255,.22)_var(--progress))]"
                style={{ "--progress": `${progress * 100}%` } as CSSProperties}
              />
            </div>
          )}

          {overlayVisible && (
            <div className="absolute right-[clamp(16px,2.4vw,34px)] bottom-[clamp(14px,3vh,30px)] z-[5] flex items-center gap-2 text-[11px] font-bold tracking-[.19em] text-[#8d8881] uppercase [&_svg]:h-[13px] [&_svg]:w-[13px]">
              <Glyph name={started ? "pause" : "play"} />
              {/* Before the first play there is nothing to have paused, so the
                  only honest state at that point is "ready". */}
              <span>{started ? "Paused" : "Ready"}</span>
            </div>
          )}
        </div>

        {/* Floating edge control, as in the reference. */}
        <button
          type="button"
          className={`${CHROME_BUTTON} stage-popout absolute top-1/2 right-[max(4px,calc((100vw_-_1720px)/2_-_48px))] z-[5] h-[34px] min-w-[42px] -translate-y-1/2 rounded-[9px] border border-white/14 bg-[rgba(20,20,20,.82)] max-[760px]:hidden ${isWide ? "right-[14px]" : ""}`}
          onClick={togglePip}
          aria-label={isNative ? "Picture in picture" : isWide ? "Fit to page" : "Widen player"}
          title={isNative ? "Picture in picture" : isWide ? "Fit to page" : "Widen player"}
        >
          <Glyph name="popout" />
        </button>
      </div>

      {/* ---------------------------- control bar ---------------------------- */}
      <div className="watch-controlbar relative px-[max(26px,calc((100vw_-_1720px)/2))] pt-[18px] pb-5 transition-opacity duration-250 max-[760px]:px-[18px]">
        {live && total > 0 ? (
          <input
            className="scrub mb-2 block h-[3px] w-full cursor-pointer appearance-none rounded-[3px] border-0 bg-[linear-gradient(90deg,#f4f2ee_var(--progress),rgba(255,255,255,.22)_var(--progress))] outline-0 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#f5ad12]"
            type="range"
            min={0}
            max={total}
            step="any"
            value={shown}
            onChange={(event) =>
              isNative ? seekTo(Number(event.target.value)) : previewSeek(Number(event.target.value))
            }
            aria-label="Seek"
            aria-valuetext={`${clock(shown)} of ${clock(total)}`}
            style={{ "--progress": `${progress * 100}%` } as CSSProperties}
          />
        ) : (
          // Either nothing is loaded yet, or this mirror has no relay and there
          // is no position to report — a rule, not a control that would look
          // interactive and then do nothing.
          <div className="mb-2 block h-[3px] w-full rounded-[3px] bg-white/16" aria-hidden />
        )}

        <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3.5 max-[760px]:gap-px">
          <div className="flex min-w-0 items-center gap-1">
            {live ? (
              <>
                <button
                  type="button"
                  className={CHROME_BUTTON}
                  onClick={togglePlay}
                  aria-label={isPlaying ? "Pause" : "Play"}
                  title={isPlaying ? "Pause (k)" : "Play (k)"}
                >
                  <Glyph name={isPlaying ? "pause" : "play"} />
                </button>
                <button
                  type="button"
                  className={CHROME_BUTTON}
                  onClick={() => seekBy(-10)}
                  aria-label="Back 10 seconds"
                >
                  <Glyph name="back10" />
                </button>
                <button
                  type="button"
                  className={CHROME_BUTTON}
                  onClick={() => seekBy(10)}
                  aria-label="Forward 10 seconds"
                >
                  <Glyph name="forward10" />
                </button>
                <div className="volume-pod flex items-center">
                  <button
                    type="button"
                    className={CHROME_BUTTON}
                    onClick={toggleMute}
                    aria-label={isMuted ? "Unmute" : "Mute"}
                  >
                    <Glyph name={isMuted ? "mute" : "volume"} />
                  </button>
                </div>
              </>
            ) : (
              <button
                type="button"
                className={CHROME_BUTTON}
                onClick={togglePlay}
                aria-label="Play"
                title="Play (k)"
              >
                <Glyph name="play" />
              </button>
            )}
          </div>

          <div className="flex min-w-0 items-center justify-center gap-3.5 [&_time]:text-[12.5px] [&_time]:text-[#f2efea] [&_time]:tabular-nums [&_time_span]:text-[#8f8a83] [&_em]:overflow-hidden [&_em]:text-xs [&_em]:text-ellipsis [&_em]:whitespace-nowrap [&_em]:text-[#8f8a83] [&_em]:not-italic max-[1080px]:[&_em]:hidden">
            {live && total > 0 ? (
              <>
                <time>
                  {clock(shown)} <span>/ {clock(total)}</span>
                </time>
                {endsAt && <em>Ends at {endsAt}</em>}
              </>
            ) : (
              <>
                <time>{nowPlaying ? nowPlaying : runtimeLabel || "Streaming"}</time>
                <em>{live ? "Reading the stream…" : `${source.label} controls the transport in-frame`}</em>
              </>
            )}
          </div>

          <div className="flex min-w-0 items-center justify-end gap-1 max-[760px]:[&_button:nth-last-child(2)]:hidden">
            {onStep && (
              <>
                <button
                  type="button"
                  className={CHROME_BUTTON}
                  onClick={() => onStep(-1)}
                  disabled={!canStepBack}
                  aria-label="Previous episode"
                  title="Previous episode"
                >
                  <Glyph name="prev" />
                </button>
                <button
                  type="button"
                  className={CHROME_BUTTON}
                  onClick={() => onStep(1)}
                  disabled={!canStepForward}
                  aria-label="Next episode"
                  title="Next episode"
                >
                  <Glyph name="next" />
                </button>
              </>
            )}
            {panels.map(panelButton)}
            <button
              type="button"
              className={`${CHROME_BUTTON}${isWide ? " is-active bg-white/20 text-white" : ""}`}
              onClick={togglePip}
              aria-label={isNative ? "Picture in picture" : "Widen player"}
              title={isNative ? "Picture in picture" : "Widen player"}
            >
              <Glyph name="pip" />
            </button>
            <button
              type="button"
              className={`${CHROME_BUTTON}${isFullscreen ? " is-active bg-white/20 text-white" : ""}`}
              onClick={toggleFullscreen}
              aria-label={isFullscreen ? "Exit fullscreen" : "Fullscreen"}
              title={isFullscreen ? "Exit fullscreen (f)" : "Fullscreen (f)"}
            >
              <Glyph name={isFullscreen ? "collapse" : "expand"} />
            </button>
          </div>
        </div>

        {activePanel && (
          <div className="watch-panel absolute right-[max(26px,calc((100vw_-_1720px)/2))] bottom-[calc(100%_-_8px)] z-[8] max-h-[min(58vh,460px)] w-[min(340px,calc(100vw_-_52px))] overflow-auto rounded-[14px] border border-white/13 bg-[rgba(15,15,15,.98)] shadow-[0_26px_70px_rgba(0,0,0,.72)] max-[760px]:right-[18px]" role="dialog" aria-label={activePanel.label}>
            <header className="sticky top-0 flex items-center justify-between border-b border-white/8 bg-[rgba(15,15,15,.98)] px-4 py-3.5 [&_b]:text-[13px]">
              <b>{activePanel.label}</b>
              <button className="cursor-pointer border-0 bg-transparent px-1.5 py-1 text-[13px] text-[#8f8a83] hover:text-white" type="button" onClick={() => setOpenPanel(null)} aria-label="Close">
                ✕
              </button>
            </header>
            <div className="p-3">{activePanel.content}</div>
          </div>
        )}
      </div>
    </div>
  );
}
