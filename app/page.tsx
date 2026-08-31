import { StreamingHome } from "@/components/StreamingHome";
import { getHomeData } from "@/lib/home";
import { cookies } from "next/headers";

// Catalog is rebuilt hourly rather than on every request.
export const revalidate = 3600;

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ lang?: string | string[] }>;
}) {
  const params = await searchParams;
  const requestedLanguage = Array.isArray(params.lang) ? params.lang[0] : params.lang;
  const language = requestedLanguage ?? (await cookies()).get("krzene-language")?.value;
  return <StreamingHome data={await getHomeData(language)} />;
}
