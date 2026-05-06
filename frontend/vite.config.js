import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // Toda petición que empiece con /api va al backend
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
      }
    }
  },
})