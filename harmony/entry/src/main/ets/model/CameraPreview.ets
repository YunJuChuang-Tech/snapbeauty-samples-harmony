import camera from '@ohos.multimedia.camera';
import common from '@ohos.app.ability.common';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import { SnapBeautyEngine } from '@snapbeauty/core';

// The public SDK owns a single native preview; all page instances share this queue.
export class CameraPreview {
  private static queue: Promise<void> = Promise.resolve();
  private static owner: CameraPreview | undefined;
  private generation: number = 0;
  private input: camera.CameraInput | undefined;
  private output: camera.PreviewOutput | undefined;
  private session: camera.PhotoSession | undefined;
  private attached: boolean = false;
  private context: common.UIAbilityContext;
  private engine: SnapBeautyEngine;
  private report: (message: string) => void;
  constructor(context: common.UIAbilityContext, engine: SnapBeautyEngine, report: (message: string) => void) {
    this.context = context; this.engine = engine; this.report = report;
  }

  request(active: boolean, front: boolean, surface: string, root: string): void {
    const ticket = ++this.generation;
    CameraPreview.queue = CameraPreview.queue.then(async () => {
      await this.close();
      if (!active || ticket !== this.generation || !surface || !root) { return; }
      if (CameraPreview.owner && CameraPreview.owner !== this) { await CameraPreview.owner.close(); }
      try {
        await this.open(ticket, front, surface, root);
      } catch (error) {
        await this.close();
        if (ticket === this.generation) { this.report(`相机启动失败：${error.message}`); }
      }
    }).catch(() => { this.report('相机释放失败，请重新进入应用'); });
  }

  private async open(ticket: number, front: boolean, surface: string, root: string): Promise<void> {
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, ['ohos.permission.CAMERA']);
    if (ticket !== this.generation) { return; }
    if (result.authResults.length !== 1 || result.authResults[0] !== 0) { throw new Error('请在系统设置中允许相机权限，再点击重试'); }
    const manager = camera.getCameraManager(this.context);
    const position = front ? camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK;
    const device = manager.getSupportedCameras().find((item: camera.CameraDevice) => item.cameraPosition === position);
    if (!device) { throw new Error('没有找到此摄像头'); }
    const profiles = manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO).previewProfiles;
    const candidates = profiles.filter((p: camera.Profile) => p.size.width <= 1920 && p.size.height <= 1920);
    candidates.sort((a: camera.Profile, b: camera.Profile) =>
      Math.abs(a.size.width * a.size.height - 1280 * 720) - Math.abs(b.size.width * b.size.height - 1280 * 720));
    const profile = candidates.length > 0 ? candidates[0] : profiles[0];
    if (!profile) { throw new Error('没有可用的相机预览格式'); }
    const cameraSurface = this.engine.attach(surface, root, profile.size.width, profile.size.height);
    this.attached = true;
    CameraPreview.owner = this;
    this.input = manager.createCameraInput(device);
    await this.input.open();
    if (ticket !== this.generation) { await this.close(); return; }
    this.output = manager.createPreviewOutput(profile, cameraSurface);
    this.session = manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
    this.session.beginConfig();
    this.session.addInput(this.input);
    this.session.addOutput(this.output);
    await this.session.commitConfig();
    const rotation = this.output.getPreviewRotation(0);
    this.output.setPreviewRotation(rotation, true);
    const rotated = rotation === camera.ImageRotation.ROTATION_90 || rotation === camera.ImageRotation.ROTATION_270;
    // Keep the camera stream's horizontal orientation without an extra SDK flip.
    this.engine.configureFrame(rotated ? profile.size.height : profile.size.width,
      rotated ? profile.size.width : profile.size.height, false);
    const rates = this.output.getSupportedFrameRates();
    if (rates.some((rate: camera.FrameRateRange) => rate.min <= 30 && rate.max >= 30)) { this.output.setFrameRate(30, 30); }
    if (ticket !== this.generation) { await this.close(); return; }
    await this.session.start();
    if (ticket !== this.generation) { await this.close(); return; }
    this.report('相机美颜 · 单人模式');
  }

  private async close(): Promise<void> {
    // Stop the CameraKit producer before the SDK releases its NativeImage/EGL consumer.
    if (this.session) {
      try { await this.session.stop(); } catch (_) {}
      try { await this.session.release(); } catch (_) {}
      this.session = undefined;
    }
    if (this.output) { try { await this.output.release(); } catch (_) {} this.output = undefined; }
    if (this.input) { try { await this.input.close(); } catch (_) {} this.input = undefined; }
    if (this.attached) { this.engine.release(); this.attached = false; }
    if (CameraPreview.owner === this) { CameraPreview.owner = undefined; }
  }
}
