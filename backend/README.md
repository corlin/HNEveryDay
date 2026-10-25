# HNEveryDay 后端（Cloudflare Workers）

托管 AI（标题翻译、摘要、全文翻译、Agent）、设备认证（App Attest）、额度与订阅状态。设计见
[`docs/PRO_PAYWALL_AND_BACKEND_SPEC.md`](../docs/PRO_PAYWALL_AND_BACKEND_SPEC.md)。新闻流不经过这里。

## 本地开发

```sh
cd backend
npm install
npm test                 # vitest，运行在 workerd 中，含真实 App Attest / Apple 证书链测试向量
npm run typecheck
npm run db:migrate:local
npx wrangler dev         # 需要 .dev.vars 提供 LLM_API_KEY、TOKEN_SECRET
```

`.dev.vars` 示例（不要提交）：

```
LLM_API_KEY=sk-...
TOKEN_SECRET=<openssl rand -base64 32>
ATTEST_MODE=off
```

## 首次部署

```sh
npx wrangler d1 create hneveryday           # 把 database_id 填进 wrangler.toml
npx wrangler kv namespace create CONFIG      # 把 id 填进 wrangler.toml
npm run db:migrate:remote
npx wrangler secret put LLM_API_KEY
npx wrangler secret put TOKEN_SECRET
npx wrangler secret put ADMIN_TOKEN
# 可选：App Store Server API 对账
npx wrangler secret put ASC_KEY_ID
npx wrangler secret put ASC_ISSUER_ID
npx wrangler secret put ASC_PRIVATE_KEY      # .p8 文件内容
npm run deploy
```

部署前还需要：

1. 在 `wrangler.toml` 填写 `APP_TEAM_ID`（Apple 开发者 Team ID），`APP_BUNDLE_ID` 与 Xcode 一致。
2. App Store Connect → App 信息 → App Store 服务器通知，生产与沙盒 URL 都填 `https://hnapi.caifu.social/api/v1/appstore/notifications`，版本选 **Version 2**。
3. 在模型服务商控制台设置月度花费上限（`DAILY_TOKEN_BUDGET` 只是第二道防线）。
4. TestFlight 构建的 App Attest 走生产环境；用 Xcode 直接安装的调试包是 `appattestdevelop`，需要临时把 `ALLOW_DEV_ATTEST` 设为 `"true"`。沙盒购买需要 `ALLOW_SANDBOX = "true"`。

## 远程配置与 kill switch

默认值在 `src/config.ts`。在 KV 里写入 `config` 键即可覆盖，约 1 分钟内生效，无需重新部署：

```sh
# 关闭 Agent
npx wrangler kv key put --binding CONFIG config '{"features":{"agent":false}}' --remote
# 中国区备案/登记号拿到后，写入设置页的模型披露信息
npx wrangler kv key put --binding CONFIG config '{"model_disclosure":"本应用 AI 服务基于 DeepSeek 大模型（备案号：…）"}' --remote
# 应急：按地区关闭托管 AI（cf.country，两位码），并按 App Store 店面隐藏付费墙（三位码）
npx wrangler kv key put --binding CONFIG config '{"disabled_countries":["CN"],"disabled_storefronts":["CHN"]}' --remote
# 调整免费额度
npx wrangler kv key put --binding CONFIG config '{"quotas":{"free":{"summary":20}}}' --remote
```

## 运维

- 下线某个故事的 AI 内容：`curl -X POST https://hnapi.caifu.social/api/v1/admin/takedown -H "authorization: Bearer $ADMIN_TOKEN" -d '{"story_id":123}'`
- 查看举报：`npx wrangler d1 execute hneveryday --remote --command "SELECT * FROM reports ORDER BY id DESC LIMIT 50"`
- 今日 token 用量：`SELECT * FROM budget_daily ORDER BY day DESC LIMIT 7`
- 缓存命中情况：`SELECT kind, lang, COUNT(*) FROM ai_outputs GROUP BY 1, 2`
- 回滚：`npx wrangler rollback`。D1 迁移只增不删，旧版本 Worker 可直接回滚。
- 更换模型或修改 prompt：改 `LLM_MODEL` 或 `src/prompts.ts` 里的 `PROMPT_VERSIONS`；旧产物不再命中，90 天后由 Cron 清理。

## 接口

见规格文档第六章。所有业务接口需要 `Authorization: Bearer <device_token>`，可选 `X-App-Version` 用于最低版本控制。
