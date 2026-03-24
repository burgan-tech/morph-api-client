<script setup lang="ts">
import { RouterView } from 'vue-router';
</script>

<template>
  <div class="layout">
    <header>
      <strong>Morph PoC</strong>
      <span class="tag">single page</span>
    </header>
    <main>
      <RouterView />
    </main>
  </div>
</template>

<style scoped>
.layout {
  max-width: min(1040px, 96vw);
  margin: 0 auto;
  padding: 1rem 1rem 2rem;
  font-family: system-ui, sans-serif;
}
header {
  display: flex;
  align-items: center;
  gap: 0.65rem;
  margin-bottom: 1.25rem;
  padding-bottom: 0.65rem;
  border-bottom: 1px solid #e2e8f0;
}
.tag {
  font-size: 0.65rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #64748b;
  background: #f1f5f9;
  padding: 0.2em 0.5em;
  border-radius: 4px;
}
</style>
