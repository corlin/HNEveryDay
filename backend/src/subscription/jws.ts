// Verification of StoreKit 2 / App Store Server signed data (JWS with an x5c chain to Apple Root CA - G3).

import { APPLE_ROOT_CA_G3_BASE64 } from "../auth/apple-roots";
import { fromBase64, fromUtf8, utf8 } from "../util/bytes";
import { importCertificateKey, verifyCertificateChain } from "../util/x509";

const LEAF_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

let trustedRootOverride: Uint8Array | null = null;

/** Tests only: trust a different root certificate. */
export function setTrustedRootForTesting(der: Uint8Array | null): void {
  trustedRootOverride = der;
}

export class JwsError extends Error {}

export async function verifyAppleJws<T>(jws: string, now = new Date()): Promise<T> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new JwsError("JWS: malformed");
  const [headerB64, payloadB64, signatureB64] = parts;

  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(fromUtf8(fromBase64(headerB64)));
  } catch {
    throw new JwsError("JWS: invalid header");
  }
  if (header.alg !== "ES256") throw new JwsError("JWS: unsupported alg");
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) throw new JwsError("JWS: expected 3 certificates");

  const root = trustedRootOverride ?? fromBase64(APPLE_ROOT_CA_G3_BASE64);
  let leaf, intermediate;
  try {
    [leaf, intermediate] = await verifyCertificateChain(header.x5c.map((c) => fromBase64(c)), root, now);
  } catch (error) {
    throw new JwsError(`JWS: ${(error as Error).message}`);
  }
  if (!leaf.extensions.has(LEAF_OID)) throw new JwsError("JWS: leaf certificate is not an App Store signing certificate");
  if (!intermediate.extensions.has(INTERMEDIATE_OID)) throw new JwsError("JWS: unexpected intermediate certificate");

  const key = await importCertificateKey(leaf);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    fromBase64(signatureB64),
    utf8(`${headerB64}.${payloadB64}`),
  );
  if (!valid) throw new JwsError("JWS: invalid signature");

  try {
    return JSON.parse(fromUtf8(fromBase64(payloadB64))) as T;
  } catch {
    throw new JwsError("JWS: invalid payload");
  }
}

/** JWSTransactionDecodedPayload (subset). */
export interface TransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  revocationReason?: number;
  type?: string;
  environment?: "Sandbox" | "Production" | "Xcode" | "LocalTesting";
  appAccountToken?: string;
  inAppOwnershipType?: string;
}

/** JWSRenewalInfoDecodedPayload (subset). */
export interface RenewalInfoPayload {
  originalTransactionId: string;
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

/** ResponseBodyV2DecodedPayload (subset). */
export interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data?: {
    bundleId?: string;
    environment?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
    status?: number;
  };
}
