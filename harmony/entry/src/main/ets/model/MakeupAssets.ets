import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import crypto from '@ohos.security.cryptoFramework';
import { Catalog, InstalledAssets } from '@snapbeauty/core';

interface AssetFile { path: string; bytes: number; sha256: string; }
interface Manifest { schema: number; files: AssetFile[]; }
interface DecodedFile { file: string; sha256: string; bytes: number; }
interface ImageRecord extends DecodedFile {
  width: number; height: number; premultiplied: boolean; argb?: DecodedFile;
}
interface ResourceIndex { schema: number; images: Record<string, ImageRecord>; }
let installQueue: Promise<void> = Promise.resolve();

async function sha256(bytes: Uint8Array): Promise<string> {
  const md = crypto.createMd('SHA256');
  await md.update({ data: bytes });
  const digest = await md.digest();
  let result = '';
  digest.data.forEach((value: number) => { result += value.toString(16).padStart(2, '0'); });
  return result;
}
function safePath(path: string): boolean {
  return path.length > 0 && !path.startsWith('/') && !path.includes('\\') && !path.includes(':') &&
    path.split('/').every((part: string) => part.length > 0 && part !== '.' && part !== '..');
}
function writeFile(path: string, bytes: Uint8Array): void {
  const directory = path.substring(0, path.lastIndexOf('/'));
  if (!fs.accessSync(directory)) { fs.mkdirSync(directory, true); }
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    const buffer = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(buffer).set(bytes);
    let offset = 0;
    while (offset < bytes.length) {
      const count = fs.writeSync(file.fd, buffer.slice(offset));
      if (count <= 0) { throw new Error('写入妆容资源失败'); }
      offset += count;
    }
  } finally { fs.closeSync(file); }
}

// The host combines SDK engine data with its own artwork before starting native rendering.
export async function installDemoAssets(context: common.UIAbilityContext): Promise<InstalledAssets> {
  const task = installQueue.then(() => install(context));
  installQueue = task.then(() => {}, () => {});
  return task;
}

async function install(context: common.UIAbilityContext): Promise<InstalledAssets> {
  const manager = context.resourceManager;
  const decoder = util.TextDecoder.create('utf-8');
  const sdkRaw = await manager.getRawFileContent('engine/asset-manifest.json');
  const hostRaw = await manager.getRawFileContent('demo-makeup/asset-manifest.json');
  const sdk = JSON.parse(decoder.decodeToString(sdkRaw)) as Manifest;
  const host = JSON.parse(decoder.decodeToString(hostRaw)) as Manifest;
  if (sdk.schema !== 1 || host.schema !== 1 || sdk.files.length === 0 || host.files.length === 0) {
    throw new Error('资源清单版本错误');
  }
  const root = `${context.filesDir}/sample-assets/${await sha256(sdkRaw)}-${await sha256(hostRaw)}`;
  const marker = `${root}/.complete`;
  if (!fs.accessSync(marker)) {
    const manifests: Manifest[] = [sdk, host];
    const prefixes: string[] = ['engine', 'demo-makeup'];
    let engineIndex: ResourceIndex | undefined;
    let makeupIndex: ResourceIndex | undefined;
    for (let i = 0; i < manifests.length; i++) {
      for (const file of manifests[i].files) {
        if (!safePath(file.path) || file.bytes < 0 || file.bytes > 128 * 1024 * 1024) {
          throw new Error('资源路径或大小无效');
        }
        const data = await manager.getRawFileContent(`${prefixes[i]}/${file.path}`);
        if (data.length !== file.bytes || await sha256(data) !== file.sha256) {
          throw new Error(`资源校验失败: ${file.path}`);
        }
        if (file.path === 'resources.json') {
          const index = JSON.parse(decoder.decodeToString(data)) as ResourceIndex;
          if (index.schema !== 1) { throw new Error('图像索引版本错误'); }
          if (i === 0) { engineIndex = index; } else { makeupIndex = index; }
        } else { writeFile(`${root}/${file.path}`, data); }
      }
    }
    if (!engineIndex || !makeupIndex) { throw new Error('图像索引缺失'); }
    if (Object.keys(engineIndex.images).some((key: string) => key.startsWith('makeup/'))) {
      throw new Error('SDK 不应内置宿主妆容');
    }
    for (const key of Object.keys(makeupIndex.images)) {
      if (!key.startsWith('makeup/')) { throw new Error('宿主妆容索引路径无效'); }
      engineIndex.images[key] = makeupIndex.images[key];
    }
    writeFile(`${root}/resources.json`, new util.TextEncoder().encodeInto(JSON.stringify(engineIndex)));
    writeFile(marker, new Uint8Array([1]));
  }
  const catalog = JSON.parse(fs.readTextSync(`${root}/catalog.json`)) as Catalog;
  return { root: root, catalog: catalog };
}
