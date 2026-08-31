import { LegalPage } from "@/components/LegalPage";

export default function ContactPage() {
  const email = process.env.NEXT_PUBLIC_SUPPORT_EMAIL?.trim() || "support@krzene.site";
  return <LegalPage title="Contact">
    <section><h2>Support</h2><p>For account, privacy, playback, advertising, or technical questions, email <a href={`mailto:${email}`}>{email}</a>. Include the email used for your account and a short description, but never send passwords, API keys, or one-time codes.</p></section>
  </LegalPage>;
}
