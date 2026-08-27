"use client";

import { useCallback, useEffect, useState } from "react";

const STORAGE_KEY = "krzene-catalog-sponsor-next-at";
const CLOSE_DELAY_SECONDS = 5;
const MINIMUM_DELAY_MS = 5 * 60 * 1000;
const RANDOM_EXTRA_DELAY_MS = 3 * 60 * 1000;

function nextDelay(): number {
  return MINIMUM_DELAY_MS + Math.floor(Math.random() * (RANDOM_EXTRA_DELAY_MS + 1));
}

function saveNextOpening(): void {
  window.sessionStorage.setItem(STORAGE_KEY, String(Date.now() + nextDelay()));
}

export function CatalogSponsorModal({
  enabled,
  onOpenPremium,
}: {
  enabled: boolean;
  onOpenPremium: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [secondsUntilClose, setSecondsUntilClose] = useState(CLOSE_DELAY_SECONDS);

  const sponsorUrl = process.env.NEXT_PUBLIC_CATALOG_SPONSOR_URL?.trim();
  const sponsorImage = process.env.NEXT_PUBLIC_CATALOG_SPONSOR_IMAGE_URL?.trim();
  const isDirectSponsor = Boolean(sponsorUrl);
  const title = process.env.NEXT_PUBLIC_CATALOG_SPONSOR_TITLE?.trim()
    || (isDirectSponsor ? "A message from our sponsor" : "Enjoy Krzene without catalog ads");
  const description = process.env.NEXT_PUBLIC_CATALOG_SPONSOR_DESCRIPTION?.trim()
    || (isDirectSponsor
      ? "Discover this offer from a Krzene sponsor."
      : "Get 30 days of Premium for PHP 50 and remove Krzene display ads from every standard profile.");
  const ctaLabel = process.env.NEXT_PUBLIC_CATALOG_SPONSOR_CTA?.trim()
    || (isDirectSponsor ? "Visit sponsor" : "See Premium");

  const dismiss = useCallback(() => {
    saveNextOpening();
    setOpen(false);
  }, []);

  useEffect(() => {
    if (!enabled || open) return;

    const stored = Number(window.sessionStorage.getItem(STORAGE_KEY));
    const nextAt = Number.isFinite(stored) && stored > 0 ? stored : Date.now() + nextDelay();
    if (nextAt !== stored) window.sessionStorage.setItem(STORAGE_KEY, String(nextAt));

    const delay = nextAt - Date.now();
    if (delay <= 0) {
      setOpen(true);
      return;
    }

    const timer = window.setTimeout(() => setOpen(true), delay);
    return () => window.clearTimeout(timer);
  }, [enabled, open]);

  useEffect(() => {
    if (enabled || !open) return;
    setOpen(false);
  }, [enabled, open]);

  useEffect(() => {
    if (!open) return;
    const unlockAt = Date.now() + CLOSE_DELAY_SECONDS * 1000;
    setSecondsUntilClose(CLOSE_DELAY_SECONDS);

    const updateCountdown = () => {
      setSecondsUntilClose(Math.max(0, Math.ceil((unlockAt - Date.now()) / 1000)));
    };
    const timer = window.setInterval(updateCountdown, 250);
    updateCountdown();
    return () => window.clearInterval(timer);
  }, [open]);

  useEffect(() => {
    if (!open || secondsUntilClose > 0) return;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") dismiss();
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [dismiss, open, secondsUntilClose]);

  if (!enabled || !open) return null;

  const closeReady = secondsUntilClose === 0;
  const openPremium = () => {
    dismiss();
    onOpenPremium();
  };

  return (
    <div
      className="ui-modal-enter fixed inset-0 z-100 flex min-h-dvh items-center justify-center bg-black/80 px-5 py-[max(40px,env(safe-area-inset-top,0px))] backdrop-blur-xl"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && closeReady) dismiss();
      }}
    >
      <section
        className="ui-modal-panel-enter relative w-full max-w-[480px] overflow-hidden rounded-[24px] border border-white/10 bg-[linear-gradient(145deg,#191919,#0b0b0b)] shadow-[0_35px_110px_rgba(0,0,0,.82)] max-[560px]:rounded-[20px]"
        role="dialog"
        aria-modal="true"
        aria-labelledby="catalog-sponsor-title"
        aria-describedby="catalog-sponsor-description"
      >
        {sponsorImage && (
          <div className="aspect-[16/7] overflow-hidden border-b border-white/8 bg-[#121212]">
            <img className="h-full w-full object-cover" src={sponsorImage} alt="" />
          </div>
        )}

        <button
          type="button"
          className="absolute top-4 right-4 flex h-10 min-w-10 items-center justify-center rounded-full border border-white/10 bg-black/70 px-3 text-xs font-bold text-[#d6d2cc] backdrop-blur-lg transition enabled:cursor-pointer enabled:hover:bg-white enabled:hover:text-black disabled:cursor-not-allowed disabled:text-[#85817b]"
          onClick={dismiss}
          disabled={!closeReady}
          aria-label={closeReady ? "Close promotion" : `Close available in ${secondsUntilClose} seconds`}
        >
          {closeReady ? (
            <svg className="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18" /></svg>
          ) : (
            <span aria-live="polite">{secondsUntilClose}s</span>
          )}
        </button>

        <div className="p-8 max-[560px]:px-5 max-[560px]:py-7">
          <span className="inline-flex rounded-full border border-white/10 bg-white/6 px-3 py-1 text-[10px] font-extrabold tracking-[.14em] text-[#a8a39c] uppercase">
            {isDirectSponsor ? "Sponsored" : "Krzene Premium"}
          </span>
          <h2 id="catalog-sponsor-title" className="mt-5 max-w-[390px] font-display text-[31px] leading-[1.05] font-extrabold tracking-[-.04em] max-[560px]:text-[28px]">{title}</h2>
          <p id="catalog-sponsor-description" className="mt-3 max-w-[400px] text-sm leading-relaxed text-[#9b968f]">{description}</p>

          {isDirectSponsor ? (
            <a
              className="mt-7 flex min-h-[52px] w-full items-center justify-center rounded-xl bg-[#f5f3ef] px-5 text-sm font-extrabold text-[#101010] transition hover:bg-white active:scale-[.985]"
              href={sponsorUrl}
              target="_blank"
              rel="noopener sponsored"
              onClick={dismiss}
            >
              {ctaLabel}
            </a>
          ) : (
            <button
              type="button"
              className="mt-7 flex min-h-[52px] w-full cursor-pointer items-center justify-center rounded-xl border-0 bg-[#f5f3ef] px-5 text-sm font-extrabold text-[#101010] transition hover:bg-white active:scale-[.985]"
              onClick={openPremium}
            >
              {ctaLabel}
            </button>
          )}
          <p className="mt-4 text-center text-[10px] leading-relaxed text-[#625f5a]">
            This catalog promotion never appears during playback. Premium and Kids profiles do not see it.
          </p>
        </div>
      </section>
    </div>
  );
}
