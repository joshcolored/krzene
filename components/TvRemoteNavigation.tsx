"use client";

import { useEffect } from "react";

const FOCUSABLE = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(",");

type Direction = "left" | "right" | "up" | "down";

function visible(element: HTMLElement) {
  const style = window.getComputedStyle(element);
  const rect = element.getBoundingClientRect();
  return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
}

function focusScope(): ParentNode {
  const dialogs = Array.from(document.querySelectorAll<HTMLElement>("[role='dialog'][aria-modal='true']"))
    .filter(visible);
  return dialogs.at(-1) ?? document;
}

function candidates(): HTMLElement[] {
  return Array.from(focusScope().querySelectorAll<HTMLElement>(FOCUSABLE)).filter(visible);
}

function center(element: HTMLElement) {
  const rect = element.getBoundingClientRect();
  return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
}

function nextInDirection(current: HTMLElement, direction: Direction, options: HTMLElement[]) {
  const from = center(current);
  let best: { element: HTMLElement; score: number } | null = null;

  for (const element of options) {
    if (element === current) continue;
    const to = center(element);
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const primary = direction === "left" ? -dx : direction === "right" ? dx : direction === "up" ? -dy : dy;
    if (primary <= 6) continue;

    const secondary = direction === "left" || direction === "right" ? Math.abs(dy) : Math.abs(dx);
    // Strongly prefer items in the same row/column, while still allowing the
    // remote to cross uneven card grids and responsive layouts.
    const score = primary + secondary * 2.2;
    if (!best || score < best.score) best = { element, score };
  }

  return best?.element ?? null;
}

/**
 * Adds browser-independent D-pad navigation for TV browsers and PWA installs.
 * It is deliberately global so profile dialogs, the catalog, and the watch
 * page all follow the same focus behavior.
 */
export function TvRemoteNavigation() {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const direction: Direction | null =
        event.key === "ArrowLeft" ? "left" :
          event.key === "ArrowRight" ? "right" :
            event.key === "ArrowUp" ? "up" :
              event.key === "ArrowDown" ? "down" : null;
      if (!direction) return;

      const active = document.activeElement as HTMLElement | null;
      if (active?.matches("input, textarea, select, [contenteditable='true']")) return;

      const options = candidates();
      if (!options.length) return;
      const current = active && options.includes(active) ? active : null;
      const target = current ? nextInDirection(current, direction, options) : options[0];
      if (!target) return;

      event.preventDefault();
      document.documentElement.classList.add("tv-navigation-active");
      target.focus({ preventScroll: true });
      target.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "nearest" });
    };

    const onPointerDown = () => document.documentElement.classList.remove("tv-navigation-active");
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("pointerdown", onPointerDown, { passive: true });
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("pointerdown", onPointerDown);
      document.documentElement.classList.remove("tv-navigation-active");
    };
  }, []);

  return null;
}
