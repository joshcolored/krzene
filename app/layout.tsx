import type { Metadata, Viewport } from "next";
import "./globals.css";
import { Analytics } from "@vercel/analytics/next";
import { AuthProvider } from "@/components/AuthProvider";
import { PwaRegister } from "@/components/PwaRegister";
import { TvRemoteNavigation } from "@/components/TvRemoteNavigation";

export const metadata: Metadata = {
  title: "Krzene — Your next story starts here",
  description: "A cinematic streaming interface built with Next.js.",
  applicationName: "Krzene",
  other: {
    "google-adsense-account": "ca-pub-5965941687701015",
  },
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "Krzene",
  },
  icons: {
    icon: [{ url: "/icon.svg", type: "image/svg+xml" }],
    shortcut: "/icon.svg",
    apple: "/apple-touch-icon.png",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#070707",
  colorScheme: "dark",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className="bg-krzene-bg font-sans text-krzene-text antialiased">
        <AuthProvider>{children}</AuthProvider>
        <TvRemoteNavigation />
        <PwaRegister />
        <Analytics />
      </body>
    </html>
  );
}
