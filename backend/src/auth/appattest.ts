// App Attest verification, following
// https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server

import { bytesEqual, concatBytes, fromBase64, pemToDer, sha256, utf8 } from "../util/bytes";
import { cborMapGet, decodeCbor } from "../util/cbor";
import { derChildren, ecdsaDerToRaw, readDer } from "../util/der";
import { verifyCertificateChain } from "../util/x509";
import { APPLE_APP_ATTESTATION_ROOT_CA_PEM } from "./apple-roots";

const NONCE_EXTENSION_OID = "1.2.840.113635.100.8.2";
const AAGUID_PRODUCTION = concatBytes(utf8("appattest"), new Uint8Array(7));
const AAGUID_DEVELOPMENT = utf8("appattestdevelop");

export interface AppIdentity {
  teamId: string;
  bundleId: string;
}

export interface AttestationResult {
  /** DER SubjectPublicKeyInfo of the attested key, used to verify later assertions. */
  publicKeySpki: Uint8Array;
  environment: "production" | "development";
}

interface AuthData {
  rpIdHash: Uint8Array;
  counter: number;
  aaguid?: Uint8Array;
  credentialId?: Uint8Array;
}

function parseAuthData(authData: Uint8Array, withAttestedCredential: boolean): AuthData {
  if (authData.length < 37) throw new Error("AppAttest: authData too short");
  const view = new DataView(authData.buffer, authData.byteOffset, authData.byteLength);
  const result: AuthData = {
    rpIdHash: authData.subarray(0, 32),
    counter: view.getUint32(33),
  };
  if (withAttestedCredential) {
    if (authData.length < 55) throw new Error("AppAttest: missing attested credential data");
    result.aaguid = authData.subarray(37, 53);
    const idLength = view.getUint16(53);
    result.credentialId = authData.subarray(55, 55 + idLength);
  }
  return result;
}

function bytesField(value: unknown, name: string): Uint8Array {
  if (!(value instanceof Uint8Array)) throw new Error(`AppAttest: ${name} missing`);
  return value;
}

export async function verifyAttestation(params: {
  attestation: Uint8Array;
  challenge: Uint8Array;
  keyId: string;
  app: AppIdentity;
  allowDevelopment: boolean;
  now?: Date;
}): Promise<AttestationResult> {
  const decoded = decodeCbor(params.attestation);
  if (cborMapGet(decoded, "fmt") !== "apple-appattest") throw new Error("AppAttest: unexpected format");
  const attStmt = cborMapGet(decoded, "attStmt");
  const x5c = cborMapGet(attStmt, "x5c");
  if (!Array.isArray(x5c) || x5c.length < 2) throw new Error("AppAttest: missing certificate chain");
  const authData = bytesField(cborMapGet(decoded, "authData"), "authData");

  // 1. Certificate chain up to the App Attestation root.
  const [credCert] = await verifyCertificateChain(
    x5c.map((c, i) => bytesField(c, `x5c[${i}]`)),
    pemToDer(APPLE_APP_ATTESTATION_ROOT_CA_PEM),
    params.now ?? new Date(),
  );

  // 2-4. nonce = SHA256(authData || SHA256(challenge)) must match the credential certificate extension.
  const clientDataHash = await sha256(params.challenge);
  const nonce = await sha256(concatBytes(authData, clientDataHash));
  const extension = credCert.extensions.get(NONCE_EXTENSION_OID);
  if (!extension) throw new Error("AppAttest: nonce extension missing");
  const { node: seq } = readDer(extension);
  const [tagged] = derChildren(seq);
  const [octets] = derChildren(tagged);
  if (!bytesEqual(octets.content, nonce)) throw new Error("AppAttest: nonce mismatch");

  // 5. Key identifier is the SHA256 of the credential public key.
  const keyId = fromBase64(params.keyId);
  if (!bytesEqual(await sha256(credCert.publicKeyPoint), keyId)) throw new Error("AppAttest: key id mismatch");

  // 6-9. authData checks.
  const parsed = parseAuthData(authData, true);
  const appId = `${params.app.teamId}.${params.app.bundleId}`;
  if (!bytesEqual(parsed.rpIdHash, await sha256(utf8(appId)))) throw new Error("AppAttest: app id mismatch");
  if (parsed.counter !== 0) throw new Error("AppAttest: counter must be zero");

  let environment: AttestationResult["environment"];
  if (bytesEqual(parsed.aaguid!, AAGUID_PRODUCTION)) environment = "production";
  else if (params.allowDevelopment && bytesEqual(parsed.aaguid!, AAGUID_DEVELOPMENT)) environment = "development";
  else throw new Error("AppAttest: unexpected environment");

  if (!bytesEqual(parsed.credentialId!, keyId)) throw new Error("AppAttest: credential id mismatch");

  return { publicKeySpki: credCert.spki, environment };
}

export async function verifyAssertion(params: {
  assertion: Uint8Array;
  clientData: Uint8Array;
  publicKeySpki: Uint8Array;
  previousCounter: number;
  app: AppIdentity;
}): Promise<{ counter: number }> {
  const decoded = decodeCbor(params.assertion);
  const signature = bytesField(cborMapGet(decoded, "signature"), "signature");
  const authenticatorData = bytesField(cborMapGet(decoded, "authenticatorData"), "authenticatorData");

  const clientDataHash = await sha256(params.clientData);
  const nonce = await sha256(concatBytes(authenticatorData, clientDataHash));
  const key = await crypto.subtle.importKey(
    "spki",
    params.publicKeySpki,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    ecdsaDerToRaw(signature, 32),
    nonce,
  );
  if (!valid) throw new Error("AppAttest: invalid assertion signature");

  const parsed = parseAuthData(authenticatorData, false);
  const appId = `${params.app.teamId}.${params.app.bundleId}`;
  if (!bytesEqual(parsed.rpIdHash, await sha256(utf8(appId)))) throw new Error("AppAttest: app id mismatch");
  if (parsed.counter <= params.previousCounter) throw new Error("AppAttest: counter did not increase");
  return { counter: parsed.counter };
}
