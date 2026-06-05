module ReactEmailRails; end
module ReactEmailRails::Generators; end

module ReactEmailRails::Generators
  # Candidate Vite config filenames in precedence order; shared by both generators.
  VITE_CONFIG_FILES = [
    "vite.config.ts",
    "vite.config.mts",
    "vite.config.js",
    "vite.config.mjs",
    "vite.config.cts",
    "vite.config.cjs",
  ].freeze
end
