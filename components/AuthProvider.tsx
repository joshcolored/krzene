"use client";

import type { AuthChangeEvent, Session, User } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { Media } from "@/lib/media";
import { createClient } from "@/lib/supabase/client";
import { isSupabaseConfigured } from "@/lib/supabase/config";

const WATCHLIST_KEY = "wmn-watchlist-v2";

export type ViewerProfile = {
  id: string;
  ownerId: string;
  name: string;
  avatarUrl: string | null;
  avatarColor: string;
  isKids: boolean;
};

type AuthValue = {
  configured: boolean;
  ready: boolean;
  user: User | null;
  profiles: ViewerProfile[];
  activeProfile: ViewerProfile | null;
  library: Media[];
  authError: string | null;
  signInWithGoogle: () => Promise<void>;
  signOut: () => Promise<void>;
  selectProfile: (profile: ViewerProfile) => Promise<void>;
  createProfile: (name: string, isKids: boolean) => Promise<ViewerProfile | null>;
  deleteProfile: (profileId: string) => Promise<void>;
  toggleLibrary: (media: Media) => Promise<void>;
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

function readLocalLibrary(): Media[] {
  try {
    return JSON.parse(window.localStorage.getItem(WATCHLIST_KEY) || "[]") as Media[];
  } catch {
    return [];
  }
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [user, setUser] = useState<User | null>(null);
  const [profiles, setProfiles] = useState<ViewerProfile[]>([]);
  const [activeProfile, setActiveProfile] = useState<ViewerProfile | null>(null);
  const [library, setLibrary] = useState<Media[]>([]);
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
    if (stored) await loadLibrary(stored);
  }, [loadLibrary]);

  useEffect(() => {
    const supabase = createClient();
    if (!supabase) {
      setLibrary(readLocalLibrary());
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
      else setLibrary(readLocalLibrary());
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
          setLibrary(readLocalLibrary());
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
    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") || window.location.origin;
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
    setLibrary(readLocalLibrary());
  }, []);

  const selectProfile = useCallback(async (profile: ViewerProfile) => {
    setActiveProfile(profile);
    if (user) window.localStorage.setItem(`wmn-active-profile-${user.id}`, profile.id);
    await loadLibrary(profile);
  }, [loadLibrary, user]);

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
    }
  }, [activeProfile?.id, profiles.length]);

  const toggleLibrary = useCallback(async (media: Media) => {
    const existed = library.some((item) => item.key === media.key);
    const previous = library;
    const next = existed ? library.filter((item) => item.key !== media.key) : [...library, media];
    setLibrary(next);

    if (!user || !activeProfile) {
      try { window.localStorage.setItem(WATCHLIST_KEY, JSON.stringify(next)); } catch { /* unavailable */ }
      return;
    }

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

  const value = useMemo<AuthValue>(() => ({
    configured: isSupabaseConfigured,
    ready,
    user,
    profiles,
    activeProfile,
    library,
    authError,
    signInWithGoogle,
    signOut,
    selectProfile,
    createProfile,
    deleteProfile,
    toggleLibrary,
  }), [activeProfile, authError, createProfile, deleteProfile, library, profiles, ready, selectProfile, signInWithGoogle, signOut, toggleLibrary, user]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider");
  return value;
}
