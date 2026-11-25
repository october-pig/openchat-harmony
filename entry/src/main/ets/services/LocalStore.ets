import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { asset } from '@kit.AssetStoreKit';
import { ChatMessage, Session, Workspace, defaults, restoreMessage } from '../model/Chat';
import { exportHistory, importHistory } from './History';
import { HISTORY_LIMIT } from './HistoryZip';

const KEY_ALIAS = 'deepseek-api-key';

interface NativeArchive {
  format: string;
  version: number;
  sessions: Session[];
}

export class LocalStore {
  private context: common.UIAbilityContext;
  private filename: string;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.filename = context.filesDir + '/chat-workspace.json';
  }

  load(): Workspace {
    if (!fileIo.accessSync(this.filename)) {
      return { version: 1, selected: '', sessions: [], settings: defaults() };
    }
    const data = JSON.parse(fileIo.readTextSync(this.filename)) as Workspace;
    data.sessions = restoreSessions(data.sessions);
    data.settings = data.settings ?? defaults();
    return data;
  }

  save(data: Workspace): void {
    const temporary = this.filename + '.tmp';
    writeText(temporary, JSON.stringify(data), true);
    fileIo.renameSync(temporary, this.filename);
  }

  async exportSessions(sessions: Session[]): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = ['deepseek_data-' + new Date().toISOString().slice(0, 10) + '.zip'];
    const locations = await new picker.DocumentViewPicker(this.context).save(options);
    if (!locations.length) {
      return false;
    }
    const archive = await exportHistory(sessions);
    writeBytes(locations[0], archive, false);
    return true;
  }

  async importSessions(): Promise<Session[] | undefined> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['聊天记录|.zip,.json'];
    const files = await new picker.DocumentViewPicker(this.context).select(options);
    if (!files.length) {
      return undefined;
    }
    const file = fileIo.openSync(files[0], fileIo.OpenMode.READ_ONLY);
    try {
      const byteLength = fileIo.statSync(file.fd).size;
      if (byteLength <= 0 || byteLength > HISTORY_LIMIT) {
        throw new Error('Archive size is invalid.');
      }
      const buffer = new ArrayBuffer(byteLength);
      if (fileIo.readSync(file.fd, buffer) !== byteLength) {
        throw new Error('Archive read was incomplete.');
      }
      if (byteLength >= 4 && new DataView(buffer).getUint32(0, true) === 0x04034b50) {
        return restoreSessions(await importHistory(buffer));
      }
      const archive = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer))) as NativeArchive;
      if (archive.format !== 'deepseek-harmonyos' || archive.version !== 1) {
        throw new Error('Unsupported archive format.');
      }
      return restoreSessions(archive.sessions);
    } finally {
      fileIo.closeSync(file);
    }
  }
}

function restoreSessions(sessions: Session[]): Session[] {
  if (!Array.isArray(sessions)) {
    throw new Error('Invalid conversations.');
  }
  const sessionIds = new Set<string>();
  for (const session of sessions) {
    if (!session || typeof session.id !== 'string' || sessionIds.has(session.id) ||
      typeof session.updated !== 'number' || !Number.isFinite(new Date(session.updated).getTime()) ||
      typeof session.title !== 'string' || typeof session.head !== 'string' || !Array.isArray(session.messages)) {
      throw new Error('Invalid conversation.');
    }
    sessionIds.add(session.id);
    const ids = new Map<string, string>();
    for (const message of session.messages) {
      if (!message || !message.id || ids.has(message.id) || typeof message.text !== 'string' ||
        (message.role !== 'user' && message.role !== 'assistant') ||
        (message.parent ? !ids.has(message.parent) || ids.get(message.parent) === message.role :
          message.role !== 'user') ||
        !validMessageLists(message)) {
        throw new Error('Invalid chat message.');
      }
      ids.set(message.id, message.role);
    }
    if (session.head && !ids.has(session.head)) {
      throw new Error('Invalid active branch.');
    }
    session.messages = session.messages.map((message: ChatMessage) => restoreMessage(message));
  }
  return sessions;
}

function validMessageLists(message: ChatMessage): boolean {
  return Array.isArray(message.files) && message.files.every((file) =>
    Boolean(file) && typeof file.id === 'string' && typeof file.name === 'string' && typeof file.image === 'boolean') &&
    Array.isArray(message.sources) && message.sources.every((source) =>
      Boolean(source) && typeof source.url === 'string' &&
      (source.title === undefined || source.title === null || typeof source.title === 'string')) &&
    Array.isArray(message.blocks) && message.blocks.every((block) => Boolean(block) && typeof block.type === 'string');
}

function writeText(path: string, content: string, create: boolean): void {
  const bytes = new util.TextEncoder().encodeInto(content);
  writeBytes(path, bytes.buffer as ArrayBuffer, create);
}

function writeBytes(path: string, bytes: ArrayBuffer, create: boolean): void {
  const mode = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC | (create ? fileIo.OpenMode.CREATE : 0);
  const file = fileIo.openSync(path, mode);
  try {
    if (fileIo.writeSync(file.fd, bytes) !== bytes.byteLength) {
      throw new Error('The file was only partially written.');
    }
    fileIo.fsyncSync(file.fd);
  } finally {
    fileIo.closeSync(file);
  }
}

function alias(): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(KEY_ALIAS));
  return query;
}

export async function readKey(): Promise<string> {
  const query = alias();
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  try {
    const result = await asset.query(query);
    const secret = result[0]?.get(asset.Tag.SECRET);
    return secret instanceof Uint8Array ? util.TextDecoder.create('utf-8').decodeToString(secret) : '';
  } catch (err) {
    if ((err as BusinessError).code === asset.ErrorCode.NOT_FOUND) {
      return '';
    }
    throw new Error('Could not read the API key.');
  }
}

export async function saveKey(key: string): Promise<void> {
  const query = alias();
  if (!key) {
    try {
      await asset.remove(query);
    } catch (err) {
      if ((err as BusinessError).code !== asset.ErrorCode.NOT_FOUND) {
        throw new Error('Could not remove the API key.');
      }
    }
    return;
  }
  query.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(key));
  query.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  await asset.add(query);
}
