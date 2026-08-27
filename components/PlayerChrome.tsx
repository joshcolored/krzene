"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import type { VidSrcBridgeState, VidSrcRemote } from "@/lib/vidsrc-bridge";

type Props = {
  children: ReactNode;
  playback: VidSrcBridgeState;
  remote: VidSrcRemote;
  title: string;
};

type FullDoc = Document & {
  webkitFullscreenElement?: Element | null;
  webkitExitFullscreen?: () => Promise<void> | void;
};

type FullNode = HTMLDivElement & {
  webkitRequestFullscreen?: () => Promise<void> | void;
};

const BUTTON = "inline-flex h-11 min-w-11 cursor-pointer items-center justify-center rounded-xl border-0 bg-transparent p-0 text-white transition hover:bg-white/15 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#f5ad12] disabled:cursor-default disabled:opacity-30 [&_svg]:h-[21px] [&_svg]:w-[21px]";

function clock(value: number) {
  const total = Math.max(0, Math.floor(value || 0));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  return hours
    ? hours + ":" + String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0")
    : minutes + ":" + String(seconds).padStart(2, "0");
}

function Glyph({ name }: { name: "play" | "pause" | "back" | "next" | "volume" | "mute" | "expand" | "collapse" }) {
  const props = { viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.8, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true };
  if (name === "play") return <svg {...props} fill="currentColor" stroke="none"><path d="m8 5 11 7-11 7V5Z" /></svg>;
  if (name === "pause") return <svg {...props} fill="currentColor" stroke="none"><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></svg>;
  if (name === "back") return <svg {...props}><path d="M12 5.3a7 7 0 1 1-6.8 8.5M12 2.5 8.5 5.3 12 8" /><text x="12" y="16" textAnchor="middle" fontSize="7" fontWeight="700" fill="currentColor" stroke="none">10</text></svg>;
  if (name === "next") return <svg {...props}><path d="M12 5.3a7 7 0 1 0 6.8 8.5M12 2.5l3.5 2.8L12 8" /><text x="12" y="16" textAnchor="middle" fontSize="7" fontWeight="700" fill="currentColor" stroke="none">10</text></svg>;
  if (name === "volume") return <svg {...props}><path d="M11 5 6.5 8.8H3v6.4h3.5L11 19V5Z" fill="currentColor" stroke="none" /><path d="M15 9.2a4 4 0 0 1 0 5.6M18 6.5a8 8 0 0 1 0 11" /></svg>;
  if (name === "mute") return <svg {...props}><path d="M11 5 6.5 8.8H3v6.4h3.5L11 19V5Z" fill="currentColor" stroke="none" /><path d="m15 9 5 6m0-6-5 6" /></svg>;
  if (name === "collapse") return <svg {...props}><path d="M4 9h3a2 2 0 0 0 2-2V4m11 5h-3a2 2 0 0 1-2-2V4M4 15h3a2 2 0 0 1 2 2v3m11-5h-3a2 2 0 0 0-2 2v3" /></svg>;
  return <svg {...props}><path d="M9 4H6a2 2 0 0 0-2 2v3m9-5h3a2 2 0 0 1 2 2v3M9 20H6a2 2 0 0 1-2-2v-3m9 5h3a2 2 0 0 0 2-2v-3" /></svg>;
}

export function PlayerChrome({ children, playback, remote, title }: Props) {
  const stageRef = useRef<HTMLDivElement>(null);
  const idleTimer = useRef<number | null>(null);
  const [visible, setVisible] = useState(true);
  const [pseudoFullscreen, setPseudoFullscreen] = useState(false);
  const [nativeFullscreen, setNativeFullscreen] = useState(false);
  const connected = playback.connected;
  const fullscreen = pseudoFullscreen || nativeFullscreen;

  const wake = useCallback(() => {
    setVisible(true);
    if (idleTimer.current) window.clearTimeout(idleTimer.current);
    if (playback.playing) idleTimer.current = window.setTimeout(() => setVisible(false), 2800);
  }, [playback.playing]);

  useEffect(() => {
    wake();
    return () => {
      if (idleTimer.current) window.clearTimeout(idleTimer.current);
    };
  }, [wake]);

  useEffect(() => {
    const sync = () => {
      const doc = document as FullDoc;
      setNativeFullscreen((doc.fullscreenElement ?? doc.webkitFullscreenElement) === stageRef.current);
    };
    document.addEventListener("fullscreenchange", sync);
    document.addEventListener("webkitfullscreenchange", sync);
    return () => {
      document.removeEventListener("fullscreenchange", sync);
      document.removeEventListener("webkitfullscreenchange", sync);
    };
  }, []);

  useEffect(() => {
    if (!pseudoFullscreen) return;
    const body = document.body.style.overflow;
    const root = document.documentElement.style.overflow;
    document.body.style.overflow = "hidden";
    document.documentElement.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = body;
      document.documentElement.style.overflow = root;
    };
  }, [pseudoFullscreen]);

  const togglePlay = useCallback(() => {
    playback.playing ? remote.pause() : remote.play();
    wake();
  }, [playback.playing, remote, wake]);

  const toggleFullscreen = useCallback(() => {
    const node = stageRef.current as FullNode | null;
    const doc = document as FullDoc;
    if (!node) return;
    if (pseudoFullscreen) {
      setPseudoFullscreen(false);
      return;
    }
    if (doc.fullscreenElement || doc.webkitFullscreenElement) {
      Promise.resolve(doc.exitFullscreen?.() ?? doc.webkitExitFullscreen?.()).catch(() => setPseudoFullscreen(false));
      return;
    }
    const request = node.requestFullscreen?.bind(node) ?? node.webkitRequestFullscreen?.bind(node);
    if (!request) {
      setPseudoFullscreen(true);
      return;
    }
    try {
      Promise.resolve(request()).catch(() => setPseudoFullscreen(true));
    } catch {
      setPseudoFullscreen(true);
    }
  }, [pseudoFullscreen]);

  return (
    <div
      ref={stageRef}
      className={[
        "relative aspect-video w-full overflow-hidden bg-black",
        pseudoFullscreen ? "fixed inset-0 z-[120] h-dvh w-screen rounded-none" : "rounded-lg max-[760px]:rounded-md",
      ].join(" ")}
      onPointerMove={wake}
      onPointerDown={wake}
      aria-label={title + " player"}
    >
      <div className={connected ? "absolute inset-0 [&_iframe]:pointer-events-none" : "absolute inset-0"}>{children}</div>

      {connected && (
        <div
          className="absolute inset-0 z-10 cursor-pointer touch-manipulation"
          role="button"
          tabIndex={0}
          aria-label={playback.playing ? "Pause video" : "Play video"}
          onClick={togglePlay}
          onKeyDown={(event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              togglePlay();
            }
          }}
        />
      )}

      {connected && (playback.barVisible || playback.chromeVisible) && <div className="pointer-events-none absolute inset-x-0 top-0 z-[11] h-[15%] bg-[linear-gradient(#000_15%,rgba(0,0,0,.88)_62%,transparent)]" aria-hidden="true" />}
      {connected && playback.chromeVisible && <div className="pointer-events-none absolute inset-x-0 bottom-0 z-[11] h-[22%] bg-[linear-gradient(transparent,rgba(0,0,0,.92)_48%,#000)]" aria-hidden="true" />}

      <div className={[
        "absolute inset-x-0 bottom-0 z-20 bg-[linear-gradient(transparent,rgba(0,0,0,.9)_40%,#000)] px-3 pt-12 pb-2 transition-opacity duration-200 max-[520px]:px-1.5 max-[520px]:pt-8",
        visible || !playback.playing ? "opacity-100" : "pointer-events-none opacity-0",
      ].join(" ")}>
        {connected && playback.duration > 0 ? (
          <input
            className="block h-5 w-full cursor-pointer accent-[#f5ad12]"
            type="range"
            min={0}
            max={playback.duration}
            step={1}
            value={Math.min(playback.position, playback.duration)}
            onChange={(event) => remote.seekTo(Number(event.target.value))}
            onPointerDown={(event) => event.stopPropagation()}
            aria-label="Seek video"
          />
        ) : <div className="mx-2 h-px bg-white/20" />}

        <div className="flex min-w-0 items-center gap-0.5">
          <button type="button" className={BUTTON} onClick={togglePlay} aria-label={playback.playing ? "Pause" : "Play"}><Glyph name={playback.playing ? "pause" : "play"} /></button>
          <button type="button" className={BUTTON} onClick={() => remote.seekBy(-10)} disabled={!connected} aria-label="Back 10 seconds"><Glyph name="back" /></button>
          <button type="button" className={BUTTON} onClick={() => remote.seekBy(10)} disabled={!connected} aria-label="Forward 10 seconds"><Glyph name="next" /></button>
          <button type="button" className={BUTTON} onClick={() => remote.setMuted(!playback.muted)} disabled={!connected} aria-label={playback.muted ? "Unmute" : "Mute"}><Glyph name={playback.muted ? "mute" : "volume"} /></button>
          <time className="ml-1 min-w-0 truncate text-[11px] font-semibold text-white tabular-nums">
            {connected && playback.duration > 0 ? clock(playback.position) + " / " + clock(playback.duration) : "Tap video once to connect"}
          </time>
          <button type="button" className={BUTTON + " ml-auto"} onClick={toggleFullscreen} aria-label={fullscreen ? "Exit fullscreen" : "Fullscreen"}><Glyph name={fullscreen ? "collapse" : "expand"} /></button>
        </div>
      </div>
    </div>
  );
}
