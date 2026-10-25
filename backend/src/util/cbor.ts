// Minimal CBOR decoder for App Attest attestation and assertion objects.

export type CborValue =
  | number
  | bigint
  | string
  | boolean
  | null
  | undefined
  | Uint8Array
  | CborValue[]
  | Map<CborValue, CborValue>;

export function decodeCbor(bytes: Uint8Array): CborValue {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 0;

  const readLength = (info: number): number => {
    if (info < 24) return info;
    if (info === 24) return view.getUint8(offset++);
    if (info === 25) {
      const v = view.getUint16(offset);
      offset += 2;
      return v;
    }
    if (info === 26) {
      const v = view.getUint32(offset);
      offset += 4;
      return v;
    }
    if (info === 27) {
      const v = view.getBigUint64(offset);
      offset += 8;
      if (v > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("CBOR: length too large");
      return Number(v);
    }
    throw new Error("CBOR: indefinite lengths are not supported");
  };

  const read = (): CborValue => {
    if (offset >= bytes.length) throw new Error("CBOR: truncated");
    const initial = view.getUint8(offset++);
    const major = initial >> 5;
    const info = initial & 0x1f;
    switch (major) {
      case 0:
        return readLength(info);
      case 1:
        return -1 - readLength(info);
      case 2: {
        const len = readLength(info);
        if (offset + len > bytes.length) throw new Error("CBOR: truncated bytes");
        const out = bytes.slice(offset, offset + len);
        offset += len;
        return out;
      }
      case 3: {
        const len = readLength(info);
        if (offset + len > bytes.length) throw new Error("CBOR: truncated text");
        const out = new TextDecoder().decode(bytes.subarray(offset, offset + len));
        offset += len;
        return out;
      }
      case 4: {
        const len = readLength(info);
        const out: CborValue[] = [];
        for (let i = 0; i < len; i++) out.push(read());
        return out;
      }
      case 5: {
        const len = readLength(info);
        const out = new Map<CborValue, CborValue>();
        for (let i = 0; i < len; i++) {
          const key = read();
          out.set(key, read());
        }
        return out;
      }
      case 6:
        readLength(info);
        return read();
      case 7:
        if (info === 20) return false;
        if (info === 21) return true;
        if (info === 22) return null;
        if (info === 23) return undefined;
        throw new Error("CBOR: unsupported simple/float value");
      default:
        throw new Error("CBOR: unsupported major type");
    }
  };

  return read();
}

export function cborMapGet(value: CborValue, key: string): CborValue {
  if (!(value instanceof Map)) throw new Error("CBOR: expected map");
  return value.get(key);
}
