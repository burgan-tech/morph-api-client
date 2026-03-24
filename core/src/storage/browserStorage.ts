import type { StorageProvider } from '../types.js';

function createBrowserStorageAdapter(store: Storage, prefix: string): StorageProvider {
  return {
    read: async (key, _storageConfig) => {
      try {
        return store.getItem(prefix + key);
      } catch {
        return null;
      }
    },
    write: async (key, value, _storageConfig) => {
      try {
        store.setItem(prefix + key, value);
      } catch {
        /* quota / private mode */
      }
    },
    delete: async (key, _storageConfig) => {
      try {
        store.removeItem(prefix + key);
      } catch {
        /* ignore */
      }
    },
    deleteByPrefix: async (pfx, _storageConfig) => {
      const needle = prefix + pfx;
      try {
        for (let i = store.length - 1; i >= 0; i--) {
          const k = store.key(i);
          if (k?.startsWith(needle)) store.removeItem(k);
        }
      } catch {
        /* ignore */
      }
    },
  };
}

/** sessionStorage-backed token store. Tokens survive SPA reloads but not new tabs. */
export function createBrowserSessionStorage(prefix = 'morph:tk:'): StorageProvider {
  return createBrowserStorageAdapter(sessionStorage, prefix);
}

/** localStorage-backed token store. Tokens persist across tabs and sessions. */
export function createBrowserLocalStorage(prefix = 'morph:tk:'): StorageProvider {
  return createBrowserStorageAdapter(localStorage, prefix);
}
