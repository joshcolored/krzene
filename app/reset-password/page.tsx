"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { useAuth } from "@/components/AuthProvider";

export default function ResetPasswordPage() {
  const {
    ready,
    user,
    authError,
    changePassword,
    requestPasswordReset,
    finishPasswordRecovery,
  } = useAuth();
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [messageIsError, setMessageIsError] = useState(false);
  const [complete, setComplete] = useState(false);

  const updatePassword = async (event: FormEvent) => {
    event.preventDefault();
    if (submitting) return;
    if (password.length < 8) {
      setMessage("Your new password must contain at least 8 characters.");
      setMessageIsError(true);
      return;
    }
    if (password !== confirmation) {
      setMessage("The new passwords do not match.");
      setMessageIsError(true);
      return;
    }

    setSubmitting(true);
    setMessage(null);
    try {
      await changePassword(password);
      finishPasswordRecovery();
      setPassword("");
      setConfirmation("");
      setComplete(true);
      setMessage("Your password has been changed successfully.");
      setMessageIsError(false);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Your password could not be changed.");
      setMessageIsError(true);
    } finally {
      setSubmitting(false);
    }
  };

  const resend = async (event: FormEvent) => {
    event.preventDefault();
    if (submitting || !email.trim()) return;
    setSubmitting(true);
    setMessage(null);
    try {
      await requestPasswordReset(email);
      setMessage("If an account exists for that email, a new reset link has been sent.");
      setMessageIsError(false);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "A new reset link could not be sent.");
      setMessageIsError(true);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="flex min-h-dvh items-center justify-center bg-[radial-gradient(circle_at_50%_25%,rgba(32,50,47,.72),#070707_52%)] px-5 py-12 text-white">
      <section className="w-full max-w-[470px] rounded-[26px] border border-white/10 bg-[linear-gradient(145deg,#191919,#0d0d0d)] px-8 py-10 text-center shadow-[0_35px_110px_rgba(0,0,0,.75)] max-[560px]:px-5 max-[560px]:py-8">
        <img className="mx-auto mb-5 h-16 w-16 rounded-[18px]" src="/krzene-mark.svg" alt="" />

        {!ready ? (
          <>
            <div className="mx-auto my-7 h-7 w-7 animate-spin rounded-full border-2 border-white/20 border-t-krzene-red" />
            <p className="text-sm text-[#96918a]">Checking your secure reset link…</p>
          </>
        ) : complete ? (
          <>
            <div className="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-full border border-[#236348] bg-[#11372a] text-3xl font-bold text-[#48d39b]">✓</div>
            <h1 className="font-display text-[30px] font-extrabold tracking-[-.035em]">Password changed</h1>
            <p className="mt-3 text-sm leading-relaxed text-[#96918a]">You can now use your new password to sign in to Krzene.</p>
            <Link className="mt-7 inline-flex min-h-[50px] w-full items-center justify-center rounded-xl bg-krzene-red px-5 font-extrabold text-white" href="/">Continue to Krzene</Link>
          </>
        ) : user ? (
          <>
            <p className="mb-3 text-xs font-extrabold tracking-[.15em] text-[#48d39b]">SECURE RECOVERY</p>
            <h1 className="font-display text-[30px] font-extrabold tracking-[-.035em]">Choose a new password</h1>
            <p className="mt-3 mb-7 text-sm leading-relaxed text-[#96918a]">Create a new password for <span className="text-white">{user.email}</span>.</p>
            <form className="space-y-3 text-left" onSubmit={updatePassword}>
              <input className="w-full rounded-xl border border-white/10 bg-[#171717] px-4 py-3.5 text-white outline-none placeholder:text-[#666] focus:border-krzene-red" type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="new-password" placeholder="New password" autoFocus />
              <input className="w-full rounded-xl border border-white/10 bg-[#171717] px-4 py-3.5 text-white outline-none placeholder:text-[#666] focus:border-krzene-red" type="password" value={confirmation} onChange={(event) => setConfirmation(event.target.value)} autoComplete="new-password" placeholder="Confirm new password" />
              <p className="text-xs leading-relaxed text-[#77736e]">Use at least 8 characters. A security notification will be sent after the password changes.</p>
              {(message || authError) && <p className={`text-center text-xs leading-relaxed ${messageIsError ? "text-[#ff8b93]" : "text-[#48d39b]"}`}>{message ?? authError}</p>}
              <button className="flex min-h-[50px] w-full cursor-pointer items-center justify-center rounded-xl bg-krzene-red px-5 font-extrabold text-white disabled:cursor-wait disabled:opacity-60" type="submit" disabled={submitting}>{submitting ? "Saving…" : "Save new password"}</button>
            </form>
          </>
        ) : (
          <>
            <p className="mb-3 text-xs font-extrabold tracking-[.15em] text-[#ff6571]">LINK UNAVAILABLE</p>
            <h1 className="font-display text-[30px] font-extrabold tracking-[-.035em]">Request a new reset link</h1>
            <p className="mt-3 mb-7 text-sm leading-relaxed text-[#96918a]">This password-reset link is invalid, expired, or was opened in a different browser. Enter your email to receive a new link.</p>
            <form className="space-y-3 text-left" onSubmit={resend}>
              <input className="w-full rounded-xl border border-white/10 bg-[#171717] px-4 py-3.5 text-white outline-none placeholder:text-[#666] focus:border-krzene-red" type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" placeholder="Email" autoFocus />
              {(message || authError) && <p className={`text-center text-xs leading-relaxed ${messageIsError ? "text-[#ff8b93]" : "text-[#48d39b]"}`}>{message ?? authError}</p>}
              <button className="flex min-h-[50px] w-full cursor-pointer items-center justify-center rounded-xl bg-krzene-red px-5 font-extrabold text-white disabled:cursor-wait disabled:opacity-60" type="submit" disabled={submitting}>{submitting ? "Sending…" : "Send new reset link"}</button>
            </form>
            <Link className="mt-5 inline-block text-sm font-bold text-[#aaa6a0] hover:text-white" href="/">Back to Krzene</Link>
          </>
        )}
      </section>
    </main>
  );
}
