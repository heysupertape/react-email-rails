import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    // Vitest 5 default. Keep it explicit so mock call history cannot leak across cases.
    clearMocks: true,
    // Promoted out of experimental in 5.0: reuse transforms across local reruns and CI jobs.
    fsModuleCache: true,
  },
})
