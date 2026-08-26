"use client";

import { useState } from "react";
import { useAuth, type ViewerProfile } from "./AuthProvider";

function ProfileAvatar({ profile }: { profile: ViewerProfile }) {
  return (
    <span className="profile-avatar" style={{ "--profile-color": profile.avatarColor } as React.CSSProperties}>
      {profile.avatarUrl ? <img src={profile.avatarUrl} alt="" referrerPolicy="no-referrer" /> : <b>{profile.name.slice(0, 1).toUpperCase()}</b>}
      {profile.isKids && <i>KIDS</i>}
    </span>
  );
}

export function ProfileChooser({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { user, profiles, activeProfile, selectProfile, createProfile, deleteProfile, signOut, authError } = useAuth();
  const [mode, setMode] = useState<"choose" | "add" | "manage">("choose");
  const [name, setName] = useState("");
  const [isKids, setIsKids] = useState(false);

  if (!open || !user) return null;

  const choose = async (profile: ViewerProfile) => {
    await selectProfile(profile);
    setMode("choose");
    onClose();
  };

  const add = async () => {
    const created = await createProfile(name, isKids);
    if (!created) return;
    setName("");
    setIsKids(false);
    await choose(created);
  };

  return (
    <div className="profile-gate" role="dialog" aria-modal="true" aria-labelledby="profile-title">
      {activeProfile && <button className="profile-close" onClick={onClose} aria-label="Close profile chooser">×</button>}
      <img className="profile-logo" src="/krzene-logo.svg" alt="Krzene" />
      <div className="profile-gate-inner">
        <p className="profile-account">{user.email}</p>
        <h1 id="profile-title">{mode === "add" ? "Create a profile" : mode === "manage" ? "Manage profiles" : "Who’s watching?"}</h1>
        <p>{mode === "add" ? "Give everyone their own library." : "Choose a profile to continue."}</p>

        {mode === "add" ? (
          <div className="profile-form">
            <span className="profile-avatar profile-avatar-preview" style={{ "--profile-color": "#e21927" } as React.CSSProperties}>+</span>
            <input value={name} onChange={(event) => setName(event.target.value)} maxLength={32} placeholder="Profile name" autoFocus />
            <label><input type="checkbox" checked={isKids} onChange={(event) => setIsKids(event.target.checked)} /> Kids profile</label>
            <button className="profile-primary" onClick={add} disabled={!name.trim()}>Create profile</button>
            <button className="profile-secondary" onClick={() => setMode("choose")}>Cancel</button>
          </div>
        ) : (
          <>
            <div className="profile-list">
              {profiles.map((profile) => (
                <div className="profile-option-wrap" key={profile.id}>
                  <button className={`profile-option ${activeProfile?.id === profile.id ? "current" : ""}`} onClick={() => choose(profile)}>
                    <ProfileAvatar profile={profile} />
                    <span>{profile.name}</span>
                  </button>
                  {mode === "manage" && profiles.length > 1 && <button className="profile-delete" onClick={() => deleteProfile(profile.id)} aria-label={`Delete ${profile.name}`}>×</button>}
                </div>
              ))}
              {mode !== "manage" && profiles.length < 5 && (
                <button className="profile-option" onClick={() => setMode("add")}>
                  <span className="profile-avatar add-profile">+</span><span>Add profile</span>
                </button>
              )}
            </div>
            <div className="profile-gate-actions">
              <button className="profile-secondary" onClick={() => setMode(mode === "manage" ? "choose" : "manage")}>{mode === "manage" ? "Done" : "Manage profiles"}</button>
              <button className="profile-secondary" onClick={signOut}>Sign out</button>
            </div>
          </>
        )}
        {authError && <p className="profile-error">{authError}</p>}
      </div>
    </div>
  );
}
