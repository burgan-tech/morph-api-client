<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { morph, getSimulationConsoleVerbose, setSimulationConsoleVerbose } from '../morph';
import { getPocSimulationConfig, type PocSimStep } from '../pocSimulation';
import {
  runPocSimStep,
  filterStepsForAutoTick,
  filterBlockStepForAutoTick,
} from '../pocSimulationRunner';
import { evalPocSimCondition } from '../pocSimulationWhen';
import { simulatorProbe404 } from '../pocSimUi';

const simConfig = getPocSimulationConfig();

type SimRow = {
  seq: number;
  tick: number;
  at: string;
  request: string;
  status: number | string;
  ms: number;
  detail: string;
};

const intervalMs = ref(5000);
const running = ref(false);
const busy = ref(false);
const verbose = ref(false);
const rows = ref<SimRow[]>([]);
const maxRows = 60;
/** When true, conditional blocks always run their steps; `when` is not evaluated (no SKIP rows for failed conditions). */
const ignoreConditionalWhen = ref(false);
const sessionLostMessage = ref('');
let seq = 0;
let timer: ReturnType<typeof setInterval> | null = null;

function logVerbose(msg: string, extra?: unknown) {
  if (getSimulationConsoleVerbose()) {
    console.log(`[sim] ${msg}`, extra ?? '');
  }
}

function pushRow(r: Omit<SimRow, 'seq' | 'at'>) {
  seq += 1;
  const full: SimRow = {
    ...r,
    seq,
    at: new Date().toISOString(),
  };
  rows.value.unshift(full);
  if (rows.value.length > maxRows) rows.value.length = maxRows;
  logVerbose(`tick ${r.tick} ${r.request} → ${r.status} ${r.ms}ms`, r.detail || undefined);
}

async function runStep(
  tick: number,
  step: PocSimStep,
  sessionDeadAuthIds: string[] | undefined,
  tickAuthFailures: Set<string>,
) {
  const r = await runPocSimStep(morph, simConfig, step, tick);
  logVerbose(`tick ${tick} ${r.label} → ${r.status} ${r.ms}ms`, r.detail);
  if (r.authFailedAuthId && sessionDeadAuthIds?.includes(r.authFailedAuthId)) {
    tickAuthFailures.add(r.authFailedAuthId);
  }
  pushRow({ tick, request: r.label, status: r.status, ms: r.ms, detail: r.detail });
}

async function runTick(tick: number) {
  logVerbose(`— tick ${tick} start —`);

  const deadCfg = simConfig.sessionDeadCheck;
  const tickAuthFailures = new Set<string>();

  for (const step of filterStepsForAutoTick(simConfig.steps)) {
    await runStep(tick, step, deadCfg?.authIds, tickAuthFailures);
  }

  if (
    deadCfg &&
    deadCfg.authIds.length > 0 &&
    deadCfg.authIds.every((id) => tickAuthFailures.has(id))
  ) {
    sessionLostMessage.value = deadCfg.message;
    pushRow({
      tick,
      request: 'Simulation',
      status: 'STOP',
      ms: 0,
      detail: sessionLostMessage.value,
    });
    stopLoop();
    logVerbose('stopped: sessionDeadCheck authIds all AUTH in one tick');
    return;
  }

  for (const block of simConfig.conditionalBlocks ?? []) {
    const whenOk =
      ignoreConditionalWhen.value ||
      (await evalPocSimCondition(block.when, {
        morph,
        isProviderEnvReady: (pk) => morph.isProviderEnvReady(pk),
        getProbe404: () => simulatorProbe404.value,
      }));
    if (!whenOk) {
      if (block.skipRow) {
        pushRow({
          tick,
          request: block.skipRow.label,
          status: 'SKIP',
          ms: 0,
          detail: block.skipRow.detail,
        });
        logVerbose(`skip conditional ${block.id}`);
      }
      continue;
    }
    for (const step of block.steps.filter(filterBlockStepForAutoTick)) {
      await runStep(tick, step, deadCfg?.authIds, tickAuthFailures);
    }
  }

  logVerbose(`— tick ${tick} end —`);
}

function startLoop() {
  if (timer) return;
  sessionLostMessage.value = '';
  running.value = true;
  let tick = 0;
  const ms = Math.max(1000, intervalMs.value);
  const run = async () => {
    if (!running.value || busy.value) return;
    busy.value = true;
    tick += 1;
    try {
      await runTick(tick);
    } catch (e) {
      console.error('[sim] tick failed', e);
      pushRow({
        tick,
        request: 'TICK',
        status: 'ERR',
        ms: 0,
        detail: e instanceof Error ? e.message : String(e),
      });
    } finally {
      busy.value = false;
    }
  };
  void run();
  timer = setInterval(run, ms);
}

function stopLoop() {
  running.value = false;
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
}

function clearRows() {
  rows.value = [];
  seq = 0;
}

onMounted(() => {
  verbose.value = getSimulationConsoleVerbose();
});

onUnmounted(() => {
  stopLoop();
});

function onVerboseChange(e: Event) {
  const on = (e.target as HTMLInputElement).checked;
  verbose.value = on;
  setSimulationConsoleVerbose(on);
}
</script>

<template>
  <div class="poc-sim">
    <h2>Simulation</h2>
    <p class="poc-sim__lead">
      Loop from <code>docs/poc/poc-simulation.json</code> — <code>mockApi.baseUrl</code> for raw <code>fetch</code>; Morph
      <code>host</code> steps use <code>main-api</code>. Short Keycloak lifetimes:
      <code>poc/keycloak/set-simulation-lifetimes.sh</code>. Optional <code>VITE_SIMULATION_MODE=true</code> for 5s refresh lead.
    </p>

    <div class="poc-sim__controls">
      <label>
        Interval (ms)
        <input v-model.number="intervalMs" type="number" min="1000" step="500" :disabled="running" />
      </label>
      <button type="button" :disabled="running" @click="startLoop">Start</button>
      <button type="button" :disabled="!running" @click="stopLoop">Stop</button>
      <button type="button" class="poc-sim__ghost" @click="clearRows">Clear log</button>
      <label class="poc-sim__check" title="Adds [sim] per request + Morph debug logs.">
        <input type="checkbox" :checked="verbose" @change="onVerboseChange" />
        Verbose console
      </label>
      <label class="poc-sim__check" title="Browsers log 404 fetch as errors in the console even when intentional">
        <input v-model="simulatorProbe404" type="checkbox" :disabled="running" />
        404 probe (<code>/sim/not-found</code>)
      </label>
      <label
        class="poc-sim__check"
        title="Run every conditional block each tick even when `when` is false — expect AUTH / errors instead of SKIP (full visibility)."
      >
        <input v-model="ignoreConditionalWhen" type="checkbox" :disabled="running" />
        Ignore <code>when</code> (full conditional run)
      </label>
      <span v-if="busy" class="poc-sim__badge">tick running…</span>
    </div>

    <p v-if="sessionLostMessage" class="poc-sim__alert" role="alert">
      {{ sessionLostMessage }}
    </p>

    <div class="poc-sim__table-card">
      <h3>Last requests</h3>
      <p class="poc-sim__hint">
        Newest first. <code>AUTH</code> = no valid token. <code>SKIP</code> = conditional <code>when</code> false (enable
        <strong>Ignore when</strong> above to run those steps anyway and see real failures).
      </p>
      <div class="poc-sim__table-wrap">
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>Tick</th>
              <th>Time</th>
              <th>Request</th>
              <th>Status</th>
              <th>ms</th>
              <th>Detail</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in rows" :key="r.seq">
              <td>{{ r.seq }}</td>
              <td>{{ r.tick }}</td>
              <td class="mono">{{ r.at.slice(11, 23) }}</td>
              <td class="poc-sim__req">{{ r.request }}</td>
              <td>
                <span
                  class="pill"
                  :class="{
                    ok:
                      r.status === 'OK' ||
                      (typeof r.status === 'number' && r.status >= 200 && r.status < 300),
                    warn: r.status === 404 || r.status === 401 || r.status === 'STOP',
                    skip: r.status === 'SKIP',
                    bad: r.status === 'AUTH' || r.status === 'ERR' || r.status === 'NET',
                  }"
                >
                  {{ r.status }}
                </span>
              </td>
              <td class="mono">{{ r.ms }}</td>
              <td class="poc-sim__detail">{{ r.detail }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="!rows.length" class="poc-sim__empty">Start the loop to record traffic.</p>
    </div>
  </div>
</template>

<style scoped>
.poc-sim h2 {
  margin: 0 0 0.35rem;
  font-size: 1rem;
}
.poc-sim h3 {
  margin: 0 0 0.35rem;
  font-size: 0.9rem;
}
.poc-sim__lead {
  font-size: 0.8rem;
  color: #475569;
  line-height: 1.45;
  margin: 0 0 0.85rem;
}
.poc-sim__lead code {
  font-size: 0.85em;
  background: #f1f5f9;
  padding: 0.08em 0.3em;
  border-radius: 4px;
}
.poc-sim__controls {
  display: flex;
  flex-wrap: wrap;
  gap: 0.65rem 1rem;
  align-items: center;
  margin-bottom: 0.75rem;
}
.poc-sim__controls label {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  font-size: 0.8rem;
}
.poc-sim__controls input[type='number'] {
  width: 5.25rem;
}
.poc-sim__check {
  user-select: none;
}
.poc-sim__controls button {
  margin: 0;
  padding: 0.35rem 0.65rem;
  font-size: 0.8rem;
  cursor: pointer;
  border-radius: 6px;
  border: 1px solid #cbd5e1;
  background: #fff;
}
.poc-sim__ghost {
  background: transparent !important;
}
.poc-sim__badge {
  font-size: 0.78rem;
  color: #64748b;
}
.poc-sim__table-card {
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 0.75rem;
  background: #fafafa;
}
.poc-sim__hint {
  font-size: 0.75rem;
  color: #64748b;
  margin: 0 0 0.5rem;
}
.poc-sim__table-wrap {
  overflow: auto;
  max-height: 360px;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  background: #fff;
}
table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.75rem;
}
th,
td {
  text-align: left;
  padding: 0.3rem 0.45rem;
  border-bottom: 1px solid #f1f5f9;
  vertical-align: top;
}
th {
  background: #f8fafc;
  position: sticky;
  top: 0;
}
.mono {
  font-family: ui-monospace, monospace;
  white-space: nowrap;
}
.poc-sim__req {
  max-width: 200px;
  word-break: break-all;
}
.poc-sim__detail {
  max-width: 200px;
  word-break: break-word;
  color: #64748b;
}
.pill {
  display: inline-block;
  padding: 0.1em 0.4em;
  border-radius: 4px;
  font-weight: 600;
  font-size: 0.85em;
}
.pill.ok {
  background: #dcfce7;
  color: #166534;
}
.pill.warn {
  background: #fef9c3;
  color: #854d0e;
}
.pill.bad {
  background: #fee2e2;
  color: #991b1b;
}
.pill.skip {
  background: #e2e8f0;
  color: #475569;
}
.poc-sim__empty {
  color: #94a3b8;
  font-size: 0.8rem;
  margin: 0.4rem 0 0;
}
.poc-sim__alert {
  margin: 0 0 0.65rem;
  padding: 0.55rem 0.75rem;
  border-radius: 8px;
  border: 1px solid #f59e0b;
  background: #fffbeb;
  color: #92400e;
  font-size: 0.8rem;
  line-height: 1.4;
}
</style>
