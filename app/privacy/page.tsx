import { LegalPage } from "@/components/LegalPage";

export default function PrivacyPage() {
  return <LegalPage title="Privacy Policy">
    <section><h2>Information we handle</h2><p>When you sign in, Krzene uses Supabase to store your account identifier, viewer profiles, library, and viewing progress. Google supplies the basic profile information you approve during sign-in. We do not receive your Google password.</p></section>
    <section><h2>Payments</h2><p>Premium checkout is hosted by PayMongo. Krzene stores payment references, status, and access dates, but does not receive or store your full card or wallet credentials.</p></section>
    <section><h2>Advertising</h2><p>Non-Premium catalog pages may use Google AdSense. Google and its partners may use cookies or similar technologies to deliver, measure, and personalize ads according to your consent and applicable law. Kids profiles and Premium accounts do not receive Krzene display ads.</p></section>
    <section><h2>Service providers</h2><p>We use Supabase for authentication and data storage, PayMongo for payments, Google for sign-in and advertising, TMDB for catalog metadata, and third-party playback providers. Each provider processes data under its own terms and privacy policy.</p></section>
    <section><h2>Your choices</h2><p>You can remove profiles and library items in the app. To request access, correction, or deletion of account data, contact us through the <a href="/contact">Contact page</a>.</p></section>
  </LegalPage>;
}
