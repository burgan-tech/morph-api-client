import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

/** Merge VITE_* from `poc/.env` and `poc/ts-vue/.env`; ts-vue wins only for non-empty values. */
function mergedViteEnv(mode: string): Record<string, string> {
  const tsVueRoot = __dirname
  const pocRoot = path.resolve(tsVueRoot, '..')
  const fromPoc = loadEnv(mode, pocRoot, 'VITE_')
  const fromVue = loadEnv(mode, tsVueRoot, 'VITE_')
  const out = { ...fromPoc }
  for (const [k, v] of Object.entries(fromVue)) {
    if (v !== '') out[k] = v
  }
  return out
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const viteEnv = mergedViteEnv(mode)
  const defineEnv = Object.fromEntries(
    Object.entries(viteEnv).map(([k, v]) => [`import.meta.env.${k}`, JSON.stringify(v)]),
  )

  const keycloakOrigin = viteEnv.VITE_KEYCLOAK_ORIGIN ?? 'http://localhost:8080'

  const repoRoot = path.resolve(__dirname, '../..')

  return {
    envDir: __dirname,
    define: defineEnv,
    plugins: [vue()],
    server: {
      // HMR must use the same hostname as the page (e.g. localhost vs 127.0.0.1) or the WS fails and
      // the injected client throws in a tight loop: Cannot read properties of undefined (reading 'send').
      strictPort: true,
      hmr: { host: 'localhost' },
      fs: {
        allow: [__dirname, path.resolve(__dirname, '..'), repoRoot],
      },
      proxy: {
        '/__keycloak': {
          target: keycloakOrigin,
          changeOrigin: true,
          secure: false,
          rewrite: (pathStr) => pathStr.replace(/^\/__keycloak/, ''),
        },
        // Browser → https://oauth2.googleapis.com/token is CORS-blocked; proxy like Keycloak.
        '/__google-oauth': {
          target: 'https://oauth2.googleapis.com',
          changeOrigin: true,
          secure: true,
          rewrite: (pathStr) => pathStr.replace(/^\/__google-oauth/, ''),
        },
      },
    },
  }
})
