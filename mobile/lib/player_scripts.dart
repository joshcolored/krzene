// CineSrc suppresses its parent-window events in a top-level WebView. Observe
// the media element directly; do not drive startup by clicking provider UI.
const krzenePlayerScript = r'''
(() => {
  if (window.__krzenePlayerPrepared) return;
  window.__krzenePlayerPrepared = true;
  window.open = () => null;
  const attached = new WeakSet();
  let activeVideo = null;
  let scanTimer = null;
  const post = (payload) => {
    try { KrzeneBridge.postMessage(JSON.stringify(payload)); } catch (_) {}
  };
  window.addEventListener('message', (event) => {
    if (event.origin !== 'https://cinesrc.st') return;
    try {
      const payload = typeof event.data === 'string'
        ? JSON.parse(event.data) : event.data;
      if (payload && payload.type !== 'cinesrc:command') post(payload);
    } catch (_) {}
  });
  const report = (video, phase = 'progress') => {
    if (!video.isConnected || activeVideo !== video) return;
    post({ type: 'KRZENE_PROGRESS', data: {
      position: video.currentTime || 0,
      duration: Number.isFinite(video.duration) ? video.duration : 0,
      paused: video.paused,
      readyState: video.readyState,
      muted: video.muted,
      playbackRate: video.playbackRate,
      phase,
      buffering: !!video.error || (!video.paused && video.readyState < 3)
    }});
  };
  const disableCaptions = (video) => {
    Array.from(video.textTracks || []).forEach((track) => {
      if (track.mode !== 'disabled') track.mode = 'disabled';
    });
  };
  window.__krzeneBoostLevel = 1;
  const applyBoost = (video) => {
    const level = window.__krzeneBoostLevel;
    // Keep the normal audio path untouched until the user requests a boost.
    if (level <= 1 && !video.__krzeneGain) return;
    try {
      const owner = video.ownerDocument.defaultView;
      const AudioEngine = owner.AudioContext || owner.webkitAudioContext;
      if (!AudioEngine) return;
      if (!video.__krzeneGain) {
        // A failed attachment (e.g. a provider-owned audio graph) is not retried
        // on every DOM mutation. Creating a second source for a video is invalid.
        if (video.__krzeneGainAttempted) return;
        video.__krzeneGainAttempted = true;
        owner.__krzeneAudioContext ||= new AudioEngine();
        const context = owner.__krzeneAudioContext;
        const source = context.createMediaElementSource(video);
        const gain = context.createGain();
        source.connect(gain);
        gain.connect(context.destination);
        video.__krzeneGain = gain;
      }
      const context = owner.__krzeneAudioContext;
      if (video.volume !== 1) video.volume = 1;
      video.__krzeneGain.gain.setTargetAtTime(level, context.currentTime, 0.015);
      context.resume().catch(() => {});
    } catch (_) {}
  };
  window.__krzeneSetBoost = (level) => {
    window.__krzeneBoostLevel = Math.max(1, Math.min(3, Number(level) || 1));
    if (activeVideo) applyBoost(activeVideo);
  };
  const attach = (video) => {
    activeVideo = video;
    if (attached.has(video)) return;
    attached.add(video);
    video.playsInline = true;
    video.setAttribute('playsinline', '');
    video.setAttribute('webkit-playsinline', '');
    video.controls = false;
    disableCaptions(video);
    video.textTracks?.addEventListener('addtrack', () => disableCaptions(video));
    let started = !video.paused;
    let attempted = false;
    const startOnce = () => {
      if (started || attempted || !video.paused || video.readyState < 3) return;
      attempted = true;
      // One fallback after media is playable. Abort/network failures are left
      // to CineSrc's recovery, never treated as an autoplay permission failure.
      video.play().catch((error) => {
        if (error?.name !== 'NotAllowedError') return;
        video.muted = true;
        video.play().catch(() => report(video, 'autoplayblocked'));
      });
    };
    for (const phase of ['loadedmetadata', 'loadeddata', 'canplay', 'playing',
      'play', 'pause', 'waiting', 'stalled', 'seeking', 'seeked', 'ended',
      'timeupdate', 'error', 'volumechange', 'ratechange']) {
      video.addEventListener(phase, () => {
        if (phase === 'playing') started = true;
        report(video, phase);
        if (phase === 'canplay') startOnce();
      });
    }
    applyBoost(video);
    report(video);
    startOnce();
  };
  const scan = () => {
    scanTimer = null;
    document.querySelectorAll([
      '[class*="popunder" i]', '[id*="popunder" i]',
      '[class*="popup-ad" i]', '[id*="popup-ad" i]',
      '[class*="ad-overlay" i]', '[id*="ad-overlay" i]',
      'iframe[src*="doubleclick.net"]',
      'iframe[src*="googlesyndication.com"]',
      'iframe[src*="popads.net"]'
    ].join(',')).forEach((node) => node.remove());
    document.querySelectorAll('video').forEach(attach);
  };
  new MutationObserver(() => {
    if (scanTimer === null) scanTimer = setTimeout(scan, 50);
  }).observe(document.documentElement, { childList: true, subtree: true });
  const style = document.createElement('style');
  style.textContent = 'video::cue { color: transparent !important; background: transparent !important; }';
  document.documentElement.appendChild(style);
  scan();
  // Sample actual media time even while the controls are hidden. No synthetic
  // progress, play clicks, seeks or audio graph recreation in this interval.
  window.setInterval(() => {
    if (activeVideo) report(activeVideo);
  }, 500);
})();
''';
