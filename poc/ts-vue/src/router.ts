import { createRouter, createWebHistory } from 'vue-router';
import HomeView from './views/HomeView.vue';
import OAuthCallbackView from './views/OAuthCallbackView.vue';

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'home', component: HomeView },
    { path: '/oauth/callback', name: 'oauth-callback', component: OAuthCallbackView },
  ],
});
