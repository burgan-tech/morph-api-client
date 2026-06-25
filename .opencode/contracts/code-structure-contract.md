# morph-api-client — Code Structure Contract

Modül/katman haritası, public API yüzeyi ve adlandırma desenleri. Yollar repo köküne göredir.

---

## 1. Üst seviye yapı

```
package.json            Monorepo kökü (private): npm scripts dev / build:core / build:vue / build (:5)
README.md               Quick start (PoC) + Layout tablosu
core/                   ⭐ Yayımlanan SDK paketi (morph-api-client)
  package.json          name=morph-api-client, ESM+CJS+d.ts, sıfır runtime dep (:1)
  vite.config.ts        Kütüphane build (vite + vite-plugin-dts)
  tsconfig.json
  src/                  TÜM SDK kaynağı (~1850 satır)
poc/                    Kanıtlama/demo — ÜRÜN DEĞİL
  ts-vue/               Vue 3 demo app (tüketici örneği)
  keycloak/             Docker Keycloak realm + setup.sh / test-flows.sh
  mock-api/             Express mock REST API (JWT doğrular)
docs/                   Tasarım & API dokümanları (kod ile hizalı; birincil yön kaynağı)
```

> "Layout" tablosu `README.md:56-68`'te; mimari ve proje yapısı `docs/architecture.md:151-173`'te.

### `core/src/` modül haritası
```
client/         Public facade'ler
  MorphClient.ts    init() · host() · auth() · getTokenStatus() · OAuth flow (:6)
  HostClient.ts     get/post/put/patch/delete/head/options/request → rt.http.hostFetch (:4)
  AuthHandle.ts     login(submitCode)/acquireWithClientCredentials/exchangeToken/logout/refresh… 
config/         interpolate.ts ($variable enjeksiyonu) · validate.ts (validateAndIndexConfig → CtxRef, hostByKey)
tokens/         tokenLifecycle.ts (grant'lar, kilitler, resolveAccessToken, 401 recovery) · tokenVault.ts (depolama I/O)
http/           hostPipeline.ts (hostFetch, fetchWithTrace, 401 retry, trace)
oauth/          tokenHttp.ts (grant token endpoint HTTP'leri)
util/           jwt, expiry, duration, url, normalizeOrigin, oauthAuthorize, oauthReturn, oauthState, exchangeSources, httpTrace
storage/        browserStorage.ts (createBrowserSessionStorage / createBrowserLocalStorage)
runtime.ts      MorphRuntime — ince koordinatör (config sorguları + OAuth flow), modülleri kurar (:22)
types.ts        Public arayüzler (MorphConfig, MorphOptions, AuthContextConfig, …)
errors.ts       Hata sınıfları
index.ts        Public export yüzeyi (yayımlanan API)
```

---

## 2. Katman mimarisi

Üstten alta (her ok "delege eder"):
`Host App → MorphClient (facade) → {HostClient | AuthHandle} → MorphRuntime (koordinatör)
→ {HostPipeline | TokenLifecycle} → TokenVault → {StorageProvider, NetworkDelegate} (enjekte)`.

Tasarım ilkeleri (`docs/architecture.md:9-16`): **config-driven** (auth davranışı JSON config'te,
kodda değil), **multi-context** (device/1fa/2fa/external bağımsız token döngüleri), **provider↔host
ayrımı** (kim token verir ↔ token nerede kullanılır; çoka-çok), **callback delegation** (interaktif
akışı host app yapar), **platform-agnostic core** (yalnız storage + transport platforma özgü, enjekte),
**proactive refresh** (expiry'den önce yenileme). SDK = HTTP client'ın KENDİSİDİR (`:7`).

HTTP pipeline (her istek): auth çözümü → istek kurma (URL + header + `Bearer`) → `fetchWithTrace`
(timeout/abort/trace) → 401 recovery (refresh-kilit + tek retry) → 401 delegate (`onAuthRequired`)
→ yanıt parse (JSON, opsiyonel decrypt). Kanıt: `docs/architecture.md:84-98`, `http/hostPipeline.ts:124-160`.

---

## 3. Public API yüzeyi (interface → nerede)

> Tek yayımlanan giriş: `core/src/index.ts`. Bir sembolü çözmek için sırayla:
1. `index.ts`'te export satırını bul (sınıf / tip / fn / hata).
2. Sınıf facade ise → `core/src/client/<Ad>.ts`; tip ise → `core/src/types.ts`; hata ise →
   `core/src/errors.ts`; yardımcı fn ise → `core/src/util/` veya `config/`.
3. Davranış `MorphRuntime`'a delege ediliyorsa → `runtime.ts`; oradan `tokens/` veya `http/`.

Önemli: facade'ler **durum tutmaz**; tek durum `MorphRuntime` içinde (`tokens`, `http`) ve
`StorageProvider`'dadır. `MorphClient.dispose()` runtime'ı kapatır (`MorphClient.ts:98`).

---

## 4. Adlandırma & konvansiyonlar

| Aradığın | Desen / Konum |
|---|---|
| Public facade metodu | `core/src/client/{MorphClient,HostClient,AuthHandle}.ts` |
| Config tipi / şekli | `core/src/types.ts` (`MorphConfig`=`providers[]`+`hosts[]`+`rootCallbackAuthId?`, `:113`) |
| auth id biçimi | `"provider/context"` (örn. `morph-auth/2fa`) veya çıplak `"provider"`; ayrıştırma `runtime.ts:57` (`parseAuthRef`) |
| Grant tipleri | `client_credentials` / `authorization_code` / `refresh_token` / token-exchange; `tokenLifecycle.ts:114-134`, tip `types.ts:239` |
| `$variable` enjeksiyonu | `config/interpolate.ts` (`interpolateString`); config string'lerinde `$var` |
| Hata sınıfı | `core/src/errors.ts` (`Unknown*Error`, `AuthError`, `TokenEndpointError`, `MorphHttpError`) |
| Storage anahtarı | context `tokenTypes.*.storage` (`scope/type/protection/key`), `types.ts:21`; I/O `tokens/tokenVault.ts` |
| Token başlığı | varsayılan `Authorization: Bearer <token>`; context `tokenTypes.*.header` ile özelleştirilebilir (`types.ts:16`) |
| Yardımcı fn | `core/src/util/` (jwt, expiry, duration, oauth*) |
| Davranış sözleşmesi (doküman) | `docs/api-reference.md`, `docs/token-lifecycle.md`, `docs/configuration.md` |

Kod stili: ESM (`.js` uzantılı import'lar TS'te — `import … from './x.js'`), `type`-only import'lar,
sınıf-tabanlı modüller. Kütüphane build vite ile (`core/vite.config.ts`), tipler vite-plugin-dts.

---

## 5. Kritik dosyalar (top-10)

| # | Dosya | Neden kritik |
|---|---|---|
| 1 | `core/src/index.ts` | Yayımlanan public API yüzeyi — her iz buradan başlar |
| 2 | `core/src/runtime.ts` | MorphRuntime koordinatör; config sorguları + OAuth flow orkestrasyonu |
| 3 | `core/src/tokens/tokenLifecycle.ts` | Tüm token mantığı: grant'lar, kilitler, resolveAccessToken, 401 recovery (~400 satır) |
| 4 | `core/src/http/hostPipeline.ts` | Host HTTP isteği, 401 recovery + tek retry, trace |
| 5 | `core/src/types.ts` | Public config & opsiyon arayüzleri (MorphConfig/MorphOptions/AuthContextConfig) |
| 6 | `core/src/client/MorphClient.ts` | Tüketicinin başlangıç noktası (`init`, `host`, `auth`) |
| 7 | `core/src/client/AuthHandle.ts` | Context başına token işlemleri (login/exchange/logout/refresh) |
| 8 | `core/src/config/validate.ts` | `validateAndIndexConfig` → `ResolvedMorphConfig` (hostByKey, contextByAuthId) |
| 9 | `core/src/tokens/tokenVault.ts` | Depolama I/O + anahtar interpolasyonu (StorageProvider'a delege) |
| 10 | `docs/architecture.md` | Tüm sistemin hizalı tasarım haritası (katman + bağımlılık grafı + kararlar) |
