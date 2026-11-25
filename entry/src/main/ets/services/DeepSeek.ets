import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Attachment, ChatMessage, ReplyBlock, ResultPage, Source } from '../model/Chat';

export const API_ORIGIN = 'https://api.deepseek.com';
const MESSAGES = API_ORIGIN + '/anthropic/v1';
const FILES_BETA = 'files-api-2025-04-14';

interface FileRef {
  type: string;
  file_id: string;
}

interface ApiBlock extends ReplyBlock {
  source?: FileRef;
}

interface ApiMessage {
  role: string;
  content: string | ApiBlock[];
}

interface ApiTool {
  type: string;
  name: string;
}

interface ApiThinking {
  type: string;
}

interface ApiSafety {
  level: string;
}

interface ApiTitle {
  enabled: boolean;
}

interface ApiRequest {
  model: string;
  system: string;
  stream: boolean;
  max_tokens: number;
  messages: ApiMessage[];
  thinking: ApiThinking;
  tools: ApiTool[];
  safety_check?: ApiSafety;
  title?: ApiTitle;
}

interface ApiError {
  message?: string;
}

interface ApiDelta {
  type?: string;
  text?: string;
  thinking?: string;
  signature?: string;
  citation?: Source;
  stop_reason?: string;
  title?: string;
}

interface ApiEvent {
  type: string;
  index?: number;
  content_block?: ReplyBlock;
  delta?: ApiDelta;
  error?: ApiError;
  message?: string;
}

interface ApiFile {
  id?: string;
  filename?: string;
}

export interface ReplyOptions {
  generateTitle: boolean;
  prefix: boolean;
  reminder: string;
}

export class HttpFailure extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export class Transfer {
  private request?: http.HttpRequest;
  private onAbort?: () => void;
  cancelled: boolean = false;

  attach(request: http.HttpRequest, onAbort?: () => void): void {
    this.request = request;
    this.onAbort = onAbort;
  }

  close(): void {
    this.request?.destroy();
    this.request = undefined;
    this.onAbort = undefined;
  }

  cancel(): void {
    this.cancelled = true;
    const abort = this.onAbort;
    this.close();
    abort?.();
  }
}

export class EventStream {
  private decoder = util.TextDecoder.create('utf-8');
  private buffer: string = '';
  private lines: string[] = [];
  private consume: (data: string) => void;

  constructor(consume: (data: string) => void) {
    this.consume = consume;
  }

  feed(data: ArrayBuffer): string {
    const decoded = this.decoder.decodeToString(new Uint8Array(data), { stream: true });
    this.buffer += decoded;
    let start = 0;
    for (let index = 0; index < this.buffer.length; index++) {
      const char = this.buffer.charAt(index);
      if (char !== '\n' && char !== '\r') {
        continue;
      }
      if (char === '\r' && index + 1 === this.buffer.length) {
        break;
      }
      this.line(this.buffer.slice(start, index));
      if (char === '\r' && this.buffer.charAt(index + 1) === '\n') {
        index++;
      }
      start = index + 1;
    }
    this.buffer = this.buffer.slice(start);
    return decoded;
  }

  private line(line: string): void {
    if (!line && this.lines.length) {
      this.consume(this.lines.join('\n'));
      this.lines = [];
    } else if (line.startsWith('data:')) {
      const data = line.slice(5);
      this.lines.push(data.startsWith(' ') ? data.slice(1) : data);
    } else if (line === 'data') {
      this.lines.push('');
    }
  }
}

function requestUser(message: ChatMessage): ApiMessage {
  const files = message.files.filter((file: Attachment): boolean => Boolean(file.id));
  if (!files.length) {
    return { role: 'user', content: message.text };
  }
  const blocks: ApiBlock[] = files.map((file: Attachment): ApiBlock => {
    return { type: file.image ? 'image' : 'document', source: { type: 'file', file_id: file.id } };
  });
  if (message.text) {
    blocks.push({ type: 'text', text: message.text });
  }
  return { role: 'user', content: blocks };
}

function requestAssistant(message: ChatMessage, prefix: boolean): ApiMessage {
  const blocks: ApiBlock[] = [];
  for (const block of message.blocks) {
    if (block.type === 'text' && block.text) {
      blocks.push({ type: 'text', text: block.text });
    } else if (prefix && message.thinking && block.type === 'thinking' && block.thinking && block.signature) {
      blocks.push({ type: 'thinking', thinking: block.thinking, signature: block.signature });
    } else if (block.type === 'server_tool_use' && block.kind === 'read_link' && message.blocks.some(
      (result: ReplyBlock) => result.type === 'web_fetch_tool_result' && result.tool_use_id === block.id &&
        Boolean(result.signature))) {
      blocks.push({ type: block.type, id: block.id, name: block.name, input: block.input, kind: block.kind });
    } else if (block.type === 'web_fetch_tool_result' && block.kind === 'read_link' && block.signature) {
      blocks.push({ type: block.type, tool_use_id: block.tool_use_id, kind: block.kind,
        content: block.content, signature: block.signature });
    }
  }
  if (!blocks.some((block: ApiBlock) => block.type === 'text')) {
    blocks.push({ type: 'text', text: message.text });
  }
  return { role: 'assistant', content: blocks };
}

function requestBody(path: ChatMessage[], reply: ChatMessage, options: ReplyOptions): ApiRequest {
  const messages: ApiMessage[] = [];
  let hasDocuments = false;
  for (let i = 0; i + 1 < path.length; i += 2) {
    const question = path[i];
    const answer = path[i + 1];
    if ((!question.text && !question.files.some((file: Attachment) => Boolean(file.id))) ||
      !answer.text || answer.stopReason === 'refusal' || !['done', 'stopped'].includes(answer.status)) {
      continue;
    }
    messages.push(requestUser(question), requestAssistant(answer, false));
    hasDocuments ||= question.files.some((file: Attachment) => Boolean(file.id) && !file.image);
  }
  const question = path[path.length - 1];
  hasDocuments ||= question.files.some((file: Attachment) => Boolean(file.id) && !file.image);
  if (options.reminder && !hasDocuments) {
    messages.push({ role: 'latest_reminder', content: options.reminder });
  }
  messages.push(requestUser(question));
  if (options.prefix) {
    messages.push(requestAssistant(reply, true));
  }
  const tools: ApiTool[] = [];
  if (!hasDocuments && !options.prefix) {
    tools.push({ type: 'deepseek_read_url', name: 'deepseek_read_url' });
    if (reply.search) {
      tools.push({ type: 'deepseek_web_search', name: 'deepseek_web_search' });
    }
  }
  return {
    model: 'deepseek-flash',
    system: '该助手为DeepSeek，由深度求索公司创造。',
    stream: true,
    max_tokens: 8192,
    messages: messages,
    thinking: { type: reply.thinking ? 'enabled' : 'disabled' },
    tools: tools,
    safety_check: hasDocuments || options.prefix ? undefined : { level: 'high' },
    title: !hasDocuments && options.generateTitle ? { enabled: true } : undefined
  };
}

function failure(status: number, raw: string): HttpFailure {
  let detail = '';
  try {
    const event = JSON.parse(raw) as ApiEvent;
    detail = event.error?.message ?? event.message ?? '';
  } catch {
    // The server may use a non-JSON error response.
  }
  return new HttpFailure(status, detail);
}

function addSource(reply: ChatMessage, source?: Source): void {
  if (source?.url && /^https?:\/\//i.test(source.url) &&
    !reply.sources.some((existing: Source) => existing.url === source.url)) {
    reply.sources = [...reply.sources, source];
  }
}

class ReplyStream {
  private reply: ChatMessage;
  private indexes = new Map<number, ReplyBlock>();
  title: string = '';
  finished: boolean = false;

  constructor(reply: ChatMessage) {
    this.reply = reply;
  }

  consume(raw: string): void {
    let event: ApiEvent;
    try {
      event = JSON.parse(raw) as ApiEvent;
    } catch {
      return;
    }
    if (this.finished) {
      return;
    }
    if (event.error) {
      throw new HttpFailure(0, event.error.message ?? '');
    }
    if (event.type === 'message_stop') {
      this.finished = true;
    } else if (event.type === 'message_delta' && event.delta) {
      this.reply.stopReason = event.delta.stop_reason ?? '';
      this.title = event.delta.title ?? this.title;
      if (this.reply.stopReason === 'refusal') {
        this.reply.text = '';
        this.reply.reasoning = '';
        this.reply.blocks = [];
        this.reply.sources = [];
      }
    } else if (event.type === 'content_block_start' && event.index !== undefined && event.content_block) {
      this.startBlock(event.index, event.content_block);
    } else if (event.type === 'content_block_delta' && event.index !== undefined && event.delta) {
      this.addDelta(event.index, event.delta);
    }
  }

  private startBlock(index: number, block: ReplyBlock): void {
    this.indexes.set(index, block);
    this.reply.blocks.push(block);
    if (block.type === 'text') {
      this.reply.activity = '';
      this.reply.text += block.text ?? '';
      block.citations?.forEach((source: Source) => addSource(this.reply, source));
    } else if (block.type === 'thinking') {
      this.reply.reasoning += block.thinking ?? '';
    } else if (block.type === 'server_tool_use') {
      this.reply.activity = block.kind === 'read_link' ? 'reading' : 'searching';
    } else if (block.type === 'web_search_tool_result' && Array.isArray(block.content)) {
      (block.content as Source[]).forEach((source: Source) => addSource(this.reply, source));
    } else if (block.type === 'web_fetch_tool_result' && block.content) {
      const result = block.content as ResultPage;
      if (result.url) {
        addSource(this.reply, { url: result.url, title: result.content?.title });
      }
    }
  }

  private addDelta(index: number, delta: ApiDelta): void {
    const block = this.indexes.get(index);
    if (!block) {
      return;
    }
    if (delta.type === 'text_delta' && delta.text) {
      block.text = (block.text ?? '') + delta.text;
      this.reply.text += delta.text;
    } else if (delta.type === 'thinking_delta' && delta.thinking) {
      block.thinking = (block.thinking ?? '') + delta.thinking;
      this.reply.reasoning += delta.thinking;
    } else if (delta.type === 'signature_delta' && delta.signature) {
      block.signature = (block.signature ?? '') + delta.signature;
    } else if (delta.type === 'citations_delta' && delta.citation) {
      addSource(this.reply, delta.citation);
    }
  }
}

export async function streamReply(key: string, path: ChatMessage[], reply: ChatMessage,
  options: ReplyOptions, transfer: Transfer): Promise<string> {
  const body = requestBody(path, reply, options);
  const headers: Record<string, string> = {
    'x-api-key': key,
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream'
  };
  if (path.some((message: ChatMessage) => message.files.some((file: Attachment) => Boolean(file.id)))) {
    headers['anthropic-beta'] = FILES_BETA;
  }
  const stream = new ReplyStream(reply);
  let eventFailure: Error | undefined;
  const sse = new EventStream((data: string) => {
    if (!eventFailure) {
      try {
        stream.consume(data);
      } catch (err) {
        eventFailure = err as Error;
      }
    }
  });
  const request = http.createHttp();
  try {
    await new Promise<void>((resolve, reject) => {
      let raw = '';
      let status: number | undefined;
      let ended = false;
      const finish = (): void => {
        if (!ended || status === undefined) {
          return;
        }
        if (status < 200 || status >= 300) {
          reject(failure(status, raw));
        } else if (eventFailure) {
          reject(eventFailure);
        } else if (!stream.finished) {
          reject(new HttpFailure(0, ''));
        } else {
          resolve();
        }
      };
      transfer.attach(request, () => reject(new Error('Cancelled')));
      request.on('dataReceive', (bytes: ArrayBuffer) => {
        const chunk = sse.feed(bytes);
        if (raw.length < 8192 && !stream.finished) {
          raw += chunk.slice(0, 8192 - raw.length);
        }
      });
      request.on('dataEnd', () => {
        ended = true;
        finish();
      });
      request.requestInStream(MESSAGES + '/messages', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        usingCache: false,
        connectTimeout: 20000,
        readTimeout: 180000
      }).then((code: number) => {
        status = code;
        finish();
      }).catch(() => reject(new HttpFailure(0, '')));
    });
    return stream.title;
  } finally {
    transfer.close();
  }
}

export async function verifyKey(key: string): Promise<void> {
  const request = http.createHttp();
  try {
    const response = await request.request(API_ORIGIN + '/models', {
      method: http.RequestMethod.GET,
      header: { 'Authorization': 'Bearer ' + key },
      usingCache: false,
      connectTimeout: 15000,
      readTimeout: 15000
    });
    if (response.responseCode !== 200) {
      throw failure(response.responseCode, String(response.result));
    }
  } finally {
    request.destroy();
  }
}

export async function uploadFile(key: string, name: string, mime: string, bytes: ArrayBuffer,
  purpose: string): Promise<Attachment> {
  const request = http.createHttp();
  try {
    const parts: http.MultiFormData[] = [];
    if (purpose) {
      parts.push({ name: 'purpose', contentType: 'text/plain', data: purpose });
    }
    parts.push({ name: 'file', contentType: mime, remoteFileName: name, data: bytes });
    const response = await request.request(MESSAGES + '/files', {
      method: http.RequestMethod.POST,
      header: { 'x-api-key': key, 'anthropic-beta': FILES_BETA, 'Content-Type': 'multipart/form-data' },
      usingCache: false,
      readTimeout: 180000,
      expectDataType: http.HttpDataType.STRING,
      multiFormDataList: parts
    });
    const raw = String(response.result);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw failure(response.responseCode, raw);
    }
    const file = JSON.parse(raw) as ApiFile;
    if (!file.id) {
      throw new Error('Missing attachment id.');
    }
    return { id: file.id, name: name, image: mime.startsWith('image/') };
  } finally {
    request.destroy();
  }
}
