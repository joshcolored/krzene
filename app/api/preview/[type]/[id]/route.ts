import { fetchPreviewKey } from "@/lib/tmdb";

export async function GET(_request: Request, context: { params: Promise<{ type: string; id: string }> }) {
  const { type, id } = await context.params;
  if ((type !== "movie" && type !== "tv") || !/^\d+$/.test(id) || !Number.isSafeInteger(Number(id)) || Number(id) < 1) {
    return new Response("Invalid title", { status: 400 });
  }
  const key = await fetchPreviewKey(type, Number(id));
  if (!key) return new Response("No official preview", { status: 404 });
  // A real HTTPS document supplies the embed's origin/referrer in mobile WebViews.
  // Keep the still visible until YouTube confirms that playback has begun.
  return new Response(`<!doctype html><html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>html,body{margin:0;height:100%;background:#070707;overflow:hidden}#player{width:100%;height:100%}</style>
    </head><body><div id="player"></div><script>
    function report(value){if(window.KrzenePreview)window.KrzenePreview.postMessage(value)}
    function onYouTubeIframeAPIReady(){new YT.Player('player',{
      videoId:${JSON.stringify(key)},
      playerVars:{playsinline:1,controls:0,rel:0,origin:location.origin},
      events:{onReady:function(e){e.target.mute();e.target.playVideo()},
        onStateChange:function(e){if(e.data===1)report('playing');if(e.data===0)report('ended')},
        onError:function(){report('failed')},onAutoplayBlocked:function(){report('failed')}}
    })}
    </script><script src="https://www.youtube.com/iframe_api" onerror="report('failed')"></script></body></html>`, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Referrer-Policy": "strict-origin-when-cross-origin", "Cache-Control": "public, max-age=3600" },
  });
}
