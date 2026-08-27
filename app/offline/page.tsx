import Link from "next/link";

export default function OfflinePage() {
  return (
    <main className="flex min-h-dvh items-center justify-center bg-[#070707] px-5 text-center text-white">
      <section className="w-full max-w-[430px] rounded-[24px] border border-white/10 bg-[#111] px-7 py-10 shadow-[0_30px_100px_#000]">
        <img className="mx-auto h-16 w-16 rounded-[18px]" src="/krzene-mark.svg" alt="" />
        <h1 className="mt-7 font-display text-3xl font-extrabold tracking-[-.04em]">You’re offline</h1>
        <p className="mt-3 text-sm leading-relaxed text-[#99958f]">
          Reconnect to browse the catalog or start playback. Previously loaded app screens remain available.
        </p>
        <Link className="mt-7 inline-flex min-h-12 items-center justify-center rounded-xl bg-white px-6 font-extrabold text-black" href="/">
          Try again
        </Link>
      </section>
    </main>
  );
}
