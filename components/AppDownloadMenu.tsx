"use client";

import { useEffect, useRef } from "react";

export function AppDownloadMenu({ mobile = false }: { mobile?: boolean }) {
  const menu = useRef<HTMLDetailsElement>(null);

  useEffect(() => {
    const dismiss = (event: PointerEvent) => {
      if (event.target instanceof Node && !menu.current?.contains(event.target)) {
        menu.current?.removeAttribute("open");
      }
    };
    document.addEventListener("pointerdown", dismiss);
    return () => document.removeEventListener("pointerdown", dismiss);
  }, []);

  return (
    <details
      ref={menu}
      className={mobile ? "group relative" : "group relative max-[760px]:hidden"}
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          menu.current?.removeAttribute("open");
          menu.current?.querySelector("summary")?.focus();
        }
      }}
      onBlur={(event) => {
        // Touch browsers can blur the summary with no next focus target before
        // dispatching the link's click. Keep it visible until that tap completes.
        // Outside taps are handled separately by the pointerdown listener.
        if (event.relatedTarget && !event.currentTarget.contains(event.relatedTarget)) {
          menu.current?.removeAttribute("open");
        }
      }}
    >
      <summary className={`flex cursor-pointer list-none items-center gap-2 rounded-xl text-xs font-bold text-[#aaa6a0] transition hover:bg-white/8 hover:text-white focus-visible:outline-2 focus-visible:outline-white [&::-webkit-details-marker]:hidden ${mobile ? "border border-white/8 bg-white/5 px-2.5 py-2.5" : "h-10 px-2"}`}>
        <svg className="h-5 w-5 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M12 3.5v11M7.8 10.5 12 14.7l4.2-4.2M5 16.5v3h14v-3" />
        </svg>
        <span className="flex-1">Get app</span>
        <svg className="h-3 w-3 transition group-open:rotate-180" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="m3 4.5 3 3 3-3" /></svg>
      </summary>
      <div className={`rounded-xl border border-white/10 bg-[#171717] p-1.5 shadow-xl ${mobile ? "mt-1" : "absolute right-0 top-[calc(100%_+_8px)] z-50 w-48"}`}>
        <a className="flex min-h-11 items-center gap-3 rounded-lg px-3 py-2 text-sm font-bold text-white hover:bg-white/10 focus-visible:bg-white/10" href="https://drive.google.com/file/d/1t5pi-N9qajckfxnMQtmOBFFTep48H95O/view?usp=sharing">
          <svg className="h-5 w-5 shrink-0 text-[#3ddc84]" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="m17.6 9.48 1.84-3.18a.38.38 0 0 0-.66-.38l-1.87 3.23A11.4 11.4 0 0 0 12 8.09c-1.76 0-3.42.38-4.91 1.06L5.22 5.92a.38.38 0 0 0-.66.38L6.4 9.48C3.24 11.2 1.08 14.41.76 18.18h22.48c-.32-3.77-2.48-6.98-5.64-8.7ZM6.87 15.3a.94.94 0 1 1 0-1.88.94.94 0 0 1 0 1.88Zm10.26 0a.94.94 0 1 1 0-1.88.94.94 0 0 1 0 1.88Z" />
          </svg>
          Android
        </a>
        <a className="flex min-h-11 items-center gap-3 rounded-lg px-3 py-2 text-sm font-bold text-white hover:bg-white/10 focus-visible:bg-white/10" href="https://testflight.apple.com/join/ZWXbXR8M">
          <svg className="h-5 w-5 shrink-0" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M17.05 12.54c.03 3.21 2.82 4.28 2.85 4.29-.02.08-.45 1.53-1.47 3.02-.88 1.29-1.79 2.58-3.23 2.61-1.41.03-1.86-.84-3.47-.84-1.61 0-2.11.81-3.44.87-1.39.05-2.45-1.4-3.34-2.69-1.82-2.64-3.21-7.45-1.34-10.7a5.2 5.2 0 0 1 4.4-2.67c1.37-.03 2.67.92 3.51.92.84 0 2.42-1.14 4.07-.97.69.03 2.64.28 3.89 2.11-.1.06-2.46 1.43-2.43 4.05ZM14.4 4.62c.74-.89 1.24-2.12 1.1-3.35-1.06.04-2.35.71-3.11 1.61-.68.78-1.28 2.03-1.12 3.23 1.18.09 2.39-.6 3.13-1.49Z" />
          </svg>
          iOS · TestFlight
        </a>
      </div>
    </details>
  );
}
