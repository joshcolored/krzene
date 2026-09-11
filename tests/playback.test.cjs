const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require('typescript');

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
