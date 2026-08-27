"use client";

import type { AuthChangeEvent, Session, User } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { Media } from "@/lib/media";
import { createClient } from "@/lib/supabase/client";
import { isSupabaseConfigured } from "@/lib/supabase/config";

export type ViewerProfile = {
  id: string;
  ownerId: string;
  name: string;
  avatarUrl: string | null;
  avatarColor: string;
  isKids: boolean;
};

export type ContinueWatchingItem = {
  media: Media;
  position: number;
  duration: number;
  season: number | null;
  episode: number | null;
  updatedAt: string;
};

type AuthValue = {
  configured: boolean;
  ready: boolean;
  user: User | null;
  profiles: ViewerProfile[];
  activeProfile: ViewerProfile | null;
  library: Media[];
  continueWatching: ContinueWatchingItem[];
  authError: string | null;
  signInWithGoogle: () => Promise<void>;
  signOut: () => Promise<void>;
  selectProfile: (profile: ViewerProfile) => Promise<void>;
  createProfile: (name: string, isKids: boolean) => Promise<ViewerProfile | null>;
  deleteProfile: (profileId: string) => Promise<void>;
  toggleLibrary: (media: Media) => Promise<void>;
  saveWatchProgress: (media: Media, position: number, duration: number, season?: number | null, episode?: number | null) => Promise<void>;
};

const AuthContext = createContext<AuthValue | null>(null);

function fromRow(row: Record<string, unknown>): ViewerProfile {
  return {
    id: String(row.id),
    ownerId: String(row.owner_id),
    name: String(row.name),
    avatarUrl: typeof row.avatar_url === "string" ? row.avatar_url : null,
    avatarColor: typeof row.avatar_color === "string" ? row.avatar_color : "#e21927",
    isKids: Boolean(row.is_kids),
  };
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [user, setUser] = useState<User | null>(null);
  const [profiles, setProfiles] = useState<ViewerProfile[]>([]);
  const [activeProfile, setActiveProfile] = useState<ViewerProfile | null>(null);
  const [library, setLibrary] = useState<Media[]>([]);
  const [continueWatching, setContinueWatching] = useState<ContinueWatchingItem[]>([]);
  const [authError, setAuthError] = useState<string | null>(null);

  const loadLibrary = useCallback(async (profile: ViewerProfile) => {
    const supabase = createClient();
    if (!supabase) return;
    const { data, error } = await supabase
      .from("library_items")
      .select("media")
      .eq("profile_id", profile.id)
      .order("created_at", { ascending: false });
    if (error) {
      setAuthError("Your library could not be loaded. Apply the Supabase migration and try again.");
      return;
    }
    setLibrary((data ?? []).map((row: { media: unknown }) => row.media as Media));
  }, []);

  const loadContinueWatching = useCallback(async (profile: ViewerProfile) => {
    const supabase = createClient();
    if (!supabase) return;
    const { data, error } = await supabase
      .from("watch_progress")
      .select("media,position,duration,season,episode,updated_at")
      .eq("profile_id", profile.id)
      .order("updated_at", { ascending: false })
      .limit(20);
    if (error) {
      setAuthError("Viewing progress could not be loaded. Apply the latest Supabase migration.");
      return;
    }
    setContinueWatching((data ?? []).map((row: Record<string, unknown>) => ({
      media: row.media as Media,
      position: Number(row.position) || 0,
      duration: Number(row.duration) || 0,
      season: row.season == null ? null : Number(row.season),
      episode: row.episode == null ? null : Number(row.episode),
      updatedAt: String(row.updated_at),
    })));
  }, []);

  const hydrateProfiles = useCallback(async (nextUser: User) => {
    const supabase = createClient();
    if (!supabase) return;
    const { data, error } = await supabase.from("viewer_profiles").select("*").order("created_at");
    if (error) {
      setAuthError("Profiles are not ready yet. Apply the Supabase migration first.");
      return;
    }

    let nextProfiles: ViewerProfile[] = (data ?? []).map((row: Record<string, unknown>) => fromRow(row));
    if (!nextProfiles.length) {
      const suggestedName =
        nextUser.user_metadata?.full_name || nextUser.user_metadata?.name || nextUser.email?.split("@")[0] || "Profile";
      const { data: created, error: createError } = await supabase
        .from("viewer_profiles")
        .insert({
          owner_id: nextUser.id,
          name: String(suggestedName).slice(0, 32),
          avatar_url: nextUser.user_metadata?.avatar_url ?? null,
        })
        .select()
        .single();
      if (createError || !created) {
        setAuthError("Your first profile could not be created.");
        return;
      }
      nextProfiles = [fromRow(created)];
    }

    setProfiles(nextProfiles);
    const storedId = window.localStorage.getItem(`wmn-active-profile-${nextUser.id}`);
    const stored = nextProfiles.find((profile) => profile.id === storedId) ?? null;
    setActiveProfile(stored);
    if (stored) await Promise.all([loadLibrary(stored), loadContinueWatching(stored)]);
  }, [loadContinueWatching, loadLibrary]);

  useEffect(() => {
    const supabase = createClient();
    if (!supabase) {
      setLibrary([]);
      setReady(true);
      return;
    }

    let cancelled = false;
    let unsubscribe = () => {};

    void (async () => {
      const { data }: { data: { user: User | null } } = await supabase.auth.getUser();
      if (cancelled) return;
      setUser(data.user);
      if (data.user) await hydrateProfiles(data.user);
      else setLibrary([]);
      if (cancelled) return;
      setReady(true);

      const { data: listener } = supabase.auth.onAuthStateChange((_event: AuthChangeEvent, session: Session | null) => {
        const nextUser = session?.user ?? null;
        setUser(nextUser);
        setAuthError(null);
        if (nextUser) void hydrateProfiles(nextUser);
        else {
          setProfiles([]);
          setActiveProfile(null);
          setLibrary([]);
          setContinueWatching([]);
        }
      });
      unsubscribe = () => listener.subscription.unsubscribe();
    })();

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [hydrateProfiles]);

  const signInWithGoogle = useCallback(async () => {
    const supabase = createClient();
    if (!supabase) {
      setAuthError("Add the Supabase environment variables to enable Google sign-in.");
      return;
    }
    // OAuth must return to the exact origin that created Supabase's PKCE
    // verifier cookie. A build-time URL can accidentally send custom-domain
    // users to the Vercel domain, where that cookie does not exist.
    const siteUrl = window.location.origin.replace(/\/$/, "");
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: `${siteUrl}/auth/callback?next=/`, queryParams: { prompt: "select_account" } },
    });
    if (error) setAuthError(error.message);
  }, []);

  const signOut = useCallback(async () => {
    const supabase = createClient();
    await supabase?.auth.signOut();
    setUser(null);
    setProfiles([]);
    setActiveProfile(null);
    setLibrary([]);
    setContinueWatching([]);
  }, []);

  const selectProfile = useCallback(async (profile: ViewerProfile) => {
    setActiveProfile(profile);
    setLibrary([]);
    setContinueWatching([]);
    if (user) window.localStorage.setItem(`wmn-active-profile-${user.id}`, profile.id);
    await Promise.all([loadLibrary(profile), loadContinueWatching(profile)]);
  }, [loadContinueWatching, loadLibrary, user]);

  const createProfile = useCallback(async (name: string, isKids: boolean) => {
    const supabase = createClient();
    const cleanName = name.trim().slice(0, 32);
    if (!supabase || !user || !cleanName) return null;
    const colors = ["#e21927", "#287c8e", "#805ad5", "#d97706", "#238c63"];
    const { data, error } = await supabase
      .from("viewer_profiles")
      .insert({ owner_id: user.id, name: cleanName, is_kids: isKids, avatar_color: colors[profiles.length % colors.length] })
      .select()
      .single();
    if (error || !data) {
      setAuthError(error?.message ?? "Profile could not be created.");
      return null;
    }
    const profile = fromRow(data);
    setProfiles((current) => [...current, profile]);
    return profile;
  }, [profiles.length, user]);

  const deleteProfile = useCallback(async (profileId: string) => {
    if (profiles.length <= 1) return;
    const supabase = createClient();
    const { error } = await supabase?.from("viewer_profiles").delete().eq("id", profileId) ?? { error: null };
    if (error) {
      setAuthError(error.message);
      return;
    }
    setProfiles((current) => current.filter((profile) => profile.id !== profileId));
    if (activeProfile?.id === profileId) {
      setActiveProfile(null);
      setLibrary([]);
      setContinueWatching([]);
    }
  }, [activeProfile?.id, profiles.length]);

  const toggleLibrary = useCallback(async (media: Media) => {
    if (!user || !activeProfile) return;

    const existed = library.some((item) => item.key === media.key);
    const previous = library;
    const next = existed ? library.filter((item) => item.key !== media.key) : [...library, media];
    setLibrary(next);

    const supabase = createClient();
    if (!supabase) return;
    const result = existed
      ? await supabase.from("library_items").delete().eq("profile_id", activeProfile.id).eq("media_key", media.key)
      : await supabase.from("library_items").upsert({
          owner_id: user.id,
          profile_id: activeProfile.id,
          media_key: media.key,
          media,
        }, { onConflict: "profile_id,media_key" });
    if (result.error) {
      setLibrary(previous);
      setAuthError("The library change could not be saved.");
    }
  }, [activeProfile, library, user]);

  const saveWatchProgress = useCallback(async (
    media: Media,
    position: number,
    duration: number,
    season: number | null = null,
    episode: number | null = null,
  ) => {
    if (!user || !activeProfile || position < 5) return;
    const supabase = createClient();
    if (!supabase) return;

    if (duration > 0 && position / duration >= 0.95) {
      setContinueWatching((current) => current.filter((item) => item.media.key !== media.key));
      await supabase.from("watch_progress").delete().eq("profile_id", activeProfile.id).eq("media_key", media.key);
      return;
    }

    const updatedAt = new Date().toISOString();
    const next: ContinueWatchingItem = { media, position, duration, season, episode, updatedAt };
    setContinueWatching((current) => [next, ...current.filter((item) => item.media.key !== media.key)].slice(0, 20));
    const { error } = await supabase.from("watch_progress").upsert({
      owner_id: user.id,
      profile_id: activeProfile.id,
      media_key: media.key,
      media,
      position,
      duration,
      season,
      episode,
      updated_at: updatedAt,
    }, { onConflict: "profile_id,media_key" });
    if (error) setAuthError("Viewing progress could not be saved.");
  }, [activeProfile, user]);

  const value = useMemo<AuthValue>(() => ({
    configured: isSupabaseConfigured,
    ready,
    user,
    profiles,
    activeProfile,
    library,
    continueWatching,
    authError,
    signInWithGoogle,
    signOut,
    selectProfile,
    createProfile,
    deleteProfile,
    toggleLibrary,
    saveWatchProgress,
  }), [activeProfile, authError, continueWatching, createProfile, deleteProfile, library, profiles, ready, saveWatchProgress, selectProfile, signInWithGoogle, signOut, toggleLibrary, user]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider");
  return value;
}
