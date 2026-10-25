// Minimal DER reader: just enough ASN.1 to walk X.509 certificates and ECDSA signatures.

export interface DerNode {
  tag: number;
  /** Full encoding (header + content). */
  raw: Uint8Array;
  /** Content octets. */
  content: Uint8Array;
}

export function readDer(bytes: Uint8Array, offset = 0): { node: DerNode; next: number } {
  if (offset + 2 > bytes.length) throw new Error("DER: truncated header");
  const tag = bytes[offset];
  let length = bytes[offset + 1];
  let headerLength = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new Error("DER: unsupported length");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[offset + 2 + i];
    headerLength += count;
  }
  const end = offset + headerLength + length;
  if (end > bytes.length) throw new Error("DER: truncated content");
  return {
    node: {
      tag,
      raw: bytes.subarray(offset, end),
      content: bytes.subarray(offset + headerLength, end),
    },
    next: end,
  };
}

export function derChildren(node: DerNode): DerNode[] {
  const children: DerNode[] = [];
  let offset = 0;
  while (offset < node.content.length) {
    const { node: child, next } = readDer(node.content, offset);
    children.push(child);
    offset = next;
  }
  return children;
}

export function decodeOid(content: Uint8Array): string {
  const parts: number[] = [Math.floor(content[0] / 40), content[0] % 40];
  let value = 0;
  for (let i = 1; i < content.length; i++) {
    value = value * 128 + (content[i] & 0x7f);
    if (!(content[i] & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

export function decodeTime(node: DerNode): Date {
  const text = new TextDecoder().decode(node.content);
  // UTCTime (0x17) YYMMDDHHMMSSZ, GeneralizedTime (0x18) YYYYMMDDHHMMSSZ
  const full = node.tag === 0x17 ? (Number(text.slice(0, 2)) >= 50 ? "19" : "20") + text : text;
  const m = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(full);
  if (!m) throw new Error(`DER: unsupported time ${text}`);
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]));
}

/** Converts a DER ECDSA signature (SEQUENCE { r, s }) to the raw r||s form WebCrypto expects. */
export function ecdsaDerToRaw(signature: Uint8Array, componentLength: number): Uint8Array {
  const { node } = readDer(signature);
  const [r, s] = derChildren(node);
  const out = new Uint8Array(componentLength * 2);
  const put = (int: Uint8Array, at: number) => {
    let v = int;
    while (v.length > componentLength && v[0] === 0) v = v.subarray(1);
    if (v.length > componentLength) throw new Error("ECDSA: integer too long");
    out.set(v, at + componentLength - v.length);
  };
  put(r.content, 0);
  put(s.content, componentLength);
  return out;
}
