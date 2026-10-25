import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  const migrations = await readD1Migrations("./migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            APP_TEAM_ID: "V8H6LQ9448",
            APP_BUNDLE_ID: "io.uebelacker.AppAttestExample",
            ALLOW_DEV_ATTEST: "true",
            ALLOW_SANDBOX: "true",
            LLM_BASE_URL: "https://llm.test/v1",
            LLM_MODEL: "test-model",
            LLM_API_KEY: "test-llm-key",
            TOKEN_SECRET: "test-token-secret-0123456789abcdef",
            ADMIN_TOKEN: "test-admin",
            PRO_PRODUCT_IDS: "pro.monthly,pro.annual",
          },
        },
      }),
    ],
    test: {
      setupFiles: ["./test/apply-migrations.ts"],
    },
  };
});
