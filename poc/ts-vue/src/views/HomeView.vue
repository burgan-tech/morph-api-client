<script setup lang="ts">
import { ref, reactive, watch, onMounted, computed } from 'vue';
import type { MorphTokenStatus } from 'morph-api-client';
import JsonTreeView from '../components/JsonTreeView.vue';
import PocSimulationPanel from '../components/PocSimulationPanel.vue';
import { morph, getWebSimDeviceIdentity, pocGetAuthorizationUrl, syncOAuthRedirectUrisFromBrowser } from '../morph';
import { hostHttpTraces, clearHostHttpTraces } from '../hostHttpTraceStore';
import { getPocSimulationConfig } from '../pocSimulation';
import {
  collectPlaygroundSteps,
  runPocSimStep,
  isLogoutStep,
  type PlaygroundStepRef,
} from '../pocSimulationRunner';
import { evalPocSimCondition } from '../pocSimulationWhen';
import { simulatorProbe404 } from '../pocSimUi';

type ContextAction = {
  id: string;
  label: string;
  disabled?: boolean;
  title?: string;
  primary?: boolean;
  run: () => void | Promise<void>;
};

/** Matches `docs/poc/poc-config.json` provider/context for the PoC Google IdP row. */
const GOOGLE_AUTH_ID = 'google-auth/google';
const googleProviderReady = morph.isProviderEnvReady(GOOGLE_AUTH_ID.split('/')[0]!);
const webSim = getWebSimDeviceIdentity();
const pocSimConfig = getPocSimulationConfig();
const playgroundStepRefs = computed(() => collectPlaygroundSteps(pocSimConfig));

const busy = ref(false);
const message = ref('');
const apiOutput = ref('');
const tokenStatus = ref<MorphTokenStatus[]>([]);

const mockApiModalOpen = ref(false);
const expandedHttpTraceId = ref<string | null>(null);
const httpTraceDetailTab = ref<'request' | 'response' | 'body'>('request');

const httpTraceRows = computed(() => hostHttpTraces.value);

function openMockApiModal() {
  mockApiModalOpen.value = true;
}

function closeMockApiModal() {
  mockApiModalOpen.value = false;
}

function toggleHttpTraceRow(id: string) {
  expandedHttpTraceId.value = expandedHttpTraceId.value === id ? null : id;
  httpTraceDetailTab.value = 'request';
}

function traceBodyForTree(b: unknown): unknown {
  if (b === null || b === undefined) return { _note: 'empty body' };
  if (typeof b === 'object') return b;
  return { _text: String(b) };
}

const modalOpen = ref(false);
const modalRow = ref<MorphTokenStatus | null>(null);
/** JWT dialog: access vs refresh payload (signature not verified). */
const modalTokenTab = ref<'access' | 'refresh'>('access');
const modalBusy = ref(false);

const STATUS_LABELS: Record<string, string> = {
  'morph-auth/device': 'Device',
  'morph-auth/2fa': 'Login (2fa)',
  'morph-auth/1fa': 'Session (1fa)',
  'google-auth/google': 'Google',
};

function labelFor(row: MorphTokenStatus): string {
  return STATUS_LABELS[row.authId] ?? row.authId;
}

function labelForAuthId(authId: string): string {
  return STATUS_LABELS[authId] ?? authId;
}

function expSeconds(row: MorphTokenStatus): number | undefined {
  return row.jwtExp ?? row.expiresAt;
}

function formatExp(row: MorphTokenStatus): string {
  const sec = expSeconds(row);
  if (sec === undefined) return '—';
  const d = new Date(sec * 1000);
  const iso = d.toISOString().replace('T', ' ').slice(0, 19) + 'Z';
  const left = sec - Math.floor(Date.now() / 1000);
  if (left <= 0) return `${iso} (expired ${Math.abs(left)}s ago)`;
  return `${iso} (in ${left}s)`;
}

function statusLine(row: MorphTokenStatus): string {
  if (!row.hasAccessToken) return '—';
  if (!row.accessLikelyValid) return 'expired';
  return 'OK';
}

async function refreshStatus() {
  tokenStatus.value = await morph.getTokenStatus();
}

function openJwtPreview(row: MorphTokenStatus) {
  modalRow.value = row;
  modalTokenTab.value = 'access';
  modalOpen.value = true;
}

function closeModal() {
  modalOpen.value = false;
  modalRow.value = null;
}

function formatRefreshExp(row: MorphTokenStatus): string {
  if (!row.hasRefreshToken) return '—';
  const sec = row.refreshJwtExp;
  if (sec === undefined) return 'opaque token (no JWT exp)';
  const d = new Date(sec * 1000);
  const iso = d.toISOString().replace('T', ' ').slice(0, 19) + 'Z';
  const left = sec - Math.floor(Date.now() / 1000);
  if (left <= 0) return `${iso} (expired ${Math.abs(left)}s ago)`;
  return `${iso} (in ${left}s)`;
}

function canIdpRefresh(row: MorphTokenStatus): boolean {
  return row.hasRefreshToken || row.grantHint === 'client_credentials';
}

const modalJson = computed(() => {
  const r = modalRow.value;
  if (!r) return '';
  if (modalTokenTab.value === 'access') {
    if (r.decodeError) return JSON.stringify({ decodeError: r.decodeError }, null, 2);
    if (r.claims) return JSON.stringify(r.claims, null, 2);
    return JSON.stringify({ note: 'No access token or not a decodable JWT' }, null, 2);
  }
  if (!r.hasRefreshToken) {
    return JSON.stringify({ note: 'No refresh token in storage' }, null, 2);
  }
  if (r.refreshDecodeError) {
    return JSON.stringify({ refreshDecodeError: r.refreshDecodeError }, null, 2);
  }
  if (r.refreshClaims) return JSON.stringify(r.refreshClaims, null, 2);
  return JSON.stringify(
    {
      note: 'Refresh token is present but opaque (not a JWT) — common with some IdPs',
    },
    null,
    2,
  );
});

async function idpRefreshFromModal() {
  const row = modalRow.value;
  if (!row || !canIdpRefresh(row)) return;
  modalBusy.value = true;
  message.value = '';
  try {
    await morph.auth(row.authId).refreshTokens();
    await refreshStatus();
    const id = row.authId;
    modalRow.value = tokenStatus.value.find((r) => r.authId === id) ?? null;
    if (!modalRow.value) closeModal();
  } catch (e) {
    message.value = e instanceof Error ? e.message : String(e);
  } finally {
    modalBusy.value = false;
  }
}

onMounted(async () => {
  syncOAuthRedirectUrisFromBrowser();
  const kc = await morph.completeOAuthReturn();
  if (kc.status !== 'none') {
    message.value = kc.message ?? '';
  }
  await refreshStatus();
});

async function runAcquire(authId: string) {
  busy.value = true;
  message.value = '';
  try {
    await morph.auth(authId).acquireWithClientCredentials();
    message.value = `Token acquired (${authId}).`;
    await refreshStatus();
  } catch (e) {
    message.value = e instanceof Error ? e.message : String(e);
  } finally {
    busy.value = false;
  }
}

function startLogin() {
  window.location.href = pocGetAuthorizationUrl('morph-auth/2fa');
}

function playgroundHintForBlock(blockId?: string): string {
  if (blockId === 'google_verify') {
    return 'Condition not met: configure Google OAuth and sign in (google-auth/google).';
  }
  if (blockId === 'probe_404') {
    return 'Condition not met: enable “404 probe” in the Simulation section.';
  }
  return 'Condition not met for this step.';
}

function playgroundButtonDisabled(item: PlaygroundStepRef): boolean {
  if (item.step.type === 'host' && item.step.auth === GOOGLE_AUTH_ID && !googleProviderReady) return true;
  return false;
}

function playgroundButtonTitle(item: PlaygroundStepRef): string | undefined {
  if (item.step.type === 'host' && item.step.auth === GOOGLE_AUTH_ID && !googleProviderReady) {
    return 'Configure VITE_GOOGLE_* in .env (see docs/poc/google-setup.md)';
  }
  return undefined;
}

async function runPlaygroundStep(item: PlaygroundStepRef) {
  busy.value = true;
  apiOutput.value = '';
  message.value = '';
  try {
    if (item.when !== undefined) {
      const ok = await evalPocSimCondition(item.when, {
        morph,
        isProviderEnvReady: (pk) => morph.isProviderEnvReady(pk),
        getProbe404: () => simulatorProbe404.value,
      });
      if (!ok) {
        message.value = playgroundHintForBlock(item.blockId);
        return;
      }
    }
    const tick = Date.now();
    const r = await runPocSimStep(morph, pocSimConfig, item.step, tick);
    if (r.body !== undefined && r.body !== null) {
      apiOutput.value =
        typeof r.body === 'object' ? JSON.stringify(r.body, null, 2) : String(r.body);
    } else {
      apiOutput.value = '';
    }
    const failed =
      r.status === 'AUTH' ||
      r.status === 'ERR' ||
      r.status === 'NET' ||
      (typeof r.status === 'number' && r.status >= 400);
    if (failed) {
      message.value = r.detail || String(r.status);
    } else if (isLogoutStep(item.step)) {
      message.value = r.detail;
      await refreshStatus();
    } else {
      message.value = '';
    }
  } catch (e) {
    message.value = e instanceof Error ? e.message : String(e);
  } finally {
    busy.value = false;
  }
}

function startGoogle() {
  message.value = '';
  try {
    window.location.href = pocGetAuthorizationUrl(GOOGLE_AUTH_ID);
  } catch (e) {
    message.value = e instanceof Error ? e.message : String(e);
  }
}

/** Group contexts by provider key for scannable UI. */
const statusByProvider = computed(() => {
  const m = new Map<string, MorphTokenStatus[]>();
  for (const r of tokenStatus.value) {
    const list = m.get(r.providerKey) ?? [];
    list.push(r);
    m.set(r.providerKey, list);
  }
  return [...m.entries()].sort(([a], [b]) => a.localeCompare(b));
});

/** Standalone provider-config dialog (header “Config” button). */
const providerOnlyModalKey = ref<string | null>(null);

function openProviderConfigModal(providerKey: string) {
  providerOnlyModalKey.value = providerKey;
}

function closeProviderConfigModal() {
  providerOnlyModalKey.value = null;
}

const providerOnlyModalData = computed(() => {
  const pk = providerOnlyModalKey.value;
  if (!pk) return null;
  try {
    return morph.getProviderMeta(pk);
  } catch (e) {
    return { _error: e instanceof Error ? e.message : String(e) };
  }
});

const modalTreeData = computed(() => {
  try {
    return JSON.parse(modalJson.value) as unknown;
  } catch {
    return { _note: 'Non-JSON payload', _raw: modalJson.value };
  }
});

function buildActionsForRow(row: MorphTokenStatus): ContextAction[] {
  const out: ContextAction[] = [];
  const gh = row.grantHint;

  if (gh === 'client_credentials') {
    out.push({
      id: `acq-${row.authId}`,
      label: 'Acquire token',
      run: () => runAcquire(row.authId),
    });
  }

  if (gh === 'authorization_code') {
    if (row.providerKey === 'morph-auth') {
      out.push({ id: `login-${row.authId}`, label: 'Keycloak login', run: startLogin });
    }
    if (row.providerKey === 'google-auth') {
      out.push({
        id: 'google-login',
        label: 'Google login',
        disabled: !googleProviderReady,
        title: googleProviderReady ? undefined : 'Configure VITE_GOOGLE_* in .env (see docs/poc/google-setup.md)',
        run: startGoogle,
      });
    }
  }

  return out;
}

const actionsByAuthId = computed(() => {
  const m = new Map<string, ContextAction[]>();
  for (const r of tokenStatus.value) {
    m.set(r.authId, buildActionsForRow(r));
  }
  return m;
});

/** Selected subject auth id per target context (`token.exchangeSource` options). */
const exchangePicks = reactive<Record<string, string>>({});

function exchangeSourcesForTarget(targetAuthId: string): string[] {
  try {
    return morph.getExchangeSources(targetAuthId);
  } catch {
    return [];
  }
}

function sourceRowFor(authId: string): MorphTokenStatus | undefined {
  return tokenStatus.value.find((r) => r.authId === authId);
}

watch(
  tokenStatus,
  (rows) => {
    for (const r of rows) {
      const srcs = exchangeSourcesForTarget(r.authId);
      if (!srcs.length) {
        delete exchangePicks[r.authId];
        continue;
      }
      const cur = exchangePicks[r.authId];
      if (!cur || !srcs.includes(cur)) exchangePicks[r.authId] = srcs[0];
    }
  },
  { immediate: true },
);

function exchangeGoDisabled(targetAuthId: string): boolean {
  const src = exchangePicks[targetAuthId];
  if (!src) return true;
  return !sourceRowFor(src)?.accessLikelyValid;
}

function exchangeGoTitle(targetAuthId: string): string {
  const src = exchangePicks[targetAuthId];
  if (!src) return 'Choose a subject context';
  if (!sourceRowFor(src)?.accessLikelyValid) return `Need a valid access token on ${src}`;
  return `RFC 8693: ${src} → ${targetAuthId}`;
}

function onExchangeSourceChange(targetAuthId: string, ev: Event) {
  const v = (ev.target as HTMLSelectElement).value;
  if (v) exchangePicks[targetAuthId] = v;
}

async function runExchange(sourceAuthId: string, targetAuthId: string) {
  busy.value = true;
  message.value = '';
  try {
    await morph.auth(sourceAuthId).exchangeToken(targetAuthId);
    message.value = `Exchanged ${sourceAuthId} → ${targetAuthId}`;
    await refreshStatus();
  } catch (e) {
    message.value = e instanceof Error ? e.message : String(e);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="home">
    <h1 class="home__title">Overview</h1>
    <p class="hint home__intro">
      One screen: vault status, per-row <strong>JWT</strong> dialog (access / refresh), <strong>token exchange</strong> on
      target rows, mock API, simulation.
    </p>
    <p
      class="hint"
      :title="`deviceId: ${webSim.deviceId}\ninstallationId: ${webSim.installationId}`"
    >
      Web sim: <code>deviceId</code> = browser id (localStorage), <code>installationId</code> = session id (sessionStorage, new per tab session).
      {{ webSim.deviceId.slice(0, 8) }}… / {{ webSim.installationId.slice(0, 8) }}…
    </p>

    <section class="card">
      <h2>Status</h2>
      <p class="hint subtle">
        <code>morph.getTokenStatus()</code> — <strong>JWT</strong> opens payload tree; provider tree via <strong>Config</strong>.
        <code>token.exchangeSource</code>: subject dropdown + <strong>Exchange</strong> on the target row.
      </p>
      <p v-if="!googleProviderReady" class="hint google-env-hint">
        Google login disabled until <code>VITE_GOOGLE_CLIENT_ID</code> + <code>VITE_GOOGLE_CLIENT_SECRET</code> are set — see
        <code>docs/poc/google-setup.md</code>.
      </p>
      <ul class="status-list">
        <li v-for="[providerKey, rows] in statusByProvider" :key="providerKey" class="provider-block">
          <div class="provider-key-row">
            <span class="provider-key">{{ providerKey }}</span>
            <button type="button" class="btn-config" @click.stop="openProviderConfigModal(providerKey)">Config</button>
          </div>
          <ul class="provider-contexts">
            <li v-for="row in rows" :key="row.authId" class="context-block">
              <div class="context-row">
                <button type="button" class="token-summary" @click="openJwtPreview(row)">
                  <span class="token-summary__label">{{ labelFor(row) }}</span>
                  <span
                    class="token-summary__state"
                    :class="{ ok: row.accessLikelyValid, bad: row.hasAccessToken && !row.accessLikelyValid }"
                  >
                    {{ statusLine(row) }}
                  </span>
                  <span class="token-summary__meta mono">
                    <span class="token-summary__exp">{{ formatExp(row) }}</span>
                    <span v-if="row.hasRefreshToken" class="token-summary__badge">refresh</span>
                  </span>
                </button>
                <div class="token-toolbar">
                  <button
                    type="button"
                    class="ctx-btn ctx-btn--jwt"
                    title="View access / refresh JWT payloads (signature not verified)"
                    @click.stop="openJwtPreview(row)"
                  >
                    JWT
                  </button>
                  <button
                    v-for="a in actionsByAuthId.get(row.authId) ?? []"
                    :key="a.id"
                    type="button"
                    class="ctx-btn"
                    :class="{ 'ctx-btn--primary': a.primary }"
                    :disabled="busy || !!a.disabled"
                    :title="a.title"
                    @click.stop="a.run()"
                  >
                    {{ a.label }}
                  </button>
                  <div v-if="exchangeSourcesForTarget(row.authId).length" class="exchange-dd">
                    <label class="exchange-dd__lbl" :for="'ex-src-' + row.authId">Subject</label>
                    <select
                      :id="'ex-src-' + row.authId"
                      class="exchange-select"
                      :value="exchangePicks[row.authId]"
                      :disabled="busy"
                      @change="onExchangeSourceChange(row.authId, $event)"
                    >
                      <option
                        v-for="s in exchangeSourcesForTarget(row.authId)"
                        :key="s"
                        :value="s"
                      >
                        {{ labelForAuthId(s) }} ({{ s }})
                      </option>
                    </select>
                    <button
                      type="button"
                      class="ctx-btn ctx-btn--exchange"
                      :disabled="busy || exchangeGoDisabled(row.authId)"
                      :title="exchangeGoTitle(row.authId)"
                      @click.stop="runExchange(exchangePicks[row.authId], row.authId)"
                    >
                      Exchange
                    </button>
                  </div>
                </div>
              </div>
              <span v-if="row.authId === GOOGLE_AUTH_ID && !googleProviderReady" class="muted small">
                (OAuth not configured)
              </span>
            </li>
          </ul>
        </li>
      </ul>
      <div class="snapshot-row">
        <button
          type="button"
          class="btn-reload"
          :disabled="busy"
          title="Re-reads storage only; does not call the token endpoint"
          @click="refreshStatus"
        >
          Reload snapshot
        </button>
      </div>
    </section>

    <section class="card">
      <h2>Mock API</h2>
      <p class="hint subtle">
        Playground buttons are built from <code>docs/poc/poc-simulation.json</code> (same steps as Simulation + conditional
        blocks). Host calls use <code>morph.host(...)</code>; HTTP log via SDK <code>onHttpTrace</code> (Authorization
        redacted).
      </p>
      <button type="button" class="btn-mock-open" @click="openMockApiModal">Open mock API &amp; HTTP log</button>
      <p v-if="!googleProviderReady" class="hint google-env-hint">
        Google host steps stay disabled until <code>VITE_GOOGLE_*</code> is set.
      </p>
    </section>

    <div
      v-if="mockApiModalOpen"
      class="modal-backdrop"
      role="dialog"
      aria-modal="true"
      aria-labelledby="mock-api-modal-title"
      @click.self="closeMockApiModal"
    >
      <div class="modal modal--mock-api">
        <header class="modal-head">
          <div class="modal-head__titles">
            <h3 id="mock-api-modal-title">Mock API</h3>
            <p class="modal-sub mono">docs/poc/poc-simulation.json · onHttpTrace</p>
          </div>
          <button type="button" class="modal-close" aria-label="Close" @click="closeMockApiModal">×</button>
        </header>

        <div class="mock-api-modal__actions">
          <button
            v-for="(item, idx) in playgroundStepRefs"
            :key="`${item.blockId ?? 'root'}-${idx}-${item.step.label}`"
            type="button"
            class="ctx-btn"
            :class="{ 'ctx-btn--danger': item.step.type === 'logout_provider' }"
            :disabled="busy || playgroundButtonDisabled(item)"
            :title="playgroundButtonTitle(item)"
            @click="runPlaygroundStep(item)"
          >
            {{ item.step.label }}
          </button>
        </div>
        <p v-if="!googleProviderReady" class="hint subtle mock-api-modal__hint">Google requires <code>VITE_GOOGLE_*</code> in <code>.env</code>.</p>

        <div class="http-trace-panel">
          <div class="http-trace-head">
            <h4>HTTP log</h4>
            <button type="button" class="btn-ghost-sm" @click="clearHostHttpTraces">Clear log</button>
          </div>
          <p v-if="!httpTraceRows.length" class="hint subtle http-trace-empty">
            No traced requests yet (host calls from playground or Simulation).
          </p>
          <ul v-else class="http-trace-list">
            <li v-for="t in httpTraceRows" :key="t.id" class="http-trace-item">
              <button type="button" class="http-trace-row" @click="toggleHttpTraceRow(t.id)">
                <span class="http-trace-method">{{ t.method }}</span>
                <span class="http-trace-path mono">{{ t.path }}</span>
                <span
                  class="http-trace-status"
                  :class="{ bad: !!t.networkError || t.statusCode >= 400 }"
                >
                  {{ t.networkError ? 'ERR' : t.statusCode }}
                </span>
                <span class="http-trace-ms mono">{{ t.durationMs }}ms</span>
                <span class="http-trace-auth mono">{{ t.authId }}</span>
              </button>
              <div v-if="expandedHttpTraceId === t.id" class="http-trace-detail">
                <p v-if="t.networkError" class="http-trace-net-err">{{ t.networkError }}</p>
                <p v-else class="http-trace-url mono">{{ t.url }}</p>
                <div class="http-trace-tabs" role="tablist">
                  <button
                    type="button"
                    role="tab"
                    class="http-trace-tab"
                    :class="{ active: httpTraceDetailTab === 'request' }"
                    :aria-selected="httpTraceDetailTab === 'request'"
                    @click="httpTraceDetailTab = 'request'"
                  >
                    Request headers
                  </button>
                  <button
                    type="button"
                    role="tab"
                    class="http-trace-tab"
                    :class="{ active: httpTraceDetailTab === 'response' }"
                    :aria-selected="httpTraceDetailTab === 'response'"
                    @click="httpTraceDetailTab = 'response'"
                  >
                    Response headers
                  </button>
                  <button
                    type="button"
                    role="tab"
                    class="http-trace-tab"
                    :class="{ active: httpTraceDetailTab === 'body' }"
                    :aria-selected="httpTraceDetailTab === 'body'"
                    @click="httpTraceDetailTab = 'body'"
                  >
                    Response body
                  </button>
                </div>
                <div class="json-tree-scroll http-trace-tree">
                  <JsonTreeView
                    v-if="httpTraceDetailTab === 'request'"
                    :data="t.requestHeaders"
                    root-label="request headers"
                  />
                  <JsonTreeView
                    v-else-if="httpTraceDetailTab === 'response'"
                    :data="t.responseHeaders"
                    root-label="response headers"
                  />
                  <JsonTreeView
                    v-else
                    :data="traceBodyForTree(t.responseBody)"
                    root-label="response body"
                  />
                </div>
              </div>
            </li>
          </ul>
        </div>
      </div>
    </div>

    <section class="card card--sim">
      <PocSimulationPanel />
    </section>

    <pre v-if="message" class="msg">{{ message }}</pre>
    <pre v-if="apiOutput" class="api-out">{{ apiOutput }}</pre>

    <div
      v-if="modalOpen && modalRow"
      class="modal-backdrop"
      role="dialog"
      aria-modal="true"
      aria-labelledby="jwt-modal-title"
      @click.self="closeModal"
    >
      <div class="modal modal--jwt">
        <header class="modal-head">
          <div class="modal-head__titles">
            <h3 id="jwt-modal-title">JWT · {{ labelFor(modalRow) }}</h3>
            <p class="modal-sub mono">{{ modalRow.authId }}</p>
          </div>
          <button type="button" class="modal-close" aria-label="Close" @click="closeModal">×</button>
        </header>
        <p class="modal-meta mono jwt-modal-meta">
          <template v-if="modalTokenTab === 'access'">Access · exp {{ formatExp(modalRow) }}</template>
          <template v-else>Refresh · {{ formatRefreshExp(modalRow) }}</template>
        </p>
        <div class="jwt-dialog-tabs" role="tablist">
          <button
            type="button"
            role="tab"
            :aria-selected="modalTokenTab === 'access'"
            class="jwt-dialog-tab"
            :class="{ active: modalTokenTab === 'access' }"
            @click="modalTokenTab = 'access'"
          >
            Access token
          </button>
          <button
            type="button"
            role="tab"
            :disabled="!modalRow.hasRefreshToken"
            :aria-selected="modalTokenTab === 'refresh'"
            class="jwt-dialog-tab"
            :class="{ active: modalTokenTab === 'refresh' }"
            @click="modalTokenTab = 'refresh'"
          >
            Refresh token
          </button>
        </div>
        <div class="json-tree-scroll">
          <JsonTreeView :data="modalTreeData" :root-label="modalTokenTab === 'access' ? 'access payload' : 'refresh payload'" />
        </div>
        <footer class="modal-actions">
          <button
            v-if="canIdpRefresh(modalRow)"
            type="button"
            class="primary"
            :disabled="modalBusy"
            @click="idpRefreshFromModal"
          >
            {{ modalBusy ? 'Calling IdP…' : 'Refresh from IdP' }}
          </button>
          <p v-else class="modal-actions-hint">No refresh or client_credentials path for this context.</p>
        </footer>
      </div>
    </div>

    <div
      v-if="providerOnlyModalKey"
      class="modal-backdrop"
      role="dialog"
      aria-modal="true"
      aria-label="Provider configuration"
      @click.self="closeProviderConfigModal"
    >
      <div class="modal modal--wide">
        <header class="modal-head">
          <h3>Provider: {{ providerOnlyModalKey }}</h3>
          <button type="button" class="modal-close" aria-label="Close" @click="closeProviderConfigModal">×</button>
        </header>
        <p class="modal-meta mono"><code>morph.getProviderMeta('{{ providerOnlyModalKey }}')</code></p>
        <div v-if="providerOnlyModalData" class="json-tree-scroll json-tree-scroll--standalone">
          <JsonTreeView :data="providerOnlyModalData" :root-label="providerOnlyModalKey ?? undefined" />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.home__title {
  margin: 0 0 0.35rem;
  font-size: 1.35rem;
}
.home__intro {
  margin-top: 0;
}
.card {
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  padding: 1rem 1rem 0.9rem;
  margin-bottom: 1rem;
  background: #fff;
}
.card h2 {
  margin-top: 0;
  font-size: 0.95rem;
}
.card--sim {
  padding-top: 0.85rem;
}
.primary {
  font-weight: 600;
}
.msg {
  background: #f3f4f6;
  padding: 0.75rem;
  border-radius: 6px;
  overflow: auto;
  margin: 0 0 0.65rem;
}
.api-out {
  background: #0f172a;
  color: #e2e8f0;
  padding: 0.85rem;
  border-radius: 8px;
  overflow: auto;
  font-size: 0.78rem;
  line-height: 1.45;
  margin: 0 0 1rem;
  max-height: 320px;
}
.tools-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  align-items: center;
  margin-bottom: 0.35rem;
}
.snapshot-row {
  margin-top: 0.25rem;
}
.btn-reload {
  margin: 0;
  padding: 0.4rem 0.75rem;
  font-size: 0.8rem;
  border-radius: 6px;
  border: 1px solid #cbd5e1;
  background: #fff;
  cursor: pointer;
  color: #334155;
}
.btn-reload:hover:not(:disabled) {
  background: #f8fafc;
}
.btn-reload:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.ctx-btn--danger {
  border-color: #fecaca;
  color: #b91c1c;
  background: #fef2f2;
}
.ctx-btn--danger:hover:not(:disabled) {
  background: #fee2e2;
  border-color: #f87171;
}
.hint {
  font-size: 0.875rem;
  color: #4b5563;
  margin: 0 0 0.75rem;
  line-height: 1.5;
}
.hint.subtle {
  margin-top: -0.25rem;
  font-size: 0.8rem;
  color: #6b7280;
}
.hint code {
  font-size: 0.8em;
  background: #f3f4f6;
  padding: 0.1em 0.35em;
  border-radius: 4px;
}
.muted {
  color: #9ca3af;
  font-size: 0.95em;
}
.small {
  display: block;
  margin: -0.25rem 0 0.35rem 1.5rem;
  font-size: 0.75rem;
}
.status-list {
  list-style: none;
  padding: 0;
  margin: 0 0 0.75rem;
}
.provider-block {
  margin-bottom: 0.75rem;
}
.provider-key-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  margin-bottom: 0.35rem;
}
.provider-key {
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #64748b;
}
.btn-config {
  flex-shrink: 0;
  margin: 0;
  padding: 0.2rem 0.55rem;
  font-size: 0.7rem;
  font-weight: 600;
  border: 1px solid #cbd5e1;
  border-radius: 4px;
  background: #fff;
  color: #334155;
  cursor: pointer;
}
.btn-config:hover {
  background: #f8fafc;
  border-color: #94a3b8;
}
.provider-contexts {
  list-style: none;
  padding: 0;
  margin: 0;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  overflow: hidden;
  background: #fafafa;
}
.context-block {
  border-bottom: 1px solid #e8eef3;
}
.context-block:last-child {
  border-bottom: none;
}
.context-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 0.5rem 0.75rem;
  align-items: center;
  padding: 0.45rem 0.55rem;
  min-width: 0;
}
@media (max-width: 720px) {
  .context-row {
    grid-template-columns: 1fr;
  }
  .token-toolbar {
    justify-content: flex-start;
    padding-left: 0;
    padding-bottom: 0.35rem;
    border-left: none;
  }
}
.token-summary {
  display: grid;
  grid-template-columns: minmax(5.5rem, 7.5rem) minmax(2.75rem, 3.5rem) minmax(0, 1fr);
  gap: 0.35rem 0.65rem;
  align-items: center;
  min-width: 0;
  width: 100%;
  text-align: left;
  padding: 0.45rem 0.55rem;
  margin: 0;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  background: #fff;
  cursor: pointer;
  font: inherit;
}
.token-summary:hover {
  background: #f8fafc;
  border-color: #cbd5e1;
}
.token-summary__label {
  font-weight: 600;
  font-size: 0.88rem;
  color: #1e293b;
}
.token-summary__state {
  font-size: 0.8rem;
  font-weight: 600;
  color: #64748b;
}
.token-summary__state.ok {
  color: #166534;
}
.token-summary__state.bad {
  color: #991b1b;
}
.token-summary__meta {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  min-width: 0;
}
.token-summary__exp {
  font-size: 0.72rem;
  color: #475569;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.token-summary__badge {
  flex-shrink: 0;
  font-size: 0.6rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  background: #e0e7ff;
  color: #3730a3;
  padding: 0.2em 0.45em;
  border-radius: 4px;
  font-weight: 600;
}
.token-toolbar {
  display: flex;
  flex-flow: row wrap;
  gap: 0.35rem;
  align-items: center;
  justify-content: flex-end;
  padding-left: 0.35rem;
  border-left: 1px solid #e2e8f0;
}
.exchange-dd {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.35rem;
  padding: 0.2rem 0.45rem;
  border-radius: 8px;
  border: 1px solid #ddd6fe;
  background: #faf5ff;
}
.exchange-dd__lbl {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #6b21a8;
  margin: 0;
  cursor: default;
}
.exchange-select {
  margin: 0;
  min-width: 9rem;
  max-width: min(22rem, 52vw);
  padding: 0.32rem 0.45rem;
  font-size: 0.72rem;
  border: 1px solid #c4b5fd;
  border-radius: 6px;
  background: #fff;
  color: #1e1b4b;
  cursor: pointer;
}
.exchange-select:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.ctx-btn--exchange {
  border-color: #a78bfa;
  color: #5b21b6;
  background: #f5f3ff;
}
.ctx-btn--exchange:hover:not(:disabled) {
  background: #ede9fe;
  border-color: #8b5cf6;
}
.ctx-btn--jwt {
  border-color: #94a3b8;
  color: #0f172a;
  font-weight: 600;
  background: #f8fafc;
}
.ctx-btn--jwt:hover:not(:disabled) {
  background: #e2e8f0;
  border-color: #64748b;
}
.ctx-btn {
  margin: 0;
  padding: 0.35rem 0.55rem;
  font-size: 0.75rem;
  border: 1px solid #d1d5db;
  border-radius: 6px;
  background: #fff;
  color: #374151;
  cursor: pointer;
}
.ctx-btn:hover:not(:disabled) {
  background: #f9fafb;
  border-color: #9ca3af;
}
.ctx-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.ctx-btn--primary {
  font-weight: 600;
  border-color: #2563eb;
  color: #1d4ed8;
  background: #eff6ff;
}
.ctx-btn--primary:hover:not(:disabled) {
  background: #dbeafe;
}
.google-env-hint {
  margin-top: -0.35rem;
  font-size: 0.78rem;
  color: #6b7280;
}
.json-tree-scroll {
  margin: 0;
  padding: 0.75rem 1rem 1rem;
  overflow: auto;
  flex: 1;
  min-height: 6rem;
  max-height: min(52vh, 520px);
  background: #0f172a;
  border-radius: 0;
}
.json-tree-scroll--standalone {
  border-radius: 0 0 10px 10px;
  max-height: min(60vh, 560px);
}
.mono {
  font-family: ui-monospace, monospace;
}
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 50;
  padding: 1rem;
}
.modal {
  background: #fff;
  border-radius: 10px;
  max-width: 42rem;
  width: 100%;
  max-height: min(85vh, 640px);
  display: flex;
  flex-direction: column;
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
}
.modal--wide {
  max-width: min(52rem, 96vw);
}
.modal--jwt {
  max-width: min(44rem, 96vw);
}
.modal-head__titles {
  min-width: 0;
}
.modal-sub {
  margin: 0.2rem 0 0;
  font-size: 0.72rem;
  color: #64748b;
  word-break: break-all;
}
.jwt-modal-meta {
  background: #fafafa;
}
.jwt-dialog-tabs {
  display: flex;
  gap: 0;
  border-bottom: 2px solid #e2e8f0;
  padding: 0 0.75rem;
  background: #f8fafc;
}
.jwt-dialog-tab {
  margin: 0;
  padding: 0.55rem 1rem;
  border: none;
  background: transparent;
  cursor: pointer;
  font-size: 0.82rem;
  color: #64748b;
  border-bottom: 3px solid transparent;
  margin-bottom: -2px;
}
.jwt-dialog-tab:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
.jwt-dialog-tab.active {
  color: #0f172a;
  font-weight: 700;
  border-bottom-color: #0ea5e9;
}
.modal-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 1rem;
  border-bottom: 1px solid #e5e7eb;
}
.modal-head h3 {
  margin: 0;
  font-size: 1rem;
}
.modal-close {
  border: none;
  background: transparent;
  font-size: 1.5rem;
  line-height: 1;
  cursor: pointer;
  color: #6b7280;
  padding: 0 0.25rem;
  margin: 0;
}
.modal-meta {
  margin: 0;
  padding: 0.5rem 1rem;
  font-size: 0.75rem;
  color: #6b7280;
  border-bottom: 1px solid #f3f4f6;
}
.modal-pre {
  margin: 0;
  padding: 1rem;
  overflow: auto;
  flex: 1;
  min-height: 8rem;
  font-size: 0.75rem;
  line-height: 1.45;
  background: #0f172a;
  color: #e2e8f0;
}
.modal-actions {
  padding: 0.75rem 1rem;
  border-top: 1px solid #e5e7eb;
  border-radius: 0 0 10px 10px;
  background: #fafafa;
}
.modal-actions .primary {
  margin: 0;
}
.modal-actions-hint {
  margin: 0;
  font-size: 0.8rem;
  color: #64748b;
}
.btn-mock-open {
  margin: 0;
  padding: 0.45rem 1rem;
  font-size: 0.875rem;
  font-weight: 600;
  border-radius: 8px;
  border: 1px solid #2563eb;
  background: #eff6ff;
  color: #1d4ed8;
  cursor: pointer;
}
.btn-mock-open:hover {
  background: #dbeafe;
}
.modal--mock-api {
  max-width: min(56rem, 98vw);
  width: 100%;
  max-height: min(92vh, 900px);
  display: flex;
  flex-direction: column;
}
.mock-api-modal__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  padding: 0.5rem 1rem 0.75rem;
  border-bottom: 1px solid #f1f5f9;
}
.mock-api-modal__hint {
  margin: 0 1rem 0.5rem !important;
}
.http-trace-panel {
  display: flex;
  flex-direction: column;
  min-height: 0;
  flex: 1;
  padding: 0.5rem 0 0;
}
.http-trace-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 1rem 0.35rem;
}
.http-trace-head h4 {
  margin: 0;
  font-size: 0.82rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: #475569;
}
.btn-ghost-sm {
  margin: 0;
  padding: 0.2rem 0.55rem;
  font-size: 0.72rem;
  border-radius: 6px;
  border: 1px solid #cbd5e1;
  background: #fff;
  cursor: pointer;
  color: #475569;
}
.btn-ghost-sm:hover {
  background: #f8fafc;
}
.http-trace-empty {
  margin: 0 1rem 0.75rem !important;
}
.http-trace-list {
  list-style: none;
  margin: 0;
  padding: 0 0.5rem 0.75rem;
  overflow: auto;
  max-height: min(42vh, 400px);
}
.http-trace-item {
  margin-bottom: 0.35rem;
}
.http-trace-row {
  width: 100%;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto auto minmax(0, 6.5rem);
  gap: 0.35rem 0.5rem;
  align-items: center;
  text-align: left;
  padding: 0.4rem 0.5rem;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #fafafa;
  cursor: pointer;
  font: inherit;
  font-size: 0.78rem;
}
.http-trace-row:hover {
  background: #f1f5f9;
}
.http-trace-method {
  font-weight: 700;
  color: #0369a1;
}
.http-trace-path {
  color: #334155;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.http-trace-status {
  font-weight: 700;
  color: #166534;
}
.http-trace-status.bad {
  color: #b91c1c;
}
.http-trace-ms {
  color: #64748b;
  font-size: 0.7rem;
}
.http-trace-auth {
  font-size: 0.65rem;
  color: #64748b;
  overflow: hidden;
  text-overflow: ellipsis;
}
.http-trace-detail {
  margin-top: 0.35rem;
  padding: 0.5rem 0.5rem 0.65rem;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #fff;
}
.http-trace-url {
  margin: 0 0 0.5rem;
  font-size: 0.68rem;
  color: #64748b;
  word-break: break-all;
}
.http-trace-net-err {
  margin: 0 0 0.5rem;
  font-size: 0.78rem;
  color: #b91c1c;
}
.http-trace-tabs {
  display: flex;
  gap: 0;
  border-bottom: 2px solid #e5e7eb;
  margin-bottom: 0.35rem;
}
.http-trace-tab {
  margin: 0;
  padding: 0.35rem 0.65rem;
  border: none;
  background: transparent;
  cursor: pointer;
  font-size: 0.75rem;
  color: #64748b;
  border-bottom: 2px solid transparent;
  margin-bottom: -2px;
}
.http-trace-tab.active {
  color: #0f172a;
  font-weight: 600;
  border-bottom-color: #0ea5e9;
}
.http-trace-tree {
  max-height: min(38vh, 320px);
  min-height: 8rem;
  border-radius: 6px;
}
</style>
