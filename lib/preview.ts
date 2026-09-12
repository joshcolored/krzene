export type PreviewVideo = { key: string; site: string; type: string; official?: boolean };

export function selectOfficialPreview(videos: PreviewVideo[]): string | null {
  const candidates = videos.filter((video) =>
    video.official === true && video.site === "YouTube" &&
    ["Teaser", "Trailer"].includes(video.type) && /^[\w-]{11}$/.test(video.key),
  );
  return (candidates.find((video) => video.type === "Teaser") ?? candidates[0])?.key ?? null;
}
