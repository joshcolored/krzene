const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');
const vm = require('node:vm');

function load(name) {
  const filename = path.resolve(__dirname, '../lib', name + '.ts');
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  });
  const mod = new Module(filename, module);
  mod.filename = filename;
  mod.paths = module.paths;
  mod._compile(compiled.outputText, filename);
  return mod.exports;
}
const { embedUrl, PLAYBACK_SOURCES } = load('playback');
const { parseSubtitle, subtitleTextAt } = load('browser-subtitles');
const { parseCineSrcMessage, reducePlaybackEvent } = load('playback-bridge');
const { mappingsFromDataset, resolveAnimeEpisode } = load('anime-mappings');
test('only CineSrc and Zoryva are selectable, CineSrc stays default', () => {
  assert.deepEqual(PLAYBACK_SOURCES.map(s => s.id), ['cinesrc', 'zoryva']);
  assert.equal(embedUrl('tv', 1429, 2, 3), 'https://cinesrc.st/embed/tv/1429?s=2&e=3');
});
test('Zoryva movie/TV URLs use TMDB IDs and encoded theme color', () => {
  assert.equal(embedUrl('movie', 129, null, null, { provider: 'zoryva' }),
    'https://zoryva.me/embed/movie/129?color=%23e50914&exit=hide');
  assert.equal(embedUrl('tv', 1429, 2, 3, { provider: 'zoryva' }),
    'https://zoryva.me/embed/tv/1429/2/3?color=%23e50914&exit=hide');
  assert.throws(() => embedUrl('tv', 'tt123', 1, 1));
});
test('CineSrc resume and episode syntax is unchanged', () => {
  assert.equal(embedUrl('tv', 1429, 2, 3, { autoplay: true, startAt: 42.9 }),
    'https://cinesrc.st/embed/tv/1429?s=2&e=3&autoplay=true&t=42');
});
test('CineSrc supports Krzene custom controls and quality parameters', () => {
  assert.equal(
    embedUrl('movie', 129, null, null, { customControls: true, quality: '1080' }),
    'https://cinesrc.st/embed/movie/129?controls=false&seek=10&color=%23e21927&continueprompt=false&quality=1080',
  );
});
test('season/cour and episode offsets map to AniList, not TMDB IDs', () => {
  const mappings = mappingsFromDataset({
    'tmdb_show:1429:s3': {
      'anilist:99147': { '1-12': '1-12' },
      'anilist:104578': { '13-22': '1-10' },
    },
    'tmdb_movie:1429': { 'anilist:999': { '1': '1' } },
  }, 'tv', 1429);
  const mapped = resolveAnimeEpisode(mappings, 3, 14);
  assert.deepEqual(mapped, { anilistId: 104578, episode: 2 });
  assert.equal(embedUrl('tv', 1429, 1, mapped.episode, { provider: 'zoryva', anilistId: mapped.anilistId }),
    'https://zoryva.me/embed/anime/104578/1/2?color=%23e50914&exit=hide');
  assert.equal(resolveAnimeEpisode(mappings, 4, 1), null);
  assert.equal(resolveAnimeEpisode(mappings, 3, 23), null);
});
test('unmapped, ambiguous and split episodes do not guess', () => {
  const mappings = mappingsFromDataset({ 'tmdb_show:1:s1': {
    'anilist:2': { '1-2': '1-2' }, 'anilist:3': { '1-2': '1-2' },
    'anilist:4': { '3-4': '1-4|2' }, 'anilist:5': {},
  } }, 'tv', 1);
  assert.equal(resolveAnimeEpisode(mappings, 1, 1), null);
  assert.equal(resolveAnimeEpisode(mappings, 1, 3), null);
  assert.deepEqual(mappingsFromDataset({}, 'movie', 129), []);
});
test('movie IDs and discontinuous/open-ended ranges are supported', () => {
  const movie = mappingsFromDataset({ 'tmdb_movie:129': { 'anilist:199': { '1': '1' } } }, 'movie', 129);
  assert.deepEqual(resolveAnimeEpisode(movie, 1, 1), { anilistId: 199, episode: 1 });
  const mappings = mappingsFromDataset({ 'tmdb_show:1:s1': { 'anilist:2': {
    '1-4': '1-2,4-5', '5-': '6-',
  } } }, 'tv', 1);
  assert.deepEqual(resolveAnimeEpisode(mappings, 1, 3), { anilistId: 2, episode: 4 });
  assert.deepEqual(resolveAnimeEpisode(mappings, 1, 7), { anilistId: 2, episode: 8 });
});
test('browser subtitle parser follows timing, offset and speed', () => {
  const cues = parseSubtitle('1\n00:00:01,000 --> 00:00:03,000\nHello web\n');
  assert.equal(subtitleTextAt(cues, 2, 0, 1), 'Hello web');
  assert.equal(subtitleTextAt(cues, 1.4, 0.5, 1), null);
  assert.equal(subtitleTextAt(cues, 1, 0, 2), 'Hello web');
});

test('custom playback supports browser-safe autoplay without losing episode resume', () => {
  const url = new URL(embedUrl('tv', 1429, 2, 3, {
    autoplay: true, muted: true, customControls: true, startAt: 42,
  }));
  assert.equal(url.searchParams.get('muted'), 'true');
  assert.equal(url.searchParams.get('t'), '42');
  assert.equal(url.searchParams.get('continueprompt'), 'false');
});

test('CineSrc readiness follows media events, not source or command messages', () => {
  const idle = { connected: false, playing: false, buffering: true, position: 0, duration: 0 };
  for (const message of [
    { type: 'cinesrc:sourceused', sourceId: 'test' },
    { type: 'cinesrc:command', command: 'play' },
    { type: 'cinesrc:response', command: 'getPaused', result: {} },
  ]) assert.equal(reducePlaybackEvent(idle, message), idle);
  const ready = reducePlaybackEvent(idle, { type: 'cinesrc:ready' });
  assert.equal(ready.connected, true);
  assert.equal(ready.buffering, true);
  const metadata = reducePlaybackEvent(ready, { type: 'cinesrc:loadedmetadata', duration: 120 });
  assert.equal(metadata.duration, 120);
  assert.equal(metadata.buffering, false);
  const playing = reducePlaybackEvent(metadata, { type: 'cinesrc:play' });
  assert.equal(playing.playing, true);
  const recovery = reducePlaybackEvent(playing, { type: 'cinesrc:error', error: 'temporary network error' });
  assert.equal(recovery.connected, true);
  assert.equal(recovery.buffering, true);
  assert.equal(reducePlaybackEvent(recovery, { type: 'cinesrc:play' }).buffering, false);
});

test('autoplay rejection allows a user play action and invalid messages are ignored', () => {
  assert.equal(parseCineSrcMessage('not JSON'), null);
  assert.equal(parseCineSrcMessage({ type: 'advertisement' }), null);
  const blocked = reducePlaybackEvent({ connected: true, playing: false, buffering: true }, {
    type: 'cinesrc:error', error: 'NotAllowedError: user gesture required',
  });
  assert.equal(blocked.autoplayBlocked, true);
  assert.equal(blocked.buffering, false);
  assert.equal(reducePlaybackEvent(blocked, { type: 'cinesrc:play' }).autoplayBlocked, false);
});

function mobileBridge({ paused = false, readyState = 4, playError } = {}) {
  const dart = fs.readFileSync(path.resolve(__dirname, '../mobile/lib/player_scripts.dart'), 'utf8');
  const script = dart.match(/const krzenePlayerScript = r'''([\s\S]*?)''';/)[1];
  const messages = [], intervals = [], timers = [];
  let observer, audioContexts = 0, playCalls = 0;
  const listeners = new Map();
  const track = { mode: 'showing' };
  const video = {
    isConnected: true, paused, readyState, currentTime: 42, duration: 120,
    muted: false, playbackRate: 1, volume: 1,
    textTracks: Object.assign([track], { addEventListener() {} }),
    setAttribute() {},
    addEventListener(type, listener) { listeners.set(type, listener); },
    play() { playCalls++; return playError ? Promise.reject(playError) : Promise.resolve(); },
  };
  const document = {
    documentElement: { appendChild() {} },
    createElement() { return {}; },
    querySelectorAll(selector) { return selector === 'video' ? [video] : []; },
  };
  const window = {
    addEventListener() {}, setInterval(fn) { intervals.push(fn); },
    AudioContext: function () {
      audioContexts++;
      this.createMediaElementSource = () => ({ connect() {} });
      this.createGain = () => ({ connect() {}, gain: { setTargetAtTime() {} } });
      this.resume = () => Promise.resolve();
    },
  };
  video.ownerDocument = { defaultView: window };
  const context = vm.createContext({ window, document,
    MutationObserver: function (callback) { observer = callback; this.observe = () => {}; },
    setTimeout: (fn) => { timers.push(fn); return timers.length; },
    KrzeneBridge: { postMessage: value => messages.push(JSON.parse(value)) },
  });
  vm.runInContext(script, context);
  return { video, messages, window,
    executeAgain: () => vm.runInContext(script, context),
    mutate: () => { observer(); while (timers.length) timers.shift()(); },
    emit: (type) => listeners.get(type)?.(),
    tick: () => intervals.forEach(fn => fn()),
    get audioContexts() { return audioContexts; },
    get playCalls() { return playCalls; },
  };
}

test('mobile bridge observes startup without extra play, seek or audio initialization', () => {
  const bridge = mobileBridge();
  bridge.executeAgain();
  for (let i = 0; i < 10; i++) { bridge.mutate(); bridge.tick(); }
  assert.equal(bridge.playCalls, 0);
  assert.equal(bridge.audioContexts, 0);
  assert.equal(bridge.video.currentTime, 42);
  assert.equal(bridge.messages.at(-1).data.paused, false);
  bridge.emit('playing');
  bridge.video.paused = true;
  bridge.emit('pause');
  bridge.emit('canplay');
  bridge.mutate();
  assert.equal(bridge.playCalls, 0, 'must not restart user-paused playback');
  bridge.window.__krzeneSetBoost(2);
  assert.equal(bridge.audioContexts, 1);
  bridge.window.__krzeneSetBoost(1);
  bridge.mutate();
  assert.equal(bridge.audioContexts, 1);
});

test('mobile loading state stays truthful and the one fallback waits for playable media', () => {
  const bridge = mobileBridge({ paused: true, readyState: 0 });
  bridge.tick(); bridge.mutate();
  assert.equal(bridge.playCalls, 0);
  assert.equal(bridge.messages.at(-1).data.readyState, 0);
  bridge.video.readyState = 4;
  bridge.emit('canplay'); bridge.emit('canplay'); bridge.mutate();
  assert.equal(bridge.playCalls, 1);
  bridge.video.paused = false;
  bridge.video.readyState = 2;
  bridge.emit('waiting');
  assert.equal(bridge.messages.at(-1).data.buffering, true);
});

test('mobile never treats an interrupted play as an autoplay rejection', async () => {
  const bridge = mobileBridge({ paused: true, playError: { name: 'AbortError' } });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(bridge.playCalls, 1);
  assert.equal(bridge.video.muted, false);
  bridge.mutate(); bridge.emit('canplay');
  assert.equal(bridge.playCalls, 1);
});

test('mobile retries muted only for an autoplay permission rejection', async () => {
  const bridge = mobileBridge({ paused: true, playError: { name: 'NotAllowedError' } });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(bridge.playCalls, 2);
  assert.equal(bridge.video.muted, true);
  assert.equal(bridge.messages.at(-1).data.phase, 'autoplayblocked');
  bridge.mutate(); bridge.emit('canplay');
  assert.equal(bridge.playCalls, 2);
});

test('mobile snapshots preserve a media error until the provider recovers', () => {
  const bridge = mobileBridge();
  bridge.video.error = { code: 2 };
  bridge.emit('error'); bridge.tick();
  assert.equal(bridge.messages.at(-1).data.buffering, true);
  bridge.video.error = null;
  bridge.emit('playing'); bridge.tick();
  assert.equal(bridge.messages.at(-1).data.buffering, false);
});
