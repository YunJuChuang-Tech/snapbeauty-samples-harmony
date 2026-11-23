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
        Row({ space: 10 }) {
          Text('‹').fontSize(30).fontColor('#DDFF9A').width(30).onClick(() => {
            this.clearOriginal(); this.scene = false; this.requestCamera();
          })
          Text('✦').fontSize(28).fontColor('#DDFF9A')
          Column({ space: 4 }) {
            Text('SNAPBEAUTY').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#F2F4EC')
            Text('SAMPLES  /  相机体验').fontSize(10).fontColor('#A3ADA4')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('01').fontSize(12).fontColor('#DDFF9A')
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        Stack({ alignContent: Alignment.Bottom }) {
          XComponent({ id: 'camera-preview', type: XComponentType.SURFACE, controller: this.controller })
            .width('100%').height('100%')
            .onLoad(() => { this.surface = this.controller.getXComponentSurfaceId(); this.requestCamera(); })
            .onDestroy(() => { this.surface = ''; this.clearOriginal(); this.requestCamera(); })
          Column() {
            Row() {
              Text('●  LIVE PREVIEW').fontSize(10).fontWeight(FontWeight.Bold).fontColor('#DDFF9A')
                .padding(12).backgroundColor('#B3101311').borderRadius(20)
              Blank()
              Button('翻转').fontSize(12).fontColor('#F2F4EC').backgroundColor('#B3101311').enabled(this.ready)
                .onClick(() => { this.clearOriginal(); this.settings.front = !this.settings.front; this.settings.save(); this.requestCamera(); })
            }.width('100%').padding(12)
            Blank()
            if (this.original) { Text('原图').fontColor('#F2F4EC').padding(8).backgroundColor('#B3101311').borderRadius(18) }
            Text(this.message).fontSize(12).fontColor('#F2F4EC').padding(10).backgroundColor('#B3101311')
              .borderRadius(18).margin({ bottom: 12 })
            if (this.ready) {
              Text('重试预览').fontSize(11).fontColor('#DDFF9A').padding(8).onClick(() => {
                this.clearOriginal(); this.requestCamera();
              })
            }
          }.width('100%').height('100%')
        }.width('100%').layoutWeight(1)
        Column() {
          Column({ space: 5 }) {
            Text('━━━━').fontSize(10).fontColor('#657365')
            Text(this.panel ? '收起面板  ↓' : '展开效果面板  ↑').fontSize(11).fontColor('#DDFF9A')
          }.width('100%').height(48).justifyContent(FlexAlign.Center).onClick(() => {
            this.clearOriginal(); this.panel = !this.panel;
          }).gesture(PanGesture({ direction: PanDirection.Vertical }).onActionEnd((event: GestureEvent) => {
            if (event.offsetY > 20) { this.clearOriginal(); this.panel = false; }
            if (event.offsetY < -20) { this.panel = true; }
          }))
          if (this.panel && this.ready) {
            Row() {
              ForEach(['美肤', '美型', '妆容', '滤镜', '口红'], (title: string, index: number) => {
                Text(title).fontSize(15).fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.tab === index ? '#DDFF9A' : '#A3ADA4').layoutWeight(1).textAlign(TextAlign.Center)
                  .height(44).onClick(() => { this.settings.tab = index; this.refresh(); })
              })
            }.width('100%')
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.options, (item: EffectOption, index: number) => {
                  Text(item.label).fontSize(12).fontColor(this.selected === index ? '#101311' : '#F2F4EC')
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .backgroundColor(this.selected === index ? '#DDFF9A' : '#2B332D').borderRadius(18)
                    .onClick(() => { this.settings.select(index); this.update(); })
                }, (item: EffectOption) => item.id)
              }
            }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(48)
            Row() {
              Text(this.tab === 2 ? '妆容浓度' : this.tab === 3 ? '滤镜' : this.tab === 4 ? '口红' : this.options[this.selected]?.label || '强度')
                .fontSize(12).fontColor('#F2F4EC').layoutWeight(1)
              if (this.tab < 2) {
                Text('恢复默认').fontSize(11).fontColor('#A3ADA4').padding(8)
                  .onClick(() => { this.settings.resetItem(); this.update(); })
              }
              Text(this.valueLabel()).fontSize(13).fontColor('#DDFF9A').width(36).textAlign(TextAlign.End)
            }.width('100%').height(36)
            Slider({ value: this.strength * 100, min: 0, max: 100, step: 1 })
              .width('100%').height(40).selectedColor('#DDFF9A').enabled(this.tab < 2 || this.selected > 0)
              .onChange((value: number) => { this.settings.change(value / 100); this.update(); })
            Text(this.tab === 4 && this.selected === 0 ? '选择口红后可调强度' : '左右滑动选项 · 调节效果强度')
              .fontSize(10).fontColor('#A3ADA4').width('100%').height(32)
            Row({ space: 16 }) {
              Button('重置').fontSize(12).fontColor('#F2F4EC').backgroundColor('#303A31').width(72).height(48)
                .onClick(() => { this.clearOriginal(); this.settings.reset(); this.update(); })
              Button(this.original ? '正在查看原图' : '按住对比原图').fontSize(14).fontWeight(FontWeight.Bold)
                .fontColor('#101311').backgroundColor('#DDFF9A').layoutWeight(1).height(48)
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) { this.original = true; this.engine.setShowOriginal(true); }
                  if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.clearOriginal(); }
                })
            }.width('100%').padding({ bottom: 12 })
          }
        }.width('100%').padding({ left: 20, right: 20 }).backgroundColor('#191E1A')
          .borderRadius({ topLeft: 24, topRight: 24 })
      }
    }.width('100%').height('100%').backgroundColor('#101311')
  }
}
