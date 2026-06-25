# morph-api-client — Kritik Akışlar

SDK'nın en sık sorulan akışları, uçtan uca (public giriş → modüller → dış uç). Her adım
`dosya:satır` kanıtlı. Bu dosya kendi içinde bağımsızdır. Yollar repo köküne göredir.

Genel desen: `MorphClient.init(config, options)` → facade (`host()`/`auth()`) → `MorphRuntime`
→ `HostPipeline` veya `TokenLifecycle` → config ile verilen OAuth/host ucu (repoda hardcoded değil).

---

## 1. Kimlikli host isteği (`host(key).get/post(...)`) — merkezî akış
1. **Giriş:** `MorphClient.host("main-api")` → `HostClient` döner (`client/MorphClient.ts:17`).
   `.get(path, opts)` → `rt.http.hostFetch(...)` (`client/HostClient.ts:18`).
2. **Auth çözümü:** `HostPipeline.hostFetch` kullanılacak context'i belirler (host `defaultAuth`
   veya istekteki `auth` override), `host.allowedAuth`'a göre doğrular, sonra
   `TokenLifecycle.resolveAccessToken(authId, ref, 'http')` ile geçerli access token alır
   (`http/hostPipeline.ts:33,45`).
3. **İstek kurma + fetch:** URL = host `baseUrl` + path; header'lar (`$variable` interpolasyonlu) +
   `Authorization: Bearer <token>` birleştirilir; tek `fetch()` timeout/abort ile (`fetchWithTrace`
   `http/hostPipeline.ts:76`). Her denemede `MorphHttpTraceEvent` `onHttpTrace` ile yayılır
   (`Authorization` redakte) (`types.ts:305`).
4. **401 recovery:** Yanıt 401 ve `recoveryPolicy.onUnauthorized === 'refresh'` ise
   `handle401Recovery` (kilit içinde refresh) → `resolveAccessToken` tekrar → istek **bir kez**
   yeniden denenir (`http/hostPipeline.ts:127-131`).
5. **401 delegate:** Hâlâ 401 ve policy `'delegate'` ise `onAuthRequired` tetiklenir ve `AuthError`
   fırlatılır (`http/hostPipeline.ts:135`).
6. **Yanıt:** `Content-Type: application/json` ise gövde JSON parse edilir, opsiyonel
   `onDecryptResponse`; `MorphResponse<T>` döner (`docs/architecture.md:98`, `types.ts:292`).
Dış uç: config'teki host `baseUrl` (depo dışı).

---

## 2. access token çözümü (resolveAccessToken) — token mantığının kalbi
`TokenLifecycle.resolveAccessToken(authId, ref, purpose)` bir context için geçerli access
token'ı döndürür: vault'tan yükler, **expiry/refreshPolicy'ye göre proaktif** yeniler ya da
gerekli grant'ı çalıştırır. HostPipeline (`:45,:129`) ve exchange akışı (`tokenLifecycle.ts:174`)
bunu kullanır. Proaktif yenileme: token expire OLMADAN, `refreshPolicy.refreshBeforeExpiry`
penceresinde yenilenir (`docs/architecture.md:16`, tip `types.ts:69`). Eşzamanlılık: her authId
için `withLock` ile tek-uçuş garanti (`tokenLifecycle.ts:51`).

---

## 3. Interaktif giriş (authorization_code / 1fa, harici provider)
1. **Authorize URL:** `MorphClient.getAuthorizationUrl(authId)` → `runtime.ts:186` →
   `buildOAuth2AuthorizationUrl` (`util/oauthAuthorize.ts`); `state` = `encodeOAuthState(authId)`
   (`runtime.ts:197`). Host app kullanıcıyı bu URL'e yönlendirir (SDK UI açmaz).
2. **Dönüş:** IdP `?code=&state=` ile geri döner. Host app `MorphClient.completeOAuthCallback({code,state,...})`
   çağırır → `runtime.ts:210`. State decode edilir (`decodeOAuthState`), authId bulunur,
   `tokens.submitCode(authId, ref, code)` ile kod token'a çevrilir (`runtime.ts:225`).
   Uygulama kökünde (`/?code=`) ise `completeOAuthReturn()` kısayolu (`runtime.ts:241`); state yoksa
   `rootCallbackAuthId` kullanılır (`runtime.ts:230`).
3. **Kod→token:** `TokenLifecycle.submitCode` `authorization_code` grant'ını `executeGrant` ile
   çalıştırır, PKCE `codeVerifier` opsiyonel (`tokens/tokenLifecycle.ts:135,152`). Token vault'a
   yazılır + `onTokenChange` bildirilir.
`AuthHandle` eşdeğeri: `auth(authId).submitCode(code, {codeVerifier})` (`client/AuthHandle.ts:13`).
Dış uç: config'teki provider authorize + token endpoint.

---

## 4. Makine kimliği (client_credentials / device context)
- `auth(authId).acquireWithClientCredentials()` (`client/AuthHandle.ts:20`) →
  `TokenLifecycle.acquireWithClientCredentials` (`tokenLifecycle.ts:162`) →
  `fetchClientCredentialsSet` → `executeGrant(..., 'client_credentials', ...)` (`:120`).
- `MorphOptions.autoAcquireNonInteractive=true` ise, `interaction:'non-interactive'` context'lerde
  `onAuthRequired` anında SDK bunu otomatik yapar (`types.ts:273`).
Kullanım: pre-login / public içerik çağrıları (device context, `docs/architecture.md:119`).

---

## 5. Step-up / token exchange (2fa) — RFC 8693
1. `auth(sourceAuthId).exchangeToken(targetAuthId)` (`client/AuthHandle.ts:27`) →
   `TokenLifecycle.exchangeToken` (`tokenLifecycle.ts:170`): önce kaynak context'in access
   token'ı `resolveAccessToken` ile alınır (`:174`), sonra `executeTokenExchange` hedef context'e
   exchange grant'ını çalıştırır (`:125`, grant tipi `urn:ietf:params:oauth:grant-type:token-exchange`
   `:25`).
2. Hangi context hangi kaynaktan exchange edilebilir? `token.exchangeSource` (string|array) belirler;
   `getExchangeSources`/`getExchangeTargets` UI için listeler (`runtime.ts:166-182`, tip `types.ts:64`).
- İsteğe bağlı `onTokenExchange` kancası verilirse exchange host app'e delege edilebilir
  (`types.ts:254`).
Dış uç: config'teki token-exchange endpoint.

---

## 6. token yenileme & logout
- **Manuel refresh:** `auth(authId).refreshTokens()` (`client/AuthHandle.ts:72`) →
  `refreshTokensManual` → `executeRefresh` (`tokenLifecycle.ts:114`, `refresh_token` grant).
- **Otomatik refresh:** host isteğinde 401 → `handle401Recovery` (akış #1, adım 4); ve proaktif
  pencere (akış #2).
- **Logout:** `auth(authId).logout(reason)` (`client/AuthHandle.ts:55`) → context için
  `tokens.logout`, çıplak provider için `logoutProvider` (`:59-62`); config'te `logout.endpoint`
  varsa çağrılır, vault temizlenir, `onLogout(reason)` bildirilir (sebepler `types.ts:1`).

---

## 7. Ağ I/O dışında: config doğrulama (init anı)
`MorphClient.init` → `createRuntime` → `validateAndIndexConfig(config)` (`runtime.ts:262`,
`config/validate.ts`): config doğrulanır ve indekslenir (`hostByKey`, `contextByAuthId`,
`contextsByProvider`); hata varsa `ConfigValidationError`. Çalışma zamanı sorguları
(`getHost`, `parseAuthRef`, `getTokenStatus`) bu indeks üzerinden döner — hiçbir ağ çağrısı yok
(`runtime.ts:105` `getTokenStatus` salt vault + JWT decode).

---

## Notlar
- Tüm bu akışlarda **endpoint/scope/policy değerleri config'ten** gelir; repo yalnız ÖRNEK config
  içerir (`poc/keycloak/morph-realm.json`, `docs/poc/poc-config.json`). Üretim config'i tüketici
  uygulamadadır.
- `docs/token-lifecycle.md` token akışlarının, `docs/api-reference.md` metot sözleşmelerinin
  hizalı kaynağıdır; davranış iddiasını yine de kod dosya:satır ile destekle.
