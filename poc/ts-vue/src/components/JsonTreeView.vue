<script setup lang="ts">
import { computed } from 'vue';
import JsonTreeView from './JsonTreeView.vue';

const props = withDefaults(
  defineProps<{
    data: unknown;
    /** Optional label for the root object summary */
    rootLabel?: string;
    depth?: number;
  }>(),
  { depth: 0 },
);

const isArr = computed(() => Array.isArray(props.data));
const isObj = computed(
  () => props.data !== null && typeof props.data === 'object' && !Array.isArray(props.data),
);
const objEntries = computed((): [string, unknown][] => {
  if (!isObj.value || props.data === null || typeof props.data !== 'object') return [];
  return Object.entries(props.data as Record<string, unknown>);
});
const arrLen = computed(() => (Array.isArray(props.data) ? props.data.length : 0));
const asArray = computed(() => (Array.isArray(props.data) ? props.data : []));
</script>

<template>
  <span v-if="data === null" class="jv jv-null">null</span>
  <span v-else-if="typeof data === 'boolean'" class="jv jv-bool">{{ data }}</span>
  <span v-else-if="typeof data === 'number'" class="jv jv-num">{{ data }}</span>
  <span v-else-if="typeof data === 'string'" class="jv jv-str">"{{ data }}"</span>
  <details v-else-if="isArr" class="jv-node" :open="depth < 4">
    <summary class="jv-sum">
      <span class="jv-punc">[</span>
      <span class="jv-meta">{{ arrLen }} items</span>
      <span class="jv-punc">]</span>
    </summary>
    <ul class="jv-list">
      <li v-for="(item, i) in asArray" :key="i" class="jv-li">
        <span class="jv-idx">{{ i }}</span>
        <JsonTreeView :data="item" :depth="depth + 1" />
      </li>
    </ul>
  </details>
  <details v-else-if="isObj" class="jv-node" :open="depth < 3">
    <summary class="jv-sum">
      <span class="jv-punc">{</span>
      <span class="jv-meta">{{ rootLabel ?? (depth === 0 ? 'root' : 'Object') }} · {{ objEntries.length }} keys</span>
      <span class="jv-punc">}</span>
    </summary>
    <ul class="jv-list">
      <li v-for="[k, v] in objEntries" :key="k" class="jv-li">
        <span class="jv-key">{{ k }}</span>
        <span class="jv-colon">:</span>
        <JsonTreeView :data="v" :depth="depth + 1" />
      </li>
    </ul>
  </details>
  <span v-else class="jv jv-undef">undefined</span>
</template>

<style scoped>
.jv-node {
  margin: 0;
  padding: 0;
  border: none;
}
.jv-node > summary {
  list-style: none;
  cursor: pointer;
  user-select: none;
  padding: 0.15rem 0;
  color: #94a3b8;
  font-size: 0.8rem;
}
.jv-node > summary::-webkit-details-marker {
  display: none;
}
.jv-node > summary::before {
  content: '▸';
  display: inline-block;
  width: 1em;
  color: #64748b;
  transition: transform 0.12s ease;
}
.jv-node[open] > summary::before {
  transform: rotate(90deg);
}
.jv-sum {
  font-family: ui-monospace, monospace;
}
.jv-punc {
  color: #64748b;
  margin: 0 0.15rem;
}
.jv-meta {
  color: #64748b;
  font-size: 0.75rem;
}
.jv-list {
  list-style: none;
  margin: 0.2rem 0 0.35rem 0.85rem;
  padding: 0 0 0 0.5rem;
  border-left: 1px solid #334155;
}
.jv-li {
  margin: 0.2rem 0;
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 0.25rem 0.35rem;
}
.jv-idx {
  font-family: ui-monospace, monospace;
  font-size: 0.75rem;
  color: #a78bfa;
  min-width: 1.5rem;
}
.jv-key {
  font-family: ui-monospace, monospace;
  font-size: 0.8rem;
  color: #7dd3fc;
  font-weight: 500;
}
.jv-colon {
  color: #64748b;
}
.jv {
  font-family: ui-monospace, monospace;
  font-size: 0.8rem;
  word-break: break-word;
}
.jv-str {
  color: #86efac;
}
.jv-num {
  color: #fcd34d;
}
.jv-bool {
  color: #f9a8d4;
}
.jv-null,
.jv-undef {
  color: #94a3b8;
  font-style: italic;
}
</style>
