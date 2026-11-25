import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { SnapBeautyEngine } from '@snapbeauty/core';
import { installDemoAssets } from '../model/MakeupAssets';
import { CameraPreview } from '../model/CameraPreview';
import { EffectOption, EffectSettings } from '../model/EffectSettings';

interface FilterCatalog { inputScale: Record<string, number>; }
interface HostFilter { id: string; file: string; width: number; height: number; }
interface HostFilterIndex { schema: number; filters: HostFilter[]; }

@Entry
@Component
struct Index {
  @StorageLink('sampleForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State message: string = '正在校验美颜资源…';
  @State ready: boolean = false;
  @State tab: number = 0;
  @State options: EffectOption[] = [];
  @State selected: number = 0;
  @State strength: number = 0.35;
  @State bidirectional: boolean = false;
  @State panel: boolean = true;
  @State malePreset: boolean = false;
  @State scene: boolean = false;
  @State original: boolean = false;
  private controller: XComponentController = new XComponentController();
  private engine: SnapBeautyEngine = new SnapBeautyEngine();
  private settings: EffectSettings = new EffectSettings();
  private camera: CameraPreview | undefined;
  private root: string = '';
  private surface: string = '';
  private visible: boolean = false;
  private disposed: boolean = false;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.camera = new CameraPreview(context, this.engine, (message: string) => { if (!this.disposed) { this.message = message; } });
    installDemoAssets(context).then((assets) => {
      if (this.disposed) { return; }
      this.root = assets.root;
      // Read the actual LUT list rather than the SDK demo's curated catalog subset.
      const filters = JSON.parse(fs.readTextSync(`${assets.root}/snapbeauty/luts/luts.json`)) as FilterCatalog;
      // CC BY-SA host filters shipped with this app (host-filters/NOTICE.md), registered like built-in ones.
      const hostFilters = JSON.parse(fs.readTextSync(`${assets.root}/host-filters/index.json`)) as HostFilterIndex;
      for (const f of hostFilters.filters) {
        const file = fs.openSync(`${assets.root}/${f.file}`, fs.OpenMode.READ_ONLY);
        try {
          const rgba = new ArrayBuffer(f.width * f.height * 4);
          if (fs.readSync(file.fd, rgba) !== rgba.byteLength) { throw new Error(`滤镜资源不完整: ${f.id}`); }
          this.engine.registerFilter(f.id, rgba, f.width, f.height);
        } finally { fs.closeSync(file); }
      }
      this.settings.initialize(context, assets.catalog,
        Object.keys(filters.inputScale).concat(hostFilters.filters.map((f: HostFilter) => f.id)).sort());
      this.settings.apply(this.engine);
      this.ready = true;
      this.refresh();
      this.requestCamera();
    }).catch((error: Error) => { this.message = `资源初始化失败：${error.message}`; });
  }
  onPageShow(): void { this.visible = true; this.requestCamera(); }
  onPageHide(): void { this.visible = false; this.clearOriginal(); this.requestCamera(); this.settings.save(); }
  aboutToDisappear(): void {
    this.disposed = true; this.visible = false; this.clearOriginal(); this.requestCamera(); this.settings.save();
  }
  private foregroundChanged(): void { if (!this.foreground) { this.clearOriginal(); } this.requestCamera(); }
  private requestCamera(): void {
    this.camera?.request(this.scene && this.visible && this.foreground && this.ready && !this.disposed,
      this.settings.front, this.surface, this.root);
  }
  private clearOriginal(): void { this.original = false; this.engine.setShowOriginal(false); }
  private refresh(): void {
    this.tab = this.settings.tab;
    this.options = this.settings.options();
    this.selected = this.settings.selected[this.tab];
    this.strength = this.settings.strength();
    this.bidirectional = this.options[this.selected]?.neutral === 0.5;
    this.malePreset = this.settings.malePreset;
  }
  private update(): void { this.settings.apply(this.engine); this.settings.save(); this.refresh(); }
  private valueLabel(): string {
    const value = Math.round(this.strength * 100 - (this.bidirectional ? 50 : 0));
    return `${this.bidirectional && value > 0 ? '+' : ''}${value}`;
  }

  build() {
    Column() {
      if (!this.scene) {
        Column() {
          Text('✦').fontSize(44).fontColor('#DDFF9A').width(64).height(64).textAlign(TextAlign.Center)
          Text('SnapBeauty\nSamples').fontSize(32).fontWeight(FontWeight.Bold).fontColor('#F2F4EC')
            .width('100%').margin({ top: 24, bottom: 12 })
          Text('选一个场景，马上开始。').fontSize(15).fontColor('#A3ADA4').width('100%').margin({ bottom: 32 })
          Column({ space: 8 }) {
            Text('01  相机美颜').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#DDFF9A').width('100%')
            Text('本地预览 · 参数调节 · 原图对比').fontSize(12).fontColor('#A3ADA4').width('100%')
          }.width('100%').padding(20).backgroundColor('#202921').borderRadius(20)
            .onClick(() => { this.scene = true; this.requestCamera(); })
          Text('简单一点，自然一点。').fontSize(12).fontColor('#A3ADA4').width('100%').margin({ top: 30 })
        }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start).padding({ left: 24, right: 24 })
          .width('100%').height('100%')
      } else {
        Row({ space: 8 }) {
          Text('‹').fontSize(26).fontColor('#DDFF9A').width(24).onClick(() => {
            this.clearOriginal(); this.scene = false; this.requestCamera();
          })
          Text('✦').fontSize(22).fontColor('#DDFF9A')
          Column({ space: 2 }) {
            Text('SNAPBEAUTY').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#F2F4EC')
            Text('SAMPLES  /  相机体验').fontSize(9).fontColor('#A3ADA4')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('01').fontSize(11).fontColor('#DDFF9A')
        }.width('100%').padding({ left: 14, right: 14, top: 6, bottom: 6 })
        Stack({ alignContent: Alignment.Bottom }) {
          XComponent({ id: 'camera-preview', type: XComponentType.SURFACE, controller: this.controller })
            .width('100%').height('100%')
            .onLoad(() => { this.surface = this.controller.getXComponentSurfaceId(); this.requestCamera(); })
            .onDestroy(() => { this.surface = ''; this.clearOriginal(); this.requestCamera(); })
            .onClick(() => { this.clearOriginal(); this.panel = !this.panel; })
          Column() {
            Row({ space: 6 }) {
              Text(this.original ? '正在查看原图' : this.message).fontSize(10).fontColor('#F2F4EC').maxLines(1)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor('#88101311').borderRadius(14)
              Blank()
              Row({ space: 2 }) {
                Text('女生').fontSize(11).fontWeight(!this.malePreset ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(!this.malePreset ? '#101311' : '#F2F4EC')
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .backgroundColor(!this.malePreset ? '#DDFF9A' : Color.Transparent).borderRadius(12)
                  .onClick(() => { this.clearOriginal(); this.settings.applyGenderPreset(false); this.update(); })
                Text('男生').fontSize(11).fontWeight(this.malePreset ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.malePreset ? '#101311' : '#F2F4EC')
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .backgroundColor(this.malePreset ? '#DDFF9A' : Color.Transparent).borderRadius(12)
                  .onClick(() => { this.clearOriginal(); this.settings.applyGenderPreset(true); this.update(); })
              }.padding(3).backgroundColor('#99101311').borderRadius(15)
              Button('翻转').fontSize(11).fontColor('#F2F4EC').backgroundColor('#99101311').height(28)
                .padding({ left: 10, right: 10 }).enabled(this.ready)
                .onClick(() => { this.clearOriginal(); this.settings.front = !this.settings.front; this.settings.save(); this.requestCamera(); })
            }.width('100%').padding({ left: 12, right: 12, top: 10 })
            Blank()
            Row({ space: 8 }) {
              Blank()
              if (this.ready) {
                Text('重试').fontSize(10).fontColor('#DDFF9A')
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor('#88101311').borderRadius(14)
                  .onClick(() => { this.clearOriginal(); this.requestCamera(); })
              }
              Button('重置').fontSize(11).fontColor('#F2F4EC').backgroundColor('#99101311').height(28)
                .padding({ left: 12, right: 12 })
                .onClick(() => { this.clearOriginal(); this.settings.reset(); this.update(); })
              Button(this.original ? '正在查看原图' : '按住对比原图').fontSize(11).fontWeight(FontWeight.Bold)
                .fontColor('#101311').backgroundColor('#D9DDFF9A').height(28).padding({ left: 12, right: 12 })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) { this.original = true; this.engine.setShowOriginal(true); }
                  if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.clearOriginal(); }
                })
            }.width('100%').padding({ left: 12, right: 12, bottom: 6 })
            Column() {
              Row({ space: 8 }) {
                Text('━━').fontSize(10).fontColor('#95A496')
                Text(this.panel ? '收起面板  ↓' : '展开效果面板  ↑').fontSize(10).fontColor('#DDFF9A')
              }.width('100%').height(28).justifyContent(FlexAlign.Center).onClick(() => {
                this.clearOriginal(); this.panel = !this.panel;
              }).gesture(PanGesture({ direction: PanDirection.Vertical }).onActionEnd((event: GestureEvent) => {
                if (event.offsetY > 20) { this.clearOriginal(); this.panel = false; }
                if (event.offsetY < -20) { this.panel = true; }
              }))
              if (this.panel && this.ready) {
                Row({ space: 6 }) {
                  Text(this.tab === 2 ? '妆容浓度' : this.tab === 3 ? '滤镜' : this.tab === 4 ? '口红' : this.options[this.selected]?.label || '强度')
                    .fontSize(11).fontColor('#F2F4EC').maxLines(1)
                  Slider({ value: this.strength * 100, min: 0, max: 100, step: 1 })
                    .layoutWeight(1).height(28).selectedColor('#DDFF9A').enabled(this.tab < 2 || this.selected > 0)
                    .onChange((value: number) => { this.settings.change(value / 100); this.update(); })
                  Text(this.valueLabel()).fontSize(12).fontColor('#DDFF9A').width(30).textAlign(TextAlign.End)
                  if (this.tab < 2) {
                    Text('恢复').fontSize(10).fontColor('#A3ADA4').padding({ left: 4, right: 2 })
                      .onClick(() => { this.settings.resetItem(); this.update(); })
                  }
                }.width('100%').height(32)
                Scroll() {
                  Row({ space: 5 }) {
                    ForEach(this.options, (item: EffectOption, index: number) => {
                      Text(item.label).fontSize(11).fontColor(this.selected === index ? '#101311' : '#F2F4EC')
                        .padding({ left: 11, right: 11, top: 6, bottom: 6 })
                        .backgroundColor(this.selected === index ? '#DDFF9A' : '#7A262D28').borderRadius(14)
                        .onClick(() => { this.settings.select(index); this.update(); })
                    }, (item: EffectOption) => item.id)
                  }
                }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(36)
                Row() {
                  ForEach(['美肤', '美型', '妆容', '滤镜', '口红'], (title: string, index: number) => {
                    Text(title).fontSize(13).fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(this.tab === index ? '#DDFF9A' : '#A3ADA4').layoutWeight(1).textAlign(TextAlign.Center)
                      .height(34).onClick(() => { this.settings.tab = index; this.refresh(); })
                  })
                }.width('100%').padding({ bottom: 6 })
              }
            }.width('100%').padding({ left: 14, right: 14 }).backgroundColor('#A8101411')
              .borderRadius({ topLeft: 20, topRight: 20 })
          }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor('#101311')
  }
}
