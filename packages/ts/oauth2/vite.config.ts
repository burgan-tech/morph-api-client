import { defineConfig } from 'vite';
import dts from 'vite-plugin-dts';
import { resolve } from 'node:path';

export default defineConfig({
  plugins: [
    dts({
      include: ['src'],
      rollupTypes: false,
      outDir: 'dist',
    }),
  ],
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'MorphOAuth2',
      fileName: 'index',
      formats: ['es', 'cjs'],
    },
    sourcemap: true,
    emptyOutDir: true,
    rollupOptions: {
      external: ['@morph/core'],
    },
  },
});
