"use client";

import { useState } from "react";
import { useAuth, type ViewerProfile } from "./AuthProvider";

function ProfileAvatar({ profile }: { profile: ViewerProfile }) {
  return (
    <span
      className="relative flex h-28 w-28 items-center justify-center overflow-hidden rounded-[26%] border-[3px] border-transparent shadow-[0_15px_50px_rgba(0,0,0,.45)] transition duration-200 group-hover:-translate-y-[3px] group-hover:border-[#f7f4ef] group-aria-pressed:-translate-y-[3px] group-aria-pressed:border-[#f7f4ef] max-[760px]:h-[88px] max-[760px]:w-[88px]"
      style={{ background: `radial-gradient(circle at 30% 25%, color-mix(in srgb, ${profile.avatarColor} 60%, white), ${profile.avatarColor})` }}
    >
      {profile.avatarUrl ? <img className="h-full w-full object-cover" src={profile.avatarUrl} alt="" referrerPolicy="no-referrer" /> : <b className="font-display text-[44px] font-extrabold">{profile.name.slice(0, 1).toUpperCase()}</b>}
      {profile.isKids && <i className="absolute right-[5px] bottom-[5px] rounded-[5px] bg-black/70 px-[5px] py-[3px] text-[8px] not-italic">KIDS</i>}
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
    <div className="pwa-profile-modal ui-modal-enter fixed inset-0 z-100 flex min-h-dvh items-center justify-center overflow-y-auto bg-[radial-gradient(circle_at_50%_42%,rgba(31,48,46,.9),rgba(8,9,9,.98)_55%)] px-6 pt-[90px] pb-[54px] max-[760px]:items-start max-[760px]:px-4 max-[760px]:pb-10" role="dialog" aria-modal="true" aria-labelledby="profile-title">
      {activeProfile && (
        <button
          className="pwa-profile-close absolute top-[22px] right-7 flex h-10 w-10 cursor-pointer items-center justify-center rounded-full border border-white/9 bg-white/8 text-[#bbb7b0] transition hover:border-white/20 hover:bg-white/14 hover:text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white max-[760px]:right-[17px]"
          onClick={onClose}
          aria-label="Close profile chooser"
        >
          <svg className="h-[18px] w-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true">
            <path d="M6 6l12 12M18 6 6 18" />
          </svg>
        </button>
      )}
      <img className="pwa-profile-logo absolute top-6 left-7 h-[34px] w-auto max-[760px]:left-[18px] max-[760px]:h-7" src="/krzene-logo.svg" alt="Krzene" />
      <div className="ui-modal-panel-enter w-full max-w-[820px] text-center">
        <p className="mb-4 inline-block rounded-[20px] border border-white/9 bg-white/7 px-[13px] py-2 text-xs text-[#aaa6a0]">{user.email}</p>
        <h1 className="font-display my-[10px] text-[clamp(38px,5vw,64px)] leading-none font-extrabold tracking-[-.045em] max-[760px]:text-[40px]" id="profile-title">{mode === "add" ? "Create a profile" : mode === "manage" ? "Manage profiles" : "Who’s watching?"}</h1>
        <p className="m-0 text-[#aaa6a0]">{mode === "add" ? "Give everyone their own library." : "Choose a profile to continue."}</p>

        {mode === "add" ? (
          <div className="mx-auto mt-[42px] flex max-w-[300px] flex-col items-center gap-3">
            <span className="flex h-28 w-28 items-center justify-center rounded-full bg-[radial-gradient(circle_at_30%_25%,#ee6972,#e21927)] font-sans text-[52px] font-light text-white shadow-[0_15px_50px_rgba(0,0,0,.45)]">+</span>
            <input className="w-full rounded-[10px] border border-[#3a3937] bg-[#171717] px-[14px] py-[13px] text-center text-white outline-none focus:border-krzene-red" value={name} onChange={(event) => setName(event.target.value)} maxLength={32} placeholder="Profile name" autoFocus />
            <label className="my-[3px] mb-2 text-[13px] text-[#aaa6a0]"><input className="mr-[7px] accent-krzene-red" type="checkbox" checked={isKids} onChange={(event) => setIsKids(event.target.checked)} /> Kids profile</label>
            <button className="cursor-pointer rounded-[11px] border border-[#ed3441] bg-krzene-red px-[17px] py-3 font-extrabold disabled:cursor-not-allowed disabled:opacity-45" onClick={add} disabled={!name.trim()}>Create profile</button>
            <button className="cursor-pointer rounded-[11px] border border-white/9 bg-white/4 px-[17px] py-3 font-extrabold" onClick={() => setMode("choose")}>Cancel</button>
          </div>
        ) : (
          <>
            <div className="mx-auto mt-[54px] mb-[58px] flex flex-wrap items-start justify-center gap-6 max-[760px]:mt-[38px] max-[760px]:mb-[45px] max-[760px]:gap-x-[10px] max-[760px]:gap-y-5">
              {profiles.map((profile) => (
                <div className="relative" key={profile.id}>
                  <button className="group flex w-[126px] cursor-pointer flex-col items-center gap-[13px] border-0 bg-transparent p-0 max-[760px]:w-[104px]" aria-pressed={activeProfile?.id === profile.id} onClick={() => choose(profile)}>
                    <ProfileAvatar profile={profile} />
                    <span className="max-w-[126px] overflow-hidden text-sm font-bold text-ellipsis whitespace-nowrap text-[#aaa6a0] group-hover:text-white group-aria-pressed:text-white">{profile.name}</span>
                  </button>
                  {mode === "manage" && profiles.length > 1 && <button className="absolute -top-2 right-[3px] z-2 h-7 w-7 cursor-pointer rounded-full border-2 border-[#090909] bg-krzene-red text-lg" onClick={() => deleteProfile(profile.id)} aria-label={`Delete ${profile.name}`}>×</button>}
                </div>
              ))}
              {mode !== "manage" && profiles.length < 5 && (
                <button className="group flex w-[126px] cursor-pointer flex-col items-center gap-[13px] border-0 bg-transparent p-0 max-[760px]:w-[104px]" onClick={() => setMode("add")}>
                  <span className="flex h-28 w-28 items-center justify-center rounded-full border-[3px] border-white/12 bg-white/8 font-sans text-[58px] leading-none font-light text-[#aaa6a0] transition group-hover:-translate-y-[3px] group-hover:border-[#f7f4ef] max-[760px]:h-[88px] max-[760px]:w-[88px]">+</span><span className="text-sm font-bold text-[#aaa6a0] group-hover:text-white">Add profile</span>
                </button>
              )}
            </div>
            <div className="flex justify-center gap-[10px]">
              <button className="cursor-pointer rounded-[11px] border border-white/9 bg-white/4 px-[17px] py-3 font-extrabold" onClick={() => setMode(mode === "manage" ? "choose" : "manage")}>{mode === "manage" ? "Done" : "Manage profiles"}</button>
              <button className="cursor-pointer rounded-[11px] border border-white/9 bg-white/4 px-[17px] py-3 font-extrabold" onClick={signOut}>Sign out</button>
            </div>
          </>
        )}
        {authError && <p className="mx-auto mt-[18px] text-xs text-[#ff8b93]">{authError}</p>}
      </div>
    </div>
  );
}
