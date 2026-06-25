# morph-api-client — Bilinen Tuzaklar

Yanıltıcı varsayımlar, "X gibi görünür ama Y'dir" durumları, ölü/örnek bölgeler. Her madde
kanıtlı ya da `DOĞRULANMADI:` etiketli. Emin olmadığını tespit gibi yazma. Kendi içinde bağımsız.

---

## 1. Config repoda YOK — endpoint'ler hardcoded değil (en sık hata)
Provider/context/host tanımları, OAuth endpoint'leri, scope'lar ve `$variable` değerleri
**runtime'da dışarıdan** `MorphClient.init(config, options)` ile verilir (`core/src/client/MorphClient.ts:9`,
tip `core/src/types.ts:113`). "Bu istek şu URL'e gider" derken: URL config'teki host/provider
`baseUrl`'ünden gelir; repoda sabit değildir. Repodaki tek config **ÖRNEKTİR**
(`poc/keycloak/morph-realm.json`, `docs/poc/poc-config.json`) — ürün config'i tüketici uygulamadadır.

## 2. `poc/` ÜRÜN değil — SDK davranışına kanıt sayma
`poc/ts-vue` (Vue demo), `poc/keycloak` (Docker realm + script'ler), `poc/mock-api` (Express)
yalnız kanıtlama/demo'dur. SDK davranışını `core/src/`'tan kanıtla; `poc/` yalnız "tüketici nasıl
kullanır" örneğidir. Aynı şekilde `core/dist/` (vite build çıktısı) ve `node_modules/` kanıt değildir.

## 3. SDK ayrı bir "token manager" DEĞİL — HTTP client'ın KENDİSİDİR
Yaygın yanlış model: "token'ı al, sonra başka bir HTTP client'a ver". Hayır — her host isteği
SDK'nın auth pipeline'ından geçer; token çözme/iliştirme/yenileme `host(...).get/post` içinde
transparan olur (`docs/architecture.md:7`, `http/hostPipeline.ts:33-45`). Token'ı "elle alıp
dışarı vermek" tipik akış değildir (`peekTokens` debug içindir).

## 4. SDK UI render etmez / interaktif akış başlatmaz — delege eder
Login ekranı, biometrik, WebView redirect SDK'da yoktur. SDK token çözemeyince host app'e
`onAuthRequired(authId, delegateMetadata)` ile **ne gerektiğini** söyler; **nasıl** yapılacağına
host app karar verir (`docs/architecture.md:14,209-211`, `types.ts:213`). `getAuthorizationUrl`
sadece URL üretir; yönlendirmeyi host app yapar (`runtime.ts:186`).

## 5. authId iki biçimlidir — `provider/context` vs çıplak `provider`
`parseAuthRef` ikisini ayırır (`runtime.ts:57`): tek-segment = provider (logout/provider-geneli),
iki-segment = belirli context. `exchangeToken`/`refreshTokens` gibi metotlar **context** (iki-segment)
auth id ister; provider verilirse hata fırlatır (`client/AuthHandle.ts:29,74`). Karıştırma.

## 6. `getTokenStatus` ağ yapmaz, refresh tetiklemez
Salt vault snapshot + JWT decode'dur; `onAuthRequired` çağırmaz, token yenilemez
(`runtime.ts:105`, `types.ts:180`). "Token geçerli mi?" için canlı garanti değil; `accessLikelyValid`
yalnız depolanan `expiresAt`/JWT `exp`'e bakar. Gerçek geçerlilik ancak istek anında
`resolveAccessToken` ile sağlanır.

## 7. `claims`/`refreshClaims` hassastır + opaque token decode edilmez
`MorphTokenStatus.claims` access token JWT payload'ıdır — debug amaçlı, **hassas** (`types.ts:194`).
Token `format:'opaque'` ise decode edilmez, `claims` null kalır (`types.ts:29`). "claims hep dolu"
varsayma; format `tokenTypes.access.format`'a bağlı.

## 8. 401 yeniden deneme YALNIZ BİR KEZ + policy'ye bağlı
401 sonrası otomatik refresh+retry yalnız `recoveryPolicy.onUnauthorized === 'refresh'` ise ve
**tek sefer** olur (`http/hostPipeline.ts:127-131`). Policy `'delegate'` ise retry yok; `onAuthRequired`
+ `AuthError` (`:135`). Policy yoksa 401 olduğu gibi döner. "SDK sonsuza dek dener" yanlış.

## 9. Sıfır runtime bağımlılığı — `fetch` platformdan
`core/package.json` yalnız devDeps içerir (typescript/vite/vite-plugin-dts); SDK çalışma zamanında
platformun global `fetch`'ini kullanır. "Şu HTTP kütüphanesini kullanıyor" deme — kullanmıyor.
Depolama da `StorageProvider` ile enjekte; tarayıcı örneği `storage/browserStorage.ts`.

## 10. Dart/Flutter paritesi PLAN — bu repo TS'tir
`docs/architecture.md:5` Dart/Flutter paritesini "planlı" der; bu repoda Dart kodu YOKTUR.
"morph-api-client Flutter tarafı" sorusu bu repo dışıdır (ayrı/ileride repo). Bu repodaki her şey
`core/src/` altında TypeScript'tir.

## 11. TS import'ları `.js` uzantılıdır (ESM) — yazım hatası değil
`import { X } from './foo.js'` görünce şaşırma; bu `"type":"module"` ESM çıktısı için doğru TS
yazımıdır (kaynak `foo.ts`, derlenince `foo.js`). `index.ts` export'ları hep `.js` uzantılı
(`core/src/index.ts`).

## 12. Repo adı ile paket adı farklı
Monorepo kökü `package.json` adı `morph-api-client-repo` (private, `:2`); **yayımlanan paket**
`core/package.json` içinde `morph-api-client`'tır (`:2`). "morph-api-client" denince tüketicinin
import ettiği paket = `core/`. Demo script'leri (`dev`/`build:vue`) kökteki repo'nundur, paketin değil.
