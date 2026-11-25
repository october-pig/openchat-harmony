import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Attachment, ChatMessage, Session, Settings, Workspace, canContinue, defaults, newSession,
  pathTo } from '../model/Chat';
import { HttpFailure, ReplyOptions, Transfer, streamReply, verifyKey } from '../services/DeepSeek';
import { LocalStore, readKey, saveKey } from '../services/LocalStore';
import { Reader, Recorder, pickUploads, transcribe } from '../services/Media';
import { Message } from '../components/Message';
import { SettingsPanel } from '../components/SettingsPanel';
import { Palette } from '../components/Theme';
import { DemoIcon } from '../components/Icon';
import { CONTROL_MOTION, PRESS_EFFECT, fadeMotion, panelMotion } from '../components/Motion';

interface ComposerDraft {
  text: string;
  files: Attachment[];
}

interface ComposerMode {
  label: string;
  glyph: Resource;
  active: boolean;
  id: string;
  toggle: () => void;
}

interface HistoryRow {
  session: Session;
  heading: string;
}

interface HistoryList {
  rows: HistoryRow[];
}

@Entry
@Component
struct Index {
  @StorageLink('systemDark') @Watch('applyAppearance') systemDark: boolean = false;
  @StorageLink('systemEnglish') @Watch('applyAppearance') systemEnglish: boolean = false;
  @State private palette: Palette = new Palette(false);
  @State private settings: Settings = defaults();
  @State private english: boolean = false;
  @State private sessions: Session[] = [];
  @State private selected: string = '';
  @State private visible: ChatMessage[] = [];
  @State private draft: string = '';
  @State private attachments: Attachment[] = [];
  @State private editing: string = '';
  @State private thinking: boolean = false;
  @State private search: boolean = false;
  @State private busy: boolean = false;
  @State private uploading: boolean = false;
  @State private savingKey: boolean = false;
  @State private keyConfigured: boolean = false;
  @State private page: string = 'chat';
  @State private settingsSection: string = 'general';
  @State private collapsed: boolean = false;
  @State private viewportWidth: number = 440;
  @State private viewportHeight: number = 696;
  @State private showHistory: boolean = false;
  @State private historyQuery: string = '';
  @State private wide: boolean = false;
  @State private notice: string = '';
  @State private recording: boolean = false;
  @State private voiceBusy: boolean = false;
  @State private reading: string = '';
  @State private renameId: string = '';
  @State private renameText: string = '';
  @State private keyNotice: string = '';
  private apiKey: string = '';
  private local?: LocalStore;
  private transfer?: Transfer;
  private mediaReader?: Reader;
  private recorder?: Recorder;
  private recordTimeout: number = -1;
  private persistenceTimer: number = -1;
  private scrollTimer: number = -1;
  private noticeTimer: number = -1;
  private followBottom: boolean = true;
  private drafts: Map<string, ComposerDraft> = new Map();
  private scroller: Scroller = new Scroller();
  private historyScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.systemEnglish = !i18n.System.getSystemLanguage().startsWith('zh');
    this.local = new LocalStore(this.host());
    try {
      const saved = this.local.load();
      this.settings = saved.settings;
      this.sessions = saved.sessions;
      this.selected = saved.selected;
      this.refreshMessages();
    } catch {
      this.notify(this.t('无法载入聊天记录', 'Chat history could not be loaded'));
    }
    this.applyAppearance();
    readKey().then((key: string) => {
      if (!this.savingKey) {
        this.apiKey = key;
        this.keyConfigured = Boolean(key);
        if (!key) {
          this.showSettings('data');
        }
      }
    }).catch(() => this.notify(this.t('无法读取 API Key', 'The API key could not be read')));
  }

  aboutToDisappear(): void {
    this.transfer?.cancel();
    clearTimeout(this.noticeTimer);
    clearTimeout(this.recordTimeout);
    clearTimeout(this.persistenceTimer);
    clearTimeout(this.scrollTimer);
    this.recorder?.release().catch(() => {});
    this.mediaReader?.stop().catch(() => {});
  }

  onPageShow(): void {
    this.updateSystemBars();
  }

  onBackPress(): boolean {
    if (this.renameId) {
      this.renameId = '';
      return true;
    }
    if (this.page === 'settings') {
      this.page = 'chat';
      return true;
    }
    if (this.showHistory && !this.wide) {
      this.showHistory = false;
      return true;
    }
    if (this.editing) {
      this.cancelEdit();
      return true;
    }
    return false;
  }

  private host(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private t(zh: string, en: string): string {
    return this.english ? en : zh;
  }

  private toggleWideSidebar(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.collapsed = !this.collapsed;
    });
  }

  private applyAppearance(): void {
    this.english = this.settings.language === 'system' ? this.systemEnglish : this.settings.language === 'en';
    this.palette = new Palette(this.settings.theme === 'dark' || (this.settings.theme === 'system' && this.systemDark));
    this.updateSystemBars();
  }

  private updateSystemBars(): void {
    const mainWindow = this.getUIContext().getSharedLocalStorage()?.get<window.Window>('mainWindow');
    if (!mainWindow) {
      return;
    }
    try {
      mainWindow.setWindowBackgroundColor(this.palette.background);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: this.palette.ink,
        navigationBarContentColor: this.palette.ink
      }).catch((error: BusinessError) => {
        hilog.warn(0, 'DeepSeekNative', 'Could not style system bars: %{public}d', error.code);
      });
    } catch (error) {
      hilog.warn(0, 'DeepSeekNative', 'Could not style window: %{public}d', (error as BusinessError).code);
    }
  }

  private workspace(sessions: Session[], selected: string): Workspace {
    return { version: 1, selected: selected, sessions: sessions, settings: this.settings };
  }

  private persist(): void {
    try {
      this.local?.save(this.workspace(this.sessions, this.selected));
    } catch {
      this.notify(this.t('无法保存到本机', 'This change could not be saved'));
    }
  }

  private notify(message: string): void {
    clearTimeout(this.noticeTimer);
    this.notice = message;
    this.noticeTimer = setTimeout(() => this.notice = '', 4800);
  }

  private showSettings(section: string = 'general'): void {
    this.getUIContext().getFocusController().clearFocus();
    this.keyNotice = '';
    this.settingsSection = section;
    this.page = 'settings';
  }

  private async updateKey(value: string): Promise<void> {
    if (this.savingKey) {
      return;
    }
    this.savingKey = true;
    try {
      if (value) {
        this.keyNotice = this.t('正在验证…', 'Verifying…');
        await verifyKey(value);
      }
      await saveKey(value);
      this.apiKey = value;
      this.keyConfigured = Boolean(value);
      this.keyNotice = value ? this.t('已保存密钥', 'API key saved') : this.t('已移除密钥', 'API key removed');
      if (value && this.page === 'settings') {
        this.getUIContext().getFocusController().clearFocus();
        this.page = 'chat';
      }
    } catch (error) {
      this.keyNotice = error instanceof HttpFailure ? this.describeError(error as Error) :
        this.t('无法更新密钥，请检查网络后重试', 'Could not update the key. Check the network and try again.');
    } finally {
      this.savingKey = false;
    }
  }

  private describeError(error: Error): string {
    if (error instanceof HttpFailure) {
      switch (error.status) {
        case 401:
        case 403:
          return this.t('API Key 无效或没有访问权限', 'Invalid API key or access denied');
        case 402:
          return this.t('DeepSeek 账户余额不足', 'Insufficient DeepSeek account balance');
        case 429:
          return this.t('请求过于频繁，请稍后再试', 'Request limit reached. Try again later.');
        default:
          if (error.message && error.message.length < 250) {
            return this.apiKey ? error.message.split(this.apiKey).join('••••') : error.message;
          }
          if (error.status) {
            return this.t('DeepSeek 返回错误 ', 'DeepSeek returned error ') + error.status;
          }
      }
    }
    return this.t('连接中断，请检查网络后重试', 'Connection interrupted. Check your network and try again.');
  }

  private confirm(title: string, explanation: string, action: () => void): void {
    this.getUIContext().showAlertDialog({
      title: title,
      message: explanation,
      primaryButton: { value: this.t('取消', 'Cancel'), action: () => {} },
      secondaryButton: { value: this.t('确认', 'Confirm'), action: action }
    });
  }

  private openLink(url: string): void {
    if (/^https?:\/\//i.test(url)) {
      this.host().openLink(url).catch(() => this.notify(this.t('无法打开链接', 'The link could not be opened')));
    }
  }

  private copy(value: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
    pasteboard.getSystemPasteboard().setData(data).then(() => this.notify(this.t('已复制', 'Copied')))
      .catch(() => this.notify(this.t('复制失败', 'Copy failed')));
  }

  private current(): Session | undefined {
    return this.sessions.find((session: Session) => session.id === this.selected);
  }

  private refreshMessages(): void {
    const current = this.current();
    this.visible = current ? pathTo(current, current.head) : [];
  }

  private setSession(id: string): void {
    if (this.uploading || this.recording || this.voiceBusy) {
      this.notify(this.t('请等待当前操作完成', 'Wait for the current operation to finish'));
      return;
    }
    if (this.selected !== id && !this.editing) {
      this.drafts.set(this.selected, { text: this.draft, files: this.attachments });
    }
    if (this.selected !== id || this.editing) {
      this.editing = '';
      this.draft = this.drafts.get(id)?.text ?? '';
      this.attachments = this.drafts.get(id)?.files ?? [];
    }
    this.getUIContext().getFocusController().clearFocus();
    this.selected = id;
    this.page = 'chat';
    this.showHistory = false;
    this.refreshMessages();
    this.scrollBottom(true);
    this.persist();
  }

  private touch(session: Session): void {
    session.updated = Date.now();
    this.sessions = this.sessions.slice().sort((left: Session, right: Session) => right.updated - left.updated);
    if (session.id === this.selected) {
      this.refreshMessages();
    }
    this.persist();
  }

  private scrollBottom(force: boolean = false): void {
    if (force) {
      this.followBottom = true;
    }
    if (!this.followBottom || this.page !== 'chat') {
      return;
    }
    clearTimeout(this.scrollTimer);
    this.scrollTimer = setTimeout((): void => this.scroller.scrollEdge(Edge.Bottom), 35);
  }

  private title(session: Session): string {
    return session.title || this.t('新对话', 'New chat');
  }

  private saveRename(): void {
    const session = this.sessions.find((item: Session) => item.id === this.renameId);
    const name = this.renameText.trim();
    if (session && name) {
      session.title = name;
      session.customTitle = true;
      this.touch(session);
    }
    this.renameId = '';
  }

  private deleteSession(session: Session): void {
    this.confirm(this.t('删除此对话？', 'Delete this conversation?'), this.title(session), () => {
      if (session.id === this.selected) {
        this.selected = '';
        this.editing = '';
        this.draft = '';
        this.attachments = [];
      }
      this.drafts.delete(session.id);
      this.sessions = this.sessions.filter((item: Session) => item.id !== session.id);
      this.refreshMessages();
      this.persist();
    });
  }

  private siblings(message: ChatMessage): ChatMessage[] {
    return this.current()?.messages.filter((item: ChatMessage) => item.parent === message.parent) ?? [];
  }

  private branchIndex(message: ChatMessage): number {
    return this.siblings(message).findIndex((item: ChatMessage): boolean => item.id === message.id);
  }

  private selectBranch(message: ChatMessage, step: number): void {
    const session = this.current();
    const target = this.siblings(message)[this.branchIndex(message) + step];
    if (!session || !target || this.busy) {
      return;
    }
    let leaf = target;
    while (true) {
      const children = session.messages.filter((item: ChatMessage) => item.parent === leaf.id);
      if (!children.length) {
        break;
      }
      leaf = children[children.length - 1];
    }
    session.head = leaf.id;
    this.refreshMessages();
    this.persist();
  }

  private beginEdit(message: ChatMessage): void {
    if (this.busy || this.uploading || this.recording || this.voiceBusy) {
      return;
    }
    if (!this.editing) {
      this.drafts.set(this.selected, { text: this.draft, files: this.attachments });
    }
    this.editing = message.id;
    this.draft = message.text;
    this.attachments = message.files.slice();
    this.scrollBottom(true);
    setTimeout(() => this.getUIContext().getFocusController().requestFocus('edit-message-body'), 40);
  }

  private cancelEdit(): void {
    const saved = this.drafts.get(this.selected);
    this.draft = saved?.text ?? '';
    this.attachments = saved?.files ?? [];
    this.editing = '';
  }

  private canSend(): boolean {
    return Boolean(this.draft.trim() || this.attachments.some((file: Attachment) => Boolean(file.id))) && !this.uploading && !this.recording && !this.voiceBusy;
  }

  private requireKey(): boolean {
    if (this.apiKey) {
      return true;
    }
    this.showSettings('data');
    this.keyNotice = this.t('请先添加 DeepSeek API Key', 'Add a DeepSeek API key first');
    return false;
  }

  private send(): void {
    if (this.busy || !this.canSend() || !this.requireKey()) {
      return;
    }
    let session = this.current();
    if (!session) {
      session = newSession();
      this.sessions = [session, ...this.sessions];
      this.selected = session.id;
      this.drafts.delete('');
    }
    const prior = session.messages.find((message: ChatMessage) => message.id === this.editing);
    const question = new ChatMessage();
    question.parent = prior ? prior.parent : session.head;
    question.text = this.draft.trim();
    question.files = this.attachments.slice();
    session.messages.push(question);
    const generateTitle = !session.title;
    if (generateTitle) {
      session.title = Array.from(question.text.replace(/\s+/g, ' ')).slice(0, 30).join('') ||
        question.files[0]?.name || this.t('新对话', 'New chat');
    }
    if (this.editing) {
      this.cancelEdit();
    } else {
      this.draft = '';
      this.attachments = [];
      this.drafts.delete(this.selected);
    }
    this.getUIContext().getFocusController().clearFocus();
    this.generate(session, question, generateTitle);
  }

  private retry(message: ChatMessage, prefix: boolean): void {
    const session = this.current();
    if (!session || this.busy || !this.requireKey()) {
      return;
    }
    const question = session.messages.find((item: ChatMessage) => item.id === message.parent);
    if (question && !question.text && !question.files.some((file: Attachment) => Boolean(file.id))) {
      this.notify(this.t('历史附件不可用，请编辑消息并重新上传。', 'The original attachments are unavailable. Edit the message and reattach them.'));
      return;
    }
    if (question) {
      this.generate(session, question, !prefix && !question.parent && !session.customTitle && message.status === 'error',
        message, prefix);
    }
  }

  private generate(session: Session, question: ChatMessage, title: boolean,
    original?: ChatMessage, prefix: boolean = false): void {
    const reply = prefix && original ? original : new ChatMessage();
    reply.role = 'assistant';
    reply.parent = question.id;
    reply.status = 'streaming';
    reply.error = '';
    reply.activity = '';
    reply.thinking = original?.thinking ?? this.thinking;
    reply.search = original?.search ?? this.search;
    if (!prefix) {
      session.messages.push(reply);
    }
    session.head = reply.id;
    this.busy = true;
    this.touch(session);
    this.scrollBottom(true);
    const now = new Date();
    const date = now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0') + '-' +
      String(now.getDate()).padStart(2, '0');
    const weekday = new Intl.DateTimeFormat(this.english ? 'en' : 'zh-CN', { weekday: 'long' }).format(now);
    const options: ReplyOptions = {
      generateTitle: title,
      prefix: prefix,
      reminder: [date, weekday, this.settings.location.trim().split('/').pop()?.replace(/,/g, ' ') ?? '', 'App',
        this.english ? 'English' : '中文'].join(',')
    };
    const request = new Transfer();
    this.transfer = request;
    const scrollTick = setInterval(() => {
      if (this.selected === session.id) {
        this.scrollBottom();
      }
    }, 170);
    const saveTick = setInterval(() => this.persist(), 4000);
    streamReply(this.apiKey, pathTo(session, question.id), reply, options, request)
      .then((generated: string) => {
        reply.status = 'done';
        if (generated && !session.customTitle) {
          session.title = generated;
        }
      })
      .catch((err: Error) => {
        if (request.cancelled) {
          reply.status = 'stopped';
        } else {
          reply.status = 'error';
          reply.error = this.describeError(err);
        }
      })
      .finally(() => {
        clearInterval(scrollTick);
        clearInterval(saveTick);
        reply.activity = '';
        this.transfer = undefined;
        this.busy = false;
        this.touch(session);
        this.scrollBottom();
      });
  }

  private async addAttachment(): Promise<void> {
    if (this.uploading || this.recording || this.voiceBusy || this.busy || !this.requireKey()) {
      return;
    }
    const remaining = 10 - this.attachments.length;
    if (remaining <= 0) {
      this.notify(this.t('每次最多添加 10 个附件', 'Add up to 10 attachments per message'));
      return;
    }
    this.uploading = true;
    try {
      await pickUploads(this.host(), this.apiKey, remaining, (file: Attachment) => {
        this.attachments = [...this.attachments, file];
      });
    } catch (err) {
      this.notify(err instanceof HttpFailure ? this.describeError(err as Error) :
        this.t('附件上传失败，请检查文件类型与大小', 'Upload failed. Check the file type and size.'));
    } finally {
      this.uploading = false;
    }
  }

  private async toggleRecording(): Promise<void> {
    if (this.voiceBusy || this.busy || this.uploading || !this.requireKey()) {
      return;
    }
    this.voiceBusy = true;
    try {
      if (this.recorder && this.recording) {
        clearTimeout(this.recordTimeout);
        const recorder = this.recorder;
        this.recorder = undefined;
        this.recording = false;
        const text = await transcribe(this.apiKey, await recorder.wav());
        if (text) {
          this.draft += (this.draft ? ' ' : '') + text;
        } else {
          this.notify(this.t('未识别到语音', 'No speech detected'));
        }
      } else {
        const recorder = new Recorder();
        this.recorder = recorder;
        this.recording = await recorder.start(this.host());
        if (this.recording) {
          this.recordTimeout = setTimeout(() => this.toggleRecording(), 120000);
        } else {
          this.recorder = undefined;
          this.notify(this.t('请允许访问麦克风', 'Allow access to the microphone'));
        }
      }
    } catch (err) {
      this.recorder = undefined;
      this.recording = false;
      this.notify(err instanceof HttpFailure ? this.describeError(err as Error) : this.t('语音处理失败', 'Speech processing failed'));
    } finally {
      this.voiceBusy = false;
    }
  }

  private async readAloud(message: ChatMessage): Promise<void> {
    if (!this.requireKey()) {
      return;
    }
    if (this.mediaReader) {
      const current = this.reading;
      const previous = this.mediaReader;
      this.mediaReader = undefined;
      this.reading = '';
      await previous.stop().catch(() => {});
      if (current === message.id || this.mediaReader) {
        return;
      }
    }
    const reader = new Reader();
    this.mediaReader = reader;
    this.reading = message.id;
    try {
      await reader.play(this.apiKey, message.text, this.settings.voice ?? 'stella');
    } catch (err) {
      if (this.mediaReader === reader) {
        this.notify(err instanceof HttpFailure ? this.describeError(err as Error) : this.t('无法播放回复', 'Audio playback failed'));
      }
    } finally {
      if (this.mediaReader === reader) {
        this.mediaReader = undefined;
        this.reading = '';
      }
    }
  }

  private async exportHistory(): Promise<void> {
    try {
      if (await this.local?.exportSessions(this.sessions)) {
        this.notify(this.t('历史已导出', 'History exported'));
      }
    } catch {
      this.notify(this.t('导出失败', 'Export failed'));
    }
  }

  private async importHistory(): Promise<void> {
    try {
      const imported = await this.local?.importSessions();
      if (imported) {
        this.confirm(this.t('导入聊天记录？', 'Import chat history?'),
          this.t('导入会覆盖当前的所有本地会话。', 'This replaces all current local conversations.'),
          () => this.replaceHistory(imported));
      }
    } catch {
      this.notify(this.t('无法读取历史文件，请选择 DeepSeek 导出的 ZIP。',
        'Could not read the archive. Choose a ZIP exported by DeepSeek.'));
    }
  }

  private replaceHistory(sessions: Session[]): void {
    if (this.busy || this.uploading || this.recording || this.voiceBusy) {
      this.notify(this.t('请等待当前操作完成', 'Wait for the current operation to finish'));
      return;
    }
    try {
      this.local?.save(this.workspace(sessions, ''));
      this.sessions = sessions;
      this.selected = '';
      this.visible = [];
      this.drafts.clear();
      this.draft = '';
      this.editing = '';
      this.attachments = [];
      this.notify(this.t('聊天记录已更新', 'Chat history updated'));
    } catch {
      this.notify(this.t('无法保存聊天记录', 'Chat history could not be saved'));
    }
  }

  @Builder
  icon(glyph: Resource, title: string, id: string, diameter: number, size: number, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      DemoIcon({ glyph: glyph, iconSize: size, tint: this.palette.ink })
    }.id(id).width(diameter).height(diameter).padding(0).backgroundColor(Color.Transparent)
    .clickEffect(PRESS_EFFECT).accessibilityText(title).onClick(action)
  }

  @Builder
  header() {
    Row() {
      if (!this.wide) {
        this.icon($r('app.media.demo_menu'), this.t('打开边栏', 'Open sidebar'), 'open-history', 44, 20,
          () => this.showHistory = true)
      }
      if (this.visible.length) {
        Text(this.current()?.title || this.t('新对话', 'New chat')).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.palette.ink).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1).margin({ left: 12, right: 12 })
        if (!this.wide) {
          this.icon($r('app.media.demo_new_chat'), this.t('开启新对话', 'New chat'), 'new-chat', 44, 20,
            () => this.setSession(''))
        }
      }
    }.height(60).width('100%').padding({ left: this.wide ? (this.collapsed ? 131 : 18) : 10,
      right: this.wide ? 18 : 10, top: 12, bottom: this.wide ? 0 : 4 })
  }

  private historyGroup(value: number): string {
    const days = Math.floor((new Date().setHours(0, 0, 0, 0) - new Date(value).setHours(0, 0, 0, 0)) / 86400000);
    if (days <= 0) {
      return this.t('今天', 'Today');
    }
    if (days === 1) {
      return this.t('昨天', 'Yesterday');
    }
    if (days < 7) {
      return this.t('7 天内', 'Previous 7 days');
    }
    if (days < 30) {
      return this.t('30 天内', 'Previous 30 days');
    }
    return new Intl.DateTimeFormat(this.english ? 'en' : 'zh-CN',
      { month: 'long', year: 'numeric' }).format(new Date(value));
  }

  private historyRows(): HistoryRow[] {
    const query = this.historyQuery.trim().toLowerCase();
    const matches = query ? this.sessions.filter((session: Session) =>
      this.title(session).toLowerCase().includes(query) ||
      session.messages.some((message: ChatMessage) => message.text.toLowerCase().includes(query))) : this.sessions;
    let previousGroup = '';
    return matches.map((session: Session): HistoryRow => {
      const group = this.historyGroup(session.updated);
      const heading = group === previousGroup ? '' : group;
      previousGroup = group;
      return { session: session, heading: heading };
    });
  }

  @Builder
  historyList($$: HistoryList) {
    Scroll(this.historyScroller) {
      Column() {
        if (!$$.rows.length && this.historyQuery.trim()) {
          Text(this.t('未找到匹配的会话', 'No matching conversations')).id('history-no-results')
            .fontSize(13).fontColor(this.palette.tertiary).padding({ left: 10, top: 4 })
        }
        ForEach($$.rows, (row: HistoryRow, index: number) => {
          if (row.heading) {
            Text(row.heading).fontSize(this.wide ? 12 : 14).fontColor(this.palette.tertiary)
              .fontWeight(FontWeight.Medium).width('100%').padding({ left: 10, top: index === 0 ? 4 : 16, bottom: 4 })
          }
          Row() {
            Button({ type: ButtonType.Normal }) {
              Text(this.title(row.session)).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(this.palette.ink).width('100%')
            }.id('history-' + row.session.id).layoutWeight(1).height(42).borderRadius(10)
            .padding({ left: 10, right: 3 }).backgroundColor(Color.Transparent)
            .onClick(() => this.setSession(row.session.id))
            Button({ type: ButtonType.Circle }) {
              DemoIcon({ glyph: $r('app.media.demo_ellipsis'), tint: this.palette.muted })
            }.width(34).height(34).padding(0).backgroundColor(Color.Transparent)
            .accessibilityText(this.t('更多', 'More'))
            .bindMenu([
              { value: this.t('重命名', 'Rename'), action: () => {
                this.renameText = this.title(row.session);
                this.renameId = row.session.id;
              } },
              { value: this.t('删除', 'Delete'), enabled: !this.busy, action: () => this.deleteSession(row.session) }
            ])
          }.width('100%').borderRadius(10)
          .backgroundColor(row.session.id === this.selected ? this.palette.sidebarActive : this.palette.sidebar)
        }, (row: HistoryRow, index: number) =>
          `${row.session.id}:${row.session.title}:${row.session.updated}:${row.heading}:${index === 0}`)
      }.alignItems(HorizontalAlign.Start).width('100%')
    }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
    .margin({ top: this.wide ? 24 : 16 })
  }

  @Builder
  history() {
    Column() {
      Row({ space: 8 }) {
        Search({ value: this.historyQuery, placeholder: this.t('搜索会话', 'Search conversations') })
          .id('history-search').height(36).layoutWeight(1)
          .backgroundColor(this.palette.field).border({ width: 1, radius: 18, color: this.palette.border })
          .fontColor(this.palette.ink).textFont({ size: 14 })
          .placeholderColor(this.palette.tertiary).placeholderFont({ size: 14 })
          .searchIcon({ size: 16, color: this.palette.muted })
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: { size: 14, color: this.palette.muted } })
          .onChange((value: string) => {
            this.historyQuery = value;
            this.historyScroller.scrollEdge(Edge.Top);
          })
        this.icon($r('app.media.demo_panel'), this.t('收起边栏', 'Collapse sidebar'), 'close-history', 36, 16, () => {
          this.getUIContext().getFocusController().clearFocus();
          if (this.wide) {
            this.toggleWideSidebar();
          } else {
            this.showHistory = false;
          }
        })
      }.height(48).width('100%').padding({ left: 8, top: 5 }).margin({ bottom: 16 })
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 6 }) {
          DemoIcon({ glyph: $r('app.media.demo_new_chat'), iconSize: 16, tint: this.palette.ink })
          Text(this.t('开启新对话', 'New chat')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.ink)
        }
      }.id('history-new-chat').height(40).width('100%').backgroundColor(this.palette.surface)
      .shadow({ radius: 2, offsetY: 1, color: '#1A4868B2' }).clickEffect(PRESS_EFFECT)
      .onClick(() => this.setSession(''))
      this.historyList({ rows: this.historyRows() })
      Button({ type: ButtonType.Normal }) {
        Row({ space: this.wide ? 4 : 10 }) {
          Row() {
            DemoIcon({ glyph: $r('app.media.demo_settings'), iconSize: this.wide ? 16 : 20, tint: this.palette.ink })
          }.width(this.wide ? 32 : 20).height(32).justifyContent(FlexAlign.Center)
          Text(this.t('设置', 'Settings')).fontSize(this.wide ? 14 : 16).fontColor(this.palette.ink)
        }.width('100%')
      }.id('open-settings').height(44).width('100%').padding({ left: this.wide ? 6 : 10, right: 2 })
      .backgroundColor(Color.Transparent).borderRadius(12).margin({ top: 10, bottom: this.wide ? 10 : 12 })
      .onClick(() => this.showSettings())
    }.width(this.wide ? 261 : Math.min(300, this.viewportWidth - 48)).height('100%')
    .alignItems(HorizontalAlign.Start).padding({ left: 12, right: 12, top: 6 }).backgroundColor(this.palette.sidebar)
    .border({ width: { right: 1 }, color: this.palette.border })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(this.wide ? TransitionEffect.IDENTITY : panelMotion(TransitionEdge.START))
  }

  @Builder
  greeting() {
    Text(this.t('今天有什么可以帮到你？', 'How can I help you?'))
      .fontSize(this.viewportWidth < 440 ? 20 : 24).lineHeight(this.viewportWidth < 440 ? 28 : 32)
      .fontWeight(this.viewportWidth < 440 ? 500 : 600)
      .fontColor(this.palette.ink).textAlign(TextAlign.Center)
  }

  @Builder
  welcome() {
    if (this.wide) {
      Column({ space: 21 }) {
        this.greeting()
        this.composer(false)
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding({ bottom: 64 })
    } else {
      Column() {
        this.greeting()
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      this.composer(true)
    }
  }

  @Builder
  timeline() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        ForEach(this.visible, (message: ChatMessage) => {
          Message({
            message: message,
            palette: this.palette,
            english: this.english,
            busy: this.busy,
            reading: this.reading === message.id,
            narrow: this.viewportWidth < 440,
            editing: this.editing === message.id,
            editText: this.editing === message.id ? this.draft : '',
            changeEdit: (value: string) => this.draft = value,
            commitEdit: () => this.send(),
            cancelEdit: () => this.cancelEdit(),
            branch: this.branchIndex(message),
            branches: this.siblings(message).length,
            canResume: !this.busy && message.id === this.current()?.head && canContinue(message),
            copy: (value: string) => this.copy(value),
            open: (url: string) => this.openLink(url),
            edit: () => this.beginEdit(message),
            retry: () => this.retry(message, false),
            resume: () => this.retry(message, true),
            speak: () => this.readAloud(message),
            selectBranch: (step: number) => this.selectBranch(message, step)
          })
        }, (message: ChatMessage) => message.id)
      }.constraintSize({ maxWidth: this.viewportWidth < 1024 ? 680 : 792 }).width('100%')
      .padding({ left: 20, right: 20, top: 34, bottom: 24 })
    }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
    .onDidScroll((_x: number, y: number, state: ScrollState) => {
      if (state !== ScrollState.Idle && y !== 0) {
        this.followBottom = this.scroller.isAtEnd();
      }
    }).onReachEnd(() => this.followBottom = true)
  }

  @Builder
  mode($$: ComposerMode) {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 4 }) {
        DemoIcon({ glyph: $$.glyph, iconSize: 14, tint: $$.active ? this.palette.brandText : this.palette.ink })
        if (this.viewportWidth >= (this.english ? 370 : 346)) {
          Text($$.label).fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor($$.active ? this.palette.brandText : this.palette.ink)
        }
      }
    }.id($$.id).height(34).padding({ left: 12, right: 12 })
    .backgroundColor($$.active ? this.palette.accentSoft : Color.Transparent)
    .border({ width: 1, radius: 18, color: $$.active ? this.palette.activeBorder : this.palette.border })
    .animation(CONTROL_MOTION).clickEffect(PRESS_EFFECT)
    .accessibilityText($$.label)
    .accessibilityDescription($$.active ? this.t('已开启', 'Enabled') : this.t('已关闭', 'Disabled'))
    .onClick($$.toggle)
  }

  @Builder
  composer(caveat: boolean) {
    Column() {
      if (this.notice) {
        Text(this.notice).fontSize(13).fontColor(this.palette.brandText).lineHeight(20)
          .width('100%').padding(7).backgroundColor(this.palette.accentSoft).borderRadius(8)
          .transition(fadeMotion())
      }
      Column() {
        if (this.uploading || this.recording || this.voiceBusy) {
          Row() {
            Text(this.editing ? this.t('正在编辑消息', 'Editing a message') : this.uploading ?
              this.t('正在上传附件…', 'Uploading attachments…') : this.recording ?
                this.t('正在录音', 'Recording') : this.t('正在处理语音…', 'Processing speech…'))
              .fontColor(this.palette.brandText).fontSize(13)
            Blank()
            if (this.editing) {
              Button(this.t('取消', 'Cancel')).type(ButtonType.Normal).fontSize(13).height(32)
                .fontColor(this.palette.brandText).backgroundColor(Color.Transparent).onClick(() => this.cancelEdit())
            }
          }.height(32).width('100%').padding({ left: 16, right: 12 }).transition(fadeMotion())
        }
        if (this.attachments.length && !this.editing) {
          Scroll() {
            Row({ space: 10 }) {
              ForEach(this.attachments, (file: Attachment, index: number) => {
                Button(file.name + ' ×').type(ButtonType.Normal).height(36).borderRadius(12).fontSize(12)
                  .fontColor(this.palette.ink).backgroundColor(this.palette.subtle)
                  .accessibilityText(this.t('移除附件 ', 'Remove attachment ') + file.name)
                  .onClick(() => this.attachments = this.attachments.filter((_file: Attachment, i: number) => i !== index))
              }, (file: Attachment, index: number) => file.id + ':' + index)
            }.padding({ left: 12, right: 12, top: 12 })
          }.scrollable(ScrollDirection.Horizontal).width('100%').align(Alignment.Start)
        }
        TextArea({ text: this.editing ? '' : this.draft, placeholder: this.t('请输入消息', 'Enter a message') })
          .id('chat-composer').fontSize(16).lineHeight(24).fontColor(this.palette.ink)
          .placeholderColor(this.palette.placeholder)
          .backgroundColor(Color.Transparent).width('100%').padding({ left: 16, right: 12, top: 12, bottom: 0 })
          .constraintSize({ minHeight: this.viewportWidth < 440 ? 42 : 60, maxHeight: 240 }).maxLength(64000)
          .enabled(!this.editing).onChange((value: string) => this.draft = value)
        Row() {
          Row({ space: 10 }) {
            this.mode({
              label: this.t('深度思考', 'DeepThink'),
              glyph: $r('app.media.demo_think'),
              active: this.thinking,
              id: 'toggle-thinking',
              toggle: () => this.thinking = !this.thinking
            })
            this.mode({
              label: this.t('智能搜索', 'Search'),
              glyph: $r('app.media.demo_globe'),
              active: this.search,
              id: 'toggle-search',
              toggle: () => this.search = !this.search
            })
          }
          Blank()
          Row({ space: 4 }) {
            this.icon(this.recording ? $r('app.media.demo_mic_record') : $r('app.media.demo_mic'),
              this.t('语音输入', 'Voice input'), 'voice-input', 34, 16, () => this.toggleRecording())
            this.icon($r('app.media.demo_clip'), this.t('上传文件', 'Upload file'), 'attach-file', 34, 16,
              () => this.addAttachment())
            Button({ type: ButtonType.Circle }) {
              Stack() {
                Row() {
                  DemoIcon({ glyph: $r('app.media.demo_stop'), iconSize: 16, tint: this.palette.accentText })
                }.opacity(this.busy ? 1 : 0).animation(CONTROL_MOTION)
                Row() {
                  DemoIcon({ glyph: $r('app.media.demo_send'), iconSize: 16, tint: this.palette.accentText })
                }.opacity(this.busy ? 0 : 1).animation(CONTROL_MOTION)
              }.width(16).height(16)
            }.id('send-message').height(34).width(34).padding(0).margin({ left: 6 })
            .backgroundColor(this.palette.accent)
            .accessibilityText(this.busy ? this.t('停止生成', 'Stop generation') : this.t('发送', 'Send'))
            .opacity(this.busy || (!this.editing && this.canSend()) ? 1 : 0.4)
            .animation(CONTROL_MOTION).clickEffect(PRESS_EFFECT).onClick(() => {
              if (this.busy) {
                this.transfer?.cancel();
              } else if (!this.editing) {
                this.send();
              }
            })
          }
        }.height(58).width('100%').padding({ left: 12, right: 12 }).margin({ top: 4 })
      }.width('100%').backgroundColor(this.palette.input).borderRadius(24)
      .border({ width: 1, radius: 24, color: this.palette.border })
      .shadow({ radius: 11, offsetY: 4, color: this.palette.shadowColor })
      if (caveat) {
        Text(this.t('内容由 AI 生成，请仔细甄别', 'AI-generated, for reference only'))
          .height(28).width('100%').textAlign(TextAlign.Center).fontSize(11).lineHeight(16)
          .fontColor(this.palette.tertiary)
      }
    }.width('100%').constraintSize({ maxWidth: this.viewportWidth < 1024 ? 712 : 808 })
    .padding({ left: 16, right: 16 })
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row().width('100%').height('100%').backgroundColor(this.palette.background)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      Row() {
        if (this.wide) {
          Stack({ alignContent: Alignment.TopStart }) {
            Column() {
              this.history()
            }.width(261).height('100%').translate({ x: this.collapsed ? -261 : 0 })
          }.width(this.collapsed ? 0 : 261).height('100%').clip(true)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .hitTestBehavior(this.collapsed ? HitTestMode.None : HitTestMode.Default)
          .accessibilityLevel(this.collapsed ? 'no-hide-descendants' : 'auto')
        }
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            if (!this.wide || this.visible.length) {
              this.header()
            }
            if (this.visible.length) {
              this.timeline()
              this.composer(true)
            } else {
              this.welcome()
            }
          }.width('100%').height('100%')
          if (this.wide && this.collapsed) {
            Row({ space: 16 }) {
              Row({ space: 2 }) {
                this.icon($r('app.media.demo_panel'), this.t('打开边栏', 'Open sidebar'),
                  'open-history', 36, 16, () => this.toggleWideSidebar())
                this.icon($r('app.media.demo_new_chat'), this.t('开启新对话', 'New chat'),
                  'new-chat', 36, 16, () => this.setSession(''))
              }.height(40).padding({ left: 2, right: 2 }).borderRadius(24)
              .backgroundColor(this.palette.surface).border({ width: 1, radius: 24, color: this.palette.border })
            }.margin({ top: 12, left: 16 }).transition(fadeMotion())
          }
        }.height('100%').layoutWeight(1)
      }.width('100%').height('100%')
      if (this.showHistory && !this.wide) {
        Row().width('100%').height('100%').backgroundColor(Color.Transparent).onClick(() => this.showHistory = false)
        this.history()
      }
      Stack({ alignContent: this.wide ? Alignment.Center : Alignment.Bottom }) {
        if (this.page === 'settings') {
          Row().width('100%').height('100%').backgroundColor(this.palette.overlay).backdropBlur(2)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .transition(fadeMotion())
            .onClick(() => this.page = 'chat')
          if (!this.wide) {
            Row().width('100%').height('1%').backgroundColor(this.palette.surface)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
              .transition(fadeMotion())
          }
          Stack({ alignContent: Alignment.Bottom }) {
            SettingsPanel({
              palette: this.palette,
              wide: this.wide,
              heightAvailable: this.viewportHeight,
              hasHistory: this.sessions.length > 0,
              section: this.settingsSection,
              close: () => this.page = 'chat',
              changeSection: (section: string) => this.settingsSection = section,
              english: this.english,
              configured: this.keyConfigured,
              saving: this.savingKey,
              status: this.keyNotice || this.notice,
              theme: this.settings.theme,
              language: this.settings.language,
              location: this.settings.location,
              voice: this.settings.voice ?? 'stella',
              changeVoice: (voice: string) => {
                this.settings = { theme: this.settings.theme, language: this.settings.language,
                  location: this.settings.location, voice: voice };
                this.persist();
              },
              saveKey: (key: string) => this.updateKey(key),
              removeKey: () => this.confirm(this.t('移除 API Key？', 'Remove API key?'),
                this.t('下次聊天前需要重新输入密钥。', 'Enter a key again before your next chat.'),
                () => this.updateKey('')),
              changeTheme: (theme: string) => {
                this.settings = { theme: theme, language: this.settings.language, location: this.settings.location, voice: this.settings.voice };
                this.applyAppearance();
                this.persist();
              },
              changeLanguage: (language: string) => {
                this.settings = { theme: this.settings.theme, language: language, location: this.settings.location, voice: this.settings.voice };
                this.applyAppearance();
                this.persist();
              },
              changeLocation: (location: string) => {
                this.settings = { theme: this.settings.theme, language: this.settings.language,
                  location: location, voice: this.settings.voice };
                clearTimeout(this.persistenceTimer);
                this.persistenceTimer = setTimeout(() => this.persist(), 350);
              },
              importHistory: () => this.importHistory(),
              exportHistory: () => this.exportHistory(),
              deleteHistory: () => this.confirm(this.t('清空所有会话？', 'Delete all conversations?'),
                this.t('此操作会删除本机的聊天记录。', 'This deletes chat history from this device.'),
                () => this.replaceHistory([])),
            })
          }.width(this.wide ? 760 : '100%').constraintSize({ maxWidth: '100%' })
          .transition(panelMotion(this.wide ? undefined : TransitionEdge.BOTTOM))
        }
      }.width('100%').height('100%')
      .hitTestBehavior(this.page === 'settings' ? HitTestMode.Default : HitTestMode.None)
      .accessibilityLevel(this.page === 'settings' ? 'auto' : 'no-hide-descendants')
      if (this.renameId) {
        Stack() {
          Row().width('100%').height('100%').backgroundColor('#66121B2B')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .transition(fadeMotion())
            .onClick(() => this.renameId = '')
          Column({ space: 12 }) {
            Text(this.t('重命名对话', 'Rename conversation')).fontSize(18).fontWeight(FontWeight.Bold)
              .fontColor(this.palette.ink)
            TextInput({ text: this.renameText }).id('rename-conversation').maxLength(80).height(45)
              .fontColor(this.palette.ink).backgroundColor(this.palette.subtle)
              .onChange((value: string) => this.renameText = value)
            Row({ space: 8 }) {
              Button(this.t('取消', 'Cancel')).backgroundColor(this.palette.subtle).fontColor(this.palette.ink)
                .onClick(() => this.renameId = '')
              Button(this.t('保存', 'Save')).backgroundColor(this.palette.accent).fontColor(this.palette.accentText)
                .enabled(Boolean(this.renameText.trim())).onClick(() => this.saveRename())
            }
          }.padding(18).borderRadius(17).width('86%').constraintSize({ maxWidth: 410 })
          .backgroundColor(this.palette.surface).transition(panelMotion())
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(this.palette.background)
    .onAreaChange((_old: Area, area: Area) => {
      this.viewportWidth = Number(area.width);
      this.viewportHeight = Number(area.height);
      this.wide = this.viewportWidth >= 768;
    })
  }
}
