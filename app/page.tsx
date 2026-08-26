import { StreamingHome } from "@/components/StreamingHome";
import { getHomeData } from "@/lib/home";

// Catalog is rebuilt hourly rather than on every request.
export const revalidate = 3600;

export default async function Home() {
  return <StreamingHome data={await getHomeData()} />;
}
