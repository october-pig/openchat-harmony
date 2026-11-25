import { util } from '@kit.ArkTS';

export interface Attachment {
  id: string;
  name: string;
  image: boolean;
}

export interface Source {
  url: string;
  title?: string;
  cited_text?: string;
}

export interface ToolInput {
  action?: string;
  url?: string;
  query?: string;
  queries?: string[];
}

export interface ResultPage {
  url?: string;
  content?: WebContent;
}

export interface WebContent {
  title?: string;
}

export interface ReplyBlock {
  type: string;
  text?: string;
  thinking?: string;
  signature?: string;
  citations?: Source[];
  id?: string;
  name?: string;
  kind?: string;
  input?: ToolInput;
  tool_use_id?: string;
  content?: Source[] | ResultPage;
}

@Observed
export class ChatMessage {
  id: string = util.generateRandomUUID();
  parent: string = '';
  role: string = 'user';
  text: string = '';
  reasoning: string = '';
  files: Attachment[] = [];
  sources: Source[] = [];
  blocks: ReplyBlock[] = [];
  thinking: boolean = false;
  search: boolean = false;
  status: string = 'done';
  stopReason: string = '';
  error: string = '';
  activity: string = '';
}

export interface Session {
  id: string;
  title: string;
  customTitle: boolean;
  updated: number;
  head: string;
  messages: ChatMessage[];
}

export interface Settings {
  theme: string;
  language: string;
  location: string;
  voice?: string;
}

export interface Workspace {
  version: number;
  selected: string;
  sessions: Session[];
  settings: Settings;
}

export function defaults(): Settings {
  return { theme: 'system', language: 'system', location: '' };
}

export function newSession(): Session {
  return { id: util.generateRandomUUID(), title: '', customTitle: false, updated: Date.now(), head: '', messages: [] };
}

export function pathTo(session: Session, head: string): ChatMessage[] {
  const byId = new Map<string, ChatMessage>();
  session.messages.forEach((message: ChatMessage) => byId.set(message.id, message));
  const path: ChatMessage[] = [];
  const visited = new Set<string>();
  let id = head;
  while (id && !visited.has(id)) {
    const message = byId.get(id);
    if (!message) {
      break;
    }
    visited.add(id);
    path.push(message);
    id = message.parent;
  }
  return path.reverse();
}

export function canContinue(message: ChatMessage): boolean {
  return Boolean(message.text) && message.stopReason !== 'refusal' &&
    !message.blocks.some((block: ReplyBlock) => block.type.includes('tool')) &&
    (message.status === 'stopped' || (message.status === 'done' && message.stopReason === 'max_tokens'));
}

export function restoreMessage(value: ChatMessage): ChatMessage {
  const message = new ChatMessage();
  message.id = value.id;
  message.parent = value.parent;
  message.role = value.role;
  message.text = value.text;
  message.reasoning = value.reasoning ?? '';
  message.files = value.files ?? [];
  message.sources = value.sources ?? [];
  message.blocks = value.blocks ?? [];
  message.thinking = value.thinking ?? false;
  message.search = value.search ?? false;
  message.status = value.status === 'streaming' ? 'stopped' : value.status;
  message.stopReason = value.stopReason ?? '';
  message.error = value.error ?? '';
  return message;
}
