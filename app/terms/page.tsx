import { LegalPage } from "@/components/LegalPage";

export default function TermsPage() {
  return <LegalPage title="Terms of Use">
    <section><h2>Using Krzene</h2><p>You may use Krzene only for lawful, personal purposes and must comply with the rules that apply where you live. Do not misuse, disrupt, scrape, reverse engineer, or attempt unauthorized access to the service or other accounts.</p></section>
    <section><h2>Third-party content</h2><p>Catalog information and playback are supplied by third parties. Availability, accuracy, subtitles, quality, and playback can change without notice. Krzene does not claim ownership of third-party titles or artwork.</p></section>
    <section><h2>Availability</h2><p>The service is provided as available. We may change or suspend features for security, maintenance, legal, or operational reasons.</p></section>
  </LegalPage>;
}
