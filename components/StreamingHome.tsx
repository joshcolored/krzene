"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { watchHref, type HomeData, type Media, type MediaDetail, type MediaRail } from "@/lib/media";
import { useAuth } from "./AuthProvider";
import { ProfileChooser } from "./ProfileChooser";

const NAV_ITEMS = ["Home", "Movies", "Shows", "Anime", "Library"] as const;
type NavItem = (typeof NAV_ITEMS)[number];

type IconName = "home" | "movie" | "shows" | "anime" | "library" | "search" | "chevron-left" | "chevron-right";

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
    <svg className="ui-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false" {...common}>
      {name === "home" && <><path d="M3.5 10.5 12 3.8l8.5 6.7" /><path d="M5.7 9.2v10.5h12.6V9.2M9.3 19.7v-6h5.4v6" /></>}
      {name === "movie" && <><rect x="3.5" y="6.5" width="17" height="13" rx="2" /><path d="m4.5 10 4-3.5m2.5 3.5 4-3.5m2.5 3.5 3-2.6M3.5 10h17" /></>}
      {name === "shows" && <><rect x="3.5" y="5" width="17" height="14" rx="2" /><path d="m9.5 9 6 3-6 3V9Z" /></>}
      {name === "anime" && <><path d="M12 3.5 14.3 8l5 .7-3.6 3.5.8 5-4.5-2.4-4.5 2.4.8-5-3.6-3.5 5-.7L12 3.5Z" /><path d="M9.4 11.2h.1m5 0h.1M10 13.6c1.2.8 2.8.8 4 0" /></>}
      {name === "library" && <><rect x="4" y="4" width="5" height="16" rx="1" /><rect x="10.2" y="4" width="4.8" height="16" rx="1" /><path d="m16.3 5.1 3.2-.8 2.8 14.3-3.2.7-2.8-14.2Z" /></>}
      {name === "search" && <><circle cx="10.5" cy="10.5" r="6.5" /><path d="m15.4 15.4 4.6 4.6" /></>}
      {name === "chevron-left" && <path d="m14.5 6-6 6 6 6" />}
      {name === "chevron-right" && <path d="m9.5 6 6 6-6 6" />}
    </svg>
  );
}

function artFor(media: Media): string | null {
  return media.backdrop ?? media.poster;
}

function subtitleFor(media: Media): string {
  const kindLabel = media.kind === "tv" ? "Series" : "Film";
  return [media.year ? String(media.year) : null, media.genres[0] ?? kindLabel].filter(Boolean).join(" • ");
}

function MediaCard({ media, saved, onSave }: { media: Media; saved: boolean; onSave: () => void }) {
  const art = artFor(media);
  return (
    <article className="media-card">
      <Link href={watchHref(media)} className="media-art" aria-label={`Watch ${media.title}`}>
        {art ? <img src={art} alt="" loading="lazy" /> : <span className="art-fallback">{media.title}</span>}
        <span className="media-shade" />
        <span className="play-disc">▶</span>
        <span className="quality-chip">{media.kind === "tv" ? "SERIES" : "HD"}</span>
        {media.score > 0 && <span className="score-chip">★ {media.score.toFixed(1)}</span>}
      </Link>
      <div className="media-copy">
        <div>
          <h3 title={media.title}>{media.title}</h3>
          <p>{subtitleFor(media)}</p>
        </div>
        <button
          className={`save-button ${saved ? "saved" : ""}`}
          onClick={onSave}
          aria-label={saved ? `Remove ${media.title} from watchlist` : `Add ${media.title} to watchlist`}
        >
          {saved ? "✓" : "+"}
        </button>
      </div>
    </article>
  );
}

function Rail({
  rail,
  first,
  savedKeys,
  onSave,
}: {
  rail: MediaRail;
  first: boolean;
  savedKeys: Set<string>;
  onSave: (media: Media) => void;
}) {
  const railRef = useRef<HTMLDivElement>(null);
  const scrollRail = (direction: -1 | 1) => {
    const node = railRef.current;
    if (!node) return;
    node.scrollBy({ left: direction * Math.max(node.clientWidth * 0.84, 280), behavior: "smooth" });
  };

  return (
    <section className={`rail-section ${first ? "first-rail" : ""}`}>
      <div className="section-heading">
        <div>
          <span className="section-kicker">{rail.kicker}</span>
          <h2>{rail.heading}</h2>
        </div>
        <div className="rail-meta">
          <span className="rail-count">{rail.items.length} titles</span>
          <div className="rail-controls" aria-label={`${rail.heading} carousel controls`}>
            <button type="button" className="rail-arrow" onClick={() => scrollRail(-1)} aria-label={`Previous ${rail.heading} titles`}>
              <UiIcon name="chevron-left" />
            </button>
            <button type="button" className="rail-arrow" onClick={() => scrollRail(1)} aria-label={`Next ${rail.heading} titles`}>
              <UiIcon name="chevron-right" />
            </button>
          </div>
        </div>
      </div>
      <div className="media-rail" ref={railRef}>
        {rail.items.map((media) => (
          <MediaCard key={media.key} media={media} saved={savedKeys.has(media.key)} onSave={() => onSave(media)} />
        ))}
      </div>
    </section>
  );
}

function SetupNotice({ reason }: { reason: string }) {
  return (
    <main className="site-shell">
      <div className="setup-wrap">
        <div className="setup-card">
          <span className="brand"><img src="/krzene-mark.svg" alt="" /></span>
          <h1>Add a TMDB key to fill the catalog</h1>
          <p>
            VidSrc streams the video, but its <code>vapi</code> listing endpoints are retired and return 404
            on every mirror — so movie and show listings come from TMDB instead. Playback still runs through
            VidSrc&apos;s <code>embed</code> endpoints.
          </p>
          <p className="setup-reason">{reason}</p>
          <ol>
            <li>
              Grab a free key at <b>themoviedb.org → Settings → API</b>.
            </li>
            <li>
              Put it in <code>.env.local</code> at the project root:
              <pre>TMDB_API_KEY=your_key_here</pre>
            </li>
            <li>
              Restart the dev server: <code>npm run dev</code>
            </li>
          </ol>
          <p className="setup-foot">Either a v3 API key or a v4 read access token works.</p>
        </div>
      </div>
    </main>
  );
}

function CatalogHome({
  hero,
  rails,
  vidsrcMirror,
}: {
  hero: MediaDetail;
  rails: MediaRail[];
  vidsrcMirror: string | null;
}) {
  const [active, setActive] = useState<NavItem>("Home");
  const [query, setQuery] = useState("");
  const [showSearch, setShowSearch] = useState(false);
  const [results, setResults] = useState<Media[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [showProfiles, setShowProfiles] = useState(false);
  const searchToken = useRef(0);
  const {
    ready: authReady,
    user,
    activeProfile,
    library: savedItems,
    authError,
    signInWithGoogle,
    toggleLibrary,
  } = useAuth();

  useEffect(() => {
    if (authReady && user && !activeProfile) setShowProfiles(true);
  }, [activeProfile, authReady, user]);

  const savedKeys = useMemo(() => new Set(savedItems.map((item) => item.key)), [savedItems]);

  const toggleSaved = useCallback((media: Media) => void toggleLibrary(media), [toggleLibrary]);

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
        const response = await fetch(`/api/search?q=${encodeURIComponent(trimmed)}`);
        const payload = await response.json();
        if (token === searchToken.current) setResults(payload.results ?? []);
      } catch {
        if (token === searchToken.current) setResults([]);
      } finally {
        if (token === searchToken.current) setSearching(false);
      }
    }, 300);
    return () => clearTimeout(timer);
  }, [query]);

  const visibleRails = useMemo(() => {
    switch (active) {
      case "Movies":
        return rails.filter((rail) => rail.kind === "movie");
      case "Shows":
        return rails.filter((rail) => rail.kind === "tv" && rail.id !== "anime");
      case "Anime":
        return rails.filter((rail) => rail.id === "anime");
      case "Library":
        return [];
      default:
        return rails;
    }
  }, [active, rails]);

  const totalTitles = useMemo(
    () => new Set(rails.flatMap((rail) => rail.items.map((item) => item.key))).size,
    [rails],
  );

  const topTen = rails.find((rail) => rail.id === "trending")?.items.slice(0, 10) ?? [];
  const heroArt = hero.backdrop ?? hero.poster;
  const trimmedQuery = query.trim();

  return (
    <main className="site-shell">
      <header className="floating-nav">
        <Link href="/" className="brand" aria-label="Krzene home">
          <img src="/krzene-mark.svg" alt="" />
        </Link>
        <nav aria-label="Primary navigation">
          {NAV_ITEMS.map((item) => (
            <button key={item} className={active === item ? "active" : ""} onClick={() => setActive(item)} aria-pressed={active === item}>
              <span className="nav-icon" aria-hidden="true">
                <UiIcon name={NAV_ICONS[item]} />
              </span>{" "}
              {item}
              {item === "Library" && savedItems.length > 0 && <i className="nav-badge">{savedItems.length}</i>}
            </button>
          ))}
        </nav>
        <div className="nav-actions">
          <button
            className={`search-trigger ${showSearch ? "active" : ""}`}
            onClick={() => setShowSearch((current) => !current)}
            aria-label="Search"
            aria-expanded={showSearch}
          >
            <UiIcon name="search" /> <span>Search</span>
          </button>
          <button
            className="profile"
            onClick={() => user ? setShowProfiles(true) : void signInWithGoogle()}
            aria-label={user ? "Choose or manage profile" : "Sign in with Google"}
          >
            <span className={activeProfile?.avatarUrl ? "has-avatar" : ""}>
              {activeProfile?.avatarUrl ? <img src={activeProfile.avatarUrl} alt="" referrerPolicy="no-referrer" /> : (activeProfile?.name || user?.email || "G").slice(0, 1).toUpperCase()}
            </span>
            <b>{user ? activeProfile?.name || "Profiles" : "Google"}</b>
          </button>
        </div>
      </header>

      {showSearch && (
        <div className="search-panel">
          <span><UiIcon name="search" /></span>
          <input
            autoFocus
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search every movie and show"
          />
          <button
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
        <div className="auth-toast" role="status">
          <span>{authError}</span>
          <button onClick={() => void signInWithGoogle()}>Try again</button>
        </div>
      )}

      <ProfileChooser open={showProfiles} onClose={() => setShowProfiles(false)} />

      <section
        className="hero"
        style={
          {
            "--hero-image": heroArt ? `url(${heroArt})` : "none",
            "--accent": hero.accent,
          } as React.CSSProperties
        }
      >
        <div className="hero-vignette" />
        <div className="hero-content">
          <p className="eyebrow">
            <span>{hero.kind === "tv" ? "Series" : "Feature film"}</span> • Trending now
          </p>
          <h1>{hero.title}</h1>
          <div className="hero-meta">
            {hero.score > 0 && <span>★ {hero.score.toFixed(1)}</span>}
            {hero.year && <b>{hero.year}</b>}
            {hero.runtime && <b>{hero.runtime}</b>}
            {hero.genres.map((genre) => (
              <b key={genre}>{genre}</b>
            ))}
          </div>
          <p className="hero-description">{hero.tagline || hero.overview}</p>
          <div className="hero-actions">
            <Link href={watchHref(hero)} className="primary-cta">
              ▶ <span>Watch now</span>
            </Link>
            <button className="secondary-cta" onClick={() => toggleSaved(hero)}>
              {savedKeys.has(hero.key) ? "✓ In my list" : "+ My list"}
            </button>
          </div>
        </div>
      </section>

      <div className="content-surface">
        <div className="catalog-status">
          <b>{totalTitles.toLocaleString()}</b> titles loaded · playback via VidSrc
          {vidsrcMirror ? ` (${new URL(vidsrcMirror).host})` : ""} · metadata via TMDB
        </div>

        {trimmedQuery ? (
          <section className="rail-section first-rail">
            <div className="section-heading">
              <div>
                <span className="section-kicker">SEARCH</span>
                <h2>
                  {searching
                    ? "Searching…"
                    : `${results?.length ?? 0} result${results?.length === 1 ? "" : "s"} for “${trimmedQuery}”`}
                </h2>
              </div>
            </div>
            {results && results.length > 0 ? (
              <div className="media-grid">
                {results.map((media) => (
                  <MediaCard
                    key={media.key}
                    media={media}
                    saved={savedKeys.has(media.key)}
                    onSave={() => toggleSaved(media)}
                  />
                ))}
              </div>
            ) : (
              !searching && <p className="results-note">Nothing matched. Try another title.</p>
            )}
          </section>
        ) : active === "Library" ? (
          <section className="rail-section first-rail">
            <div className="section-heading">
              <div>
                <span className="section-kicker">MY LIST</span>
                <h2>{savedItems.length ? `${savedItems.length} saved` : "Nothing saved yet"}</h2>
              </div>
            </div>
            {savedItems.length ? (
              <div className="media-grid">
                {savedItems.map((media) => (
                  <MediaCard key={media.key} media={media} saved onSave={() => toggleSaved(media)} />
                ))}
              </div>
            ) : (
              <p className="results-note">Tap + on any title to keep it here.</p>
            )}
          </section>
        ) : (
          <>
            {visibleRails.map((rail, index) => (
              <div key={rail.id} className="rail-group">
                <Rail
                  rail={rail}
                  first={index === 0}
                  savedKeys={savedKeys}
                  onSave={toggleSaved}
                />
                {active === "Home" && rail.id === "trending" && topTen.length > 0 && (
                  <section className="rail-section ranking-section">
                    <div className="section-heading">
                      <div>
                        <span className="section-kicker">TRENDING NOW</span>
                        <h2>Top 10 this week</h2>
                      </div>
                    </div>
                    <div className="ranking-grid">
                      {topTen.map((media, rankingIndex) => {
                        const art = artFor(media);
                        return (
                          <Link href={watchHref(media)} className="rank-card" key={media.key}>
                            <strong>{rankingIndex + 1}</strong>
                            <div>
                              {art ? <img src={art} alt="" loading="lazy" /> : <span className="art-fallback" />}
                              <span>
                                <b>{media.title}</b>
                                <small>{media.genres.join(" • ") || subtitleFor(media)}</small>
                              </span>
                            </div>
                          </Link>
                        );
                      })}
                    </div>
                  </section>
                )}
              </div>
            ))}
          </>
        )}
      </div>

      <footer className="site-footer">
        <div className="footer-main">
          <div className="footer-brand">
            <Link href="/" aria-label="Krzene home">
              <img src="/krzene-logo.svg" alt="Krzene" />
            </Link>
            <p>Discover your next favorite story. One profile, one library, ready on every screen.</p>
          </div>

          <div className="footer-column">
            <h3>Browse</h3>
            {NAV_ITEMS.slice(0, 4).map((item) => (
              <button key={item} onClick={() => {
                setActive(item);
                window.scrollTo({ top: 0, behavior: "smooth" });
              }}>{item}</button>
            ))}
          </div>

          <div className="footer-column">
            <h3>Your Krzene</h3>
            <button onClick={() => {
              setActive("Library");
              window.scrollTo({ top: 0, behavior: "smooth" });
            }}>My library</button>
            <button onClick={() => user ? setShowProfiles(true) : void signInWithGoogle()}>
              {user ? "Switch profile" : "Sign in with Google"}
            </button>
          </div>

          <div className="footer-column">
            <h3>Powered by</h3>
            <a href="https://www.themoviedb.org/" target="_blank" rel="noreferrer">TMDB metadata ↗</a>
            <a href="https://vidsrc.xyz/" target="_blank" rel="noreferrer">VidSrc playback ↗</a>
          </div>
        </div>

        <div className="footer-bottom">
          <span>© 2026 Krzene. All rights reserved.</span>
          <p>This product uses the TMDB API but is not endorsed or certified by TMDB.</p>
          <span className="footer-status"><i /> Streaming service online</span>
        </div>
      </footer>
    </main>
  );
}

export function StreamingHome({ data }: { data: HomeData }) {
  if (!data.configured) return <SetupNotice reason={data.reason} />;
  return <CatalogHome hero={data.hero} rails={data.rails} vidsrcMirror={data.vidsrcMirror} />;
}
