import { NextResponse } from "next/server";

const API = "https://api.opensubtitles.com/api/v1";

type SubtitleSession = { token: string; baseUrl: string; expiresAt: number };
let cachedSession: SubtitleSession | null = null;

type SubtitleResult = {
  attributes?: {
    language?: string;
    files?: { file_id?: number; file_name?: string }[];
  };
};

function subtitleHeaders(apiKey: string): Record<string, string> {
  return {
    "Api-Key": apiKey,
    "User-Agent": process.env.OPENSUBTITLES_USER_AGENT?.trim() || "Krzene v1",
    accept: "application/json",
  };
}

function apiRoot(baseUrl?: string): string {
  if (!baseUrl) return API;
  const root = baseUrl.startsWith("http") ? baseUrl : `https://${baseUrl}`;
  return root.endsWith("/api/v1") ? root : `${root.replace(/\/$/, "")}/api/v1`;
}

async function subtitleSession(apiKey: string): Promise<SubtitleSession | null> {
  const configuredToken = process.env.OPENSUBTITLES_TOKEN?.trim();
  if (configuredToken) {
    return { token: configuredToken, baseUrl: API, expiresAt: Number.MAX_SAFE_INTEGER };
  }
  if (cachedSession && cachedSession.expiresAt > Date.now()) return cachedSession;
  const username = process.env.OPENSUBTITLES_USERNAME?.trim();
  const password = process.env.OPENSUBTITLES_PASSWORD?.trim();
  if (!username || !password) return null;
  const response = await fetch(`${API}/login`, {
    method: "POST",
    headers: {
      ...subtitleHeaders(apiKey),
      "content-type": "application/json",
    },
    body: JSON.stringify({ username, password }),
    cache: "no-store",
  });
  if (!response.ok) return null;
  const payload = (await response.json()) as { token?: string; base_url?: string };
  if (!payload.token) return null;
  cachedSession = {
    token: payload.token,
    baseUrl: apiRoot(payload.base_url),
    // OpenSubtitles tokens normally last 24 hours. Refresh early.
    expiresAt: Date.now() + 20 * 60 * 60 * 1000,
  };
  return cachedSession;
}

/**
 * Finds and downloads the highest-ranked subtitle while keeping the provider
 * credential and its temporary download URL on the Krzene server.
 */
export async function GET(request: Request) {
  const apiKey = process.env.OPENSUBTITLES_API_KEY?.trim();
  if (!apiKey) {
    return NextResponse.json(
      { error: "Automatic subtitles are not configured yet. You can still import an SRT or VTT file." },
      { status: 503 },
    );
  }
  const params = new URL(request.url).searchParams;
  const type = params.get("type") === "tv" ? "tv" : "movie";
  const tmdbId = Number(params.get("id"));
  const season = Number(params.get("season"));
  const episode = Number(params.get("episode"));
  const language = (params.get("lang") || "en").toLowerCase().replace(/[^a-z-]/g, "").slice(0, 8);
  if (!Number.isInteger(tmdbId) || tmdbId < 1) {
    return NextResponse.json({ error: "Invalid TMDB id." }, { status: 400 });
  }
  if (type === "tv" && (!Number.isInteger(season) || season < 1 || !Number.isInteger(episode) || episode < 1)) {
    return NextResponse.json({ error: "Invalid TV episode." }, { status: 400 });
  }

  let session: SubtitleSession | null;
  try {
    session = await subtitleSession(apiKey);
  } catch (error) {
    console.error("OpenSubtitles login failed", error);
    session = null;
  }
  if (!session) {
    return NextResponse.json(
      { error: "Automatic subtitle downloads require valid OpenSubtitles account credentials on the Krzene server." },
      { status: 503 },
    );
  }

  const search = new URL(`${API}/subtitles`);
  search.searchParams.set(type === "tv" ? "parent_tmdb_id" : "tmdb_id", String(tmdbId));
  search.searchParams.set("type", type === "tv" ? "episode" : "movie");
  search.searchParams.set("languages", language || "en");
  search.searchParams.set("order_by", "download_count");
  search.searchParams.set("order_direction", "desc");
  if (type === "tv") {
    search.searchParams.set("season_number", String(season));
    search.searchParams.set("episode_number", String(episode));
  }

  try {
    const searchResponse = await fetch(search, {
      headers: subtitleHeaders(apiKey),
      cache: "no-store",
    });
    if (!searchResponse.ok) {
      console.error(`OpenSubtitles search → ${searchResponse.status}`);
      return NextResponse.json(
        {
          error:
            searchResponse.status === 429
              ? "The free OpenSubtitles request limit was reached. Download an SRT from Subtitle Cat and choose it from your device instead."
              : "The subtitle search service is temporarily unavailable.",
        },
        { status: searchResponse.status === 429 ? 429 : 502 },
      );
    }
    const payload = (await searchResponse.json()) as { data?: SubtitleResult[] };
    const match = payload.data?.find((item) =>
      item.attributes?.files?.some((file) => file.file_id),
    );
    const file = match?.attributes?.files?.find((candidate) => candidate.file_id);
    if (!file?.file_id) {
      return NextResponse.json(
        { error: "No subtitle was found for this title and language." },
        { status: 404 },
      );
    }

    const downloadResponse = await fetch(`${session.baseUrl}/download`, {
      method: "POST",
      headers: {
        ...subtitleHeaders(apiKey),
        Authorization: `Bearer ${session.token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ file_id: file.file_id, sub_format: "srt" }),
      cache: "no-store",
    });
    if (!downloadResponse.ok) {
      console.error(`OpenSubtitles download → ${downloadResponse.status}`);
      return NextResponse.json(
        {
          error:
            downloadResponse.status === 429
              ? "The free OpenSubtitles daily limit was reached. Download an SRT from Subtitle Cat and choose it from your device instead."
              : "The selected subtitle could not be downloaded.",
        },
        { status: downloadResponse.status === 429 ? 429 : 502 },
      );
    }
    const download = (await downloadResponse.json()) as {
      link?: string;
      file_name?: string;
    };
    if (!download.link) {
      return NextResponse.json(
        { error: "The subtitle download link was missing." },
        { status: 502 },
      );
    }
    const fileResponse = await fetch(download.link, { cache: "no-store" });
    if (!fileResponse.ok) {
      return NextResponse.json(
        { error: "The subtitle file could not be downloaded." },
        { status: 502 },
      );
    }
    const content = await fileResponse.text();
    if (!content.trim()) {
      return NextResponse.json(
        { error: "The subtitle file was empty." },
        { status: 502 },
      );
    }
    return NextResponse.json(
      {
        name: download.file_name || file.file_name || `subtitle-${file.file_id}.srt`,
        language: match?.attributes?.language || language,
        content,
      },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch (error) {
    console.error("OpenSubtitles request failed", error);
    return NextResponse.json(
      { error: "The subtitle service could not be reached." },
      { status: 502 },
    );
  }
}
