CORE_GEMS = %w[
  mruby-array-ext
  mruby-hash-ext
  mruby-string-ext
  mruby-numeric-ext
  mruby-range-ext
  mruby-symbol-ext
  mruby-object-ext
  mruby-kernel-ext
  mruby-enum-ext
  mruby-toplevel-ext
  mruby-set
  mruby-math
  mruby-random
  mruby-metaprog
  mruby-error
  mruby-compiler
  mruby-proc-ext
  mruby-method
  mruby-fiber
].freeze

# dont think we need these
#   mruby-catch
#   mruby-enum-lazy
#   mruby-time
#   mruby-bigint
#   mruby-binding
#   mruby-proc-binding


MRuby::Build.new do |conf|
  conf.toolchain
  CORE_GEMS.each { |g| conf.gem core: g }
  conf.cc do |cc|
    cc.flags << "-fPIC"
    cc.flags << "-DMRB_64BIT"
    cc.flags << "-fexceptions"
  end
end

MRuby::CrossBuild.new('emscripten') do |conf|
  conf.toolchain :emscripten
  CORE_GEMS.each { |g| conf.gem core: g }
  # compiler settings for emscripten
  # exception flags come from the emscripten toolchain (`-fwasm-exceptions`).
  # don't add `-fexceptions` here — conflicts with the wasm-native path.
  conf.cc do |cc|
    cc.flags << "-O2"
    # export all symbols so Odin can find them
    cc.flags << "-s EXPORT_ALL=1"
    cc.flags << "-s LINKABLE=1"
  end

  # archiver settings
  conf.archiver do |archiver|
    archiver.command = 'emar'
  end
end
