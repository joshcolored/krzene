import { LegalPage } from "@/components/LegalPage";

export default function CopyrightPage() {
  const email = process.env.NEXT_PUBLIC_SUPPORT_EMAIL?.trim() || "support@krzene.site";
  return <LegalPage title="Copyright">
    <section><h2>Rights and attribution</h2><p>Krzene&apos;s original interface, branding, and code are protected by applicable intellectual-property law. Movie and series names, artwork, metadata, and video remain the property of their respective owners. TMDB metadata is used under TMDB&apos;s terms.</p></section>
    <section><h2>Copyright reports</h2><p>If you believe material accessible through Krzene infringes your rights, email <a href={`mailto:${email}`}>{email}</a> with your identity, the protected work, the exact URL, your good-faith statement, and your authority to submit the request. Valid notices will be reviewed promptly.</p></section>
  </LegalPage>;
}
