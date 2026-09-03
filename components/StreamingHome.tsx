"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  isKidsMedia,
  watchHref,
  type HomeData,
  type Media,
  type MediaDetail,
  type MediaRail,
} from "@/lib/media";
import { CATALOG_LOCALES, catalogLocale } from "@/lib/catalog-locale";
import { AdSenseUnit } from "./AdSenseUnit";
import { useAuth, type ContinueWatchingItem } from "./AuthProvider";
import { CatalogSponsorModal } from "./CatalogSponsorModal";
import { ProfileChooser } from "./ProfileChooser";
import { AuthDialog } from "./AuthDialog";

const NAV_ITEMS = ["Home", "Movies", "Shows", "Anime", "Library"] as const;
type NavItem = (typeof NAV_ITEMS)[number];

type IconName =
  | "home"
  | "movie"
  | "shows"
  | "anime"
  | "library"
  | "search"
  | "language"
  | "menu"
  | "chevron-left"
  | "chevron-right"
  | "play"
  | "check"
  | "plus";

const NAV_ICONS: Record<NavItem, IconName> = {
  Home: "home",
  Movies: "movie",
  Shows: "shows",
  Anime: "anime",
  Library: "library",
};

function UiIcon({ name }: { name: IconName }) {
  const common = {
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
  };

  return (
    <svg
      className="block h-[1.15em] w-[1.15em]"
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
      {...common}
    >
      {name === "home" && (
        <>
          <path d="M3.5 10.5 12 3.8l8.5 6.7" />
          <path d="M5.7 9.2v10.5h12.6V9.2M9.3 19.7v-6h5.4v6" />
        </>
      )}
      {name === "movie" && (
        <>
          <rect x="3.5" y="6.5" width="17" height="13" rx="2" />
          <path d="m4.5 10 4-3.5m2.5 3.5 4-3.5m2.5 3.5 3-2.6M3.5 10h17" />
        </>
      )}
      {name === "shows" && (
        <>
          <rect x="3.5" y="5" width="17" height="14" rx="2" />
          <path d="m9.5 9 6 3-6 3V9Z" />
        </>
      )}
      {name === "anime" && (
        <>
          <path d="M12 3.5 14.3 8l5 .7-3.6 3.5.8 5-4.5-2.4-4.5 2.4.8-5-3.6-3.5 5-.7L12 3.5Z" />
          <path d="M9.4 11.2h.1m5 0h.1M10 13.6c1.2.8 2.8.8 4 0" />
        </>
      )}
      {name === "library" && (
        <>
          <rect x="4" y="4" width="5" height="16" rx="1" />
          <rect x="10.2" y="4" width="4.8" height="16" rx="1" />
          <path d="m16.3 5.1 3.2-.8 2.8 14.3-3.2.7-2.8-14.2Z" />
        </>
      )}
      {name === "search" && (
        <>
          <circle cx="10.5" cy="10.5" r="6.5" />
          <path d="m15.4 15.4 4.6 4.6" />
        </>
      )}
      {name === "language" && (
        <>
          <circle cx="12" cy="12" r="8.5" />
          <path d="M3.8 12h16.4M12 3.5c2.2 2.3 3.3 5.1 3.3 8.5S14.2 18.2 12 20.5M12 3.5C9.8 5.8 8.7 8.6 8.7 12s1.1 6.2 3.3 8.5" />
        </>
      )}
      {name === "menu" && (
        <>
          <path d="M5 7h14M5 12h14M5 17h14" />
        </>
      )}
      {name === "chevron-left" && <path d="m14.5 6-6 6 6 6" />}
      {name === "chevron-right" && <path d="m9.5 6 6 6-6 6" />}
      {name === "play" && <path d="m8.5 6 9 6-9 6V6Z" />}
      {name === "check" && <path d="m5 12.5 4.2 4.2L19 7" />}
      {name === "plus" && <path d="M12 5v14M5 12h14" />}
    </svg>
  );
}

function artFor(media: Media): string | null {
  return media.backdrop ?? media.poster;
}

function subtitleFor(media: Media): string {
  const kindLabel = media.kind === "tv" ? "Series" : "Film";
  return [media.year ? String(media.year) : null, media.genres[0] ?? kindLabel]
    .filter(Boolean)
    .join(" • ");
}

function clockLabel(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  const secs = whole % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`
    : `${minutes}:${String(secs).padStart(2, "0")}`;
}

function ContinueWatchingRail({
  items,
  profileName,
  className = "",
}: {
  items: ContinueWatchingItem[];
  profileName: string;
  className?: string;
}) {
  if (!items.length) return null;

  return (
    <section className={`catalog-rail-reveal ${className}`}>
      <div className="mb-[19px] flex items-end justify-between">
        <div>
          <span className="text-[10px] font-extrabold tracking-[.13em] text-[#77736e]">
            FOR {profileName.toUpperCase()}
          </span>
          <h2 className="mt-[5px] font-display text-[22px] leading-[1.2] font-bold tracking-[-.025em]">
            Continue watching
          </h2>
        </div>
        <span className="text-[11px] font-bold text-[#6f6b66]">
          {items.length} saved
        </span>
      </div>
      <div className="media-rail flex snap-x snap-proximity gap-4 overflow-x-auto pb-[10px] max-[760px]:mr-[-20px] max-[760px]:pr-5">
        {items.map((item) => {
          const progress =
            item.duration > 0 ? Math.min(item.position / item.duration, 1) : 0;
          const resumeQuery = new URLSearchParams({
            t: String(Math.floor(item.position)),
          });
          if (item.season != null) resumeQuery.set("season", String(item.season));
          if (item.episode != null) resumeQuery.set("episode", String(item.episode));

          return (
            <Link
              key={item.media.key}
              href={`${watchHref(item.media)}?${resumeQuery.toString()}`}
              className="group min-w-0 shrink-0 basis-[calc((100%_-_64px)/5)] snap-start max-[1080px]:basis-[calc((100%_-_32px)/3)] max-[760px]:basis-[74vw]"
            >
              <span className="relative block aspect-[1.56] overflow-hidden rounded-[15px] border border-white/6 bg-[#171717]">
                {artFor(item.media) ? (
                  <img
                    className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-[1.055]"
                    src={artFor(item.media)!}
                    alt=""
                  />
                ) : (
                  <span className="flex h-full items-center justify-center text-[#77736e]">
                    {item.media.title}
                  </span>
                )}
                <span className="absolute inset-0 bg-[linear-gradient(0deg,rgba(0,0,0,.72),transparent_58%)]" />
                <span
                  className="absolute bottom-0 left-0 h-1 bg-krzene-red transition-all"
                  style={{ width: `${progress * 100}%` }}
                />
                <span className="absolute right-3 bottom-3 flex h-9 w-9 items-center justify-center rounded-full bg-white text-lg text-black shadow-lg transition group-hover:scale-105">
                  <UiIcon name="play" />
                </span>
              </span>
              <span className="flex min-w-0 flex-col px-1 pt-3">
                <b className="truncate text-sm">{item.media.title}</b>
                <small className="mt-1 text-[#77736e]">
                  {item.season != null && item.episode != null
                    ? `S${item.season} · E${item.episode} · `
                    : ""}
                  Resume at {clockLabel(item.position)}
                </small>
              </span>
            </Link>
          );
        })}
      </div>
    </section>
  );
}

function MediaCard({
  media,
  saved,
  canSave,
  onSave,
}: {
  media: Media;
  saved: boolean;
  canSave: boolean;
  onSave: () => void;
}) {
  const art = artFor(media);
  return (
    <article className="min-w-0 shrink-0 basis-[calc((100%_-_64px)/5)] snap-start max-[1080px]:basis-[calc((100%_-_32px)/3)] max-[760px]:basis-[74vw]">
      <Link
        href={watchHref(media)}
        className="group relative block aspect-[1.56] overflow-hidden rounded-[15px] border border-white/5 bg-[#171717] shadow-[0_18px_35px_rgba(0,0,0,.28)]"
        aria-label={`Watch ${media.title}`}
      >
        {art ? (
          <img
            className="h-full w-full object-cover transition-transform duration-500 ease-[cubic-bezier(.2,.8,.2,1)] group-hover:scale-[1.055]"
            src={art}
            alt=""
            loading="lazy"
          />
        ) : (
          <span className="flex h-full w-full items-center justify-center bg-[linear-gradient(140deg,#1d1d1d,#121212)] p-4 text-center font-display text-[13px] leading-[1.3] font-bold text-[#5f5c58]">
            {media.title}
          </span>
        )}
        <span className="absolute inset-0 bg-[linear-gradient(0deg,rgba(0,0,0,.72),transparent_56%)]" />
        <span className="absolute top-1/2 left-1/2 flex h-[42px] w-[42px] -translate-x-1/2 -translate-y-[40%] items-center justify-center rounded-full bg-white/90 text-xl text-[#0b0b0b] opacity-0 transition duration-250 group-hover:-translate-y-1/2 group-hover:opacity-100">
          <UiIcon name="play" />
        </span>
        <span className="absolute right-[10px] bottom-[10px] rounded-[5px] border border-white/18 bg-black/70 px-[5px] py-[3px] text-[9px] font-extrabold">
          {media.kind === "tv" ? "SERIES" : "HD"}
        </span>
        {media.score > 0 && (
          <span className="absolute bottom-[10px] left-[10px] rounded-[5px] border border-white/16 bg-black/72 px-[5px] py-[3px] text-[9px] font-extrabold">
            ★ {media.score.toFixed(1)}
          </span>
        )}
      </Link>
      <div className="flex w-full min-w-0 items-center justify-between gap-2 overflow-hidden px-[3px] pt-3">
        <div
          className={`min-w-0 overflow-hidden ${canSave ? "w-[calc(100%_-_37px)] flex-[0_1_calc(100%_-_37px)]" : "w-full flex-1"}`}
        >
          <h3
            className="block w-full max-w-full overflow-hidden text-sm font-bold text-ellipsis whitespace-nowrap"
            title={media.title}
          >
            {media.title}
          </h3>
          <p className="m-0 text-[11px] text-[#77746f]">{subtitleFor(media)}</p>
        </div>
        {canSave && (
          <button
            className={`ml-auto h-[29px] w-[29px] shrink-0 cursor-pointer rounded-full border border-[#343331] bg-transparent hover:bg-white hover:text-black ${saved ? "bg-white text-black" : ""}`}
            onClick={onSave}
            aria-label={
              saved
                ? `Remove ${media.title} from watchlist`
                : `Add ${media.title} to watchlist`
            }
          >
            <span className="flex items-center justify-center text-base">
              <UiIcon name={saved ? "check" : "plus"} />
            </span>
          </button>
        )}
      </div>
    </article>
  );
}

function Rail({
  rail,
  first,
  savedKeys,
  canSave,
  onSave,
}: {
  rail: MediaRail;
  first: boolean;
  savedKeys: Set<string>;
  canSave: boolean;
  onSave: (media: Media) => void;
}) {
  const railRef = useRef<HTMLDivElement>(null);
  const scrollRail = (direction: -1 | 1) => {
    const node = railRef.current;
    if (!node) return;
    node.scrollBy({
      left: direction * Math.max(node.clientWidth * 0.84, 280),
      behavior: "smooth",
    });
  };

  return (
    <section className={`catalog-rail-reveal ${first ? "pt-0" : "pt-[72px] max-[760px]:pt-[55px]"}`}>
      <div className="mb-[19px] flex items-end justify-between">
        <div>
          <span className="text-[10px] font-extrabold tracking-[.13em] text-[#77736e]">
            {rail.kicker}
          </span>
          <h2 className="mt-[5px] font-display text-[22px] leading-[1.2] font-bold tracking-[-.025em]">
            {rail.heading}
          </h2>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-[11px] font-bold whitespace-nowrap text-[#6f6b66]">
            {rail.items.length} titles
          </span>
          <div
            className="flex gap-[6px]"
            aria-label={`${rail.heading} carousel controls`}
          >
            <button
              type="button"
              className="flex h-8 w-8 cursor-pointer items-center justify-center rounded-full border border-white/9 bg-[#151515] p-0 text-[#aaa6a0] transition hover:border-[#f2f0ec] hover:bg-[#f2f0ec] hover:text-[#111]"
              onClick={() => scrollRail(-1)}
              aria-label={`Previous ${rail.heading} titles`}
            >
              <UiIcon name="chevron-left" />
            </button>
            <button
              type="button"
              className="flex h-8 w-8 cursor-pointer items-center justify-center rounded-full border border-white/9 bg-[#151515] p-0 text-[#aaa6a0] transition hover:border-[#f2f0ec] hover:bg-[#f2f0ec] hover:text-[#111]"
              onClick={() => scrollRail(1)}
              aria-label={`Next ${rail.heading} titles`}
            >
              <UiIcon name="chevron-right" />
            </button>
          </div>
        </div>
      </div>
      <div
        className="media-rail flex snap-x snap-proximity gap-4 overflow-x-auto overscroll-x-contain px-0 pt-[2px] pb-[10px] [scroll-padding-left:2px] max-[760px]:mr-[-20px] max-[760px]:pr-5"
        ref={railRef}
      >
        {rail.items.map((media) => (
          <MediaCard
            key={media.key}
            media={media}
            saved={savedKeys.has(media.key)}
            canSave={canSave}
            onSave={() => onSave(media)}
          />
        ))}
      </div>
    </section>
  );
}

function SetupNotice({ reason }: { reason: string }) {
  return (
    <main className="min-h-screen overflow-x-clip bg-krzene-bg text-krzene-text">
      <div className="flex min-h-screen items-center justify-center px-[22px] py-10">
        <div className="w-full max-w-[620px] rounded-[22px] border border-white/9 bg-[#101010] p-[38px] shadow-[0_40px_120px_#000] max-[760px]:px-[22px] max-[760px]:py-[26px]">
          <span className="mb-[22px] inline-flex h-[42px] w-[42px] overflow-hidden rounded-[14px]">
            <img className="h-full w-full" src="/krzene-mark.svg" alt="" />
          </span>
          <h1 className="mb-4 font-display text-[30px] leading-[1.15] font-extrabold tracking-[-.03em] max-[760px]:text-[25px]">
            Add a TMDB key to fill the catalog
          </h1>
          <p className="mb-[14px] text-sm leading-[1.7] text-[#a5a19b]">
            VidSrc streams the video, but its <code>vapi</code> listing
            endpoints are retired and return 404 on every mirror — so movie and
            show listings come from TMDB instead. Playback still runs through
            VidSrc&apos;s <code>embed</code> endpoints.
          </p>
          <p className="mb-[14px] text-xs leading-[1.7] text-[#e0a04a]">
            {reason}
          </p>
          <ol className="mt-[22px] list-decimal space-y-2.5 pl-5 text-sm leading-[1.8] text-[#cbc7c1]">
            <li>
              Grab a free key at <b>themoviedb.org → Settings → API</b>.
            </li>
            <li>
              Put it in{" "}
              <code className="rounded-[5px] bg-[#1d1d1d] px-1.5 py-0.5 text-xs text-[#f0ede8]">
                .env.local
              </code>{" "}
              at the project root:
              <pre className="mt-[9px] overflow-x-auto rounded-[9px] border border-white/9 bg-[#1a1a1a] px-[14px] py-3 text-xs">
                TMDB_API_KEY=your_key_here
              </pre>
            </li>
            <li>
              Restart the dev server: <code>npm run dev</code>
            </li>
          </ol>
          <p className="mt-[22px] text-xs leading-[1.7] text-[#6f6b66]">
            Either a v3 API key or a v4 read access token works.
          </p>
        </div>
      </div>
    </main>
  );
}

function CatalogHome({
  hero,
  rails,
  vidsrcMirror,
  localeCode,
}: {
  hero: MediaDetail;
  rails: MediaRail[];
  vidsrcMirror: string | null;
  localeCode: string;
}) {
  const [active, setActive] = useState<NavItem>("Home");
  const [query, setQuery] = useState("");
  const [showSearch, setShowSearch] = useState(false);
  const [showMobileMenu, setShowMobileMenu] = useState(false);
  const [heroIndex, setHeroIndex] = useState(0);
  const [watchingKey, setWatchingKey] = useState<string | null>(null);
  const [results, setResults] = useState<Media[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [showProfiles, setShowProfiles] = useState(false);
  const [showSignIn, setShowSignIn] = useState(false);
  const searchToken = useRef(0);
  const activeLocale = catalogLocale(localeCode);
  const {
    ready: authReady,
    user,
    activeProfile,
    library: savedItems,
    continueWatching,
    authError,
    passwordRecovery,
    toggleLibrary,
  } = useAuth();

  useEffect(() => {
    if (authReady && user && !activeProfile) setShowProfiles(true);
    if (user) setShowSignIn(false);
  }, [activeProfile, authReady, user]);

  const kidsMode = activeProfile?.isKids === true;
  const visibleSavedItems = useMemo(
    () => (kidsMode ? savedItems.filter(isKidsMedia) : savedItems),
    [kidsMode, savedItems],
  );
  const visibleContinueWatching = useMemo(
    () =>
      kidsMode
        ? continueWatching.filter((item) => isKidsMedia(item.media))
        : continueWatching,
    [continueWatching, kidsMode],
  );
  const catalogRails = useMemo(
    () =>
      rails
        .filter((rail) =>
          kidsMode ? rail.id.startsWith("kids-") : !rail.id.startsWith("kids-"),
        )
        .map((rail) =>
          kidsMode ? { ...rail, items: rail.items.filter(isKidsMedia) } : rail,
        )
        .filter((rail) => rail.items.length > 0),
    [kidsMode, rails],
  );
  const savedKeys = useMemo(
    () => new Set(visibleSavedItems.map((item) => item.key)),
    [visibleSavedItems],
  );
  const visibleNavItems = useMemo(
    () =>
      user ? [...NAV_ITEMS] : NAV_ITEMS.filter((item) => item !== "Library"),
    [user],
  );

  const toggleSaved = useCallback(
    (media: Media) => {
      if (!user || !activeProfile) {
        setShowSignIn(true);
        return;
      }
      void toggleLibrary(media);
    },
    [activeProfile, toggleLibrary, user],
  );

  useEffect(() => {
    if (!user && active === "Library") setActive("Home");
  }, [active, user]);

  const changeLanguage = (nextCode: string) => {
    document.cookie = `krzene-language=${encodeURIComponent(nextCode)}; Max-Age=31536000; Path=/; SameSite=Lax`;
    const url = new URL(window.location.href);
    url.searchParams.set("lang", nextCode);
    window.location.assign(url.toString());
  };

  // Debounced server-side search keeps the TMDB credential off the client.
  useEffect(() => {
    const trimmed = query.trim();
    if (!trimmed) {
      setResults(null);
      setSearching(false);
      return;
    }
    setSearching(true);
    const token = ++searchToken.current;
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(
          `/api/search?q=${encodeURIComponent(trimmed)}&lang=${encodeURIComponent(localeCode)}${kidsMode ? "&kids=1" : ""}`,
        );
        const payload = await response.json();
        if (token === searchToken.current) setResults(payload.results ?? []);
      } catch {
        if (token === searchToken.current) setResults([]);
      } finally {
        if (token === searchToken.current) setSearching(false);
      }
    }, 300);
    return () => clearTimeout(timer);
  }, [kidsMode, localeCode, query]);

  const visibleRails = useMemo(() => {
    switch (active) {
      case "Movies":
        return catalogRails.filter((rail) => rail.kind === "movie");
      case "Shows":
        return catalogRails.filter(
          (rail) => rail.kind === "tv" && rail.id !== "anime",
        );
      case "Anime":
        return catalogRails.filter((rail) =>
          kidsMode ? rail.id === "kids-animation" : rail.id === "anime",
        );
      case "Library":
        return [];
      default:
        return catalogRails.filter(
          (rail) => rail.id !== (kidsMode ? "kids-trending" : "trending"),
        );
    }
  }, [active, catalogRails, kidsMode]);

  const totalTitles = useMemo(
    () =>
      new Set(
        catalogRails.flatMap((rail) => rail.items.map((item) => item.key)),
      ).size,
    [catalogRails],
  );

  const featureFilms = useMemo(() => {
    const candidates = [
      ...(kidsMode ? [] : [hero]),
      ...catalogRails.flatMap((rail) => rail.items),
    ].filter((item) => item.kind === "movie" && Boolean(item.backdrop));
    const seen = new Set<string>();
    return candidates
      .filter((item) => {
        if (seen.has(item.key)) return false;
        seen.add(item.key);
        return true;
      })
      .slice(0, 7);
  }, [catalogRails, hero, kidsMode]);

  useEffect(() => setHeroIndex(0), [kidsMode]);

  useEffect(() => {
    if (featureFilms.length < 2) return;
    const timer = window.setInterval(
      () => setHeroIndex((current) => (current + 1) % featureFilms.length),
      8000,
    );
    return () => window.clearInterval(timer);
  }, [featureFilms.length]);

  useEffect(() => {
    if (!watchingKey) return;
    const timer = window.setTimeout(() => setWatchingKey(null), 10000);
    return () => window.clearTimeout(timer);
  }, [watchingKey]);

  const activeHero =
    featureFilms[heroIndex] ??
    (kidsMode ? catalogRails[0]?.items[0] : hero) ??
    hero;
  const activeHeroRuntime = activeHero.key === hero.key ? hero.runtime : "";
  const activeHeroTagline = activeHero.key === hero.key ? hero.tagline : "";

  const topTen =
    catalogRails
      .find((rail) => rail.id === (kidsMode ? "kids-trending" : "trending"))
      ?.items.slice(0, 10) ?? [];
  const heroArt = activeHero.backdrop ?? activeHero.poster;
  const trimmedQuery = query.trim();
  const searchMode = showSearch || Boolean(trimmedQuery);
  const featureFilmHidden = searchMode || active === "Library";
  const adsEnabled = active === "Home" && !kidsMode;

  const rememberWatchTransition = useCallback((event: React.MouseEvent<HTMLElement>) => {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const target = event.target as HTMLElement | null;
    const link = target?.closest<HTMLAnchorElement>('a[href^="/watch/"]');
    if (!link) return;

    const image = link.querySelector("img");
    const origin = image?.parentElement ?? link;
    const rect = origin.getBoundingClientRect();
    try {
      sessionStorage.setItem("krzene:watch-transition", JSON.stringify({
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight,
        createdAt: Date.now(),
      }));
    } catch {
      // The transition is optional when storage is unavailable.
    }
  }, []);

  return (
    <main
      className="min-h-screen overflow-hidden bg-krzene-bg"
      onClickCapture={rememberWatchTransition}
    >
      <header className="pwa-home-header fixed left-1/2 z-50 flex h-[62px] w-[calc(100%_-_48px)] max-w-[1180px] -translate-x-1/2 items-center justify-between gap-[18px] rounded-[22px] border border-white/9 bg-[rgba(12,12,12,.72)] p-[8px_10px] shadow-[0_16px_50px_rgba(0,0,0,.32)] backdrop-blur-3xl max-[760px]:h-[60px] max-[760px]:w-[calc(100%_-_24px)] max-[760px]:gap-2 max-[760px]:p-[7px_8px]">
        <Link
          href={`/?lang=${encodeURIComponent(localeCode)}`}
          className="inline-flex h-[42px] basis-[42px] shrink-0 items-center justify-center overflow-hidden rounded-[14px] max-[760px]:h-10 max-[760px]:basis-10"
          aria-label="Krzene home"
        >
          <img className="h-full w-full" src="/krzene-mark.svg" alt="" />
        </Link>
        <nav
          className="flex flex-1 justify-center gap-0.5 max-[760px]:justify-around"
          aria-label="Primary navigation"
        >
          {visibleNavItems.map((item) => (
            <button
              key={item}
              className={`flex cursor-pointer items-center gap-[7px] rounded-[13px] border-0 px-3.5 py-3 text-[13px] font-bold text-[#9e9b97] transition hover:bg-white/12 hover:text-white max-[1080px]:px-[9px] max-[1080px]:[&_.nav-icon]:hidden max-[760px]:hidden ${active === item ? "bg-white/12 text-white" : "bg-transparent"}`}
              onClick={() => setActive(item)}
              aria-pressed={active === item}
            >
              <span
                className="nav-icon text-[17px] font-normal text-[#aaa6a0]"
                aria-hidden="true"
              >
                <UiIcon name={NAV_ICONS[item]} />
              </span>{" "}
              {item}
              {item === "Library" && visibleSavedItems.length > 0 && (
                <i className="ml-[5px] rounded-[9px] bg-krzene-red px-[5px] py-[3px] text-[10px] leading-none font-bold not-italic">
                  {visibleSavedItems.length}
                </i>
              )}
            </button>
          ))}
        </nav>
        <div className="flex items-center gap-[7px] border-l border-white/9 pl-3 max-[760px]:border-0 max-[760px]:p-0">
          <label
            className="flex h-10 items-center gap-1.5 rounded-xl px-2 text-[#aaa6a0] transition hover:bg-white/8 hover:text-white max-[760px]:hidden"
            title={`${activeLocale.label} · ${activeLocale.country}`}
          >
            <span className="text-base" aria-hidden="true"><UiIcon name="language" /></span>
            <span className="sr-only">Catalog language</span>
            <select
              className="max-w-[92px] cursor-pointer border-0 bg-transparent text-xs font-bold text-inherit outline-none"
              value={localeCode}
              onChange={(event) => changeLanguage(event.target.value)}
              aria-label="Catalog language"
            >
              {CATALOG_LOCALES.map((locale) => (
                <option className="bg-[#171717] text-white" key={locale.code} value={locale.code}>
                  {locale.label}
                </option>
              ))}
            </select>
          </label>
          <button
            className={`flex h-10 cursor-pointer items-center gap-1.5 rounded-xl border-0 px-2.5 text-[13px] font-bold transition hover:bg-white/8 hover:text-white max-[760px]:px-[7px] max-[760px]:text-[21px] max-[760px]:[&_span]:hidden ${showSearch ? "bg-white/8 text-white" : "bg-transparent text-[#aaa6a0]"}`}
            onClick={() => setShowSearch((current) => !current)}
            aria-label="Search"
            aria-expanded={showSearch}
          >
            <UiIcon name="search" /> <span>Search</span>
          </button>
          <button
            type="button"
            className={`hidden h-10 cursor-pointer items-center justify-center rounded-xl border-0 px-[7px] text-[21px] transition max-[760px]:flex ${showMobileMenu ? "bg-white/12 text-white" : "bg-transparent text-[#aaa6a0]"}`}
            onClick={() => setShowMobileMenu((current) => !current)}
            aria-label="More navigation"
            aria-expanded={showMobileMenu}
          >
            <UiIcon name="menu" />
          </button>
          <button
            className="flex cursor-pointer items-center gap-2 border-0 bg-transparent"
            onClick={() => (user ? setShowProfiles(true) : setShowSignIn(true))}
            aria-label={
              user ? "Choose or manage profile" : "Sign in with Google"
            }
          >
            <span
              className={`inline-flex h-9 w-9 items-center justify-center rounded-full bg-[#d9edf5] text-xs text-[#1c252b] shadow-[0_0_0_3px_rgba(255,255,255,.05)] max-[760px]:h-[34px] max-[760px]:w-[34px] ${activeProfile?.avatarUrl ? "overflow-hidden" : ""}`}
            >
              {activeProfile?.avatarUrl ? (
                <img
                  className="h-full w-full object-cover"
                  src={activeProfile.avatarUrl}
                  alt=""
                  referrerPolicy="no-referrer"
                />
              ) : (
                (activeProfile?.name || user?.email || "S")
                  .slice(0, 1)
                  .toUpperCase()
              )}
            </span>
            <b className="pr-[5px] text-xs max-[760px]:hidden">
              {user ? activeProfile?.name || "Profiles" : "Sign In"}
            </b>
          </button>
        </div>

        {showMobileMenu && (
          <div
            className="ui-menu-enter absolute top-[calc(100%_+_8px)] right-0 hidden w-[220px] origin-top-right flex-col gap-1 rounded-2xl border border-white/10 bg-[rgba(14,14,14,.98)] p-2 shadow-[0_24px_70px_rgba(0,0,0,.65)] backdrop-blur-2xl max-[760px]:flex"
            role="menu"
          >
            <label className="mb-1 flex items-center gap-3 rounded-xl border border-white/8 bg-white/5 px-3 py-2.5">
              <span className="text-lg text-[#aaa6a0]" aria-hidden="true"><UiIcon name="language" /></span>
              <span className="sr-only">Catalog language</span>
              <select
                className="min-w-0 flex-1 cursor-pointer border-0 bg-transparent text-sm font-bold text-white outline-none"
                value={localeCode}
                onChange={(event) => changeLanguage(event.target.value)}
                aria-label="Catalog language"
              >
                {CATALOG_LOCALES.map((locale) => (
                  <option className="bg-[#171717] text-white" key={locale.code} value={locale.code}>
                    {locale.label} · {locale.country}
                  </option>
                ))}
              </select>
            </label>
            {visibleNavItems.map((item) => (
              <button
                key={item}
                type="button"
                role="menuitem"
                className={`flex w-full cursor-pointer items-center gap-3 rounded-xl border-0 px-3.5 py-3 text-left text-sm font-bold transition ${active === item ? "bg-white/12 text-white" : "bg-transparent text-[#aaa6a0] hover:bg-white/8 hover:text-white"}`}
                onClick={() => {
                  setActive(item);
                  setShowMobileMenu(false);
                }}
              >
                <span className="text-lg">
                  <UiIcon name={NAV_ICONS[item]} />
                </span>
                <span>{item}</span>
                {item === "Library" && visibleSavedItems.length > 0 && (
                  <i className="ml-auto rounded-full bg-krzene-red px-2 py-1 text-[10px] leading-none not-italic text-white">
                    {visibleSavedItems.length}
                  </i>
                )}
              </button>
            ))}
          </div>
        )}
      </header>

      {showSearch && (
        <div className="pwa-home-overlay ui-search-enter fixed left-1/2 z-49 flex w-[calc(100%_-_40px)] max-w-[620px] -translate-x-1/2 items-center gap-3 rounded-[18px] border border-white/9 bg-[rgba(18,18,18,.96)] p-[10px_12px_10px_18px] shadow-[0_25px_80px_#000]">
          <span className="text-[22px] text-[#8c8882]">
            <UiIcon name="search" />
          </span>
          <input
            className="flex-1 border-0 bg-transparent py-2.5 text-[15px] text-white outline-none"
            autoFocus
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search every movie and show"
          />
          <button
            className="cursor-pointer rounded-[10px] border-0 bg-[#2b2a29] px-3 py-[9px]"
            onClick={() => {
              setQuery("");
              setShowSearch(false);
            }}
          >
            Close
          </button>
        </div>
      )}

      {!user && authError && (
        <div
          className="pwa-home-overlay ui-toast-enter fixed left-1/2 z-80 flex max-w-[calc(100%_-_32px)] -translate-x-1/2 items-center gap-3.5 rounded-xl border border-[rgba(226,25,39,.45)] bg-[#251213] px-3.5 py-[11px]"
          role="status"
        >
          <span className="text-xs text-[#e8c7c9]">{authError}</span>
          <button
            className="cursor-pointer whitespace-nowrap rounded-lg border-0 bg-krzene-red px-2.5 py-[7px] text-[11px] font-extrabold"
            onClick={() => setShowSignIn(true)}
          >
            Try again
          </button>
        </div>
      )}

      <ProfileChooser
        open={showProfiles}
        onClose={() => setShowProfiles(false)}
      />

      <CatalogSponsorModal enabled={adsEnabled && !showProfiles && !showSignIn && !passwordRecovery} />

      <AuthDialog
        open={(showSignIn && !user) || passwordRecovery}
        onClose={() => setShowSignIn(false)}
      />

      <div
        className={`grid transition-[grid-template-rows,opacity] duration-500 ease-[cubic-bezier(.22,1,.36,1)] ${featureFilmHidden ? "pointer-events-none grid-rows-[0fr] opacity-0" : "grid-rows-[1fr] opacity-100"}`}
        aria-hidden={featureFilmHidden}
      >
        <div className="min-h-0 overflow-hidden">
        <section
          className={`relative flex min-h-[780px] items-start overflow-hidden bg-[#090909] bg-cover bg-[position:63%_45%] transition-transform duration-500 ease-[cubic-bezier(.22,1,.36,1)] max-[760px]:min-h-[720px] max-[760px]:bg-[position:62%_center] ${featureFilmHidden ? "-translate-y-20 scale-[.985]" : "translate-y-0 scale-100"}`}
          style={
            {
              backgroundImage: heroArt ? `url(${heroArt})` : "none",
            } as React.CSSProperties
          }
        >
          <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(3,3,3,.98)_0%,rgba(4,4,4,.78)_31%,rgba(5,5,5,.1)_66%),linear-gradient(0deg,#070707_0%,transparent_45%)] max-[760px]:bg-[linear-gradient(0deg,#070707_2%,rgba(4,4,4,.45)_60%,rgba(0,0,0,.25)),linear-gradient(90deg,rgba(0,0,0,.65),transparent)]" />
          <div
            className="absolute inset-0 z-[1]"
            style={{
              background: `radial-gradient(circle at 40% 18%, color-mix(in srgb, ${activeHero.accent} 22%, transparent), transparent 42%)`,
            }}
          />
          <div
            className="absolute inset-x-0 bottom-0 z-[1] h-[260px] bg-black/55 backdrop-blur-3xl"
            style={{
              WebkitMaskImage:
                "linear-gradient(to bottom, transparent 0%, rgba(0,0,0,.35) 32%, black 100%)",
              maskImage:
                "linear-gradient(to bottom, transparent 0%, rgba(0,0,0,.35) 32%, black 100%)",
            }}
            aria-hidden="true"
          />
          <div className="pwa-home-hero-content relative z-[2] ml-[max(64px,calc((100vw_-_1310px)/2))] w-[min(650px,calc(100%_-_128px))] pt-[156px] pb-[110px] max-[760px]:mx-0 max-[760px]:w-full max-[760px]:px-[22px] max-[760px]:pb-[105px]">
            <p className="text-xs font-bold tracking-[.06em] text-[#a8a39c] uppercase [&_span]:text-[#47c98d]">
              <span>Feature film</span> • Trending now
            </p>
            <h1 className="my-4 flex min-h-[190px] max-w-[650px] items-center text-balance break-words font-display text-[clamp(44px,5.2vw,78px)] leading-[.94] font-extrabold tracking-[-.055em] [overflow-wrap:anywhere] [text-shadow:0_12px_50px_#000] max-[760px]:my-3 max-[760px]:min-h-[124px] max-[760px]:text-[clamp(36px,10.5vw,50px)]">
              {activeHero.title}
            </h1>
            <div className="flex flex-wrap items-center gap-2.5 [&>b]:rounded-md [&>b]:border [&>b]:border-white/18 [&>b]:px-[7px] [&>b]:py-1 [&>b]:text-[11px] [&>b]:text-[#d4d1cc] [&>span]:text-[#47c98d]">
              {activeHero.score > 0 && (
                <span>★ {activeHero.score.toFixed(1)}</span>
              )}
              {activeHero.year && <b>{activeHero.year}</b>}
              {activeHeroRuntime && <b>{activeHeroRuntime}</b>}
              {activeHero.genres.slice(0, 2).map((genre) => (
                <b key={genre}>{genre}</b>
              ))}
            </div>
            <p className="line-clamp-2 max-w-[540px] text-base leading-[1.65] text-[#c2beb8] max-[760px]:mt-2 max-[760px]:text-sm">
              {activeHeroTagline || activeHero.overview}
            </p>
            <div className="mt-7 flex w-full gap-2.5 max-[760px]:mt-5">
              <Link
                href={watchHref(activeHero)}
                className="inline-flex min-h-[52px] cursor-pointer items-center justify-center gap-2.5 whitespace-nowrap rounded-[13px] bg-[#f5f3ef] px-5 py-3.5 font-extrabold text-[#0d0d0d] transition active:scale-[.98] max-[760px]:min-w-0 max-[760px]:flex-1 max-[760px]:px-[11px] max-[760px]:text-sm"
                onClick={() => setWatchingKey(activeHero.key)}
                aria-busy={watchingKey === activeHero.key}
              >
                {watchingKey === activeHero.key ? (
                  <>
                    <span
                      className="h-[18px] w-[18px] animate-spin rounded-full border-2 border-black/20 border-t-black"
                      aria-hidden="true"
                    />
                    <span>Watching…</span>
                  </>
                ) : (
                  <>
                    <span className="text-lg">
                      <UiIcon name="play" />
                    </span>
                    <span>Watch now</span>
                  </>
                )}
              </Link>
              {user && activeProfile && (
                <button
                  className="inline-flex min-h-[52px] cursor-pointer items-center justify-center gap-2.5 whitespace-nowrap rounded-[13px] border-0 bg-white/12 px-5 py-3.5 font-extrabold text-white backdrop-blur-[10px] max-[760px]:min-w-0 max-[760px]:flex-1 max-[760px]:px-[11px] max-[760px]:text-sm"
                  onClick={() => toggleSaved(activeHero)}
                >
                  <span className="text-lg">
                    <UiIcon
                      name={savedKeys.has(activeHero.key) ? "check" : "plus"}
                    />
                  </span>
                  <span>
                    {savedKeys.has(activeHero.key) ? "In my list" : "My list"}
                  </span>
                </button>
              )}
            </div>
            {featureFilms.length > 1 && (
              <div
                className="mt-5 flex items-center gap-3"
                aria-label="Feature film carousel controls"
              >
                <button
                  type="button"
                  className="flex h-8 w-8 cursor-pointer items-center justify-center rounded-full border border-white/15 bg-black/30 text-white backdrop-blur-md transition hover:bg-white hover:text-black"
                  onClick={() =>
                    setHeroIndex(
                      (current) =>
                        (current - 1 + featureFilms.length) %
                        featureFilms.length,
                    )
                  }
                  aria-label="Previous feature film"
                >
                  <UiIcon name="chevron-left" />
                </button>
                <div className="flex gap-1.5">
                  {featureFilms.map((film, index) => (
                    <button
                      key={film.key}
                      type="button"
                      className={`h-1.5 cursor-pointer rounded-full border-0 transition-all ${index === heroIndex ? "w-7 bg-white" : "w-1.5 bg-white/35 hover:bg-white/65"}`}
                      onClick={() => setHeroIndex(index)}
                      aria-label={`Show ${film.title}`}
                      aria-current={index === heroIndex ? "true" : undefined}
                    />
                  ))}
                </div>
                <button
                  type="button"
                  className="flex h-8 w-8 cursor-pointer items-center justify-center rounded-full border border-white/15 bg-black/30 text-white backdrop-blur-md transition hover:bg-white hover:text-black"
                  onClick={() =>
                    setHeroIndex(
                      (current) => (current + 1) % featureFilms.length,
                    )
                  }
                  aria-label="Next feature film"
                >
                  <UiIcon name="chevron-right" />
                </button>
              </div>
            )}
          </div>
        </section>
        </div>
      </div>

      <div
        className={`relative z-[4] px-[max(64px,calc((100vw_-_1310px)/2))] pb-[100px] transition-[margin,padding] duration-500 ease-[cubic-bezier(.22,1,.36,1)] max-[760px]:px-5 max-[760px]:pb-[120px] ${searchMode ? "min-h-screen bg-[#090909] pt-[170px] max-[760px]:pt-[150px]" : active === "Library" ? "min-h-screen bg-[#090909] pt-[130px] max-[760px]:pt-[118px]" : "-mt-[150px] bg-[linear-gradient(to_bottom,transparent_0px,rgba(7,7,7,.72)_105px,#090909_220px)] pt-[90px] max-[760px]:-mt-[140px] max-[760px]:pt-[82px]"}`}
      >
        {active !== "Library" && (
          <div className="mb-[34px] rounded-xl border border-white/7 bg-black/25 px-4 py-3 text-[11px] tracking-[.02em] text-[#77736e] shadow-[0_12px_34px_rgba(0,0,0,.2)] backdrop-blur-xl max-[760px]:mb-[26px] [&_b]:text-[#d2cec8]">
            {kidsMode && (
              <b className="mr-2 rounded-full bg-[#d9edf5] px-2 py-1 text-[#16242a]">
                KIDS
              </b>
            )}
            <b>{totalTitles.toLocaleString()}</b>{" "}
            {kidsMode ? "kid-friendly titles" : "Movies and Series loaded"}
            {vidsrcMirror ? ` (${new URL(vidsrcMirror).host})` : ""}
          </div>
        )}

        {trimmedQuery ? (
          <section>
            <div className="mb-[19px] flex items-end justify-between">
              <div>
                <span className="text-[10px] font-extrabold tracking-[.13em] text-[#77736e]">
                  SEARCH
                </span>
                <h2 className="mt-[5px] font-display text-[22px] leading-[1.2] font-bold tracking-[-.025em]">
                  {searching
                    ? "Searching…"
                    : `${results?.length ?? 0} result${results?.length === 1 ? "" : "s"} for “${trimmedQuery}”`}
                </h2>
              </div>
            </div>
            {results && results.length > 0 ? (
              <div className="grid grid-cols-5 gap-4 max-[1080px]:grid-cols-3 max-[760px]:mr-[-20px] max-[760px]:flex max-[760px]:overflow-x-auto max-[760px]:pr-5 max-[760px]:[scrollbar-width:none]">
                {results.map((media) => (
                  <MediaCard
                    key={media.key}
                    media={media}
                    saved={savedKeys.has(media.key)}
                    canSave={Boolean(user && activeProfile)}
                    onSave={() => toggleSaved(media)}
                  />
                ))}
              </div>
            ) : (
              !searching && (
                <p className="mb-6 text-[#9d9993]">
                  Nothing matched. Try another title.
                </p>
              )
            )}
          </section>
        ) : active === "Library" ? (
          <>
            {activeProfile && (
              <ContinueWatchingRail
                items={visibleContinueWatching}
                profileName={activeProfile.name}
                className="mb-[72px] pt-4 max-[760px]:mb-[55px] max-[760px]:pt-3"
              />
            )}
          <section className="catalog-rail-reveal">
            <div className="mb-[19px] flex items-end justify-between">
              <div>
                <span className="text-[10px] font-extrabold tracking-[.13em] text-[#77736e]">
                  MY LIST
                </span>
                <h2 className="mt-[5px] font-display text-[22px] leading-[1.2] font-bold tracking-[-.025em]">
                  {visibleSavedItems.length
                    ? `${visibleSavedItems.length} saved`
                    : "Nothing saved yet"}
                </h2>
              </div>
            </div>
            {visibleSavedItems.length ? (
              <div className="grid grid-cols-5 gap-4 max-[1080px]:grid-cols-3 max-[760px]:mr-[-20px] max-[760px]:flex max-[760px]:overflow-x-auto max-[760px]:pr-5 max-[760px]:[scrollbar-width:none]">
                {visibleSavedItems.map((media) => (
                  <MediaCard
                    key={media.key}
                    media={media}
                    saved
                    canSave
                    onSave={() => toggleSaved(media)}
                  />
                ))}
              </div>
            ) : (
              <p className="mb-6 text-[#9d9993]">
                Tap + on any title to keep it here.
              </p>
            )}
          </section>
          </>
        ) : (
          <>
            {active === "Home" &&
              user &&
              activeProfile &&
              visibleContinueWatching.length > 0 && (
                <section className="mb-[72px] max-[760px]:mb-[55px]">
                  <div className="mb-[19px] flex items-end justify-between">
                    <div>
                      <span className="text-[10px] font-extrabold tracking-[.13em] text-[#77736e]">
                        FOR {activeProfile.name.toUpperCase()}
                      </span>
                      <h2 className="mt-[5px] font-display text-[22px] leading-[1.2] font-bold tracking-[-.025em]">
                        Continue watching
                      </h2>
                    </div>
                    <span className="text-[11px] font-bold text-[#6f6b66]">
                      {visibleContinueWatching.length} saved
                    </span>
                  </div>
                  <div className="media-rail flex snap-x snap-proximity gap-4 overflow-x-auto pb-[10px] max-[760px]:mr-[-20px] max-[760px]:pr-5">
                    {visibleContinueWatching.map((item) => {
                      const progress =
                        item.duration > 0
                          ? Math.min(item.position / item.duration, 1)
                          : 0;
                      const resumeQuery = new URLSearchParams({
                        t: String(Math.floor(item.position)),
                      });
                      if (item.season != null)
                        resumeQuery.set("season", String(item.season));
                      if (item.episode != null)
                        resumeQuery.set("episode", String(item.episode));
                      return (
                        <Link
                          key={item.media.key}
                          href={`${watchHref(item.media)}?${resumeQuery.toString()}`}
                          className="group min-w-0 shrink-0 basis-[calc((100%_-_64px)/5)] snap-start max-[1080px]:basis-[calc((100%_-_32px)/3)] max-[760px]:basis-[74vw]"
                        >
                          <span className="relative block aspect-[1.56] overflow-hidden rounded-[15px] border border-white/6 bg-[#171717]">
                            {artFor(item.media) ? (
                              <img
                                className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-[1.055]"
                                src={artFor(item.media)!}
                                alt=""
                              />
                            ) : (
                              <span className="flex h-full items-center justify-center text-[#77736e]">
                                {item.media.title}
                              </span>
                            )}
                            <span className="absolute inset-0 bg-[linear-gradient(0deg,rgba(0,0,0,.72),transparent_58%)]" />
                            <span
                              className="absolute bottom-0 left-0 h-1 bg-krzene-red transition-all"
                              style={{ width: `${progress * 100}%` }}
                            />
                            <span className="absolute right-3 bottom-3 flex h-9 w-9 items-center justify-center rounded-full bg-white text-lg text-black shadow-lg transition group-hover:scale-105">
                              <UiIcon name="play" />
                            </span>
                          </span>
                          <span className="flex min-w-0 flex-col px-1 pt-3">
                            <b className="truncate text-sm">
                              {item.media.title}
                            </b>
                            <small className="mt-1 text-[#77736e]">
                              {item.season != null && item.episode != null
                                ? `S${item.season} · E${item.episode} · `
                                : ""}
                              Resume at {clockLabel(item.position)}
                            </small>
                          </span>
                        </Link>
                      );
                    })}
                  </div>
                </section>
              )}
            {active === "Home" && topTen.length > 0 && (
              <section>
                <div className="mb-[19px] flex items-end justify-between">
                  <div>
                    <span className="text-[10px] font-extrabold tracking-[.13em] text-[#77736e]">
                      TRENDING NOW
                    </span>
                    <h2 className="mt-[5px] font-display text-[22px] leading-[1.2] font-bold tracking-[-.025em]">
                      Top 10 this week
                    </h2>
                  </div>
                </div>
                <div className="ranking-grid flex snap-x snap-proximity gap-4 overflow-x-auto py-[14px_10px] max-[760px]:mr-[-20px] max-[760px]:pr-5 max-[760px]:[scrollbar-width:none]">
                  {topTen.map((media, rankingIndex) => {
                    const art = artFor(media);
                    return (
                      <Link
                        href={watchHref(media)}
                        className="group flex min-w-0 shrink-0 basis-[calc((100%_-_64px)/5)] snap-start items-end max-[1080px]:basis-[calc((100%_-_32px)/3)] max-[760px]:basis-[260px]"
                        key={media.key}
                      >
                        <strong className="relative z-0 mr-[-18px] font-display text-[105px] leading-[.75] font-extrabold text-transparent [-webkit-text-stroke:1.5px_#494744]">
                          {rankingIndex + 1}
                        </strong>
                        <div className="relative z-[1] aspect-[1.35] flex-1 overflow-hidden rounded-[13px] [&>img]:h-full [&>img]:w-full [&>img]:object-cover [&>img]:transition-transform [&>img]:duration-400 group-hover:[&>img]:scale-[1.06]">
                          {art ? (
                            <img src={art} alt="" loading="lazy" />
                          ) : (
                            <span className="flex h-full w-full items-center justify-center bg-[linear-gradient(140deg,#1d1d1d,#121212)] p-4 text-center font-display text-[13px] leading-[1.3] font-bold text-[#5f5c58]" />
                          )}
                          <span className="absolute inset-x-0 bottom-0 flex flex-col bg-[linear-gradient(transparent,rgba(0,0,0,.9))] p-[30px_12px_10px] [&_small]:mt-[3px] [&_small]:text-[#aaa6a0]">
                            <b>{media.title}</b>
                            <small>
                              {media.genres.join(" • ") || subtitleFor(media)}
                            </small>
                          </span>
                        </div>
                      </Link>
                    );
                  })}
                </div>
              </section>
            )}
            <AdSenseUnit
              slot={process.env.NEXT_PUBLIC_ADSENSE_SLOT_CATALOG}
              enabled={adsEnabled}
            />
            {visibleRails.map((rail, index) => (
              <div key={rail.id}>
                <Rail
                  rail={rail}
                  first={index === 0 && active !== "Home"}
                  savedKeys={savedKeys}
                  canSave={Boolean(user && activeProfile)}
                  onSave={toggleSaved}
                />
              </div>
            ))}
          </>
        )}
      </div>

      <div className="mx-auto w-[calc(100%_-_64px)] max-w-[1310px] max-[760px]:w-[calc(100%_-_40px)]">
        <AdSenseUnit
          slot={process.env.NEXT_PUBLIC_ADSENSE_SLOT_FOOTER}
          enabled={adsEnabled}
        />
      </div>

      <footer className="pwa-footer-safe mx-auto w-[calc(100%_-_64px)] max-w-[1310px] border-t border-white/9 pt-[52px] pb-[30px] text-[#88847e] max-[760px]:mb-6 max-[760px]:w-[calc(100%_-_40px)] max-[760px]:pt-[38px]">
        <div className="grid grid-cols-[minmax(260px,1.7fr)_repeat(3,minmax(120px,.7fr))] gap-12 pb-[45px] max-[760px]:grid-cols-2 max-[760px]:gap-[34px_20px]">
          <div className="max-w-[360px] max-[760px]:col-span-full">
            <Link href="/" aria-label="Krzene home">
              <img
                className="block h-[38px] w-auto"
                src="/krzene-logo.svg"
                alt="Krzene"
              />
            </Link>
            <p className="mt-5 max-w-[330px] text-[13px] leading-[1.65] text-[#77736e]">
              Discover your next favorite story. One profile, one library, ready
              on every screen.
            </p>
          </div>

          <div className="flex flex-col items-start gap-[11px] [&_button]:cursor-pointer [&_button]:border-0 [&_button]:bg-transparent [&_button]:p-0 [&_button]:text-left [&_button]:text-xs [&_button]:text-[#77736e] [&_button]:transition-colors hover:[&_button]:text-white">
            <h3 className="mb-[7px] font-display text-xs font-bold tracking-[.08em] text-[#d8d4ce] uppercase">
              Browse
            </h3>
            {NAV_ITEMS.slice(0, 4).map((item) => (
              <button
                key={item}
                onClick={() => {
                  setActive(item);
                  window.scrollTo({ top: 0, behavior: "smooth" });
                }}
              >
                {item}
              </button>
            ))}
          </div>

          <div className="flex flex-col items-start gap-[11px] [&_button]:cursor-pointer [&_button]:border-0 [&_button]:bg-transparent [&_button]:p-0 [&_button]:text-left [&_button]:text-xs [&_button]:text-[#77736e] [&_button]:transition-colors hover:[&_button]:text-white">
            <h3 className="mb-[7px] font-display text-xs font-bold tracking-[.08em] text-[#d8d4ce] uppercase">
              Your Krzene
            </h3>
            {user && (
              <button
                onClick={() => {
                  setActive("Library");
                  window.scrollTo({ top: 0, behavior: "smooth" });
                }}
              >
                My library
              </button>
            )}
            <button
              onClick={() =>
                user ? setShowProfiles(true) : setShowSignIn(true)
              }
            >
              {user ? "Switch profile" : "Sign in with Google"}
            </button>
          </div>

          <div className="flex flex-col items-start gap-[11px] [&_a]:text-xs [&_a]:text-[#77736e] [&_a]:transition-colors hover:[&_a]:text-white">
            <h3 className="mb-[7px] font-display text-xs font-bold tracking-[.08em] text-[#d8d4ce] uppercase">
              Powered by
            </h3>
            <a
              href="https://www.themoviedb.org/"
              target="_blank"
              rel="noreferrer"
            >
              TMDB metadata ↗
            </a>
            <a href="https://vidsrc.xyz/" target="_blank" rel="noreferrer">
              VidSrc playback ↗
            </a>
          </div>
        </div>

        <div className="grid grid-cols-[1fr_minmax(280px,1.5fr)_1fr] items-center gap-5 border-t border-white/6 pt-6 text-[10px] max-[760px]:grid-cols-1 max-[760px]:items-start [&_p]:m-0 [&_p]:text-center max-[760px]:[&_p]:text-left">
          <span>© 2026 Krzene. All rights reserved.</span>
          <p className="flex flex-wrap justify-center gap-x-4 gap-y-2 max-[760px]:justify-start">
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
            <Link href="/contact">Contact</Link>
            <Link href="/copyright">Copyright</Link>
          </p>
          <span className="flex items-center justify-end gap-[7px] max-[760px]:justify-start">
            <i className="h-1.5 w-1.5 rounded-full bg-[#47c98d] shadow-[0_0_10px_rgba(71,201,141,.6)]" />{" "}
            Streaming service online
          </span>
        </div>
      </footer>
    </main>
  );
}

export function StreamingHome({ data }: { data: HomeData }) {
  if (!data.configured) return <SetupNotice reason={data.reason} />;
  return (
    <CatalogHome
      hero={data.hero}
      rails={data.rails}
      vidsrcMirror={data.vidsrcMirror}
      localeCode={data.localeCode}
    />
  );
}
