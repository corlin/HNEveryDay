import { describe, expect, it } from "vitest";
import { verifyAssertion, verifyAttestation } from "../src/auth/appattest";
import { APPLE_ROOT_CA_G3_BASE64 } from "../src/auth/apple-roots";
import { setTrustedRootForTesting, verifyAppleJws } from "../src/subscription/jws";
import { fromBase64, pemToDer, sha256, toHex, utf8 } from "../src/util/bytes";
import { cborMapGet, decodeCbor } from "../src/util/cbor";
import { parseCertificate, verifyCertificateChain } from "../src/util/x509";
import development from "./fixtures/attestation-development.json";
import production from "./fixtures/attestation-production.json";
import appleChain from "./fixtures/apple-real-chain.json";
import { makeAppleLikeChain, signJws } from "./helpers/certs";

const APP = { teamId: "V8H6LQ9448", bundleId: "io.uebelacker.AppAttestExample" };

function credCertValidity(attestation: string) {
  const x5c = cborMapGet(cborMapGet(decodeCbor(fromBase64(attestation)), "attStmt"), "x5c") as Uint8Array[];
  const cert = parseCertificate(x5c[0]);
  return new Date(cert.notBefore.getTime() + 60_000);
}

describe("Apple roots", () => {
  it("pins Apple Root CA G3 by its published fingerprint", async () => {
    const fingerprint = toHex(await sha256(fromBase64(APPLE_ROOT_CA_G3_BASE64)));
    expect(fingerprint).toBe("63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179");
  });
});

describe("App Attest attestation", () => {
  for (const [name, fixture, env] of [
    ["development", development, "development"],
    ["production", production, "production"],
  ] as const) {
    it(`accepts a real ${name} attestation`, async () => {
      const result = await verifyAttestation({
        attestation: fromBase64(fixture.attestation),
        challenge: fromBase64(fixture.challenge),
        keyId: fixture.keyId,
        app: APP,
        allowDevelopment: true,
        now: credCertValidity(fixture.attestation),
      });
      expect(result.environment).toBe(env);
      expect(result.publicKeySpki.length).toBeGreaterThan(60);
    });
  }

  it("rejects development attestations unless allowed", async () => {
    await expect(
      verifyAttestation({
        attestation: fromBase64(development.attestation),
        challenge: fromBase64(development.challenge),
        keyId: development.keyId,
        app: APP,
        allowDevelopment: false,
        now: credCertValidity(development.attestation),
      }),
    ).rejects.toThrow(/environment/);
  });

  it("rejects a different challenge", async () => {
    await expect(
      verifyAttestation({
        attestation: fromBase64(production.attestation),
        challenge: utf8("another challenge"),
        keyId: production.keyId,
        app: APP,
        allowDevelopment: true,
        now: credCertValidity(production.attestation),
      }),
    ).rejects.toThrow(/nonce/);
  });

  it("rejects a different app id", async () => {
    await expect(
      verifyAttestation({
        attestation: fromBase64(production.attestation),
        challenge: fromBase64(production.challenge),
        keyId: production.keyId,
        app: { ...APP, bundleId: "com.example.other" },
        allowDevelopment: true,
        now: credCertValidity(production.attestation),
      }),
    ).rejects.toThrow(/app id/);
  });

  it("rejects a mismatched key id", async () => {
    await expect(
      verifyAttestation({
        attestation: fromBase64(production.attestation),
        challenge: fromBase64(production.challenge),
        keyId: development.keyId,
        app: APP,
        allowDevelopment: true,
        now: credCertValidity(production.attestation),
      }),
    ).rejects.toThrow(/key id/);
  });

  it("rejects expired certificates", async () => {
    await expect(
      verifyAttestation({
        attestation: fromBase64(production.attestation),
        challenge: fromBase64(production.challenge),
        keyId: production.keyId,
        app: APP,
        allowDevelopment: true,
        now: new Date("2060-01-01"),
      }),
    ).rejects.toThrow(/not valid/);
  });
});

describe("App Attest assertion", () => {
  const ASSERTION =
    "omlzaWduYXR1cmVYRzBFAiBB8BGAwkmFCg1M5J0mOYEun0SUN1/lse79/7ypG9WiMQIhAIHvqj7eg59B1PMFX1CN4GMGlsgfFtdL30pHCf7G/dNRcWF1dGhlbnRpY2F0b3JEYXRhWCXKPdw7T3iujcFZbHVrHX0mDSMrNms5PzEbrFbQPRA6rEAAAAAB";
  const PUBLIC_KEY =
    "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEg69t2YzgcPTLUx8Zgu+rbcikeaEL\n8Ppb+HG0QTIulz8YUB9tgv1pDRruWk87nZC3our56pzIWaqXEbaWyamdzA==\n-----END PUBLIC KEY-----\n";
  const CLIENT_DATA = '{"subject":"Lorem ipsum","message":"Lorem ipsum dolor sit amet, consectetur adipiscing elit."}';

  it("accepts a real assertion and returns the counter", async () => {
    const result = await verifyAssertion({
      assertion: fromBase64(ASSERTION),
      clientData: utf8(CLIENT_DATA),
      publicKeySpki: pemToDer(PUBLIC_KEY),
      previousCounter: 0,
      app: APP,
    });
    expect(result.counter).toBe(1);
  });

  it("rejects replays (counter not increasing)", async () => {
    await expect(
      verifyAssertion({
        assertion: fromBase64(ASSERTION),
        clientData: utf8(CLIENT_DATA),
        publicKeySpki: pemToDer(PUBLIC_KEY),
        previousCounter: 1,
        app: APP,
      }),
    ).rejects.toThrow(/counter/);
  });

  it("rejects tampered client data", async () => {
    await expect(
      verifyAssertion({
        assertion: fromBase64(ASSERTION),
        clientData: utf8(CLIENT_DATA + " "),
        publicKeySpki: pemToDer(PUBLIC_KEY),
        previousCounter: 0,
        app: APP,
      }),
    ).rejects.toThrow(/signature/);
  });
});

describe("X.509 chains", () => {
  it("verifies Apple's real App Store signing chain to Root CA G3", async () => {
    const certs = await verifyCertificateChain(
      [fromBase64(appleChain.leaf), fromBase64(appleChain.intermediate)],
      fromBase64(APPLE_ROOT_CA_G3_BASE64),
      new Date(appleChain.effectiveDate),
    );
    expect(certs[0].extensions.has("1.2.840.113635.100.6.11.1")).toBe(true);
    expect(certs[1].extensions.has("1.2.840.113635.100.6.2.1")).toBe(true);
  });

  it("rejects a chain anchored to another root", async () => {
    const other = await makeAppleLikeChain();
    await expect(
      verifyCertificateChain([fromBase64(appleChain.leaf), fromBase64(appleChain.intermediate)], other.root.der, new Date(appleChain.effectiveDate)),
    ).rejects.toThrow(/signature/);
  });

  it("rejects a leaf used as an issuer", async () => {
    const chain = await makeAppleLikeChain();
    await expect(verifyCertificateChain([chain.intermediate.der, chain.leaf.der], chain.root.der, new Date())).rejects.toThrow();
  });
});

describe("StoreKit JWS", () => {
  it("verifies a JWS signed by a trusted chain and rejects other roots", async () => {
    const chain = await makeAppleLikeChain();
    const jws = await signJws({ hello: "world" }, chain);

    await expect(verifyAppleJws(jws)).rejects.toThrow(/signature|JWS/);

    setTrustedRootForTesting(chain.root.der);
    try {
      expect(await verifyAppleJws<{ hello: string }>(jws)).toEqual({ hello: "world" });
      const [h, , s] = jws.split(".");
      const forged = `${h}.${btoa(JSON.stringify({ hello: "mallory" })).replace(/=+$/, "")}.${s}`;
      await expect(verifyAppleJws(forged)).rejects.toThrow(/signature/);
    } finally {
      setTrustedRootForTesting(null);
    }
  });

  it("requires the App Store OIDs on the chain", async () => {
    const chain = await makeAppleLikeChain();
    const { makeCert } = await import("./helpers/certs");
    const plainLeaf = await makeCert({ cn: "Plain", issuer: chain.intermediate, ca: false });
    const jws = await signJws({}, { ...chain, leaf: plainLeaf });
    setTrustedRootForTesting(chain.root.der);
    try {
      await expect(verifyAppleJws(jws)).rejects.toThrow(/signing certificate/);
    } finally {
      setTrustedRootForTesting(null);
    }
  });
});
