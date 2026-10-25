// Minimal X.509 parsing and ECDSA chain verification on top of WebCrypto.
// Only covers what Apple's StoreKit and App Attest chains use: EC keys (P-256/P-384)
// signed with ecdsa-with-SHA256/SHA384.

import { bytesEqual } from "./bytes";
import { decodeOid, decodeTime, derChildren, ecdsaDerToRaw, readDer, type DerNode } from "./der";

const OID_EC_PUBLIC_KEY = "1.2.840.10045.2.1";
const OID_P256 = "1.2.840.10045.3.1.7";
const OID_P384 = "1.3.132.0.34";
const OID_ECDSA_SHA256 = "1.2.840.10045.4.3.2";
const OID_ECDSA_SHA384 = "1.2.840.10045.4.3.3";
const OID_BASIC_CONSTRAINTS = "2.5.29.19";

export interface Certificate {
  raw: Uint8Array;
  tbs: Uint8Array;
  signatureAlgorithm: string;
  signature: Uint8Array;
  notBefore: Date;
  notAfter: Date;
  /** DER SubjectPublicKeyInfo, importable with WebCrypto "spki". */
  spki: Uint8Array;
  namedCurve: "P-256" | "P-384";
  /** Uncompressed EC point (0x04 || X || Y). */
  publicKeyPoint: Uint8Array;
  extensions: Map<string, Uint8Array>;
  isCA: boolean;
}

export function parseCertificate(der: Uint8Array): Certificate {
  const { node: cert } = readDer(der);
  const [tbsNode, sigAlgNode, sigValueNode] = derChildren(cert);
  if (!tbsNode || !sigAlgNode || !sigValueNode) throw new Error("X509: malformed certificate");

  const tbsFields = derChildren(tbsNode);
  let i = 0;
  if (tbsFields[i].tag === 0xa0) i++; // [0] version
  i++; // serialNumber
  i++; // signature AlgorithmIdentifier
  i++; // issuer
  const validity = derChildren(tbsFields[i++]);
  i++; // subject
  const spkiNode = tbsFields[i++];

  const extensions = new Map<string, Uint8Array>();
  for (; i < tbsFields.length; i++) {
    if (tbsFields[i].tag !== 0xa3) continue;
    const [extSeq] = derChildren(tbsFields[i]);
    for (const ext of derChildren(extSeq)) {
      const parts = derChildren(ext);
      const oid = decodeOid(parts[0].content);
      const value = parts[parts.length - 1];
      extensions.set(oid, value.content);
    }
  }

  const [algId, keyBits] = derChildren(spkiNode);
  const [keyAlg, curveNode] = derChildren(algId);
  if (decodeOid(keyAlg.content) !== OID_EC_PUBLIC_KEY) throw new Error("X509: only EC keys are supported");
  const curveOid = decodeOid(curveNode.content);
  const namedCurve = curveOid === OID_P256 ? "P-256" : curveOid === OID_P384 ? "P-384" : null;
  if (!namedCurve) throw new Error(`X509: unsupported curve ${curveOid}`);

  const [sigAlgOid] = derChildren(sigAlgNode);

  return {
    raw: cert.raw,
    tbs: tbsNode.raw,
    signatureAlgorithm: decodeOid(sigAlgOid.content),
    signature: sigValueNode.content.subarray(1), // skip "unused bits" byte
    notBefore: decodeTime(validity[0]),
    notAfter: decodeTime(validity[1]),
    spki: spkiNode.raw,
    namedCurve,
    publicKeyPoint: keyBits.content.subarray(1),
    extensions,
    isCA: readIsCA(extensions.get(OID_BASIC_CONSTRAINTS)),
  };
}

function readIsCA(value: Uint8Array | undefined): boolean {
  if (!value) return false;
  const { node } = readDer(value);
  const [first] = derChildren(node);
  return first?.tag === 0x01 && first.content[0] !== 0;
}

export async function importCertificateKey(cert: Certificate): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", cert.spki, { name: "ECDSA", namedCurve: cert.namedCurve }, false, [
    "verify",
  ]);
}

export async function verifyCertificateSignature(cert: Certificate, issuer: Certificate): Promise<boolean> {
  const hash =
    cert.signatureAlgorithm === OID_ECDSA_SHA256
      ? "SHA-256"
      : cert.signatureAlgorithm === OID_ECDSA_SHA384
        ? "SHA-384"
        : null;
  if (!hash) throw new Error(`X509: unsupported signature algorithm ${cert.signatureAlgorithm}`);
  const key = await importCertificateKey(issuer);
  let raw: Uint8Array;
  try {
    raw = ecdsaDerToRaw(cert.signature, issuer.namedCurve === "P-256" ? 32 : 48);
  } catch {
    return false; // signature does not even fit the issuer's curve
  }
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, raw, cert.tbs);
}

/**
 * Verifies `chain` (leaf first) up to `trustedRoot`. The root may or may not be included
 * as the last element of `chain`; if it is, it must be byte-identical to `trustedRoot`.
 * Returns the parsed leaf certificate.
 */
export async function verifyCertificateChain(
  chain: Uint8Array[],
  trustedRoot: Uint8Array,
  at: Date,
): Promise<Certificate[]> {
  if (chain.length === 0) throw new Error("X509: empty chain");
  const ders = bytesEqual(chain[chain.length - 1], trustedRoot) ? chain : [...chain, trustedRoot];
  if (ders.length < 2) throw new Error("X509: chain too short");
  const certs = ders.map(parseCertificate);

  for (let i = 0; i < certs.length; i++) {
    const cert = certs[i];
    if (at < cert.notBefore || at > cert.notAfter) throw new Error(`X509: certificate ${i} is not valid at ${at.toISOString()}`);
    if (i > 0 && !cert.isCA) throw new Error(`X509: certificate ${i} is not a CA`);
    if (i < certs.length - 1 && !(await verifyCertificateSignature(cert, certs[i + 1]))) {
      throw new Error(`X509: certificate ${i} signature is invalid`);
    }
  }
  return certs;
}

export type { DerNode };
