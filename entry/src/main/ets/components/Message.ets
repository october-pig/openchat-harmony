import { ChatMessage, Attachment, Source } from '../model/Chat';
import { Markdown } from './Markdown';
import { Palette } from './Theme';
import { DemoIcon } from './Icon';
import { CONTROL_MOTION, PRESS_EFFECT, fadeMotion } from './Motion';
import { WaitingDots } from './WaitingDots';

@Component
export struct Message {
  @ObjectLink message: ChatMessage;
  @Prop palette: Palette = new Palette(false);
  @Prop english: boolean = false;
  @Prop busy: boolean = false;
  @Prop canResume: boolean = false;
  @Prop branch: number = 0;
  @Prop branches: number = 1;
  @State expanded: boolean = true;
  @State sourcesOpen: boolean = false;
  @Prop reading: boolean = false;
  @Prop narrow: boolean = false;
  @Prop editing: boolean = false;
  @Prop editText: string = '';
  changeEdit: (text: string) => void = () => {};
  commitEdit: () => void = () => {};
  cancelEdit: () => void = () => {};
  open: (url: string) => void = () => {};
  copy: (text: string) => void = () => {};
  edit: () => void = () => {};
  retry: () => void = () => {};
  resume: () => void = () => {};
  speak: () => void = () => {};
  selectBranch: (step: number) => void = () => {};

  @Builder
  action(glyph: Resource, label: string, handler: () => void) {
    Button({ type: ButtonType.Circle }) {
      DemoIcon({ glyph: glyph, iconSize: 16, tint: this.palette.muted })
    }.width(28).height(28).padding(0).backgroundColor(Color.Transparent)
    .clickEffect(PRESS_EFFECT).accessibilityText(label).onClick(handler)
  }

  @Builder
  branchControls() {
    Row() {
      if (this.branches > 1) {
        Button('‹').type(ButtonType.Normal).fontSize(20).height(40).width(37)
          .fontColor(this.palette.accent).backgroundColor(Color.Transparent)
          .accessibilityText(this.english ? 'Previous branch' : '上一个分支')
          .enabled(this.branch > 0).onClick(() => this.selectBranch(-1))
        Text((this.branch + 1) + '/' + this.branches).fontColor(this.palette.muted).fontSize(12)
        Button('›').type(ButtonType.Normal).fontSize(20).height(40).width(37)
          .fontColor(this.palette.accent).backgroundColor(Color.Transparent)
          .accessibilityText(this.english ? 'Next branch' : '下一个分支')
          .enabled(this.branch < this.branches - 1).onClick(() => this.selectBranch(1))
      }
    }
  }

  @Builder
  assistant() {
    Column({ space: 5 }) {
      if (this.message.reasoning) {
        Column() {
          if (this.message.thinking) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 6 }) {
                DemoIcon({ glyph: $r('app.media.demo_think_large'), tint: this.palette.accent })
                Text(this.message.status === 'streaming' ? (this.english ? 'Thinking' : '正在思考') :
                  (this.english ? 'Thought process' : '已思考')).fontSize(16).fontColor(this.palette.muted)
                Row() {
                  DemoIcon({ glyph: $r('app.media.demo_down'), iconSize: 14, tint: this.palette.muted })
                }.rotate({ angle: this.expanded ? 0 : -90 }).animation(CONTROL_MOTION)
              }
            }.type(ButtonType.Normal).height(34).padding(0).backgroundColor(Color.Transparent)
            .clickEffect(PRESS_EFFECT).onClick(() => {
              this.getUIContext().animateTo(CONTROL_MOTION, () => this.expanded = !this.expanded);
            })
          }
          if (this.expanded || !this.message.thinking) {
            Row({ space: 11 }) {
              Circle({ width: 5, height: 5 }).fill(this.palette.tertiary).margin({ left: 5, top: 8 })
              Text(this.message.reasoning).fontColor(this.palette.tertiary).fontSize(14).lineHeight(24)
                .layoutWeight(1).copyOption(CopyOptions.LocalDevice)
            }.width('100%').alignItems(VerticalAlign.Top).padding({ top: 5, bottom: 5 }).transition(fadeMotion())
          }
        }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 5 })
      }
      if (this.message.status === 'streaming' && (!this.message.text || this.message.activity)) {
        Row({ space: 6 }) {
          if (this.message.activity) {
            DemoIcon({ glyph: this.message.activity === 'searching' ? $r('app.media.demo_search') :
              $r('app.media.demo_globe'), tint: this.palette.muted })
            Text(this.message.activity === 'searching' ? (this.english ? 'Searching…' : '正在搜索') :
              (this.english ? 'Reading…' : '正在阅读')).fontColor(this.palette.muted).fontSize(14)
          } else if (!this.message.reasoning) {
            WaitingDots({ tint: this.palette.muted })
          }
        }.height(34).accessibilityDescription(this.english ? 'Response in progress' : '正在生成回复')
      }
      if (this.message.text) {
        Column() {
          // Recreate the renderer when the theme changes so formula images are generated in the new ink color.
          ForEach([this.palette.ink], (_ink: string) => {
            Markdown({ text: this.message.text, palette: this.palette, open: this.open, copy: this.copy })
          }, (ink: string) => ink)
        }.width('100%').transition(this.message.status === 'streaming' ? fadeMotion() : TransitionEffect.IDENTITY)
      }
      if (this.message.sources.length) {
        Column({ space: 2 }) {
          Button(this.english ? this.message.sources.length + ' web pages' : this.message.sources.length + ' 个网页')
            .type(ButtonType.Normal).height(34).borderRadius(18).fontSize(14).fontColor(this.palette.ink)
            .backgroundColor(Color.Transparent).border({ width: 1, radius: 18, color: this.palette.border })
            .clickEffect(PRESS_EFFECT).onClick(() => {
              this.getUIContext().animateTo(CONTROL_MOTION, () => this.sourcesOpen = !this.sourcesOpen);
            })
          if (this.sourcesOpen) {
            Column({ space: 2 }) {
              ForEach(this.message.sources, (source: Source, index: number) => {
                Button((index + 1) + '. ' + (source.title || source.url))
                  .type(ButtonType.Normal).fontSize(13).fontColor(this.palette.accent).height(40)
                  .backgroundColor(Color.Transparent).onClick(() => this.open(source.url))
              }, (source: Source) => source.url)
            }.alignItems(HorizontalAlign.Start).width('100%').transition(fadeMotion())
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      if (this.message.error || this.message.stopReason === 'refusal') {
        Text(this.message.error || (this.english ? 'The service declined this request.' : '服务暂时无法回答此请求。'))
          .fontSize(13).fontColor(this.palette.error).lineHeight(20)
      } else if (this.message.status === 'stopped') {
        Text(this.english ? 'Generation stopped' : '已停止生成').fontSize(12).fontColor(this.palette.muted)
      }
      if (this.message.status !== 'streaming') {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          if (this.message.text) {
            this.action($r('app.media.demo_copy'), this.english ? 'Copy' : '复制', () => this.copy(this.message.text))
            this.action(this.reading ? $r('app.media.demo_stop') : $r('app.media.demo_read'),
              this.reading ? (this.english ? 'Stop audio' : '停止朗读') : (this.english ? 'Read' : '朗读'), this.speak)
          }
          if (!this.busy) {
            this.action($r('app.media.demo_retry'), this.english ? 'Regenerate' : '重新生成', this.retry)
            if (this.canResume) {
              Button(this.english ? 'Continue' : '继续生成').height(34).type(ButtonType.Capsule)
                .fontSize(13).fontColor(this.palette.brandText).backgroundColor(Color.Transparent)
                .border({ width: 1, color: this.palette.border }).onClick(this.resume)
            }
            this.branchControls()
          }
        }.width('100%').padding({ top: 12, bottom: 10 }).transition(fadeMotion())
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  user() {
    Column({ space: 6 }) {
      if (this.editing) {
        Column() {
          TextArea({ text: this.editText }).id('edit-message-body').fontSize(16).lineHeight(24)
            .fontColor(this.palette.ink).backgroundColor(Color.Transparent)
            .constraintSize({ minHeight: 44, maxHeight: 202 }).padding({ left: 16, right: 16, top: 10 })
            .onChange(this.changeEdit)
          Row({ space: 8 }) {
            Blank()
            Button(this.english ? 'Cancel' : '取消').type(ButtonType.Capsule).height(34).fontSize(14)
              .fontColor(this.palette.ink).backgroundColor(Color.Transparent)
              .border({ width: 1, color: this.palette.border }).onClick(this.cancelEdit)
            Button(this.english ? 'Send' : '发送').type(ButtonType.Capsule).height(34).fontSize(14)
              .fontColor(this.palette.accentText).backgroundColor(this.palette.accent).onClick(this.commitEdit)
          }.padding({ left: 10, right: 10, top: 6, bottom: 10 })
        }.width('100%').borderRadius(22).backgroundColor(this.palette.background)
        .border({ width: 1, radius: 22, color: this.palette.accent })
      } else {
        Column({ space: 6 }) {
          ForEach(this.message.files, (file: Attachment) => {
            Text('↗  ' + file.name).fontSize(13).fontColor(this.palette.accent).maxLines(2)
          }, (file: Attachment, index: number) => file.id + ':' + index)
          if (this.message.text) {
            Text(this.message.text).fontColor(this.palette.ink).fontSize(16).lineHeight(24)
              .copyOption(CopyOptions.LocalDevice).wordBreak(WordBreak.BREAK_WORD)
          }
        }.constraintSize({ maxWidth: this.narrow ? '83%' : '79%' })
        .padding({ left: 16, right: 16, top: 10, bottom: 10 }).backgroundColor(this.palette.bubble).borderRadius(22)
        if (!this.busy) {
          Row({ space: 10 }) {
            this.branchControls()
            this.action($r('app.media.demo_copy'), this.english ? 'Copy' : '复制', () => this.copy(this.message.text))
            this.action($r('app.media.demo_edit'), this.english ? 'Edit message' : '编辑消息', this.edit)
          }.height(28)
        }
      }
    }.width('100%').alignItems(HorizontalAlign.End).padding({ bottom: 16 })
  }

  build() {
    if (this.message.role === 'user') {
      this.user()
    } else {
      this.assistant()
    }
  }
}
