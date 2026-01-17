MRuby::Build.new do |conf|
  # load specific toolchain settings
  conf.toolchain

  # do not include 'everything'
  # conf.gembox 'full-core'

  conf.gem core: 'mruby-array-ext'
  conf.gem core: 'mruby-hash-ext'
  conf.gem core: 'mruby-string-ext'
  conf.gem core: 'mruby-numeric-ext'
  conf.gem core: 'mruby-range-ext'
  conf.gem core: 'mruby-symbol-ext'
  conf.gem core: 'mruby-object-ext'
  conf.gem core: 'mruby-kernel-ext'
  conf.gem core: 'mruby-enum-ext'
  conf.gem core: 'mruby-enum-lazy'
  conf.gem core: 'mruby-toplevel-ext'
  conf.gem core: 'mruby-time'
  conf.gem core: 'mruby-bigint'
  conf.gem core: 'mruby-set'
  conf.gem core: 'mruby-math' # temp?
  conf.gem core: 'mruby-random' # temp?
  conf.gem core: 'mruby-metaprog'
  conf.gem core: 'mruby-error'
  conf.gem core: 'mruby-catch'
  conf.gem core: 'mruby-compiler'
  conf.gem core: 'mruby-fiber'
  conf.gem core: 'mruby-proc-ext'
  conf.gem core: 'mruby-method'
  conf.gem core: 'mruby-binding'
  conf.gem core: 'mruby-proc-binding'

  # C compiler settings
  conf.cc do |cc|
    cc.flags << "-fPIC"
    cc.flags << "-DMRB_64BIT"
    cc.flags << "-fexceptions"
  end

  # turn on bintest and test
  conf.enable_bintest
  conf.enable_test
end

# emscripten/WASM cross-build
MRuby::CrossBuild.new('emscripten') do |conf|
  # use emscripten toolchain
  conf.toolchain :emscripten

  # use full-core gembox for comprehensive functionality
  conf.gembox 'full-core'

  # compiler settings for emscripten
  conf.cc do |cc|
    cc.flags << "-O2"
    cc.flags << "-fexceptions"
    # export all symbols so Odin can find them
    cc.flags << "-s EXPORT_ALL=1"
    cc.flags << "-s LINKABLE=1"
  end

  # archiver settings
  conf.archiver do |archiver|
    archiver.command = 'emar'
  end
end
