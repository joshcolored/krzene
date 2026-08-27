import { LegalPage } from "@/components/LegalPage";

export default function ContactPage() {
  const email = process.env.NEXT_PUBLIC_SUPPORT_EMAIL?.trim() || "support@krzene.site";
  return <LegalPage title="Contact">
    <section><h2>Support</h2><p>For account, Premium, privacy, playback, or technical questions, email <a href={`mailto:${email}`}>{email}</a>. Include the email used for your account and a short description, but never send passwords, full card numbers, API keys, or one-time codes.</p></section>
    <section><h2>Payment help</h2><p>For a Premium payment issue, include the date, amount, and PayMongo reference shown on your receipt. We will never ask for your wallet PIN or card security code.</p></section>
  </LegalPage>;
}
