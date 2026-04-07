import type { MorphPlugin } from '@morph/core';
import { createBrowserSessionStorage, createBrowserLocalStorage } from './browserStorage.js';

export function browserStoragePlugin(prefix = 'morph:tk:', type: 'session' | 'local' = 'session'): MorphPlugin {
  return {
    name: '@morph/browser-storage',
    install(ctx) {
      const storage = type === 'local'
        ? createBrowserLocalStorage(prefix)
        : createBrowserSessionStorage(prefix);
      ctx.provideStorage(storage);
    },
  };
}

export { createBrowserSessionStorage, createBrowserLocalStorage } from './browserStorage.js';
