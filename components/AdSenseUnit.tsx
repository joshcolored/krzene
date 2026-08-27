"use client";

import { useEffect, useRef } from "react";

declare global {
  interface Window {
    adsbygoogle?: Record<string, unknown>[];
  }
}

export function AdSenseUnit({ slot, enabled }: { slot?: string; enabled: boolean }) {
  const pushed = useRef(false);
  const client = process.env.NEXT_PUBLIC_ADSENSE_CLIENT_ID?.trim();

  useEffect(() => {
    if (!enabled || !client || !slot) return;
    const scriptId = "krzene-adsense-script";
    let script = document.getElementById(scriptId) as HTMLScriptElement | null;
    if (!script) {
      script = document.createElement("script");
      script.id = scriptId;
      script.async = true;
      script.crossOrigin = "anonymous";
      script.src = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${encodeURIComponent(client)}`;
      document.head.appendChild(script);
    }

    const showAd = () => {
      if (pushed.current) return;
      try {
        (window.adsbygoogle = window.adsbygoogle || []).push({});
        pushed.current = true;
      } catch {
        // Ad blockers and unfilled inventory are normal and should not affect the catalog.
      }
    };
    if (script.dataset.loaded === "true") showAd();
    else script.addEventListener("load", () => {
      script!.dataset.loaded = "true";
      showAd();
    }, { once: true });
  }, [client, enabled, slot]);

  if (!enabled || !client || !slot) return null;
  return (
    <aside className="my-14 overflow-hidden rounded-2xl border border-white/6 bg-white/[.015] px-3 py-4 text-center max-[760px]:my-10" aria-label="Advertisement">
      <span className="mb-2 block text-[9px] font-bold tracking-[.16em] text-[#55514d] uppercase">Advertisement</span>
      <ins
        className="adsbygoogle block min-h-[90px]"
        data-ad-client={client}
        data-ad-slot={slot}
        data-ad-format="auto"
        data-full-width-responsive="true"
      />
    </aside>
  );
}
