import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PRESS_EFFECT } from './Motion';
import { Palette } from './Theme';

interface AppIconPreset {
  name: string;
  zh: string;
  en: string;
  preview: Resource;
}

const ICON_PRESETS: AppIconPreset[] = [
  { name: '', zh: '默认', en: 'Default', preview: $r('app.media.startIcon') },
  { name: 'whale_sleepy', zh: '困困', en: 'Sleepy', preview: $r('app.media.whale_icon_sleepy_preview') },
  { name: 'whale_delighted', zh: '开心', en: 'Happy', preview: $r('app.media.whale_icon_delighted_preview') },
  { name: 'whale_determined', zh: '认真', en: 'Focused', preview: $r('app.media.whale_icon_determined_preview') }
];

@Component
export struct AppIconPicker {
  @Prop palette: Palette = new Palette(false);
  @Prop english: boolean = false;
  @State private active: string | undefined = undefined;
  @State private pending: boolean = true;
  @State private error: boolean = false;

  aboutToAppear(): void {
    this.loadActiveIcon();
  }

  private async loadActiveIcon(): Promise<void> {
    try {
      const icons = await bundleManager.getAlternateIcons();
      this.active = icons.find((icon: bundleManager.AlternateIconInfo) => icon.enabled)?.iconName ?? '';
    } catch {
      this.error = true;
    } finally {
      this.pending = false;
    }
  }

  private async selectIcon(name: string): Promise<void> {
    if (this.pending || name === this.active) {
      return;
    }
    this.pending = true;
    this.error = false;
    try {
      await bundleManager.setAlternateIcon(name);
      this.active = name;
    } catch (error) {
      if (!name && (error as BusinessError).code === 17700309) {
        this.active = '';
      } else {
        this.error = true;
      }
    } finally {
      this.pending = false;
    }
  }

  build() {
    Column({ space: 8 }) {
      Text(this.english ? 'Home screen icon' : '桌面图标')
        .fontColor(this.palette.ink).fontSize(14).lineHeight(22).width('100%')
      Row({ space: 8 }) {
        ForEach(ICON_PRESETS, (preset: AppIconPreset) => {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 4 }) {
              Image(preset.preview).width(38).height(38).borderRadius(9).objectFit(ImageFit.Contain)
                .draggable(false).accessibilityLevel('no')
              Text(this.english ? preset.en : preset.zh).fontSize(12).maxLines(1)
                .fontColor(this.active === preset.name ? this.palette.brandText : this.palette.ink)
            }
          }.id('app-icon-' + (preset.name || 'default'))
          .layoutWeight(1).height(71).padding(0).borderRadius(12)
          .backgroundColor(this.active === preset.name ? this.palette.accentSoft : Color.Transparent)
          .border({ width: 1, color: this.active === preset.name ? this.palette.activeBorder : this.palette.border })
          .clickEffect(PRESS_EFFECT).enabled(!this.pending)
          .accessibilityText(this.english ? preset.en : preset.zh)
          .accessibilityDescription(this.active === preset.name ? (this.english ? 'Selected' : '已选中') : '')
          .onClick(() => this.selectIcon(preset.name))
        }, (preset: AppIconPreset) => preset.name || 'default')
      }.width('100%')
      if (this.error) {
        Text(this.english ? 'Could not update the home screen icon. Try again.' : '桌面图标暂时无法更新，请重试。')
          .id('app-icon-error').fontSize(12).fontColor(this.palette.error).width('100%')
      }
    }.width('100%').padding({ top: 6, bottom: 8 })
  }
}
