import { SnapBeautyEngine, SkinParams, FaceParams, Catalog } from '@snapbeauty/core';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';

export class EffectOption {
  id: string;
  label: string;
  neutral: number;
  constructor(id: string, label: string, neutral: number = 0) {
    this.id = id; this.label = label; this.neutral = neutral;
  }
}
export const SKIN: EffectOption[] = [
  new EffectOption('smoothing', '磨皮'), new EffectOption('brightening', '美白'),
  new EffectOption('rosiness', '红润'), new EffectOption('sharpness', '锐化'),
  new EffectOption('texture', '清晰'), new EffectOption('blemishRemoval', '祛斑痘'),
  new EffectOption('eyeBrightening', '亮眼'), new EffectOption('teethWhitening', '美牙'),
  new EffectOption('undereyeBags', '去黑眼圈'), new EffectOption('smileLines', '去法令纹'),
  new EffectOption('faceContour', '五官立体')
];
export const FACE: EffectOption[] = [
  new EffectOption('faceSlimming', '瘦脸'), new EffectOption('faceVTaper', 'V 脸'),
  new EffectOption('faceNarrowing', '窄脸'), new EffectOption('faceShortening', '短脸'),
  new EffectOption('faceShrinking', '小脸'), new EffectOption('cheekboneWidth', '颧骨'),
  new EffectOption('jawWidth', '下颌骨'), new EffectOption('eyeScale', '大眼'),
  new EffectOption('eyeRoundness', '圆眼'), new EffectOption('chinLength', '下巴', 0.5),
  new EffectOption('foreheadHeight', '额头', 0.5), new EffectOption('noseWidth', '瘦鼻'),
  new EffectOption('mouthSize', '嘴型', 0.5), new EffectOption('lipFullness', '唇厚', 0.5),
  new EffectOption('eyePosition', '眼睛高度', 0.5), new EffectOption('eyeCornerOpening', '开眼角'),
  new EffectOption('eyelidFold', '眼睑下至'), new EffectOption('eyeDistance', '眼距', 0.5),
  new EffectOption('eyeTilt', '眼睛倾斜', 0.5), new EffectOption('noseLength', '鼻长', 0.5),
  new EffectOption('philtrumLength', '人中', 0.5), new EffectOption('mouthCorners', '微笑嘴角'),
  new EffectOption('browPosition', '眉高', 0.5), new EffectOption('browDistance', '眉间距', 0.5),
  new EffectOption('browThickness', '眉毛粗细', 0.5)
];
const LIPSTICKS: EffectOption[] = [new EffectOption('', '无'), new EffectOption('coral', '珊瑚色'),
  new EffectOption('grapefruit', '西柚色'), new EffectOption('rosewood', '豆沙粉'),
  new EffectOption('tangerine', '元气橘'), new EffectOption('vintage', '复古红')];
const LIP_COLORS: number[][] = [[], [.611, .352, .352, .500], [.752, .267, .231, .543],
  [.713, .374, .409, .517], [.786, .326, .252, .629], [.476, .018, .025, .777]];
const DEFAULT_SKIN: number[] = [0.6, 0.48, 0.1, 0, 0.12, 0.38, 0.28, 0, 0.45, 0.35, 0.28];
const MALE_SKIN: number[] = [0.45, 0.22, 0.08, 0.16, 0.16, 0.35, 0.20, 0, 0.40, 0.20, 0.40];
const SETTINGS_SCHEMA: number = 2;

function seriesName(family: string): string {
  if (family === 'bright') { return '明亮'; }
  if (family === 'rose') { return '玫瑰'; }
  if (family === 'stylized') { return '个性'; }
  if (family === 'mono') { return '黑白'; }
  if (family === 'cool') { return '冷调'; }
  if (family === 'peach') { return '蜜桃'; }
  if (family === 'warm') { return '暖调'; }
  if (family === 'fresh') { return '清新'; }
  if (family === 'muted') { return '柔灰'; }
  if (family === 'natural') { return '自然'; }
  return '';
}
/** Same visible names as the Android sample: series plus the numeric suffix, never the raw LUT id. */
export function filterLabel(key: string): string {
  let end = key.length;
  while (end > 0 && key.charCodeAt(end - 1) >= 48 && key.charCodeAt(end - 1) <= 57) { end--; }
  const series = seriesName(key.substring(0, end));
  if (series.length > 0) { return `${series} ${key.substring(end)}`; }
  let hash = 0;
  for (let i = 0; i < key.length; i++) { hash = (Math.imul(31, hash) + key.charCodeAt(i)) | 0; }
  const hex = (hash < 0 ? hash + 4294967296 : hash).toString(16);
  return `光谱 ${hex.length > 4 ? hex.substring(hex.length - 4) : hex}`;
}
interface SavedSettings {
  schema: number; skin: number[]; face: number[]; filter: string; filterStrength: number;
  makeup: string; makeupStrength: number; coupled: boolean; front: boolean; tab: number; selected: number[];
}

function unit(value: number, fallback: number = 0): number {
  return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
}

export class EffectSettings {
  skin: number[] = DEFAULT_SKIN.slice();
  face: number[] = FACE.map((item: EffectOption) => item.neutral);
  filters: EffectOption[] = [new EffectOption('', '原色')];
  makeups: EffectOption[] = [new EffectOption('', '无妆')];
  filter: string = '';
  filterStrength: number = 0.4;
  makeup: string = '';
  makeupStrength: number = 0.6;
  coupled: boolean = false;
  front: boolean = true;
  tab: number = 0;
  selected: number[] = [0, 0, 0, 0, 0];
  lipstickLevels: number[] = [0.6, 0.6, 0.6, 0.6, 0.6, 0.6];
  malePreset: boolean = false;
  private catalog: Catalog | undefined;
  private store: preferences.Preferences | undefined;

  initialize(context: common.UIAbilityContext, catalog: Catalog, filterIds: string[]): void {
    this.catalog = catalog;
    const filterKeys: string[] = [];
    for (const id of filterIds) {
      if (id !== 'origin' && !filterKeys.includes(id)) { filterKeys.push(id); }
    }
    filterKeys.sort();
    this.filters = [new EffectOption('', '原色')].concat(filterKeys.map((id: string) => new EffectOption(id, filterLabel(id))));
    this.makeups = [new EffectOption('', '无妆')].concat(catalog.makeup.map((row) =>
      new EffectOption(row.key, row.label.length > 0 ? row.label : row.key)));
    this.useAndroidDefaults();
    this.store = preferences.getPreferencesSync(context, { name: 'camera-effects-v1' });
    try {
      const saved = JSON.parse(this.store.getSync('settings', '{}') as string) as SavedSettings;
      if (saved.schema !== SETTINGS_SCHEMA) { return; }
      if (Array.isArray(saved.skin) && saved.skin.length === SKIN.length) {
        this.skin = saved.skin.map((value: number, i: number) => unit(value, this.skin[i]));
      }
      if (Array.isArray(saved.face) && saved.face.length === FACE.length) {
        this.face = saved.face.map((value: number, i: number) => unit(value, FACE[i].neutral));
      }
      this.filter = this.filters.some((item: EffectOption) => item.id === saved.filter) ? saved.filter : '';
      this.makeup = this.makeups.some((item: EffectOption) => item.id === saved.makeup) ? saved.makeup : '';
      this.filterStrength = unit(saved.filterStrength, 0.4);
      this.makeupStrength = unit(saved.makeupStrength, 0.4);
      this.coupled = saved.coupled === true;
      this.front = saved.front !== false;
      this.tab = Number.isInteger(saved.tab) && saved.tab >= 0 && saved.tab < 4 ? saved.tab : 0;
      if (Array.isArray(saved.selected) && saved.selected.length === 4) {
        this.selected = saved.selected.map((value: number, tab: number) =>
          Number.isInteger(value) && value >= 0 && value < this.options(tab).length ? value : 0);
      }
      this.selected[2] = this.makeups.findIndex((item: EffectOption) => item.id === this.makeup);
      this.selected[3] = this.filters.findIndex((item: EffectOption) => item.id === this.filter);
      // Each entry starts with the requested effect defaults; keep the saved camera choice.
      this.useAndroidDefaults();
    } catch (_) { /* Invalid or older preferences keep safe defaults. */ }
  }

  options(tab: number = this.tab): EffectOption[] {
    return tab === 0 ? SKIN : tab === 1 ? FACE : tab === 2 ? this.makeups : tab === 3 ? this.filters : LIPSTICKS;
  }
  select(index: number): void {
    this.selected[this.tab] = index;
    if (this.tab === 2) {
      this.makeup = this.makeups[index].id;
      const row = this.catalog?.makeup.find((item) => item.key === this.makeup);
      if (this.makeup) {
        this.filter = row?.filter && this.filters.some((item: EffectOption) => item.id === row.filter) ? row.filter : '';
        this.filterStrength = this.makeupStrength;
        this.coupled = true;
      } else if (this.coupled) { this.filter = ''; this.coupled = false; }
      this.selected[3] = this.filters.findIndex((item: EffectOption) => item.id === this.filter);
    }
    if (this.tab === 3) { this.filter = this.filters[index].id; this.coupled = false; }
  }
  strength(): number {
    return this.tab === 0 ? this.skin[this.selected[0]] : this.tab === 1 ? this.face[this.selected[1]] :
      this.tab === 2 ? this.makeupStrength : this.tab === 3 ? this.filterStrength : this.lipstickLevels[this.selected[4]];
  }
  change(value: number): void {
    const v = unit(value);
    if (this.tab === 0) { this.skin[this.selected[0]] = v; }
    if (this.tab === 1) { this.face[this.selected[1]] = v; }
    if (this.tab === 2) { this.makeupStrength = v; if (this.coupled) { this.filterStrength = v; } }
    if (this.tab === 3) { this.filterStrength = v; this.coupled = false; }
    if (this.tab === 4) { this.lipstickLevels[this.selected[4]] = v; }
  }
  resetItem(): void {
    if (this.tab === 0) {
      const defaults = this.malePreset ? MALE_SKIN : DEFAULT_SKIN;
      this.change(defaults[this.selected[0]]);
    } else if (this.tab === 1) {
      this.change(this.options()[this.selected[1]].neutral);
    } else {
      this.select(0);
    }
  }
  applyGenderPreset(male: boolean): void {
    this.malePreset = male;
    if (male) {
      this.skin = MALE_SKIN.slice();
      this.face = FACE.map((item: EffectOption) => item.neutral);
      this.makeup = ''; this.filter = ''; this.coupled = false;
      this.makeupStrength = 0.6; this.filterStrength = 0.0;
      this.selected = [this.selected[0], this.selected[1], 0, 0, 1];
      this.lipstickLevels = [0.6, 0.18, 0.6, 0.6, 0.6, 0.6];
    } else {
      this.useAndroidDefaults();
    }
  }
  reset(): void { this.applyGenderPreset(this.malePreset); }
  /** Female first-open and full reset: balanced skin, neutral shape, first makeup with its paired filter at 60%. */
  private useAndroidDefaults(): void {
    this.malePreset = false;
    this.skin = DEFAULT_SKIN.slice();
    this.face = FACE.map((item: EffectOption) => item.neutral);
    this.makeup = ''; this.filter = ''; this.coupled = false;
    this.makeupStrength = 0.6; this.filterStrength = 0.6; this.selected = [0, 0, 0, 0, 0]; this.lipstickLevels = [0.6, 0.6, 0.6, 0.6, 0.6, 0.6];
    if (this.makeups.length > 1) {
      const tab = this.tab;
      this.tab = 2;
      this.select(1);
      this.tab = tab;
    }
  }
  apply(engine: SnapBeautyEngine): void {
    const s = new SkinParams();
    s.smoothing = this.skin[0] * 6; s.brightening = this.skin[1]; s.rosiness = this.skin[2];
    s.sharpness = this.skin[3]; s.texture = this.skin[4]; s.blemishRemoval = this.skin[5];
    s.eyeBrightening = this.skin[6]; s.teethWhitening = this.skin[7]; s.undereyeBags = this.skin[8];
    s.smileLines = this.skin[9]; s.faceContour = this.skin[10];
    const f = new FaceParams();
    f.faceSlimming = this.face[0]; f.faceVTaper = this.face[1]; f.faceNarrowing = this.face[2];
    f.faceShortening = this.face[3]; f.faceShrinking = this.face[4]; f.cheekboneWidth = this.face[5];
    f.jawWidth = this.face[6]; f.eyeScale = this.face[7]; f.eyeRoundness = this.face[8];
    f.chinLength = this.face[9]; f.foreheadHeight = this.face[10]; f.noseWidth = this.face[11];
    f.mouthSize = this.face[12]; f.lipFullness = this.face[13]; f.eyePosition = this.face[14];
    f.eyeCornerOpening = this.face[15]; f.eyelidFold = this.face[16]; f.eyeDistance = this.face[17];
    f.eyeTilt = this.face[18]; f.noseLength = this.face[19]; f.philtrumLength = this.face[20];
    f.mouthCorners = this.face[21]; f.browPosition = this.face[22]; f.browDistance = this.face[23];
    f.browThickness = this.face[24];
    engine.skin = s; engine.face = f;
    engine.maxFaces = 1;
    engine.frameBudgetMs = 1000 / 30;
    engine.setMakeup(this.makeup.length === 0 || this.makeupStrength <= 0 ? '' : this.makeup, this.makeupStrength);
    engine.setFilter(this.filter, this.filterStrength);
    const lip = this.selected[4];
    engine.setLipstick(lip > 0 ? LIP_COLORS[lip] : null, lip > 0 ? this.lipstickLevels[lip] : 0);
  }
  save(): void {
    const snapshot: SavedSettings = { schema: SETTINGS_SCHEMA, skin: this.skin, face: this.face, filter: this.filter,
      filterStrength: this.filterStrength, makeup: this.makeup, makeupStrength: this.makeupStrength,
      coupled: this.coupled, front: this.front, tab: this.tab, selected: this.selected };
    this.store?.putSync('settings', JSON.stringify(snapshot));
    this.store?.flush().catch(() => {});
  }
}
