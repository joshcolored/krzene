import Link from "next/link";

export function LegalPage({ title, updated = "August 27, 2026", children }: { title: string; updated?: string; children: React.ReactNode }) {
  return (
    <main className="min-h-dvh bg-[#070707] px-5 py-[max(40px,env(safe-area-inset-top))] text-[#f3f0eb]">
      <article className="mx-auto max-w-[760px]">
        <Link href="/" className="mb-10 inline-flex items-center gap-3 text-sm font-bold text-[#aaa59e] transition hover:text-white">
          <span aria-hidden="true">←</span><span>Back to Krzene</span>
        </Link>
        <p className="text-[10px] font-extrabold tracking-[.16em] text-[#47c98d] uppercase">Krzene</p>
        <h1 className="mt-3 font-display text-[clamp(38px,7vw,62px)] leading-none font-extrabold tracking-[-.05em]">{title}</h1>
        <p className="mt-4 border-b border-white/9 pb-8 text-xs text-[#77736e]">Last updated: {updated}</p>
        <div className="legal-copy space-y-8 py-9 text-[15px] leading-[1.8] text-[#b9b4ad] [&_a]:text-[#7ed9ac] [&_h2]:mb-3 [&_h2]:font-display [&_h2]:text-xl [&_h2]:font-bold [&_h2]:text-white [&_li]:ml-5 [&_li]:list-disc [&_p]:m-0">
          {children}
        </div>
      </article>
    </main>
  );
}
