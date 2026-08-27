"use client";

/**
 * Bridge to the VidSrc embed's postMessage relay.
 *
 * The embed is a chain of nested frames, each of which relays postMessages in
 * BOTH directions:
 *
 *   our page
 *    └─ mirror   /embed/{type}/{id}         draws #vs-bar — the title label
 *        └─ gate /embed/{type}/{id}?vs=…    landing poster + big play button
 *            └─ gate /embed/player/…        the real <video> + its own chrome
 *
 * Because the relay is bidirectional, the top window can both hear the player
 * and command it. That is what lets Krzene's transport be real rather than
 * decorative, and what makes it safe to seal the provider's duplicate chrome
 * off — nothing is lost by hiding controls we can now drive ourselves.
 *
 * Commands understood by the innermost player:
 *   { player: true, action: "play" | "pause" | "mute" | "unmute" }
 *   { player: true, action: "seek<n>" | "seek+<n>" | "seek-<n>" }   seconds
 *
 * (It also takes { type: "TV_SET", season, episode }. Krzene does not use it —
 * switching episodes changes the embed URL, which remounts the frame, and a
 * clean remount is more predictable than steering a player mid-stream.)
 *
 * Events it sends back up:
 *   { type: "PLAYER_EVENT", data: { player_status, player_progress,
 *                                   player_duration, quality, … } }
 *   { type: "PLAYER_UI", visible }     provider chrome shown / hidden
 *   { type: "PLAYER_TITLE", title }    also makes the mirror show #vs-bar
 *   { type: "TV_INFO" | "TV_STATE", … }
 *
 * None of this is contractual. Mirrors that ship a bare iframe wrapper (or
 * change the protocol) simply never connect, so every caller has to keep
 * working with `connected: false`.
 */

import { useCallback, useEffect, useMemo, useRef, useState, type RefObject } from "react";

/* ------------------------------------------------------------------ *
 * State
 * ------------------------------------------------------------------ */

export type VidSrcBridgeState = {
  /** A PLAYER_EVENT has arrived, so the transport below this is real. */
  connected: boolean;
  playing: boolean;
  /** Seconds, interpolated between the player's 5-second progress reports. */
  position: number;
  duration: number;
  /** Resolution reported by the player, for example `720p`. */
  quality: string | null;
  /** Resolution labels advertised by the current stream. */
  availableQualities: string[];
  /**
   * The last mute state we asked for. The player emits no volume events, so
   * this reflects our own command rather than an observation.
   */
  muted: boolean;
  /** The innermost player is drawing its title + control bar right now. */
  chromeVisible: boolean;
  /** The mirror is drawing its own #vs-bar title strip right now. */
  barVisible: boolean;
};

export type VidSrcRemote = {
  play(): void;
  pause(): void;
  setMuted(next: boolean): void;
  /** Absolute position, in seconds. */
  seekTo(seconds: number): void;
  seekBy(delta: number): void;
  /** Requests a resolution. Mirrors that do not support this command stay on Auto. */
  setQuality(height: 480 | 720 | 1080): void;
};

const IDLE: VidSrcBridgeState = {
  connected: false,
  playing: false,
  position: 0,
  duration: 0,
  quality: null,
  availableQualities: [],
  muted: false,
  chromeVisible: false,
  barVisible: false,
};

/* ------------------------------------------------------------------ *
 * Payload coercion — everything below arrives from another origin, so
 * it is treated as untrusted data and never as an instruction.
 * ------------------------------------------------------------------ */

function seconds(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function label(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, 24) : null;
}

function qualityLabel(value: unknown): string | null {
  if (typeof value === "string") return label(value);
  if (!value || typeof value !== "object") return null;
  return label((value as Record<string, unknown>).label);
}

function qualityList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(qualityLabel).filter((item): item is string => Boolean(item)))].slice(0, 12);
}

/* ------------------------------------------------------------------ *
 * Hook
 * ------------------------------------------------------------------ */

export function useVidSrcBridge(
  frameRef: RefObject<HTMLIFrameElement | null>,
  /** Changing this drops all state — pass the embed URL. */
  resetKey: string,
  enabled = true,
): [VidSrcBridgeState, VidSrcRemote] {
  const [state, setState] = useState<VidSrcBridgeState>(IDLE);

  /**
   * Wall-clock anchor for interpolation. The player only reports progress
   * every 5 seconds; without this the scrub bar would jump in 5s steps.
   */
  const anchor = useRef<{ at: number; position: number } | null>(null);
  const positionRef = useRef(0);
  const durationRef = useRef(0);

  useEffect(() => {
    positionRef.current = state.position;
    durationRef.current = state.duration;
  }, [state.position, state.duration]);

  useEffect(() => {
    setState(IDLE);
    anchor.current = null;
    positionRef.current = 0;
  }, [resetKey]);

  const send = useCallback(
    (message: Record<string, unknown>) => {
      const target = frameRef.current?.contentWindow;
      if (!target) return;
      // "*" is unavoidable: vidsrc.me redirects to another host, so the frame's
      // real origin is not knowable from here. The payload is only ever a
      // playback command — nothing sensitive crosses.
      try {
        target.postMessage(message, "*");
      } catch {
        /* Frame torn down mid-command. */
      }
    },
    [frameRef],
  );

  /* ------------------------------ inbound ------------------------------ */

  useEffect(() => {
    if (!enabled) return;

    const onMessage = (event: MessageEvent) => {
      // Trust is established by identity, not by origin: accept only the frame
      // this component mounted, and only ever read data off it.
      const frame = frameRef.current;
      if (!frame || !event.source || event.source !== frame.contentWindow) return;

      let payload: unknown = event.data;
      if (typeof payload === "string") {
        try {
          payload = JSON.parse(payload);
        } catch {
          return;
        }
      }
      if (!payload || typeof payload !== "object") return;
      const message = payload as Record<string, unknown>;

      switch (message.type) {
        // Mirrors the mirror's own bar: it shows on a title//TV payload and
        // hides only when the player says its chrome went away.
        case "PLAYER_TITLE":
        case "TV_INFO":
          setState((current) => ({ ...current, barVisible: true }));
          return;

        case "PLAYER_UI": {
          const visible = message.visible === true;
          setState((current) => ({ ...current, chromeVisible: visible, barVisible: visible }));
          return;
        }

        case "PLAYER_EVENT": {
          const data = message.data as Record<string, unknown> | undefined;
          if (!data || typeof data !== "object") return;

          const status = label(data.player_status);
          const position = seconds(data.player_progress);
          const duration = seconds(data.player_duration);
          const quality = qualityLabel(data.quality);
          const availableQualities = qualityList(data.availableQualities);

          if (position != null) anchor.current = { at: Date.now(), position };

          setState((current) => ({
            ...current,
            connected: true,
            // "seeked" says nothing about whether playback resumed, so it
            // leaves the play/pause state exactly as it was.
            playing:
              status === "playing"
                ? true
                : status === "paused" || status === "completed"
                  ? false
                  : current.playing,
            position: position ?? current.position,
            duration: duration && duration > 0 ? duration : current.duration,
            quality: quality ?? current.quality,
            availableQualities: availableQualities.length ? availableQualities : current.availableQualities,
          }));
          return;
        }

        default:
          return;
      }
    };

    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [enabled, frameRef]);

  /* --------------------------- interpolation --------------------------- */

  useEffect(() => {
    if (!state.playing || state.duration <= 0) return;
    const timer = window.setInterval(() => {
      const base = anchor.current;
      if (!base) return;
      setState((current) => {
        if (!current.playing) return current;
        const next = Math.min(base.position + (Date.now() - base.at) / 1000, current.duration);
        // Skip no-op renders; the bar only needs ~4 updates a second.
        return Math.abs(next - current.position) < 0.2 ? current : { ...current, position: next };
      });
    }, 250);
    return () => window.clearInterval(timer);
  }, [state.playing, state.duration]);

  /* ----------------------- chrome flags are a lease -------------------- *
   * The player announces its chrome appearing reliably, but "gone" only
   * arrives when it auto-hides — never if a menu swallows the event or the
   * frame is torn down mid-animation. A mask driven off a stuck flag would
   * sit over the picture indefinitely, which is worse than the bar it hides,
   * so every "visible" claim expires on its own. Anything still on screen
   * after that window is behind our paused overlay anyway.
   * --------------------------------------------------------------------- */

  useEffect(() => {
    if (!state.barVisible && !state.chromeVisible) return;
    const timer = window.setTimeout(
      () => setState((current) => ({ ...current, barVisible: false, chromeVisible: false })),
      5000,
    );
    return () => window.clearTimeout(timer);
  }, [state.barVisible, state.chromeVisible]);

  /* ----------------------------- outbound ----------------------------- */

  const remote = useMemo<VidSrcRemote>(() => {
    const mark = (position: number) => {
      anchor.current = { at: Date.now(), position };
      positionRef.current = position;
    };

    return {
      play() {
        send({ player: true, action: "play" });
        mark(positionRef.current);
        setState((current) => ({ ...current, playing: true }));
      },
      pause() {
        send({ player: true, action: "pause" });
        mark(positionRef.current);
        setState((current) => ({ ...current, playing: false }));
      },
      setMuted(next) {
        send({ player: true, action: next ? "mute" : "unmute" });
        setState((current) => ({ ...current, muted: next }));
      },
      seekTo(value) {
        const target = Math.max(0, Math.round(value));
        send({ player: true, action: `seek${target}` });
        mark(target);
        setState((current) => ({ ...current, position: target }));
      },
      seekBy(delta) {
        const step = Math.round(delta);
        if (!step) return;
        send({ player: true, action: `seek${step > 0 ? "+" : "-"}${Math.abs(step)}` });
        const total = durationRef.current;
        const next = Math.max(
          0,
          total > 0 ? Math.min(positionRef.current + step, total) : positionRef.current + step,
        );
        mark(next);
        setState((current) => ({ ...current, position: next }));
      },
      setQuality(height) {
        // The relay forwards this request to compatible mirrors. The current
        // VidSrc player still reports the real selected level, so the UI never
        // claims a resolution changed unless PLAYER_EVENT confirms it.
        send({ player: true, action: `quality${height}`, quality: height });
      },
    };
  }, [send]);

  return [state, remote];
}
