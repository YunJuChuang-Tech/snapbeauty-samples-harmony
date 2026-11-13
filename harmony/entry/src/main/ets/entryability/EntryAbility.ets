import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import { SnapBeauty } from '@snapbeauty/core';
import { util } from '@kit.ArkTS';

export default class EntryAbility extends UIAbility {
  onForeground(): void { AppStorage.setOrCreate('sampleForeground', true); }
  onBackground(): void { AppStorage.setOrCreate('sampleForeground', false); }
  onWindowStageCreate(stage: window.WindowStage): void {
    let license: string = '';
    try {
      license = new util.TextDecoder('utf-8').decodeToString(
        this.context.resourceManager.getRawFileContentSync('snapbeauty.license'));
    } catch (_) { /* The optional application-bound license is not installed. */ }
    SnapBeauty.init(this.context, license);
    stage.getMainWindow().then(async (main: window.Window) => {
      await main.setPreferredOrientation(window.Orientation.PORTRAIT);
    }).catch(() => {}).then(() => { stage.loadContent('pages/Index'); });
  }
}
