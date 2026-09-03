"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useAuth } from "./AuthProvider";

type AuthMode = "sign-in" | "sign-up" | "forgot" | "recovery";

export function AuthDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const {
    authError,
    passwordRecovery,
    signUpWithEmail,
    signInWithEmail,
    signInWithGoogle,
    signInWithApple,
    requestPasswordReset,
    changePassword,
    finishPasswordRecovery,
    clearAuthError,
    signOut,
  } = useAuth();
  const [mode, setMode] = useState<AuthMode>("sign-in");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [staySignedIn, setStaySignedIn] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [messageIsError, setMessageIsError] = useState(false);

  useEffect(() => {
    if (passwordRecovery) setMode("recovery");
  }, [passwordRecovery]);

  useEffect(() => {
    if (!open) return;
    clearAuthError();
    setMessage(null);
    if (!passwordRecovery) setMode("sign-in");
    const stored = window.localStorage.getItem("krzene-stay-signed-in");
    setStaySignedIn(stored !== "false");
  }, [clearAuthError, open, passwordRecovery]);

  if (!open && !passwordRecovery) return null;

  const changeMode = (nextMode: AuthMode) => {
    clearAuthError();
    setMessage(null);
    setPassword("");
    setConfirmation("");
    setMode(nextMode);
  };

  const close = async () => {
    if (submitting) return;
    if (passwordRecovery) {
      finishPasswordRecovery();
      await signOut();
    }
    onClose();
  };

  const validatePassword = () => {
    if (password.length < 8) return "Password must contain at least 8 characters.";
    if ((mode === "sign-up" || mode === "recovery") && password !== confirmation) {
      return "The passwords do not match.";
    }
    return null;
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (submitting) return;
    setMessage(null);
    clearAuthError();
    const emailLooksValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
    if (mode !== "recovery" && !emailLooksValid) {
      setMessage("Enter a valid email address.");
      setMessageIsError(true);
      return;
    }
    if (mode === "sign-up" && (name.trim().length < 2 || name.trim().length > 64)) {
      setMessage("Enter your name using 2 to 64 characters.");
      setMessageIsError(true);
      return;
    }
    if (mode !== "forgot") {
      const passwordError = validatePassword();
      if (passwordError) {
        setMessage(passwordError);
        setMessageIsError(true);
        return;
      }
    }

    setSubmitting(true);
    try {
      if (mode === "forgot") {
        await requestPasswordReset(email);
        setMessage("If an account exists for that email, a reset link has been sent.");
        setMessageIsError(false);
      } else if (mode === "recovery") {
        await changePassword(password);
        setMessage("Password changed successfully. A security notification will be sent to your email.");
        setMessageIsError(false);
        setPassword("");
        setConfirmation("");
        finishPasswordRecovery();
      } else if (mode === "sign-up") {
        const result = await signUpWithEmail(name, email, password, staySignedIn);
        if (result.confirmationRequired) {
          setMessage(`Check ${result.email} and confirm your email, then sign in.`);
          setMessageIsError(false);
          setMode("sign-in");
          setPassword("");
          setConfirmation("");
        } else {
          onClose();
        }
      } else {
        await signInWithEmail(email, password, staySignedIn);
        onClose();
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Authentication failed. Please try again.");
      setMessageIsError(true);
    } finally {
      setSubmitting(false);
    }
  };

  const socialSignIn = async (provider: "google" | "apple") => {
    if (submitting) return;
    setSubmitting(true);
    clearAuthError();
    setMessage(null);
    try {
      if (provider === "google") await signInWithGoogle(staySignedIn);
      else await signInWithApple(staySignedIn);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Sign-in failed. Please try again.");
      setMessageIsError(true);
      setSubmitting(false);
    }
  };

  const title = mode === "sign-up"
    ? "Create your account"
    : mode === "forgot"
      ? "Reset your password"
      : mode === "recovery"
        ? "Choose a new password"
        : "Sign in to Krzene";

  return (
    <div
      className="ui-modal-enter fixed inset-0 z-100 flex min-h-dvh items-center justify-center overflow-y-auto bg-black/75 px-5 py-10 backdrop-blur-xl"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) void close();
      }}
    >
      <section className="ui-modal-panel-enter relative w-full max-w-[460px] rounded-[24px] border border-white/10 bg-[linear-gradient(145deg,#191919,#0d0d0d)] px-8 py-9 text-center shadow-[0_35px_110px_rgba(0,0,0,.75)] max-[560px]:rounded-[20px] max-[560px]:px-5 max-[560px]:py-7" role="dialog" aria-modal="true" aria-labelledby="auth-title">
        <button type="button" className="absolute top-4 right-4 flex h-9 w-9 cursor-pointer items-center justify-center rounded-full border border-white/9 bg-white/6 text-[#aaa6a0] transition hover:bg-white/13 hover:text-white disabled:opacity-45" onClick={() => void close()} disabled={submitting} aria-label="Close authentication">
          <svg className="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18" /></svg>
        </button>

        <img className="mx-auto mb-5 h-14 w-14 rounded-[17px]" src="/krzene-mark.svg" alt="" />
        <h2 id="auth-title" className="font-display text-[28px] leading-tight font-extrabold tracking-[-.035em]">{title}</h2>
        <p className="mx-auto mt-3 mb-6 max-w-[350px] text-sm leading-relaxed text-[#96918a]">
          {mode === "forgot"
            ? "We’ll email you a secure link to choose a new password."
            : mode === "recovery"
              ? "Use at least 8 characters for your new Krzene password."
              : "Sync your profiles, library, and viewing progress across devices."}
        </p>

        {(mode === "sign-in" || mode === "sign-up") && (
          <div className="mb-5 grid grid-cols-2 rounded-xl border border-white/8 bg-black/25 p-1">
            <button type="button" className={`cursor-pointer rounded-lg px-3 py-2.5 text-sm font-bold ${mode === "sign-in" ? "bg-white/12 text-white" : "text-[#8f8a84]"}`} onClick={() => changeMode("sign-in")}>Sign in</button>
            <button type="button" className={`cursor-pointer rounded-lg px-3 py-2.5 text-sm font-bold ${mode === "sign-up" ? "bg-white/12 text-white" : "text-[#8f8a84]"}`} onClick={() => changeMode("sign-up")}>Create account</button>
          </div>
        )}

        <form className="space-y-3 text-left" onSubmit={submit}>
          {mode === "sign-up" && (
            <input className="w-full rounded-xl border border-white/10 bg-[#171717] px-4 py-3.5 text-white outline-none transition placeholder:text-[#666] focus:border-krzene-red" value={name} onChange={(event) => setName(event.target.value)} autoComplete="name" maxLength={64} placeholder="Name" />
          )}
          {mode !== "recovery" && (
            <input className="w-full rounded-xl border border-white/10 bg-[#171717] px-4 py-3.5 text-white outline-none transition placeholder:text-[#666] focus:border-krzene-red" value={email} onChange={(event) => setEmail(event.target.value)} type="email" autoComplete="email" placeholder="Email" />
          )}
          {mode !== "forgot" && (
            <input className="w-full rounded-xl border border-white/10 bg-[#171717] px-4 py-3.5 text-white outline-none transition placeholder:text-[#666] focus:border-krzene-red" value={password} onChange={(event) => setPassword(event.target.value)} type="password" autoComplete={mode === "sign-in" ? "current-password" : "new-password"} placeholder={mode === "recovery" ? "New password" : "Password"} />
          )}
          {(mode === "sign-up" || mode === "recovery") && (
            <input className="w-full rounded-xl border border-white/10 bg-[#171717] px-4 py-3.5 text-white outline-none transition placeholder:text-[#666] focus:border-krzene-red" value={confirmation} onChange={(event) => setConfirmation(event.target.value)} type="password" autoComplete="new-password" placeholder="Confirm password" />
          )}

          {mode === "sign-in" && (
            <div className="flex items-center justify-between gap-3 py-1">
              <label className="flex cursor-pointer items-center gap-2 text-xs text-[#aaa6a0]"><input className="accent-krzene-red" type="checkbox" checked={staySignedIn} onChange={(event) => setStaySignedIn(event.target.checked)} /> Stay signed in</label>
              <button type="button" className="cursor-pointer border-0 bg-transparent p-0 text-xs font-bold text-[#d8d4ce] hover:text-white" onClick={() => changeMode("forgot")}>Forgot password?</button>
            </div>
          )}

          {(message || authError) && <p className={`text-center text-xs leading-relaxed ${messageIsError || (!message && authError) ? "text-[#ff8b93]" : "text-[#47c98d]"}`}>{message ?? authError}</p>}

          <button type="submit" className="flex min-h-[50px] w-full cursor-pointer items-center justify-center rounded-xl bg-krzene-red px-5 font-extrabold text-white transition hover:bg-[#f02938] active:scale-[.985] disabled:cursor-wait disabled:opacity-60" disabled={submitting}>
            {submitting ? "Please wait…" : mode === "forgot" ? "Send reset link" : mode === "recovery" ? "Save new password" : mode === "sign-up" ? "Create account" : "Sign in with email"}
          </button>
        </form>

        {mode === "forgot" && <button type="button" className="mt-4 cursor-pointer border-0 bg-transparent text-sm font-bold text-[#aaa6a0] hover:text-white" onClick={() => changeMode("sign-in")}>Back to sign in</button>}

        {(mode === "sign-in" || mode === "sign-up") && (
          <>
            <div className="my-5 flex items-center gap-3 text-[10px] font-bold tracking-[.16em] text-[#66625d]"><span className="h-px flex-1 bg-white/9" />OR<span className="h-px flex-1 bg-white/9" /></div>
            <div className="space-y-3">
              <button type="button" className="flex min-h-[50px] w-full cursor-pointer items-center justify-center gap-3 rounded-xl border border-[#dadce0] bg-white px-5 font-bold text-[#202124] transition hover:bg-[#f7f8f8] disabled:opacity-60" onClick={() => void socialSignIn("google")} disabled={submitting}>Continue with Google</button>
              <button type="button" className="flex min-h-[50px] w-full cursor-pointer items-center justify-center gap-3 rounded-xl border border-white/20 bg-black px-5 font-bold text-white transition hover:bg-[#111] disabled:opacity-60" onClick={() => void socialSignIn("apple")} disabled={submitting}><span className="text-2xl leading-none" aria-hidden="true"></span> Continue with Apple</button>
            </div>
          </>
        )}

        <p className="mt-5 text-[11px] leading-relaxed text-[#66625d]">Supabase securely handles your account. Krzene never stores your password.</p>
      </section>
    </div>
  );
}
