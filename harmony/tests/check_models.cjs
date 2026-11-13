// Run real sample ArkTS models against public SDK and CameraKit stubs; no device validation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const ts = require(path.join(root, '.local/tooling/node_modules/@ohos/hvigor/node_modules/typescript'));
let checks = 0;
function check(value, message) { assert.ok(value, message); checks++; }
function equal(actual, expected, message) { assert.deepEqual(actual, expected, message); checks++; }
function load(file, modules) {
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const exports = {};
  vm.runInNewContext(output, { exports, require: name => {
    if (!(name in modules)) { throw Error(`Unexpected import: ${name}`); }
    return modules[name];
  }, Float32Array, ArrayBuffer, Promise, console }, { filename: file });
  return exports;
}
// The release HAR contains compiled ArkTS, not executable source for Node.
// Exercise the sample models against the documented public SDK objects here;
// the real HAR is separately compiled/linked by Hvigor in build.py.
const installed = path.join(root, 'entry/oh_modules/@snapbeauty/core');
const sdk = { SkinParams: class {}, FaceParams: class {}, SnapBeautyEngine: class {} };
const api = fs.readFileSync(path.join(installed, 'src/main/ets/SnapBeautyEngine.d.ets'), 'utf8');
for (const member of ['SnapBeautyEngine', 'SkinParams', 'FaceParams', 'setMakeup', 'setFilter', 'attach', 'release']) {
  check(api.includes(member), `Published SDK declaration: ${member}`);
}
check(fs.existsSync(path.join(installed, 'ets/modules.abc')), 'compiled SDK bytecode is supplied');
let persisted = '{}';
const preferences = { getPreferencesSync: () => ({ getSync: () => persisted,
  putSync: (_, value) => { persisted = value; }, flush: () => Promise.resolve() }) };
const { EffectSettings, SKIN, FACE } = load(path.join(root, 'entry/src/main/ets/model/EffectSettings.ets'), {
  '@snapbeauty/core': sdk, '@ohos.data.preferences': { default: preferences }
});
const assets = path.join(installed, 'src/main/resources/rawfile/engine');
const hostAssets = path.join(root, 'entry/src/main/resources/rawfile/demo-makeup');
const catalog = JSON.parse(fs.readFileSync(path.join(hostAssets, 'catalog.json')));
check(!fs.existsSync(path.join(assets, 'catalog.json')), 'SDK has no panel catalog');
check(!fs.existsSync(path.join(assets, 'makeup')), 'SDK has no host lip files');
check(!fs.existsSync(path.join(assets, 'icons')), 'SDK has no demo artwork');
const filterIds = Object.keys(JSON.parse(fs.readFileSync(path.join(assets, 'snapbeauty/luts/luts.json'))).inputScale).sort();
const settings = new EffectSettings();
settings.initialize({}, catalog, filterIds);
equal(SKIN.length, 11); equal(FACE.length, 25);
equal(settings.filters.length, 28); equal(settings.makeups.length, 16);
const engine = { skin: {}, face: {}, setMakeup(id, strength) { this.makeup = id; this.makeupStrength = strength; },
  setFilter(id, strength) { this.filter = id; this.filterStrength = strength; } };
settings.apply(engine);
const snapshot = () => JSON.parse(JSON.stringify({ skin: engine.skin, face: engine.face }));
const baseline = snapshot();
equal(baseline.skin.smoothing, 0.7 * 6, 'normalized smoothing scales to SDK 0–6');
// Each UI control must change only its corresponding public SDK property.
for (const tab of [0, 1]) {
  settings.tab = tab;
  for (let i = 0; i < settings.options().length; i++) {
    settings.reset(); settings.selected[tab] = i; settings.change(0.81); settings.apply(engine);
    const expected = JSON.parse(JSON.stringify(baseline));
    expected[tab === 0 ? 'skin' : 'face'][(tab === 0 ? SKIN : FACE)[i].id] = tab === 0 && i === 0 ? 0.81 * 6 : 0.81;
    equal(snapshot(), expected, `${tab}:${i} changes only its documented SDK property`);
  }
}
settings.reset(); settings.tab = 1; settings.selected[1] = 9;
settings.change(0.1); settings.resetItem(); equal(settings.strength(), 0.5, 'bidirectional neutral');
settings.change(Infinity); equal(settings.strength(), 0, 'nonfinite input clamped safely');
settings.change(10); equal(settings.strength(), 1, 'upper bound');
settings.tab = 2; settings.select(1);
equal(settings.filter, catalog.makeup[0].filter, 'makeup selects paired LUT');
settings.change(0.67); equal(settings.filterStrength, 0.67, 'coupled strengths');
settings.tab = 3; settings.select(2); const manual = settings.filter;
settings.tab = 2; settings.select(0); equal(settings.filter, manual, 'removing makeup preserves a manual LUT');
settings.select(1); settings.select(0); equal(settings.filter, '', 'removing makeup clears coupled LUT');
settings.tab = 2; settings.select(3); settings.change(0.63); settings.front = false; settings.save();
const restored = new EffectSettings(); restored.initialize({}, catalog, filterIds);
equal(JSON.parse(JSON.stringify(restored.skin)), JSON.parse(JSON.stringify(settings.skin)));
equal(restored.makeup, settings.makeup); equal(restored.filter, settings.filter);
equal(restored.makeupStrength, 0.63); equal(restored.front, false);
persisted = '{broken'; const damaged = new EffectSettings(); damaged.initialize({}, catalog, filterIds);
equal(damaged.skin[0], 0.7, 'damaged preferences fall back');

async function cameraChecks() {
  let log = [], holdPermission, holdInput, failCommit = false;
  const camera = {
    CameraPosition: { CAMERA_POSITION_FRONT: 1, CAMERA_POSITION_BACK: 2 }, SceneMode: { NORMAL_PHOTO: 1 },
    ImageRotation: { ROTATION_90: 90, ROTATION_270: 270 },
    getCameraManager: () => ({
      getSupportedCameras: () => [{ cameraPosition: 1 }, { cameraPosition: 2 }],
      getSupportedOutputCapability: () => ({ previewProfiles: [{ size: { width: 1280, height: 720 } }] }),
      createCameraInput: () => ({ open: async () => { log.push('input.open'); if (holdInput) { await holdInput; } }, close: async () => log.push('input.close') }),
      createPreviewOutput: () => ({ release: async () => log.push('output.release'), getPreviewRotation: () => 90,
        setPreviewRotation: () => {}, getSupportedFrameRates: () => [{ min: 15, max: 30 }], setFrameRate: () => {} }),
      createSession: () => ({ beginConfig() {}, addInput() {}, addOutput() {},
        commitConfig: async () => { log.push('commit'); if (failCommit) { throw Error('injected'); } },
        start: async () => log.push('session.start'), stop: async () => log.push('session.stop'), release: async () => log.push('session.release') })
    })
  };
  const access = { createAtManager: () => ({ requestPermissionsFromUser: async () => {
    log.push('permission'); if (holdPermission) { await holdPermission; } return { authResults: [0] };
  } }) };
  const { CameraPreview } = load(path.join(root, 'entry/src/main/ets/model/CameraPreview.ets'), {
    '@ohos.multimedia.camera': { default: camera }, '@ohos.abilityAccessCtrl': { default: access }
  });
  const engineStub = { attach: () => { log.push('engine.attach'); return 'input'; }, release: () => log.push('engine.release'),
    configureFrame: (w, h, mirror) => log.push(`frame:${w}x${h}:${mirror}`) };
  const first = new CameraPreview({}, engineStub, () => {});
  first.request(true, true, 'screen', 'assets'); await CameraPreview.queue;
  check(log.includes('frame:720x1280:false'), 'front rotation and no extra horizontal flip');
  check(log.includes('session.start'), 'session starts');
  log = []; first.request(false, true, 'screen', 'assets'); await CameraPreview.queue;
  equal(log.join(','), 'session.stop,session.release,output.release,input.close,engine.release', 'producer releases before native consumer');
  let resume; holdPermission = new Promise(resolve => { resume = resolve; }); log = [];
  first.request(true, true, 'screen', 'assets'); await new Promise(resolve => setImmediate(resolve));
  first.request(false, true, '', 'assets'); resume(); await CameraPreview.queue; holdPermission = undefined;
  check(!log.includes('engine.attach'), 'background during permission cancels before attach');
  holdInput = new Promise(resolve => { resume = resolve; }); log = [];
  first.request(true, true, 'screen', 'assets'); await new Promise(resolve => setImmediate(resolve));
  first.request(false, true, '', 'assets'); resume(); await CameraPreview.queue; holdInput = undefined;
  check(!log.includes('session.start'), 'cancelled input open never starts session');
  equal(log.at(-1), 'engine.release', 'cancelled partial startup releases native preview');
  log = []; failCommit = true; first.request(true, true, 'screen', 'assets'); await CameraPreview.queue;
  equal(log.at(-1), 'engine.release', 'failed commit releases all resources'); failCommit = false;
  first.request(true, true, 'screen', 'assets'); await CameraPreview.queue; log = [];
  const second = new CameraPreview({}, engineStub, () => {});
  second.request(true, false, 'screen2', 'assets'); await CameraPreview.queue;
  check(log.indexOf('engine.release') < log.indexOf('engine.attach'), 'single preview ownership serialized across pages');
  check(log.includes('frame:720x1280:false'), 'back camera does not mirror');
  second.request(false, false, '', ''); await CameraPreview.queue;
}
async function assetChecks() {
  const crypto = require('node:crypto');
  const digest = data => crypto.createHash('sha256').update(data).digest('hex');
  function fixture(kind = '') {
    const files = new Map(), handles = new Map(), raw = new Map();
    const memoryFs = {
      OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
      accessSync: name => files.has(name), mkdirSync: () => {},
      openSync: name => { const fd = handles.size + 1; handles.set(fd, name); files.set(name, Buffer.alloc(0)); return { fd }; },
      writeSync: (fd, value) => { const name = handles.get(fd), data = Buffer.from(value);
        files.set(name, Buffer.concat([files.get(name), data])); return data.length; },
      closeSync: () => {}, readTextSync: name => files.get(name).toString('utf8')
    };
    const util = { TextDecoder: { create: () => ({ decodeToString: value => Buffer.from(value).toString('utf8') }) },
      TextEncoder: class { encodeInto(value) { return new Uint8Array(Buffer.from(value)); } } };
    const nativeCrypto = { createMd: () => { let data = Buffer.alloc(0); return {
      update: async value => { data = Buffer.concat([data, Buffer.from(value.data)]); },
      digest: async () => ({ data: new Uint8Array(crypto.createHash('sha256').update(data).digest()) })
    }; } };
    function add(prefix, values) {
      const records = Object.entries(values).map(([name, value]) => {
        const data = Buffer.from(value); raw.set(prefix + '/' + name, data);
        return { path: name, bytes: data.length, sha256: digest(data) };
      });
      if (kind === 'traversal' && prefix === 'demo-makeup') records[0].path = '../escape';
      raw.set(prefix + '/asset-manifest.json', Buffer.from(JSON.stringify({ schema: 1, files: records })));
    }
    const sdkImages = { base: { file: 'decoded/base.rgba', width: 1, height: 1 } };
    if (kind === 'sdk-artwork') sdkImages['makeup/old.webp'] = sdkImages.base;
    const hostImages = { [kind === 'host-engine' ? 'base' : 'makeup/blush/blush_01.webp']:
      { file: 'decoded/makeup.rgba', width: 1, height: 1 } };
    add('engine', { 'resources.json': JSON.stringify({ schema: 1, images: sdkImages }), 'decoded/base.rgba': 'base' });
    add('demo-makeup', { 'resources.json': JSON.stringify({ schema: 1, images: hostImages }),
      'decoded/makeup.rgba': 'host', 'makeup/lip/lip_01.json': '{"rgba":[0.5,0.2,0.3,0.8]}',
      'catalog.json': JSON.stringify({ skin: [], shape: [], filters: [], makeup: [{ key: 'dawn' }] }) });
    if (kind === 'corrupt') raw.set('demo-makeup/makeup/lip/lip_01.json', Buffer.from('tampered'));
    let reads = 0;
    const context = { filesDir: '/files', resourceManager: { getRawFileContent: async name => {
      reads++; if (!raw.has(name)) throw Error(name); return new Uint8Array(raw.get(name));
    } } };
    const { installDemoAssets } = load(path.join(root, 'entry/src/main/ets/model/MakeupAssets.ets'), {
      '@ohos.file.fs': { default: memoryFs }, '@ohos.util': { default: util },
      '@ohos.security.cryptoFramework': { default: nativeCrypto }
    });
    return { files, context, installDemoAssets, reads: () => reads };
  }
  const valid = fixture(), assets = await valid.installDemoAssets(valid.context);
  const index = JSON.parse(valid.files.get(assets.root + '/resources.json').toString());
  check('base' in index.images && 'makeup/blush/blush_01.webp' in index.images, 'SDK and host indexes merge');
  check(valid.files.has(assets.root + '/decoded/base.rgba'), 'SDK payload installed');
  check(valid.files.has(assets.root + '/decoded/makeup.rgba'), 'host payload installed');
  equal(assets.catalog.makeup[0].key, 'dawn', 'catalog comes from host');
  const before = valid.reads(); await valid.installDemoAssets(valid.context);
  equal(valid.reads() - before, 2, 'completed install checks manifest versions without recopying payloads');
  const parallel = fixture();
  const [first, second] = await Promise.all([parallel.installDemoAssets(parallel.context), parallel.installDemoAssets(parallel.context)]);
  equal(first.root, second.root, 'concurrent pages share the same verified resource root');
  equal(parallel.files.get(first.root + '/decoded/makeup.rgba').length, 4, 'concurrent installers do not interleave file writes');
  for (const [kind, message] of [['corrupt', /校验失败/], ['traversal', /路径或大小/],
    ['sdk-artwork', /SDK 不应/], ['host-engine', /索引路径/]]) {
    const bad = fixture(kind);
    await assert.rejects(bad.installDemoAssets(bad.context), message); checks++;
    check(![...bad.files.keys()].some(name => name.endsWith('/.complete')), kind + ' never marks a partial install complete');
  }
}
Promise.all([cameraChecks(), assetChecks()]).then(() => console.log(`PASS: ${checks} model/public-API/lifecycle checks (SDK and CameraKit stubs, not device validation)`))
  .catch(error => { console.error(error); process.exitCode = 1; });
