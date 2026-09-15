import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    // Vitest 5 no longer searches ancestor directories for a config, so scope the
    // suite explicitly and keep the type-check fixtures under test/types/ out of it.
    include: ["test/**/*.test.ts"],
  },
})
