import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { SnapBeautyEngine } from '@snapbeauty/core';
import { installDemoAssets } from '../model/MakeupAssets';
import { CameraPreview } from '../model/CameraPreview';
import { EffectOption, EffectSettings } from '../model/EffectSettings';

interface FilterCatalog { inputScale: Record<string, number>; }

@Entry
@Component
struct Index {
  @StorageLink('sampleForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State message: string = '正在校验美颜资源…';
  @State ready: boolean = false;
  @State tab: number = 0;
  @State options: EffectOption[] = [];
  @State selected: number = 0;
  @State strength: number = 0.7;
  @State bidirectional: boolean = false;
  @State panel: boolean = true;
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
      this.settings.initialize(context, assets.catalog, Object.keys(filters.inputScale).sort());
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
    this.camera?.request(this.visible && this.foreground && this.ready && !this.disposed,
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
    Stack({ alignContent: Alignment.Bottom }) {
      XComponent({ id: 'camera-preview', type: XComponentType.SURFACE, controller: this.controller })
        .width('100%').height('100%')
        .onLoad(() => { this.surface = this.controller.getXComponentSurfaceId(); this.requestCamera(); })
        .onDestroy(() => { this.surface = ''; this.clearOriginal(); this.requestCamera(); })
      Column() {
        Row() {
          Column({ space: 4 }) {
            Text('SnapBeauty').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White)
            Text('相机美颜').fontSize(12).fontColor('#D0D5DC')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button('切换镜头').enabled(this.ready).onClick(() => {
            this.clearOriginal(); this.settings.front = !this.settings.front; this.settings.save(); this.requestCamera();
          }).fontSize(13).backgroundColor('#99232E3B')
        }.width('100%').padding(16)
        Text(this.message).fontSize(12).fontColor('#E3E7EC').padding(10)
          .backgroundColor('#AA192332').borderRadius(10).margin({ left: 16, right: 16 })
        if (this.ready) {
          Button('重试预览').fontSize(12).backgroundColor('#77232E3B').margin({ top: 8 })
            .onClick(() => { this.clearOriginal(); this.requestCamera(); })
        }
        Blank()
        if (this.original) { Text('原图').fontColor(Color.White).padding(10).backgroundColor('#AA192332').borderRadius(12) }
        Row({ space: 10 }) {
          Button('按住对比').fontSize(14).backgroundColor('#AA192332').enabled(this.ready)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) { this.original = true; this.engine.setShowOriginal(true); }
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.clearOriginal(); }
            })
          Blank()
          Button('重置').fontSize(14).backgroundColor('#AA192332').enabled(this.ready)
            .onClick(() => { this.clearOriginal(); this.settings.reset(); this.update(); })
          Button(this.panel ? '收起' : '效果').fontSize(14).backgroundColor('#AA192332')
            .onClick(() => { this.panel = !this.panel; })
        }.width('100%').padding(16)
        if (this.panel && this.ready) {
          Column({ space: 14 }) {
            Row() {
              ForEach(['美肤', '美型', '妆容', '滤镜'], (title: string, index: number) => {
                Text(title).fontSize(16).fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.tab === index ? '#F2BD91' : '#D0D5DC').layoutWeight(1).textAlign(TextAlign.Center)
                  .padding({ top: 12, bottom: 12 }).onClick(() => {
                    this.settings.tab = index; this.settings.save(); this.refresh();
                  })
              })
            }.width('100%')
            Scroll() {
              Row({ space: 10 }) {
                ForEach(this.options, (item: EffectOption, index: number) => {
                  Text(item.label).fontSize(13).fontColor(this.selected === index ? '#192332' : '#E3E7EC')
                    .padding({ left: 15, right: 15, top: 12, bottom: 12 })
                    .backgroundColor(this.selected === index ? '#F2BD91' : '#303C4B').borderRadius(12)
                    .onClick(() => { this.settings.select(index); this.update(); })
                }, (item: EffectOption) => item.id)
              }
            }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
            Row({ space: 8 }) {
              Text(this.valueLabel()).fontSize(14).fontColor('#F2BD91').width(40).textAlign(TextAlign.Center)
              Slider({ value: this.strength * 100, min: 0, max: 100, step: 1 })
                .layoutWeight(1).selectedColor('#F2BD91')
                .enabled(this.tab < 2 || this.selected > 0)
                .onChange((value: number) => { this.settings.change(value / 100); this.update(); })
              Button('还原').fontSize(12).backgroundColor('#303C4B')
                .onClick(() => { this.settings.resetItem(); this.update(); })
            }.width('100%')
          }.padding({ left: 16, right: 16, bottom: 20 }).width('100%').backgroundColor('#F2192332')
        }
      }.width('100%').height('100%')
    }.width('100%').height('100%').backgroundColor('#192332')
  }
}
