export type SubtitleCue = { start: number; end: number; text: string };

export type BrowserSubtitle = {
  name: string;
  source: string;
  enabled: boolean;
  offset: number;
  speed: number;
  fontSize: number;
  background: number;
  backgroundColor: string;
  color: string;
};

function timestamp(value: string): number {
  const parts = value.replace(",", ".").split(":");
  const seconds = Number(parts.pop());
  const minutes = Number(parts.pop());
  const hours = Number(parts.pop() ?? 0);
  return hours * 3600 + minutes * 60 + seconds;
}

export function parseSubtitle(source: string): SubtitleCue[] {
  const normalized = source.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
  const cues: SubtitleCue[] = [];
  for (const block of normalized.split(/\n{2,}/)) {
    const lines = block
      .split("\n")
      .map((line) => line.trimEnd())
      .filter(Boolean);
    const timingIndex = lines.findIndex((line) => line.includes("-->"));
    if (timingIndex < 0 || timingIndex + 1 >= lines.length) continue;
    const match = lines[timingIndex].match(
      /((?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3})\s*-->\s*((?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3})/,
    );
    if (!match) continue;
    const start = timestamp(match[1]);
    const end = timestamp(match[2]);
    const text = lines
      .slice(timingIndex + 1)
      .join("\n")
      .replace(/<[^>]+>/g, "")
      .replaceAll("&nbsp;", " ")
      .replaceAll("&amp;", "&")
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .trim();
    if (Number.isFinite(start) && Number.isFinite(end) && end > start && text) {
      cues.push({ start, end, text });
    }
  }
  cues.sort((left, right) => left.start - right.start);
  if (!cues.length) throw new Error("No valid subtitle cues were found.");
  return cues;
}

export function subtitleTextAt(
  cues: SubtitleCue[],
  playbackSeconds: number,
  offset: number,
  speed: number,
): string | null {
  const at = (playbackSeconds - offset) * speed;
  if (at < 0) return null;
  let low = 0;
  let high = cues.length - 1;
  while (low <= high) {
    const middle = (low + high) >> 1;
    const cue = cues[middle];
    if (at < cue.start) high = middle - 1;
    else if (at > cue.end) low = middle + 1;
    else {
      const visible = [cue.text];
      for (let index = middle + 1; index < cues.length; index += 1) {
        const next = cues[index];
        if (next.start > at) break;
        if (next.end >= at) visible.push(next.text);
      }
      return visible.join("\n");
    }
  }
  return null;
}

export function subtitleStorageKey(
  mediaKey: string,
  season: number,
  episode: number,
): string {
  return `krzene:subtitle:${mediaKey}:${season}:${episode}`;
}

export function readBrowserSubtitle(key: string): BrowserSubtitle | null {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const value = JSON.parse(raw) as Partial<BrowserSubtitle>;
    if (typeof value.name !== "string" || typeof value.source !== "string") {
      return null;
    }
    parseSubtitle(value.source);
    return {
      name: value.name,
      source: value.source,
      enabled: value.enabled !== false,
      offset: Number(value.offset) || 0,
      speed: Number(value.speed) || 1,
      fontSize: Number(value.fontSize) || 22,
      background: Number.isFinite(Number(value.background))
        ? Number(value.background)
        : 0.68,
      backgroundColor:
        typeof value.backgroundColor === "string"
          ? value.backgroundColor
          : "#000000",
      color: typeof value.color === "string" ? value.color : "#ffffff",
    };
  } catch {
    try {
      localStorage.removeItem(key);
    } catch {
      // Storage can be disabled by privacy settings; playback still works.
    }
    return null;
  }
}

export function writeBrowserSubtitle(
  key: string,
  subtitle: BrowserSubtitle | null,
): void {
  if (!subtitle) localStorage.removeItem(key);
  else localStorage.setItem(key, JSON.stringify(subtitle));
}
