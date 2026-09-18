type FullscreenDocument = Document & {
  webkitFullscreenElement?: Element | null;
  webkitFullscreenEnabled?: boolean;
  webkitExitFullscreen?: () => void | Promise<void>;
};

type FullscreenTarget = HTMLElement & {
  webkitRequestFullscreen?: () => void | Promise<void>;
};

export function fullscreenElement(doc: Document): Element | null {
  const browser = doc as FullscreenDocument;
  return browser.fullscreenElement ?? browser.webkitFullscreenElement ?? null;
}

/** Call directly from the click handler, before awaiting anything else. */
export async function enterPlayerFullscreen(target: HTMLElement): Promise<boolean> {
  const browser = target.ownerDocument as FullscreenDocument;
  const element = target as FullscreenTarget;
  try {
    if (typeof element.requestFullscreen === "function" && browser.fullscreenEnabled !== false) {
      await element.requestFullscreen({ navigationUI: "hide" });
      return true;
    }
    if (typeof element.webkitRequestFullscreen === "function" && browser.webkitFullscreenEnabled !== false) {
      await element.webkitRequestFullscreen();
      return true;
    }
  } catch {
    // Unsupported devices and denied permissions use the in-page fallback.
  }
  return false;
}

export async function exitPlayerFullscreen(doc: Document): Promise<boolean> {
  const browser = doc as FullscreenDocument;
  if (!fullscreenElement(doc)) return true;
  try {
    if (typeof browser.exitFullscreen === "function") await browser.exitFullscreen();
    else if (typeof browser.webkitExitFullscreen === "function") await browser.webkitExitFullscreen();
    else return false;
    return true;
  } catch {
    return false;
  }
}

/** The cross-origin player must receive the tap for iPhone native video fullscreen. */
export function nativePlayerUrl(sourceUrl: string, position: number): string {
  const url = new URL(sourceUrl);
  url.searchParams.set("controls", "true");
  url.searchParams.set("continueprompt", "false");
  url.searchParams.set("t", String(Math.floor(Number.isFinite(position) ? Math.max(0, position) : 0)));
  return url.toString();
}
