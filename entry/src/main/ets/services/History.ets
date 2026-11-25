import { util } from '@kit.ArkTS';
import { Attachment, ChatMessage, Session, Source } from '../model/Chat';
import { encodeZip, decodeZip } from './HistoryZip';

interface Manifest {
  export_format_version: number;
}

interface WireSession {
  id: string;
  title: string | null;
  pinned: boolean;
  current_message_id: number;
  inserted_at: string;
  updated_at: string;
  messages: WireMessage[];
}

interface IndexItem {
  id: string;
  title: string | null;
  pinned: boolean;
  inserted_at: string;
  updated_at: string;
  message_count: number;
}

interface WireMessage {
  id: number;
  parent_id: number | null;
  role: string;
  status: string;
  thinking_enabled: boolean;
  search_enabled: boolean;
  accumulated_token_usage: number;
  inserted_at: string;
  fragments: Fragment[];
}

interface Fragment {
  type: string;
  content?: string;
  elapsed_secs?: number | null;
  files?: WireFile[];
  queries?: string[];
  results?: WireSource[];
  status?: string;
}

interface WireSource {
  url: string;
  title: string;
  snippet: string;
  published_at: string | null;
  site_name: string | null;
}

interface WireFile {
  id: string;
  file_name: string;
  file_size: number;
  token_usage: number | null;
  inserted_at: string;
  export_path: string | null;
  is_image: boolean;
  width: number | null;
  height: number | null;
}

function fragments(message: ChatMessage, time: string): Fragment[] {
  const result: Fragment[] = [];
  if (message.role === 'user') {
    if (message.files.length) {
      const files = message.files.map((file: Attachment): WireFile => {
        return { id: util.generateRandomUUID(), file_name: file.name, file_size: 0, token_usage: null,
          inserted_at: time, export_path: null, is_image: file.image, width: null, height: null };
      });
      result.push({ type: 'FILE', files: files });
    }
    if (message.text) {
      result.push({ type: 'REQUEST', content: message.text });
    }
  } else {
    if (message.reasoning) {
      result.push({ type: 'THINK', content: message.reasoning, elapsed_secs: null });
    }
    if (message.sources.length) {
      const sources = message.sources.map((source: Source): WireSource => {
        return { url: source.url, title: source.title || source.url, snippet: '', published_at: null, site_name: null };
      });
      result.push({ type: 'TOOL_SEARCH', queries: [], results: sources, status: 'FINISHED' });
    }
    if (message.text) {
      result.push({ type: 'RESPONSE', content: message.text });
    }
    if (message.error) {
      result.push({ type: 'TEMPLATE_RESPONSE', content: message.error });
    }
  }
  return result;
}

export async function exportHistory(sessions: Session[]): Promise<ArrayBuffer> {
  const entries = new Map<string, string>();
  const index: IndexItem[] = [];
  const manifest: Manifest = { export_format_version: 3 };
  entries.set('manifest.json', JSON.stringify(manifest));
  for (const session of sessions) {
    const updated = new Date(session.updated).toISOString();
    const lookup = new Map<string, number>();
    const messages: WireMessage[] = [];
    for (const message of session.messages) {
      const id = messages.length + 1;
      lookup.set(message.id, id);
      const status = message.stopReason === 'refusal' ? 'CONTENT_FILTER' : message.status === 'error' ? 'FAILED' :
        message.status === 'stopped' || message.status === 'streaming' ? 'INCOMPLETE' : 'FINISHED';
      messages.push({
        id: id, parent_id: lookup.get(message.parent) ?? null, role: message.role.toUpperCase(), status: status,
        thinking_enabled: message.thinking, search_enabled: message.search, accumulated_token_usage: 0,
        inserted_at: updated, fragments: fragments(message, updated)
      });
    }
    const record: WireSession = {
      id: session.id, title: session.title, pinned: false, current_message_id: lookup.get(session.head) ?? 0,
      inserted_at: updated, updated_at: updated, messages: messages
    };
    entries.set('chat_sessions/' + session.id + '.json', JSON.stringify(record));
    index.push({
      id: session.id, title: session.title, pinned: false, inserted_at: updated, updated_at: updated,
      message_count: messages.length
    });
  }
  entries.set('chat_session_index.json', JSON.stringify(index));
  return encodeZip(entries);
}

function localMessage(source: WireMessage): ChatMessage {
  const message = new ChatMessage();
  message.id = String(source.id);
  message.parent = source.parent_id === null ? '' : String(source.parent_id);
  message.role = source.role === 'USER' ? 'user' : 'assistant';
  message.thinking = Boolean(source.thinking_enabled);
  message.search = Boolean(source.search_enabled);
  message.status = source.status === 'INCOMPLETE' || source.status === 'WIP' ? 'stopped' :
    ['FAILED', 'CONTEXT_LENGTH_EXCEEDED', 'TIMEOUT'].includes(source.status) ? 'error' : 'done';
  message.stopReason = source.status === 'CONTENT_FILTER' ? 'refusal' : '';
  for (const fragment of source.fragments) {
    if (!fragment) {
      continue;
    }
    if ((fragment.type === 'REQUEST' || fragment.type === 'RESPONSE') && typeof fragment.content === 'string' &&
      !message.stopReason) {
      message.text += (message.text ? '\n\n' : '') + fragment.content;
    } else if (fragment.type === 'THINK' && typeof fragment.content === 'string' && !message.stopReason) {
      message.reasoning += fragment.content;
    } else if (fragment.type === 'TEMPLATE_RESPONSE' && typeof fragment.content === 'string') {
      message.error = fragment.content;
    } else if (fragment.type === 'FILE' && Array.isArray(fragment.files) && message.role === 'user') {
      for (const file of fragment.files) {
        if (file && typeof file.file_name === 'string') {
          message.files.push({ id: '', name: file.file_name, image: Boolean(file.is_image) });
        }
      }
    } else if (fragment.type === 'TOOL_SEARCH' && Array.isArray(fragment.results)) {
      for (const result of fragment.results) {
        if (result && typeof result.url === 'string' && /^https?:\/\//i.test(result.url)) {
          message.sources.push({ url: result.url, title: typeof result.title === 'string' ? result.title : '' });
        }
      }
    }
  }
  return message;
}

export async function importHistory(buffer: ArrayBuffer): Promise<Session[]> {
  const entries = await decodeZip(buffer);
  const manifest = JSON.parse(entries.get('manifest.json') ?? '{}') as Manifest;
  const index = JSON.parse(entries.get('chat_session_index.json') ?? 'null') as IndexItem[];
  if (manifest.export_format_version !== 3 || !Array.isArray(index) || entries.size !== index.length + 2) {
    throw new Error('Invalid DeepSeek history index.');
  }
  const seen = new Set<string>();
  const sessions: Session[] = [];
  for (const item of index) {
    if (!item?.id || !/^[\w-]+$/.test(item.id) || seen.has(item.id)) {
      throw new Error('Invalid DeepSeek history id.');
    }
    seen.add(item.id);
    const session = JSON.parse(entries.get('chat_sessions/' + item.id + '.json') ?? 'null') as WireSession;
    const updated = Date.parse(session?.updated_at);
    if (!session || session.id !== item.id || !Number.isFinite(updated) ||
      !Array.isArray(session.messages) || item.message_count !== session.messages.length) {
      throw new Error('Invalid DeepSeek conversation.');
    }
    const messages: ChatMessage[] = [];
    const sorted = session.messages.slice().sort((left: WireMessage, right: WireMessage) => left.id - right.id);
    for (const message of sorted) {
      if (!message || !Number.isInteger(message.id) || message.id < 1 ||
        (message.role !== 'USER' && message.role !== 'ASSISTANT') || !Array.isArray(message.fragments)) {
        throw new Error('Invalid DeepSeek chat message.');
      }
      messages.push(localMessage(message));
    }
    sessions.push({ id: session.id, title: typeof session.title === 'string' ? session.title : '',
      customTitle: true, updated: updated, head: session.current_message_id ? String(session.current_message_id) : '',
      messages: messages });
  }
  return sessions.sort((left: Session, right: Session) => right.updated - left.updated);
}
