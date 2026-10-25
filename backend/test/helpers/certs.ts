// Tiny DER/X.509 writer for building throwaway ECDSA certificate chains in tests.

import { concatBytes, toBase64, toBase64Url, utf8 } from "../../src/util/bytes";

function len(n: number): Uint8Array {
  if (n < 0x80) return new Uint8Array([n]);
  const bytes: number[] = [];
  while (n > 0) {
    bytes.unshift(n & 0xff);
    n >>= 8;
  }
  return new Uint8Array([0x80 | bytes.length, ...bytes]);
}
const tlv = (tag: number, ...content: Uint8Array[]) => {
  const body = concatBytes(...content);
  return concatBytes(new Uint8Array([tag]), len(body.length), body);
};
const seq = (...c: Uint8Array[]) => tlv(0x30, ...c);
const set = (...c: Uint8Array[]) => tlv(0x31, ...c);
const int = (n: number) => tlv(0x02, new Uint8Array([n]));
const bool = (v: boolean) => tlv(0x01, new Uint8Array([v ? 0xff : 0]));
const octets = (b: Uint8Array) => tlv(0x04, b);
const bitString = (b: Uint8Array) => tlv(0x03, new Uint8Array([0]), b);
function oid(text: string): Uint8Array {
  const parts = text.split(".").map(Number);
  const out = [parts[0] * 40 + parts[1]];
  for (const p of parts.slice(2)) {
    const chunk: number[] = [p & 0x7f];
    let v = p >> 7;
    while (v > 0) {
      chunk.unshift((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.push(...chunk);
  }
  return tlv(0x06, new Uint8Array(out));
}
function time(d: Date): Uint8Array {
  const s = d.toISOString().replace(/[-:T]/g, "").slice(2, 14) + "Z";
  return tlv(0x17, utf8(s));
}
const name = (cn: string) => seq(set(seq(oid("2.5.4.3"), tlv(0x0c, utf8(cn)))));

function rawToDerSignature(raw: Uint8Array): Uint8Array {
  const half = raw.length / 2;
  const integer = (b: Uint8Array) => {
    let v = b;
    while (v.length > 1 && v[0] === 0 && !(v[1] & 0x80)) v = v.subarray(1);
    if (v[0] & 0x80) v = concatBytes(new Uint8Array([0]), v);
    return tlv(0x02, v);
  };
  return seq(integer(raw.subarray(0, half)), integer(raw.subarray(half)));
}

export interface TestCert {
  der: Uint8Array;
  keys: CryptoKeyPair;
}

export async function makeCert(options: {
  cn: string;
  issuer?: TestCert & { cn: string };
  ca: boolean;
  extensionOids?: string[];
  notBefore?: Date;
  notAfter?: Date;
}): Promise<TestCert & { cn: string }> {
  const keys = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const spki = new Uint8Array((await crypto.subtle.exportKey("spki", keys.publicKey)) as ArrayBuffer);
  const sigAlg = seq(oid("1.2.840.10045.4.3.2"));
  const extensions = [
    seq(oid("2.5.29.19"), bool(true), octets(seq(...(options.ca ? [bool(true)] : [])))),
    ...(options.extensionOids ?? []).map((o) => seq(oid(o), octets(tlv(0x05, new Uint8Array())))),
  ];
  const tbs = seq(
    tlv(0xa0, int(2)),
    int(1),
    sigAlg,
    name(options.issuer?.cn ?? options.cn),
    seq(time(options.notBefore ?? new Date(Date.now() - 86_400_000)), time(options.notAfter ?? new Date(Date.now() + 86_400_000 * 365))),
    name(options.cn),
    spki,
    tlv(0xa3, seq(...extensions)),
  );
  const signer = options.issuer?.keys.privateKey ?? keys.privateKey;
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signer, tbs));
  return { der: seq(tbs, sigAlg, bitString(rawToDerSignature(raw))), keys, cn: options.cn };
}

export async function makeAppleLikeChain() {
  const root = await makeCert({ cn: "Test Root", ca: true });
  const intermediate = await makeCert({ cn: "Test WWDR", issuer: root, ca: true, extensionOids: ["1.2.840.113635.100.6.2.1"] });
  const leaf = await makeCert({ cn: "Test Signing", issuer: intermediate, ca: false, extensionOids: ["1.2.840.113635.100.6.11.1"] });
  return { root, intermediate, leaf };
}

export async function signJws(payload: unknown, chain: { leaf: TestCert; intermediate: TestCert; root: TestCert }): Promise<string> {
  const header = { alg: "ES256", x5c: [chain.leaf, chain.intermediate, chain.root].map((c) => toBase64(c.der)) };
  const input = `${toBase64Url(utf8(JSON.stringify(header)))}.${toBase64Url(utf8(JSON.stringify(payload)))}`;
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, chain.leaf.keys.privateKey, utf8(input)));
  return `${input}.${toBase64Url(sig)}`;
}
