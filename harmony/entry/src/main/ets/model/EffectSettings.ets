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
  new EffectOption('texture', '质感'), new EffectOption('blemishRemoval', '祛斑痘'),
  new EffectOption('eyeBrightening', '亮眼'), new EffectOption('teethWhitening', '美牙'),
  new EffectOption('undereyeBags', '淡化眼袋'), new EffectOption('smileLines', '淡化法令纹'),
  new EffectOption('faceContour', '轮廓立体')
];
export const FACE: EffectOption[] = [
  new EffectOption('faceSlimming', '瘦脸'), new EffectOption('faceVTaper', 'V 脸'),
  new EffectOption('faceNarrowing', '窄脸'), new EffectOption('faceShortening', '短脸'),
  new EffectOption('faceShrinking', '小脸'), new EffectOption('cheekboneWidth', '颧骨'),
  new EffectOption('jawWidth', '下颌'), new EffectOption('eyeScale', '大眼'),
  new EffectOption('eyeRoundness', '圆眼'), new EffectOption('chinLength', '下巴', 0.5),
  new EffectOption('foreheadHeight', '额头', 0.5), new EffectOption('noseWidth', '鼻翼'),
  new EffectOption('mouthSize', '嘴型', 0.5), new EffectOption('lipFullness', '唇厚', 0.5),
  new EffectOption('eyePosition', '眼位', 0.5), new EffectOption('eyeCornerOpening', '眼角'),
  new EffectOption('eyelidFold', '眼睑'), new EffectOption('eyeDistance', '眼距', 0.5),
  new EffectOption('eyeTilt', '眼睛角度', 0.5), new EffectOption('noseLength', '鼻长', 0.5),
  new EffectOption('philtrumLength', '人中', 0.5), new EffectOption('mouthCorners', '嘴角'),
  new EffectOption('browPosition', '眉位', 0.5), new EffectOption('browDistance', '眉距', 0.5),
  new EffectOption('browThickness', '眉厚', 0.5)
];
interface SavedSettings {
  schema: number; skin: number[]; face: number[]; filter: string; filterStrength: number;
  makeup: string; makeupStrength: number; coupled: boolean; front: boolean; tab: number; selected: number[];
}

function unit(value: number, fallback: number = 0): number {
  return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
}

export class EffectSettings {
  skin: number[] = [0.7, 0.3, 0.3, 0.2, 0, 0, 0, 0, 0, 0, 0];
  face: number[] = FACE.map((item: EffectOption) => item.neutral);
  filters: EffectOption[] = [new EffectOption('', '无滤镜')];
  makeups: EffectOption[] = [new EffectOption('', '无妆')];
  filter: string = '';
  filterStrength: number = 0.4;
  makeup: string = '';
  makeupStrength: number = 0.4;
  coupled: boolean = false;
  front: boolean = true;
  tab: number = 0;
  selected: number[] = [0, 0, 0, 0];
  private catalog: Catalog | undefined;
  private store: preferences.Preferences | undefined;

  initialize(context: common.UIAbilityContext, catalog: Catalog, filterIds: string[]): void {
    this.catalog = catalog;
    this.filters = [new EffectOption('', '无滤镜')].concat(filterIds.filter((id: string) => id !== 'origin')
      .map((id: string) => new EffectOption(id, id)));
    this.makeups = [new EffectOption('', '无妆')].concat(catalog.makeup.map((row) => new EffectOption(row.key, row.key)));
    this.store = preferences.getPreferencesSync(context, { name: 'camera-effects-v1' });
    try {
      const saved = JSON.parse(this.store.getSync('settings', '{}') as string) as SavedSettings;
      if (saved.schema !== 1) { return; }
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
    } catch (_) { /* Invalid or older preferences keep safe defaults. */ }
  }

  options(tab: number = this.tab): EffectOption[] {
    return tab === 0 ? SKIN : tab === 1 ? FACE : tab === 2 ? this.makeups : this.filters;
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
      this.tab === 2 ? this.makeupStrength : this.filterStrength;
  }
  change(value: number): void {
    const v = unit(value);
    if (this.tab === 0) { this.skin[this.selected[0]] = v; }
    if (this.tab === 1) { this.face[this.selected[1]] = v; }
    if (this.tab === 2) { this.makeupStrength = v; if (this.coupled) { this.filterStrength = v; } }
    if (this.tab === 3) { this.filterStrength = v; this.coupled = false; }
  }
  resetItem(): void {
    if (this.tab < 2) { this.change(this.options()[this.selected[this.tab]].neutral); }
    else { this.select(0); }
  }
  reset(): void {
    this.skin = [0.7, 0.3, 0.3, 0.2, 0, 0, 0, 0, 0, 0, 0];
    this.face = FACE.map((item: EffectOption) => item.neutral);
    this.makeup = ''; this.filter = ''; this.coupled = false;
    this.makeupStrength = 0.4; this.filterStrength = 0.4; this.selected = [0, 0, 0, 0];
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
    engine.setMakeup(this.makeup, this.makeupStrength);
    engine.setFilter(this.filter, this.filterStrength);
  }
  save(): void {
    const snapshot: SavedSettings = { schema: 1, skin: this.skin, face: this.face, filter: this.filter,
      filterStrength: this.filterStrength, makeup: this.makeup, makeupStrength: this.makeupStrength,
      coupled: this.coupled, front: this.front, tab: this.tab, selected: this.selected };
    this.store?.putSync('settings', JSON.stringify(snapshot));
    this.store?.flush().catch(() => {});
  }
}
