import { verifyAssertion, verifyAttestation, type AppIdentity } from "../auth/appattest";
import { issueDeviceToken, limitByIp } from "../auth/token";
import type { Env } from "../env";
import { flag } from "../env";
import { HttpError, json, readJson, requireString } from "../http";
import { fromBase64, randomBytes, toBase64, toBase64Url, utf8 } from "../util/bytes";

const CHALLENGE_TTL_MS = 5 * 60 * 1000;

function appIdentity(env: Env): AppIdentity {
  return { teamId: env.APP_TEAM_ID, bundleId: env.APP_BUNDLE_ID };
}

/** Consumes a challenge exactly once; returns false if unknown or expired. */
async function consumeChallenge(env: Env, challenge: string): Promise<boolean> {
  const row = await env.DB.prepare("DELETE FROM attest_challenges WHERE challenge = ? RETURNING expires_at")
    .bind(challenge)
    .first<{ expires_at: number }>();
  return !!row && row.expires_at > Date.now();
}

export async function handleChallenge(request: Request, env: Env): Promise<Response> {
  await limitByIp(request, env);
  const challenge = toBase64Url(randomBytes(32));
  const expiresAt = Date.now() + CHALLENGE_TTL_MS;
  await env.DB.prepare("INSERT INTO attest_challenges (challenge, expires_at) VALUES (?, ?)").bind(challenge, expiresAt).run();
  return json({ challenge, expires_at: expiresAt });
}

/**
 * Body: { key_id, attestation (base64), challenge }.
 * The client must call attestKey with clientDataHash = SHA256(utf8(challenge)).
 */
export async function handleAttest(request: Request, env: Env): Promise<Response> {
  await limitByIp(request, env);
  if (env.ATTEST_MODE === "off") throw new HttpError(400, "attest_disabled", "App Attest is disabled; use /auth/anonymous");
  const body = await readJson<Record<string, unknown>>(request, 64 * 1024);
  const keyId = requireString(body.key_id, "key_id", 128);
  const attestation = requireString(body.attestation, "attestation", 48 * 1024);
  const challenge = requireString(body.challenge, "challenge", 128);
  if (!(await consumeChallenge(env, challenge))) throw new HttpError(400, "invalid_challenge", "Challenge is unknown or expired");

  let result;
  try {
    result = await verifyAttestation({
      attestation: fromBase64(attestation),
      challenge: utf8(challenge),
      keyId,
      app: appIdentity(env),
      allowDevelopment: flag(env.ALLOW_DEV_ATTEST),
    });
  } catch (error) {
    console.warn("attestation rejected", (error as Error).message);
    throw new HttpError(401, "attestation_failed", "App Attest verification failed");
  }

  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO devices (id, public_key, counter, attested, environment, created_at, last_seen)
     VALUES (?, ?, 0, 1, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET public_key = excluded.public_key, counter = 0, attested = 1,
       environment = excluded.environment, last_seen = excluded.last_seen`,
  )
    .bind(keyId, toBase64(result.publicKeySpki), result.environment, now, now)
    .run();

  return json({ device_id: keyId, attested: true, ...(await issueDeviceToken(env, keyId, true)) });
}

/**
 * Renews a device token. Body: { key_id, assertion (base64), challenge }.
 * The client signs clientData = utf8(challenge) with generateAssertion(keyId, clientDataHash: SHA256(clientData)).
 */
export async function handleAssert(request: Request, env: Env): Promise<Response> {
  await limitByIp(request, env);
  const body = await readJson<Record<string, unknown>>(request, 16 * 1024);
  const keyId = requireString(body.key_id, "key_id", 128);
  const assertion = requireString(body.assertion, "assertion", 8 * 1024);
  const challenge = requireString(body.challenge, "challenge", 128);
  if (!(await consumeChallenge(env, challenge))) throw new HttpError(400, "invalid_challenge", "Challenge is unknown or expired");

  const device = await env.DB.prepare("SELECT public_key, counter FROM devices WHERE id = ? AND attested = 1")
    .bind(keyId)
    .first<{ public_key: string; counter: number }>();
  if (!device) throw new HttpError(401, "unknown_device", "Device must attest first");

  let counter: number;
  try {
    ({ counter } = await verifyAssertion({
      assertion: fromBase64(assertion),
      clientData: utf8(challenge),
      publicKeySpki: fromBase64(device.public_key),
      previousCounter: device.counter,
      app: appIdentity(env),
    }));
  } catch (error) {
    console.warn("assertion rejected", (error as Error).message);
    throw new HttpError(401, "assertion_failed", "App Attest assertion failed");
  }

  // Conditional update guards against two concurrent renewals reusing a counter.
  const updated = await env.DB.prepare("UPDATE devices SET counter = ?, last_seen = ? WHERE id = ? AND counter < ?")
    .bind(counter, Date.now(), keyId, counter)
    .run();
  if (!updated.meta.changes) throw new HttpError(401, "assertion_failed", "App Attest assertion replayed");

  return json({ device_id: keyId, attested: true, ...(await issueDeviceToken(env, keyId, true)) });
}

/** For devices where App Attest is unavailable (simulator, some jailbroken/older devices). */
export async function handleAnonymous(request: Request, env: Env): Promise<Response> {
  await limitByIp(request, env);
  if (env.ATTEST_MODE === "enforce") throw new HttpError(403, "attestation_required", "Anonymous tokens are disabled");
  const body = await readJson<Record<string, unknown>>(request, 4 * 1024).catch(() => ({}) as Record<string, unknown>);
  // Reuse a previously issued anonymous id so usage counters survive token renewal.
  const requested = typeof body.device_id === "string" && /^anon:[A-Za-z0-9_-]{16,64}$/.test(body.device_id) ? body.device_id : null;
  const deviceId = requested ?? `anon:${toBase64Url(randomBytes(18))}`;
  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO devices (id, public_key, counter, attested, environment, created_at, last_seen)
     VALUES (?, NULL, 0, 0, NULL, ?, ?)
     ON CONFLICT(id) DO UPDATE SET last_seen = excluded.last_seen`,
  )
    .bind(deviceId, now, now)
    .run();
  return json({ device_id: deviceId, attested: false, ...(await issueDeviceToken(env, deviceId, false)) });
}
