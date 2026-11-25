import { deviceInfo } from '@kit.BasicServicesKit';
import { Palette } from './Theme';
import { AppIconPicker } from './AppIconPicker';
import { DemoIcon } from './Icon';
import { CONTROL_MOTION, PRESS_EFFECT } from './Motion';
import { PROVINCES, Province } from '../model/Locations';

@Component
export struct SettingsPanel {
  @Prop palette: Palette = new Palette(false);
  @Prop english: boolean = false;
  @Prop wide: boolean = false;
  @Prop heightAvailable: number = 700;
  @Prop section: string = 'general';
  @Prop configured: boolean = false;
  @Prop hasHistory: boolean = false;
  @Prop saving: boolean = false;
  @Prop theme: string = 'system';
  @Prop language: string = 'system';
  @Prop location: string = '';
  @Prop voice: string = 'stella';
  @Prop status: string = '';
  @State input: string = '';
  @State keyEditing: boolean = false;
  close: () => void = () => {};
  changeSection: (section: string) => void = () => {};
  saveKey: (key: string) => void = () => {};
  removeKey: () => void = () => {};
  changeTheme: (theme: string) => void = () => {};
  changeLanguage: (language: string) => void = () => {};
  changeLocation: (location: string) => void = () => {};
  changeVoice: (voice: string) => void = () => {};
  importHistory: () => void = () => {};
  exportHistory: () => void = () => {};
  deleteHistory: () => void = () => {};

  private t(zh: string, en: string): string {
    return this.english ? en : zh;
  }

  private commit(): void {
    if (this.input.trim() && !this.saving) {
      this.saveKey(this.input.trim());
    }
  }

  private provinces(): MenuElement[] {
    return PROVINCES.map((province: Province): MenuElement => {
      return { value: province.name, action: () => this.changeLocation(province.name) };
    });
  }

  private cities(): MenuElement[] {
    const province = PROVINCES.find((item: Province): boolean => item.name === this.location.split('/')[0]);
    return (province?.cities ?? []).map((city: string): MenuElement => {
      return { value: city, action: () => this.changeLocation(province?.name + '/' + city) };
    });
  }

  @Builder
  nav(label: string, glyph: Resource, target: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        DemoIcon({ glyph: glyph, tint: this.palette.ink })
        Text(label).fontSize(14).lineHeight(22).fontColor(this.palette.ink)
      }.width('100%').justifyContent(this.wide ? FlexAlign.Start : FlexAlign.Center)
    }.id('settings-' + target).height(40).borderRadius(12).layoutWeight(this.wide ? 0 : 1)
    .width(this.wide ? 164 : undefined).padding({ left: this.wide ? 8 : 0, right: this.wide ? 10 : 0 })
    .backgroundColor(this.section === target ? this.palette.hover : Color.Transparent)
    .animation(CONTROL_MOTION).clickEffect(PRESS_EFFECT)
    .accessibilityText(label).onClick(() => this.changeSection(target))
  }

  @Builder
  themeOption(label: string, glyph: Resource, value: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 2 }) {
        DemoIcon({ glyph: glyph, tint: this.palette.ink })
        Text(label).fontSize(14).lineHeight(22).fontColor(this.palette.ink)
      }.alignItems(HorizontalAlign.Center)
    }.id('theme-' + value).layoutWeight(1).height(82).padding(0).borderRadius(12)
    .border({ width: 1, radius: 12, color: this.palette.border })
    .backgroundColor(this.theme === value ? this.palette.selector : Color.Transparent)
    .clickEffect(PRESS_EFFECT).accessibilityText(label).onClick(() => this.changeTheme(value))
  }

  @Builder
  selector(label: string, options: MenuElement[], fluid: boolean, dimmed: boolean = false) {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 14 }) {
        Text(label).fontSize(14).lineHeight(22).fontColor(dimmed ? this.palette.tertiary : this.palette.ink)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(fluid ? 1 : 0)
        DemoIcon({ glyph: $r('app.media.demo_down'), iconSize: 14, tint: this.palette.muted })
      }
    }.height(36).padding({ left: 14, right: 14 }).layoutWeight(fluid ? 1 : 0)
    .backgroundColor(this.palette.selector).enabled(options.length > 0).bindMenu(options)
  }

  @Builder
  general() {
    Column() {
      Text(this.t('主题', 'Theme')).fontColor(this.palette.ink).fontSize(14).lineHeight(22).width('100%')
      if (this.wide) {
        Row({ space: 12 }) {
          this.themeOption(this.t('浅色', 'Light'), $r('app.media.demo_light'), 'light')
          this.themeOption(this.t('深色', 'Dark'), $r('app.media.demo_dark'), 'dark')
          this.themeOption(this.t('跟随系统', 'System'), $r('app.media.demo_system'), 'system')
        }.width('100%').margin({ top: 8, bottom: 10 })
      } else {
        Row({ space: 12 }) {
          this.themeOption(this.t('浅色', 'Light'), $r('app.media.demo_light'), 'light')
          this.themeOption(this.t('深色', 'Dark'), $r('app.media.demo_dark'), 'dark')
        }.width('100%').margin({ top: 8, bottom: 12 })
        Row() {
          this.themeOption(this.t('跟随系统', 'System'), $r('app.media.demo_system'), 'system')
        }.width('100%').margin({ bottom: 10 })
      }
      if (deviceInfo.sdkApiVersion >= 26) {
        AppIconPicker({ palette: this.palette, english: this.english })
      }
      Row() {
        Text(this.t('语言', 'Language')).fontColor(this.palette.ink).fontSize(14).layoutWeight(1)
        this.selector(this.english ? 'English' : '简体中文', [
          { value: '简体中文', action: () => this.changeLanguage('zh') },
          { value: 'English', action: () => this.changeLanguage('en') },
          { value: this.t('跟随系统', 'System'), action: () => this.changeLanguage('system') }
        ], false)
      }.width('100%').height(60)
      Divider().color(this.palette.border)
      Row() {
        Text(this.t('朗读音色', 'Voice')).fontColor(this.palette.ink).fontSize(14).layoutWeight(1)
        this.selector(this.voice === 'tide' ? this.t('暗潮（男声）', 'Tide (male)') : this.t('海星（女声）', 'Stella (female)'), [
          { value: this.t('海星（女声）', 'Stella (female)'), action: () => this.changeVoice('stella') },
          { value: this.t('暗潮（男声）', 'Tide (male)'), action: () => this.changeVoice('tide') }
        ], false)
      }.width('100%').height(60)
      Divider().color(this.palette.border)
      Column({ space: 12 }) {
        Text(this.t('位置信息', 'Location')).fontColor(this.palette.ink).fontSize(14).lineHeight(22).width('100%')
        if (!this.english) {
          Row({ space: 12 }) {
            this.selector(this.location.split('/')[0] || '请选择省份/地区', this.provinces(), true, !this.location)
            this.selector(this.location.split('/')[1] || '请选择市', this.cities(), true, !this.location.split('/')[1])
          }.width('100%')
        } else {
          TextInput({ text: this.location, placeholder: 'Select a country or region' }).id('location-input')
            .fontSize(14).placeholderColor(this.palette.tertiary).fontColor(this.palette.ink).height(36)
            .borderRadius(18).backgroundColor(this.palette.selector).maxLength(60).onChange(this.changeLocation)
        }
      }.width('100%').padding({ top: 12, bottom: 12 })
    }.width('100%')
  }

  @Builder
  outlined(label: string, action: () => void, danger: boolean, allowed: boolean = true) {
    Button(label).type(ButtonType.Capsule).height(this.wide ? 36 : 44).padding({ left: 21, right: 21 })
      .fontSize(14).fontColor(danger ? this.palette.error : this.palette.ink).backgroundColor(Color.Transparent)
      .border({ width: 1, radius: 22, color: danger ? this.palette.error : this.palette.border })
      .opacity(allowed ? 1 : 0.4).enabled(allowed).onClick(action)
  }

  @Builder
  dataRow(label: string, description: string, button: string, action: () => void, danger: boolean,
    allowed: boolean = true) {
    Row({ space: 8 }) {
      Column({ space: 4 }) {
        Text(label).fontSize(14).lineHeight(22).fontColor(this.palette.ink).width('100%')
        if (description) {
          Text(description).fontSize(12).lineHeight(18).fontColor(this.palette.tertiary).width('100%')
        }
      }.layoutWeight(1).padding({ right: this.wide ? 40 : 0 })
      this.outlined(button, action, danger, allowed)
    }.width('100%').constraintSize({ minHeight: description ? 84 : 60 }).padding({ top: 12, bottom: 12 })
  }

  @Builder
  data() {
    Column() {
      Text(this.configured ? this.t('修改 API Key', 'Change API key') :
        this.t('输入 API Key 开始使用', 'Enter your API key to get started'))
        .fontSize(14).lineHeight(22).fontColor(this.palette.ink).width('100%').margin({ bottom: 8 })
      if (this.configured && !this.keyEditing && !this.input) {
        Row() {
          Text('••••••••••••••••••••••••••••••').fontSize(14).fontColor(this.palette.placeholder).layoutWeight(1)
          Button({ type: ButtonType.Circle }) {
            DemoIcon({ glyph: $r('app.media.demo_edit'), iconSize: this.wide ? 16 : 20, tint: this.palette.ink })
          }.id('edit-api-key').width(33).height(33).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText(this.t('修改 API Key', 'Change API key')).onClick(() => this.keyEditing = true)
        }.height(this.wide ? 44 : 52).width('100%').borderRadius(28)
        .backgroundColor(this.palette.field).padding({ left: 16, right: 10 })
      } else {
        Row() {
          TextInput({ placeholder: this.t('请输入 API Key', 'Enter API key'), text: this.input })
            .id('api-key-input').type(InputType.Password).maxLength(512).height('100%').layoutWeight(1)
            .fontSize(this.wide ? 14 : 16).enterKeyType(EnterKeyType.Done).enableAutoFill(false).showPasswordIcon(false)
            .backgroundColor(Color.Transparent).placeholderColor(this.palette.placeholder).fontColor(this.palette.ink)
            .padding({ left: 0, right: 0 }).onChange((value: string) => this.input = value)
            .onSubmit(() => this.commit())
          if (this.wide && this.input) {
            Button(this.t('确定', 'Confirm')).id('save-api-key').height(36).padding(0)
              .fontSize(14).fontColor(this.palette.brandText).backgroundColor(Color.Transparent)
              .enabled(!this.saving).onClick(() => this.commit())
          }
        }.height(this.wide ? 44 : 52).width('100%').borderRadius(28)
        .backgroundColor(this.wide ? Color.Transparent : this.palette.field)
        .border({ width: this.wide ? 1 : 0, radius: 28, color: this.palette.border }).padding({ left: 16, right: 14 })
      }
      if (this.status) {
        Text(this.status).fontSize(12).lineHeight(18).fontColor(this.palette.tertiary)
          .width('100%').margin({ top: 6 })
      }
      if (this.configured && this.keyEditing) {
        Row({ space: 8 }) {
          this.outlined(this.t('取消', 'Cancel'), () => {
            this.keyEditing = false;
            this.input = '';
          }, false)
          this.outlined(this.t('移除密钥', 'Remove key'), () => {
            this.keyEditing = false;
            this.input = '';
            this.removeKey();
          }, true)
        }.margin({ top: 8 })
      }
      Divider().color(this.palette.border).margin({ top: 12 })
      this.dataRow(this.t('导入历史对话', 'Import chat history'),
        this.t('导入历史对话会覆盖全部本地对话和附件，支持 DeepSeek 导出的 ZIP 文件。', 'Importing replaces all local chats and attachments. Supports ZIP exports from DeepSeek.'),
        this.t('上传', 'Upload'), this.importHistory, false)
      Divider().color(this.palette.border)
      this.dataRow(this.t('导出所有历史对话', 'Export all chats'),
        this.t('包含所有历史对话及附件信息，不包含附件原件或 API Key。', 'Includes all chats and attachment details. Excludes original files and the API key.'),
        this.t('下载', 'Download'), this.exportHistory, false, this.hasHistory)
      Divider().color(this.palette.border)
      this.dataRow(this.t('删除所有对话', 'Delete all chats'), '', this.t('删除', 'Delete'), this.deleteHistory, true)
      if (!this.wide && this.input) {
        Button(this.saving ? this.t('正在验证…', 'Verifying…') : this.t('确定', 'Confirm'))
          .id('save-api-key').type(ButtonType.Capsule).height(52).width('96%').fontSize(17)
          .fontWeight(500).fontColor(this.palette.accentText).backgroundColor(this.palette.accent)
          .enabled(!this.saving).margin({ top: 16 }).onClick(() => this.commit())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  content() {
    Scroll() {
      Column() {
        if (this.section === 'general') {
          this.general()
        } else {
          this.data()
        }
      }.width('100%').padding({ top: this.wide ? 10 : 24, bottom: 12 })
    }.width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
  }

  build() {
    Column() {
      Row() {
        Text(this.t('设置', 'Settings')).fontSize(16).lineHeight(24).fontWeight(500)
          .fontColor(this.palette.ink).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          DemoIcon({ glyph: $r('app.media.demo_close'), iconSize: 14, tint: this.palette.ink })
        }.id('back-to-chat').width(36).height(36).padding(0).margin({ right: -12 })
        .backgroundColor(Color.Transparent).clickEffect(PRESS_EFFECT)
        .accessibilityText(this.t('关闭', 'Close')).onClick(this.close)
      }.width('100%').height(28).margin({ bottom: 7 })
      if (this.wide) {
        Row() {
          Column({ space: 4 }) {
            this.nav(this.t('通用设置', 'General'), $r('app.media.demo_settings'), 'general')
            this.nav(this.t('数据管理', 'Data management'), $r('app.media.demo_data'), 'data')
          }.width(172).height('100%').padding({ top: 10 }).margin({ left: -8, right: 20 })
          Column() {
            this.content()
          }.layoutWeight(1).height('100%')
        }.layoutWeight(1).width('100%')
      } else {
        Row({ space: 4 }) {
          this.nav(this.t('通用设置', 'General'), $r('app.media.demo_settings'), 'general')
          this.nav(this.t('数据管理', 'Data management'), $r('app.media.demo_data'), 'data')
        }.width('100%').height(60)
        Column() {
          this.content()
        }.layoutWeight(1).width('100%')
      }
    }.width(this.wide ? 760 : '100%')
    .height(this.wide ? Math.min(500, this.heightAvailable - 32) : Math.min(800, Math.max(320, this.heightAvailable - 64)))
    .constraintSize({ maxWidth: this.wide ? '96%' : '100%' })
    .padding({ top: 19, left: 24, right: 24, bottom: 22 }).backgroundColor(this.palette.surface)
    .borderRadius({ topLeft: 24, topRight: 24, bottomLeft: this.wide ? 24 : 0, bottomRight: this.wide ? 24 : 0 })
    .shadow({ radius: 16, color: this.wide ? '#14000000' : Color.Transparent, offsetY: 8 })
  }
}
