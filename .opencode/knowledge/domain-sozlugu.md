# morph-api-client — Domain Sözlüğü

SDK'yı okurken gerçekten gereken terimler. Kanıtsız anlamlar `DOĞRULANMADI:` ile işaretli.
Bu dosya kendi içinde bağımsızdır. Yollar repo köküne göredir.

## Çekirdek kavramlar
- **Provider** — bir auth sunucusu (OAuth2 IdP). `key`, `type:'oauth2'`, `baseUrl` ve altında
  `contexts[]` taşır; context'lere paylaşılan config'i miras verir (`types.ts:78`,
  `docs/architecture.md:100`).
- **Context (auth context)** — bir provider altında bağımsız bir token yaşam döngüsü
  (kendi client kimliği, grant'ı, depolama ve recovery politikası). `AuthContextConfig`
  (`types.ts:42`). Örnekler: device / 1fa / 2fa / google.
- **Host** — uygulamanın çağırdığı API sunucusu: `baseUrl`, `allowedAuth[]` (izinli auth id'ler),
  `defaultAuth`, opsiyonel `headers` (`types.ts:99`).
- **auth id** — `"provider/context"` (örn. `morph-auth/2fa`) ya da çıplak `"provider"`.
  Ayrıştırma `runtime.ts:57` (`parseAuthRef`). Kimlik bu string ile seçilir.
- **MorphConfig** — tüm davranışı tanımlayan kök config: `providers[]` + `hosts[]` +
  opsiyonel `rootCallbackAuthId` (`types.ts:113`). **Runtime'da dışarıdan verilir, repoda değil.**
- **MorphRuntime** — ince koordinatör; config sorguları + OAuth flow; `tokens` (TokenLifecycle)
  ve `http` (HostPipeline) modüllerini barındırır (`runtime.ts:22`).

## Context tipleri (PoC örneğindeki ayrım — `docs/architecture.md:117-127`)
- **device** — makine düzeyi kimlik; non-interactive (client_credentials); kalıcı, device-scope;
  giriş yapılmamış kullanıcı/pre-login çağrıları için.
- **1fa** — birinci faktör kullanıcı kimliği; interactive (authorization_code); user-scope, kalıcı;
  giriş yapmış oturum.
- **2fa** — step-up; 1fa'dan token exchange ile; session timeout'lara tabi.
- **google** (vb.) — harici OAuth2 provider; tam authorization_code + PKCE; session-scope.
- Not: SDK context'ler arasında hiyerarşi DAYATMAZ; her biri bağımsız çalışır; device→1fa→2fa
  ilerlemesi host app'in akış mantığı + `delegateMetadata.grantHint` ile ifade edilir (`:127`).

## Grant tipleri (OAuth2)
- **client_credentials** — `fetchClientCredentialsSet` (`tokenLifecycle.ts:120`).
- **authorization_code** — `submitCode` (`tokenLifecycle.ts:135`); opsiyonel PKCE `codeVerifier`.
- **refresh_token** — `executeRefresh` (`tokenLifecycle.ts:114`).
- **token-exchange (RFC 8693)** — `executeTokenExchange` (`tokenLifecycle.ts:125`); grant URI
  `urn:ietf:params:oauth:grant-type:token-exchange` (`:25`). Tüm grant'lar tek `executeGrant`
  üzerinden gider (`:88`). Tip birliği: `TokenExchangeGrant` (`types.ts:239`).

## Policy / config alanları
- **refreshPolicy** — `strategy` + `refreshBeforeExpiry` (proaktif yenileme penceresi, `types.ts:69`).
- **recoveryPolicy** — `onUnauthorized` (`'refresh'` | `'delegate'`), `onRefreshFail` (`types.ts:37`);
  401 davranışını belirler (`hostPipeline.ts:127,135`).
- **tokenTypes** — context başına access/refresh token tanımı: `format` (`'jwt'` varsayılan |
  `'opaque'`), `header` (`name`/`scheme`, varsayılan `Authorization`/`Bearer`), `expiryPolicy`,
  `maxTtl`, `storage` (`types.ts:28`).
- **storage (StorageConfig)** — `scope` / `type` / `protection` / `key` (`types.ts:21`); fiziksel
  I/O `StorageProvider` ile host app'te.
- **delegateMetadata** — `workflow` / `grantHint` / `interaction`
  (`'interactive'|'non-interactive'|'redirect'`) (`types.ts:5`); SDK token çözemeyince host app'e
  ne gerektiğini bu meta ile söyler.
- **networkPolicy** — `timeout` + `retry` (`types.ts:11`).
- **`$variable` interpolasyonu** — config string'lerindeki `$ad` değerleri `MorphOptions.variables`
  ile doldurulur (`config/interpolate.ts`, `interpolateString`).
- **tokenHttpBaseUrl / authorizationBrowserBaseUrl** — token-HTTP ve tarayıcı-authorize için
  `baseUrl`'den farklı origin (same-origin CORS/dev proxy senaryoları) (`types.ts:83-93`).

## Host app'in sağladığı arayüzler/kancalar (`MorphOptions`, `types.ts:249`)
- **StorageProvider** — token kalıcılığı (`read/write/delete/deleteByPrefix`, `types.ts:206`).
- **MorphCallbacks** — `onAuthRequired` / `onLogout` / `onTokenChange` (`types.ts:213`).
- **NetworkDelegate** — `getNetworkConfig(hostname)` → SSL pin / proxy / client-cert; ilk istekte
  lazy (`types.ts:235`, `docs/architecture.md:182`).
- **onTokenExchange / onSignPayload / onDecryptResponse / onClientJwtAssertion / onLog / onHttpTrace**
  — opsiyonel delege & gözlem kancaları (`types.ts:254-274`).

## Kısaltmalar / dış terimler
- **OAuth2 / OIDC** — yetkilendirme protokolü; bu SDK'nın tüm provider'ları `type:'oauth2'`.
- **PKCE** — authorization_code akışında code challenge (`pkce.codeChallengeMethod`, `types.ts:68`).
- **RFC 8693** — OAuth token exchange standardı (step-up/2fa).
- **JWT** — access/refresh token formatı (varsayılan); decode `util/jwt.ts`
  (`decodeJwtPayload`/`getJwtExpirySeconds`/`getJwtSubject`).
- **IdP** — Identity Provider (PoC'te Keycloak; `docs/poc/google-setup.md` ile Google).
- **PoC** — `poc/` altındaki kanıtlama/demo (Vue app + Keycloak realm + Express mock-api); **ürün değil**.
- **Morph** — SDK'nın/ürünün adı; `MorphClient`, `MorphRuntime`, `MorphConfig` hep bu önekli.
- **DOĞRULANMADI:** "morph-auth" provider adı, host `main-api`/`google-api` gibi anahtarlar
  yalnız ÖRNEK config/dokümandan gelir (`docs/architecture.md:104-147`); üründe farklı olabilir.
