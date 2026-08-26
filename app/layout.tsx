import type { Metadata } from "next";
import "./globals.css";
import "./player.css";
import { AuthProvider } from "@/components/AuthProvider";

export const metadata: Metadata = {
  title: "Krzene — Your next story starts here",
  description: "A cinematic streaming interface built with Next.js.",
  applicationName: "Krzene",
  icons: {
    icon: [{ url: "/icon.svg", type: "image/svg+xml" }],
    shortcut: "/icon.svg",
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className="bg-krzene-bg font-sans text-krzene-text antialiased"><AuthProvider>{children}</AuthProvider></body>
    </html>
  );
}
