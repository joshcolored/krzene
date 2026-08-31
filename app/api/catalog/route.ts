import { NextResponse } from "next/server";
import { getHomeData } from "@/lib/home";

export async function GET(request: Request) {
  const language = new URL(request.url).searchParams.get("lang");
  const data = await getHomeData(language);
  return NextResponse.json(data, {
    headers: { "Cache-Control": "public, s-maxage=1800, stale-while-revalidate=3600" },
  });
}
