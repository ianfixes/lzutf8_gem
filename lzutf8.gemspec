# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "lzutf8/version"

Gem::Specification.new do |spec|
  spec.name          = "lzutf8"
  spec.version       = LZUTF8::VERSION
  spec.licenses      = ['Apache-2.0']
  spec.authors       = ["Ian Katz"]
  spec.email         = ["ianfixes@gmail.com"]

  spec.summary       = "Compression and decompression implementation of LZUTF-8 Algorithm"
  spec.description   = spec.description
  spec.homepage      = "http://github.com/ianfixes/lzutf8_gem"

  spec.bindir        = "exe"
  rejection_regex    = %r{^(test|spec|features)/}
  libfiles           = Dir['lib/**/*.*'].reject { |f| f.match(rejection_regex) }
  binfiles           = Dir[File.join(spec.bindir, '/**/*.*')].reject { |f| f.match(rejection_regex) }
  spec.files         = ['README.md', '.yardopts'] + libfiles + binfiles

  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
