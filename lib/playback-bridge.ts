"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type RefObject,
} from "react";

export type PlaybackBridgeState = {
  connected: boolean;
  playing: boolean;
  buffering: boolean;
  position: number;
  duration: number;
  muted: boolean;
  playbackRate: number;
  volume: number;
  chromeVisible: boolean;
  barVisible: boolean;
};

export type PlaybackRemote = {
  play(): void;
  pause(): void;
  setMuted(next: boolean): void;
  setVolume(next: number): void;
  setPlaybackRate(next: number): void;
  seekTo(seconds: number): void;
  seekBy(delta: number): void;
};

const IDLE: PlaybackBridgeState = {
  connected: false,
  playing: false,
  buffering: true,
  position: 0,
  duration: 0,
  muted: false,
  playbackRate: 1,
  volume: 1,
  chromeVisible: false,
  barVisible: false,
};

function seconds(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

/** CineSrc's documented postMessage bridge with optimistic, stale-safe seek. */
export function usePlaybackBridge(
  frameRef: RefObject<HTMLIFrameElement | null>,
  resetKey: string,
  enabled = true,
): [PlaybackBridgeState, PlaybackRemote] {
  const [state, setState] = useState<PlaybackBridgeState>(IDLE);
  const anchor = useRef<{ at: number; position: number } | null>(null);
  const positionRef = useRef(0);
  const durationRef = useRef(0);
  const pendingSeek = useRef<{ target: number; at: number } | null>(null);
  const seekTimer = useRef<number | null>(null);

  useEffect(() => {
    positionRef.current = state.position;
    durationRef.current = state.duration;
  }, [state.duration, state.position]);

  useEffect(() => {
    setState(IDLE);
    anchor.current = null;
    positionRef.current = 0;
    pendingSeek.current = null;
    if (seekTimer.current != null) window.clearTimeout(seekTimer.current);
    seekTimer.current = null;
  }, [resetKey]);

  useEffect(
    () => () => {
      if (seekTimer.current != null) window.clearTimeout(seekTimer.current);
    },
    [],
  );

  const sendCommand = useCallback(
    (command: string, args: unknown[] = []) => {
      const target = frameRef.current?.contentWindow;
      if (!target || !enabled) return;
      try {
        target.postMessage(
          { type: "cinesrc:command", command, args },
          "https://cinesrc.st",
        );
      } catch {
        // The frame may be between source navigations.
      }
    },
    [enabled, frameRef],
  );

  const clearPendingSeek = useCallback(() => {
    pendingSeek.current = null;
    if (seekTimer.current != null) window.clearTimeout(seekTimer.current);
    seekTimer.current = null;
  }, []);

  useEffect(() => {
    if (!enabled) return;
    const onMessage = (event: MessageEvent) => {
      const frame = frameRef.current;
      if (
        !frame?.contentWindow ||
        event.source !== frame.contentWindow ||
        event.origin !== "https://cinesrc.st"
      ) {
        return;
      }
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
      const type = typeof message.type === "string" ? message.type : "";
      if (!type.startsWith("cinesrc:")) return;

      const reportedPosition = seconds(message.currentTime);
      const reportedDuration = seconds(message.duration);
      let acceptedPosition = reportedPosition;
      const waiting = pendingSeek.current;
      if (reportedPosition != null && waiting) {
        const reached = Math.abs(reportedPosition - waiting.target) <= 2;
        const expired = Date.now() - waiting.at >= 5000;
        if (type === "cinesrc:seeked" || reached || expired) {
          clearPendingSeek();
        } else {
          acceptedPosition = null;
        }
      }
      if (acceptedPosition != null) {
        anchor.current = { at: Date.now(), position: acceptedPosition };
        positionRef.current = acceptedPosition;
      }
      if (reportedDuration != null && reportedDuration > 0) {
        durationRef.current = reportedDuration;
      }

      setState((current) => {
        const next: PlaybackBridgeState = {
          ...current,
          connected: type !== "cinesrc:error",
          position: acceptedPosition ?? current.position,
          duration:
            reportedDuration != null && reportedDuration > 0
              ? reportedDuration
              : current.duration,
        };
        switch (type) {
          case "cinesrc:ready":
          case "cinesrc:loadedmetadata":
            next.connected = true;
            next.buffering = false;
            break;
          case "cinesrc:play":
            next.playing = true;
            next.buffering = false;
            break;
          case "cinesrc:pause":
          case "cinesrc:ended":
            next.playing = false;
            next.buffering = false;
            break;
          case "cinesrc:seeking":
            next.buffering = true;
            break;
          case "cinesrc:seeked":
            next.buffering = false;
            break;
          case "cinesrc:timeupdate":
            if (!pendingSeek.current) next.buffering = false;
            break;
          case "cinesrc:volumechange":
            next.muted = message.muted === true;
            next.volume = seconds(message.volume) ?? current.volume;
            break;
          case "cinesrc:ratechange":
            next.playbackRate =
              seconds(message.playbackRate) ?? current.playbackRate;
            break;
          case "cinesrc:error":
            next.connected = false;
            next.buffering = false;
            break;
        }
        return next;
      });
    };

    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [clearPendingSeek, enabled, frameRef]);

  useEffect(() => {
    if (!state.playing || state.duration <= 0 || state.buffering) return;
    const timer = window.setInterval(() => {
      const base = anchor.current;
      if (!base || pendingSeek.current) return;
      setState((current) => {
        if (!current.playing || current.buffering) return current;
        const next = Math.min(
          base.position +
            ((Date.now() - base.at) / 1000) * current.playbackRate,
          current.duration,
        );
        return Math.abs(next - current.position) < 0.2
          ? current
          : { ...current, position: next };
      });
    }, 250);
    return () => window.clearInterval(timer);
  }, [state.buffering, state.duration, state.playbackRate, state.playing]);

  const remote = useMemo<PlaybackRemote>(() => {
    const markSeek = (target: number) => {
      pendingSeek.current = { target, at: Date.now() };
      anchor.current = { at: Date.now(), position: target };
      positionRef.current = target;
      if (seekTimer.current != null) window.clearTimeout(seekTimer.current);
      seekTimer.current = window.setTimeout(() => {
        clearPendingSeek();
        setState((current) => ({ ...current, buffering: false }));
      }, 5000);
      setState((current) => ({ ...current, position: target, buffering: true }));
    };

    return {
      play() {
        sendCommand("play");
        anchor.current = { at: Date.now(), position: positionRef.current };
        setState((current) => ({ ...current, playing: true }));
      },
      pause() {
        sendCommand("pause");
        setState((current) => ({ ...current, playing: false }));
      },
      setMuted(next) {
        sendCommand("setMuted", [next]);
        setState((current) => ({ ...current, muted: next }));
      },
      setVolume(next) {
        const volume = Math.max(0, Math.min(1, next));
        sendCommand("setVolume", [volume]);
        setState((current) => ({ ...current, volume }));
      },
      setPlaybackRate(next) {
        const rate = Math.max(0.25, Math.min(2, next));
        sendCommand("setPlaybackRate", [rate]);
        setState((current) => ({ ...current, playbackRate: rate }));
      },
      seekTo(value) {
        const total = durationRef.current;
        const target = Math.max(0, total > 0 ? Math.min(value, total) : value);
        markSeek(target);
        sendCommand("seek", [target]);
      },
      seekBy(delta) {
        const total = durationRef.current;
        const target = Math.max(
          0,
          total > 0
            ? Math.min(positionRef.current + delta, total)
            : positionRef.current + delta,
        );
        markSeek(target);
        sendCommand("seek", [target]);
      },
    };
  }, [clearPendingSeek, sendCommand]);

  return [state, remote];
}
