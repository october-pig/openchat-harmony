import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';

const LOCAL = 0x04034b50;
const DIRECTORY = 0x02014b50;
const END = 0x06054b50;
const UTF8 = 0x0800;
const ENTRY_LIMIT = 10000;
export const HISTORY_LIMIT = 64 * 1024 * 1024;

interface EncodedEntry {
  name: Uint8Array;
  data: Uint8Array;
  offset: number;
  checksum: number;
}

function view(buffer: Uint8Array): DataView {
  return new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
}

function invalid(): Error {
  return new Error('Invalid or unsupported ZIP archive.');
}

export async function encodeZip(entries: Map<string, string>): Promise<ArrayBuffer> {
  if (entries.size > ENTRY_LIMIT) {
    throw invalid();
  }
  const encoder = new util.TextEncoder();
  const checksum = zlib.createChecksumSync();
  const prepared: EncodedEntry[] = [];
  let localSize = 0;
  let directorySize = 0;
  for (const name of entries.keys()) {
    const nameBytes = encoder.encodeInto(name);
    const data = encoder.encodeInto(entries.get(name) ?? '');
    const crc = await checksum.crc32(0, data.buffer);
    prepared.push({ name: nameBytes, data: data, checksum: crc, offset: localSize });
    localSize += 30 + nameBytes.length + data.length;
    directorySize += 46 + nameBytes.length;
  }
  if (localSize + directorySize + 22 > HISTORY_LIMIT) {
    throw invalid();
  }
  const archive = new Uint8Array(localSize + directorySize + 22);
  const fields = view(archive);
  let offset = localSize;
  for (const item of prepared) {
    const index = item.offset;
    fields.setUint32(index, LOCAL, true);
    fields.setUint16(index + 4, 20, true);
    fields.setUint16(index + 6, UTF8, true);
    fields.setUint16(index + 12, 33, true);
    fields.setUint32(index + 14, item.checksum, true);
    fields.setUint32(index + 18, item.data.length, true);
    fields.setUint32(index + 22, item.data.length, true);
    fields.setUint16(index + 26, item.name.length, true);
    archive.set(item.name, index + 30);
    archive.set(item.data, index + 30 + item.name.length);

    fields.setUint32(offset, DIRECTORY, true);
    fields.setUint16(offset + 4, 20, true);
    fields.setUint16(offset + 6, 20, true);
    fields.setUint16(offset + 8, UTF8, true);
    fields.setUint16(offset + 14, 33, true);
    fields.setUint32(offset + 16, item.checksum, true);
    fields.setUint32(offset + 20, item.data.length, true);
    fields.setUint32(offset + 24, item.data.length, true);
    fields.setUint16(offset + 28, item.name.length, true);
    fields.setUint32(offset + 42, index, true);
    archive.set(item.name, offset + 46);
    offset += 46 + item.name.length;
  }

  fields.setUint32(offset, END, true);
  fields.setUint16(offset + 8, prepared.length, true);
  fields.setUint16(offset + 10, prepared.length, true);
  fields.setUint32(offset + 12, directorySize, true);
  fields.setUint32(offset + 16, localSize, true);
  return archive.buffer;
}

async function inflate(compressed: ArrayBuffer, size: number): Promise<ArrayBuffer> {
  const decoder = zlib.createZipSync();
  const output = new ArrayBuffer(size + 1);
  const stream: zlib.ZStream = {
    nextIn: compressed, availableIn: compressed.byteLength, nextOut: output, availableOut: output.byteLength
  };
  if (await decoder.inflateInit2(stream, -15) !== zlib.ReturnStatus.OK) {
    throw invalid();
  }
  try {
    const status = await decoder.inflate(stream, zlib.CompressFlushMode.FINISH);
    const result = await decoder.getZStream();
    if (status !== zlib.ReturnStatus.STREAM_END || result.totalOut !== size ||
      result.totalIn !== compressed.byteLength) {
      throw invalid();
    }
    return output.slice(0, size);
  } finally {
    await decoder.inflateEnd(stream);
  }
}

export async function decodeZip(archive: ArrayBuffer): Promise<Map<string, string>> {
  const fields = new DataView(archive);
  const bytes = new Uint8Array(archive);
  const decoder = util.TextDecoder.create('utf-8', { fatal: true });
  const checksum = zlib.createChecksumSync();
  const entries = new Map<string, string>();
  let end = bytes.length - 22;
  while (end >= Math.max(0, bytes.length - 65557) &&
    (fields.getUint32(end, true) !== END || end + 22 + fields.getUint16(end + 20, true) !== bytes.length)) {
    end--;
  }
  if (end < Math.max(0, bytes.length - 65557) || fields.getUint16(end + 4, true) ||
    fields.getUint16(end + 6, true) || fields.getUint16(end + 8, true) !== fields.getUint16(end + 10, true)) {
    throw invalid();
  }
  const count = fields.getUint16(end + 10, true);
  const first = fields.getUint32(end + 16, true);
  if (first + fields.getUint32(end + 12, true) !== end || count > ENTRY_LIMIT) {
    throw invalid();
  }
  let offset = first;
  let decodedSize = 0;
  for (let i = 0; i < count; i++) {
    if (offset + 46 > end || fields.getUint32(offset, true) !== DIRECTORY) {
      throw invalid();
    }
    const flags = fields.getUint16(offset + 8, true);
    const method = fields.getUint16(offset + 10, true);
    const crc = fields.getUint32(offset + 16, true);
    const packedSize = fields.getUint32(offset + 20, true);
    const itemSize = fields.getUint32(offset + 24, true);
    const nameSize = fields.getUint16(offset + 28, true);
    const local = fields.getUint32(offset + 42, true);
    const next = offset + 46 + nameSize + fields.getUint16(offset + 30, true) + fields.getUint16(offset + 32, true);
    if (next > end || !nameSize || (flags & 1) || local + 30 > first || fields.getUint32(local, true) !== LOCAL) {
      throw invalid();
    }
    const name = decoder.decodeToString(bytes.subarray(offset + 46, offset + 46 + nameSize));
    offset = next;
    // Only decode known text entries. Attachment paths never access the filesystem.
    if (name !== 'manifest.json' && name !== 'chat_session_index.json' && !/^chat_sessions\/[\w-]+\.json$/.test(name)) {
      continue;
    }
    const data = local + 30 + fields.getUint16(local + 26, true) + fields.getUint16(local + 28, true);
    decodedSize += itemSize;
    if (data + packedSize > first || decodedSize > HISTORY_LIMIT || entries.has(name) || (method !== 0 && method !== 8)) {
      throw invalid();
    }
    const packed = archive.slice(data, data + packedSize);
    const contents = method === 8 ? await inflate(packed, itemSize) : packed;
    if (contents.byteLength !== itemSize || await checksum.crc32(0, contents) !== crc) {
      throw invalid();
    }
    entries.set(name, decoder.decodeToString(new Uint8Array(contents)));
  }
  if (offset !== end) {
    throw invalid();
  }
  return entries;
}
