import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { audio } from '@kit.AudioKit';
import { http } from '@kit.NetworkKit';
import { Attachment } from '../model/Chat';
import { API_ORIGIN, HttpFailure, Transfer, uploadFile } from './DeepSeek';

const IMAGE_TYPES = new Map<string, string>([
  ['png', 'image/png'], ['jpg', 'image/jpeg'], ['jpeg', 'image/jpeg'], ['webp', 'image/webp'],
  ['bmp', 'image/bmp'], ['gif', 'image/gif'], ['tiff', 'image/tiff'], ['tif', 'image/tiff']
]);
const LAYOUT = ['pdf', 'doc', 'docx', 'ppt', 'pptx'];
const DATA = ['txt', 'md', 'csv', 'tsv', 'json', 'jsonl', 'xml', 'html', 'log', 'xlsx', 'xls', 'epub',
  'py', 'js', 'ts', 'ets', 'java', 'cpp', 'c', 'h', 'go', 'rs', 'css', 'yml', 'yaml', 'sql'];
const RATE = 24000;
const RECORD_LIMIT = 120 * RATE * 2;

export async function pickUploads(context: common.UIAbilityContext, key: string, limit: number,
  deliver: (attachment: Attachment) => void): Promise<void> {
  const options = new picker.DocumentSelectOptions();
  options.maxSelectNumber = limit;
  const selected = await new picker.DocumentViewPicker(context).select(options);
  for (const uri of selected) {
    const name = new fileUri.FileUri(uri).name;
    const extension = name.split('.').pop()?.toLowerCase() ?? '';
    const image = IMAGE_TYPES.get(extension);
    if (!image && !LAYOUT.includes(extension) && !DATA.includes(extension)) {
      throw new Error(name);
    }
    const purpose = image ? '' : LAYOUT.includes(extension) ? 'rich_layout_recognition' : 'user_data';
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let buffer: ArrayBuffer;
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (size <= 0 || size > (purpose === 'user_data' ? 32 : 64) * 1024 * 1024) {
        throw new Error(name);
      }
      buffer = new ArrayBuffer(size);
      if (await fileIo.read(file.fd, buffer) !== size) {
        throw new Error(name);
      }
    } finally {
      await fileIo.close(file);
    }
    const attachment = await uploadFile(key, name, image || 'application/octet-stream', buffer, purpose);
    deliver(attachment);
  }
}

function audioFormat(): audio.AudioStreamInfo {
  return {
    samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_24000,
    channels: audio.AudioChannel.CHANNEL_1,
    sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
    encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
  };
}

export class Recorder {
  private capturer?: audio.AudioCapturer;
  private chunks: ArrayBuffer[] = [];
  private size: number = 0;

  async start(context: common.UIAbilityContext): Promise<boolean> {
    const grant = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
    if (grant.authResults[0] !== 0) {
      return false;
    }
    const capturer = await audio.createAudioCapturer({
      streamInfo: audioFormat(),
      capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 }
    });
    this.capturer = capturer;
    capturer.on('readData', (chunk: ArrayBuffer) => {
      if (this.size + chunk.byteLength <= RECORD_LIMIT) {
        this.chunks.push(chunk.slice(0));
        this.size += chunk.byteLength;
      }
    });
    try {
      await capturer.start();
    } catch (err) {
      await this.release();
      throw new Error('Audio recording could not start.');
    }
    return true;
  }

  async release(): Promise<void> {
    const capturer = this.capturer;
    this.capturer = undefined;
    if (capturer) {
      try {
        if (capturer.state === audio.AudioState.STATE_RUNNING) {
          await capturer.stop();
        }
      } finally {
        await capturer.release();
      }
    }
  }

  async wav(): Promise<ArrayBuffer> {
    await this.release();
    const output = new ArrayBuffer(44 + this.size);
    const header = new DataView(output);
    header.setUint32(0, 0x52494646);
    header.setUint32(4, this.size + 36, true);
    header.setUint32(8, 0x57415645);
    header.setUint32(12, 0x666d7420);
    header.setUint32(16, 16, true);
    header.setUint16(20, 1, true);
    header.setUint16(22, 1, true);
    header.setUint32(24, RATE, true);
    header.setUint32(28, RATE * 2, true);
    header.setUint16(32, 2, true);
    header.setUint16(34, 16, true);
    header.setUint32(36, 0x64617461);
    header.setUint32(40, this.size, true);
    const bytes = new Uint8Array(output);
    let offset = 44;
    this.chunks.forEach((chunk: ArrayBuffer) => {
      bytes.set(new Uint8Array(chunk), offset);
      offset += chunk.byteLength;
    });
    this.chunks = [];
    return output;
  }
}

interface Transcript {
  text?: string;
}

export async function transcribe(key: string, wav: ArrayBuffer): Promise<string> {
  if (wav.byteLength <= 44) {
    return '';
  }
  const request = http.createHttp();
  try {
    const response = await request.request(API_ORIGIN + '/v1/tools/asr', {
      method: http.RequestMethod.POST,
      header: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'multipart/form-data' },
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      readTimeout: 90000,
      multiFormDataList: [{ name: 'file', contentType: 'audio/wav', remoteFileName: 'recording.wav', data: wav }]
    });
    if (response.responseCode !== 200) {
      throw new HttpFailure(response.responseCode, '');
    }
    return (JSON.parse(String(response.result)) as Transcript).text?.trim() ?? '';
  } finally {
    request.destroy();
  }
}

export class Reader {
  private transfer = new Transfer();
  private renderer?: audio.AudioRenderer;

  async play(key: string, text: string, voice: string): Promise<void> {
    const request = http.createHttp();
    this.transfer.attach(request);
    let pcm: ArrayBuffer;
    try {
      const response = await request.request(API_ORIGIN + '/v1/tools/tts', {
        method: http.RequestMethod.POST,
        header: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ text: text, voice_id: voice, format: 'pcm', filter_markdown: true }),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        maxLimit: 90 * 1024 * 1024,
        readTimeout: 180000
      });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer)) {
        throw new HttpFailure(response.responseCode, '');
      }
      pcm = response.result;
    } finally {
      this.transfer.close();
    }
    if (this.transfer.cancelled) {
      return;
    }
    const renderer = await audio.createAudioRenderer({
      streamInfo: audioFormat(),
      rendererInfo: { usage: audio.StreamUsage.STREAM_USAGE_MUSIC, rendererFlags: 0 }
    });
    this.renderer = renderer;
    try {
      if (this.transfer.cancelled) {
        return;
      }
      await renderer.start();
      let position = 0;
      while (!this.transfer.cancelled && position < pcm.byteLength) {
        const written = await renderer.write(pcm.slice(position, Math.min(position + 16384, pcm.byteLength)));
        if (written <= 0) {
          break;
        }
        position += written;
      }
      if (!this.transfer.cancelled) {
        await renderer.drain();
      }
    } finally {
      if (this.renderer === renderer) {
        this.renderer = undefined;
        await renderer.release();
      }
    }
  }

  async stop(): Promise<void> {
    this.transfer.cancel();
    if (this.renderer?.state === audio.AudioState.STATE_RUNNING) {
      await this.renderer.stop();
    }
  }
}
