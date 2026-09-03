import { LegalPage } from "@/components/LegalPage";

export default function PrivacyPage() {
  return <LegalPage title="Privacy Policy">
    <section><h2>Information we handle</h2><p>When you sign in, Krzene uses Supabase to store your account identifier, name, viewer profiles, library, and viewing progress. You can use email and password, Apple, or Google. Krzene does not store your password.</p></section>
    <section><h2>Advertising</h2><p>Catalog pages may use Google AdSense. Google and its partners may use cookies or similar technologies to deliver, measure, and personalize ads according to your consent and applicable law. Kids profiles do not receive Krzene display ads.</p></section>
    <section><h2>Service providers</h2><p>We use Supabase for authentication and data storage, Apple and Google for optional social sign-in, Google for advertising, TMDB for catalog metadata, Watchmode for legal streaming-availability links, and third-party playback providers. Each provider processes data under its own terms and privacy policy.</p></section>
    <section><h2>Your choices</h2><p>You can remove profiles and library items in the app. The mobile app also lets you permanently delete your account and connected data from Help &amp; support. To request access or correction, contact us through the <a href="/contact">Contact page</a>.</p></section>
  </LegalPage>;
}
