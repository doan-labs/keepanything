import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['tests/unit/**/*.test.ts', 'tests/parity/**/*.test.ts', 'tests/scenarios/**/*.test.ts'],
    environment: 'node'
  }
})
