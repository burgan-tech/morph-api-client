<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { RouterLink, useRoute, useRouter } from 'vue-router';
import { morph, syncOAuthRedirectUrisFromBrowser } from '../morph';
import { cleanOAuthReturnFromBrowser } from '@morph/core';

const route = useRoute();
const router = useRouter();
const message = ref('Processing…');

onMounted(async () => {
  syncOAuthRedirectUrisFromBrowser();
  const result = await morph.completeOAuthCallback({
    code: typeof route.query.code === 'string' ? route.query.code : null,
    state: typeof route.query.state === 'string' ? route.query.state : null,
    error: typeof route.query.error === 'string' ? route.query.error : null,
    errorDescription: typeof route.query.error_description === 'string' ? route.query.error_description : null,
  });
  cleanOAuthReturnFromBrowser();
  if (result.status === 'success') {
    message.value = result.message ?? 'Signed in.';
    await router.replace({ name: 'home' });
  } else if (result.status === 'none') {
    message.value = 'No authorization code found.';
  } else {
    message.value = result.message ?? 'OAuth error.';
  }
});
</script>

<template>
  <div>
    <h1>OAuth callback</h1>
    <p>{{ message }}</p>
    <RouterLink to="/">Home</RouterLink>
  </div>
</template>
