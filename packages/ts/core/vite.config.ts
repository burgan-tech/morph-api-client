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
      name: 'MorphCore',
      fileName: 'index',
      formats: ['es', 'cjs'],
    },
    sourcemap: true,
    emptyOutDir: true,
  },
});
