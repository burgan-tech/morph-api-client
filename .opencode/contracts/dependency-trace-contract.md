# morph-api-client — Dependency Trace Contract

Uzmanın her task'ta okuduğu iz-sürme rehberi. Yollar repo köküne görelidir; kanıt `dosya:satır`.
Bu repo bir **TypeScript SDK/kütüphanesidir** — "giriş noktası" = public API; "dış servis" =
config ile verilen OAuth/host uçları + host app'in enjekte ettiği arayüzler.

---

## 1. Giriş noktaları (public API yüzeyi)

Paketin tek public giriş dosyası: **`core/src/index.ts`** (yayımlanan yüzey).

| Tür | Export | Kanıt |
|---|---|---|
| Facade sınıfı | `MorphClient` (`init`, `host`, `auth`, `getTokenStatus`, `getProviderMeta`, `getAuthorizationUrl`, `completeOAuthCallback`, `completeOAuthReturn`, `dispose`) | `core/src/index.ts:1`, `core/src/client/MorphClient.ts:6` |
| Facade sınıfı | `HostClient` (`get/post/put/patch/delete/head/options/request`) | `core/src/index.ts:2`, `core/src/client/HostClient.ts:4` |
| Facade sınıfı | `AuthHandle` (`submitCode`, `acquireWithClientCredentials`, `exchangeToken`, `setTokens`, `clearTokens`, `logout`, `hasValidToken`, `refreshTokens`, `peekTokens`, `getClaims`) | `core/src/index.ts:3`, `core/src/client/AuthHandle.ts` |
| Tipler | `MorphConfig`, `MorphOptions`, `MorphCallbacks`, `MorphResponse`, `TokenSet`, `StorageProvider`, `NetworkDelegate`, `HostConfig`, `ProviderConfig`, `AuthContextConfig`, … | `core/src/index.ts:5-27`, `core/src/types.ts` |
| Hatalar | `ConfigValidationError`, `UnknownHostError`, `UnknownProviderError`, `UnknownContextError`, `InvalidAuthForHostError`, `AuthError`, `TokenEndpointError`, `MorphHttpError` | `core/src/index.ts:29-38`, `core/src/errors.ts` |
| Yardımcı fn | `validateAndIndexConfig`, `decodeJwtPayload`, `getJwtExpirySeconds`, `getJwtSubject`, `buildOAuth2AuthorizationUrl`, `encode/decodeOAuthState`, `strip/cleanOAuthReturn…`, `normalizeLoopbackOrigin` | `core/src/index.ts:40-48` |
| Storage fabrikaları | `createBrowserSessionStorage`, `createBrowserLocalStorage` | `core/src/index.ts:49`, `core/src/storage/browserStorage.ts` |

Tüketici akışı: `MorphClient.init(config, options)` → `.host("key").get/post(...)` (kimlik
otomatik iliştirilir) ve `.auth("provider/context").login/exchange/logout(...)`.

> Bir public davranışı bulmak için: `index.ts`'te export'u gör → ilgili `core/src/<modül>`
> dosyasına git. Davranış sözleşmesi için `docs/api-reference.md` (1165 satır) hizalı kaynaktır.

---

## 2. İç bağımlılık grafı (modüller)

```
MorphClient (facade)  ──► MorphRuntime
HostClient            ──► MorphRuntime.http (HostPipeline)
AuthHandle            ──► MorphRuntime (parseAuthRef) + MorphRuntime.tokens (TokenLifecycle)
MorphRuntime          ──► TokenLifecycle (core/src/tokens/tokenLifecycle.ts)
MorphRuntime          ──► HostPipeline    (core/src/http/hostPipeline.ts)
HostPipeline          ──► TokenLifecycle  (resolveAccessToken, handle401Recovery)
TokenLifecycle        ──► TokenVault       (core/src/tokens/tokenVault.ts)
TokenVault            ──► StorageProvider  (host app enjekte eder)
```

Kanıt: `docs/architecture.md:72-82` (+ `runtime.ts:22-34` modülleri kurar; `MorphClient.ts:14`
`createRuntime`; `hostPipeline.ts:45,128` TokenLifecycle çağrıları). **Döngüsel bağımlılık yok;
`TokenLifecycle` yaprak modüldür.** Katmanlar: `client/` (facade) → `runtime.ts` (koordinatör)
→ `tokens/` + `http/` → `config/` & `util/` & `oauth/` & `storage/` (yardımcılar).

---

## 3. Dış bağımlılıklar

### 3a. Paketler
- **Runtime bağımlılığı YOK.** `core/package.json` yalnızca devDependencies içerir
  (`typescript`, `vite`, `vite-plugin-dts`); `"sideEffects": false`, ESM (`module`) + CJS
  (`main`) + d.ts çıktısı (`core/package.json`). Çalışma zamanında platformun `fetch`'i kullanılır.
- `poc/` ayrı bağımlılıklara sahiptir (Vue, Express) — SDK'nın değil, demo'nun bağımlılıkları.

### 3b. Dış servisler (hepsi config-driven — repoda hardcoded DEĞİL)
SDK'nın konuştuğu tüm uçlar runtime'da `MorphConfig` ile verilir; repo yalnız ÖRNEK config içerir.

| Uç | Ne zaman / nasıl | Kanıt |
|---|---|---|
| **OAuth2 token endpoint** (`token`, refresh, logout) | grant HTTP'leri; base = provider `tokenHttpBaseUrl` ya da `baseUrl` | `core/src/oauth/tokenHttp.ts`, `tokenLifecycle.ts:62` (`providerTokenHttpBase`), tip `types.ts:57` |
| **OAuth2 authorize endpoint** (tarayıcı redirect) | `getAuthorizationUrl` URL üretir; base = `authorizationBrowserBaseUrl` ya da `baseUrl` | `runtime.ts:186-208`, `util/oauthAuthorize.ts` |
| **token-exchange endpoint** (RFC 8693) | step-up / context'ler arası exchange | `tokenLifecycle.ts:25` (`urn:ietf:params:oauth:grant-type:token-exchange`), `:125` |
| **API host'ları** | `host(key).get/post(...)` → `HostPipeline.hostFetch` → tek `fetch()` | `http/hostPipeline.ts:33`, host tanımı `types.ts:99` |
| **Örnek/PoC uçları** | Keycloak realm + Express mock-api (yalnız geliştirme) | `poc/keycloak/`, `poc/mock-api/server.js`, `docs/poc/poc-config.json` |

### 3c. Host uygulamasının enjekte ettiği bağımlılıklar (depo dışı sınır)
SDK platform-bağımsızdır; şu uçlar `MorphClient.init`'te host app tarafından verilir
(`core/src/types.ts:249` `MorphOptions`):
- `storage: StorageProvider` — token kalıcılığı (read/write/delete/deleteByPrefix), `types.ts:206`.
- `callbacks: MorphCallbacks` — `onAuthRequired`/`onLogout`/`onTokenChange`, `types.ts:213`.
- `networkDelegate?: NetworkDelegate` — SSL pinning / proxy / client-cert; ilk istekte lazy çağrılır, `types.ts:235`, `docs/architecture.md:177-197`.
- `onTokenExchange?`, `onSignPayload?`, `onDecryptResponse?`, `onClientJwtAssertion?`, `onLog?`,
  `onHttpTrace?` — opsiyonel delege/gözlem kancaları, `types.ts:254-274`.

### 3d. Veritabanı
**Yok.** Bu bir istemci SDK'sıdır; kalıcılık `StorageProvider` arayüzü üzerinden host app'e
delege edilir (tarayıcıda örnek: `storage/browserStorage.ts` → `sessionStorage`/`localStorage`).

---

## 4. İz sürme algoritması (adım adım)

"`<X>` davranışı / `<X>` nereden geliyor" sorusunu şöyle çöz:

1. **Public yüzeyden başla.** İlgili çağrıyı `core/src/index.ts`'te bul (sınıf mı, fn mi).
   Tüketici metodu ise (`host().get`, `auth().login`…) facade dosyasına git
   (`client/MorphClient.ts` / `HostClient.ts` / `AuthHandle.ts`).
2. **Koordinatöre in.** Facade neredeyse her şeyi `MorphRuntime`'a delege eder
   (`MorphClient.ts:14` createRuntime; `HostClient` → `rt.http`; `AuthHandle` → `rt.tokens`).
3. **Doğru modüle dağıl:**
   - HTTP/istek/yanıt/401 → `http/hostPipeline.ts`.
   - token al/yenile/exchange/çöz/logout → `tokens/tokenLifecycle.ts` (+ depolama `tokens/tokenVault.ts`).
   - config doğrulama/indeksleme, `$variable` → `config/validate.ts`, `config/interpolate.ts`.
   - OAuth URL / state / dönüş → `util/oauthAuthorize.ts`, `util/oauthState.ts`, `util/oauthReturn.ts`.
   - JWT/expiry/duration → `util/jwt.ts`, `util/expiry.ts`, `util/duration.ts`.
4. **Sınırı belirle.** Çağrı bir host app kancasına (`StorageProvider`/`MorphCallbacks`/
   `onTokenExchange`…) veya config ile gelen bir endpoint'e ulaşıyorsa, zincir repoda biter →
   `external_dependencies`'e yaz (DURDU: depo dışı).
5. **Doküman ile çapraz-doğrula.** `docs/`'ta ilgili bölüm davranışı açıklıyorsa referans ver,
   ama davranış iddiasını kod dosya:satır ile destekle.

---

## 5. DURDU kriterleri

İz aşağıdaki durumlarda bu repoda biter; `DURDU: <somut gerekçe>` yaz:

- **Config ile gelen hedef:** Provider/context/host tanımı, endpoint, scope veya `$variable`
  değeri repoda yoktur — `MorphConfig` runtime'da dışarıdan verilir (`MorphClient.ts:9`). Hangi
  config alanının belirlediğini söyle; değeri için tüketici uygulamayı işaret et.
- **Host app kancası:** `StorageProvider`/`NetworkDelegate`/`MorphCallbacks`/`onTokenExchange`/
  `onSignPayload`/`onDecryptResponse`/`onClientJwtAssertion` çağrısı host uygulamasındadır →
  implementasyon repoda yok.
- **Platform `fetch`/tarayıcı:** Ağ I/O platformun `fetch`'ine, depolama tarayıcı `Storage`'ına
  düşer (`storage/browserStorage.ts`); bunun ötesi platform runtime'ıdır.
- **PoC/örnek sınırı:** İz `poc/` (Vue app, Keycloak, mock-api) içine giriyorsa, bu ÜRÜN değil
  ÖRNEKtir — SDK davranışı için kanıt sayma; "örnek tüketici" olarak işaretle.
- **Dart/Flutter paritesi:** Plan var ama bu repo TS'tir (`docs/architecture.md:5`); Dart
  tarafı bu repoda yok → repo dışı.
