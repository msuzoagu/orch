# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'fiddle'

def non_system_native_libraries
  handle = Fiddle::Handle::DEFAULT
  image_count = Fiddle::Function.new(
    handle['_dyld_image_count'], [], Fiddle::TYPE_INT
  )
  image_name = Fiddle::Function.new(
    handle['_dyld_get_image_name'], [Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP
  )

  Array.new(image_count.call) do |index|
    image_name.call(index).to_s
  end.reject do |path|
    path.start_with?('/System/Library/', '/usr/lib/')
  end
end

def runtime_delivery_diagnostic
  {
    'RubyVersion' => RUBY_VERSION,
    'RubyPlatform' => RUBY_PLATFORM,
    'Executable' => RbConfig.ruby,
    'RuntimeRoot' => File.realpath(RbConfig::CONFIG.fetch('prefix')),
    'WorkingDirectory' => Dir.pwd,
    'GemPaths' => Gem.path,
    'GemVersions' => Gem.loaded_specs.transform_values do |spec|
      spec.version.to_s
    end,
    'LoadedRubyFiles' => $LOADED_FEATURES.select do |path|
      path.start_with?('/')
    end,
    'NonSystemNativeLibraries' => non_system_native_libraries,
    'JSONRoundTrip' => JSON.parse(JSON.generate({ 'ready' => true }))
  }
end

if $PROGRAM_NAME == __FILE__
  begin
    unless ARGV.empty?
      raise(
        ArgumentError, 'runtime_delivery_diagnostic.rb accepts no arguments'
      )
    end

    puts(JSON.pretty_generate(runtime_delivery_diagnostic))
  rescue StandardError => error
    warn(
      "Runtime delivery diagnostic failed: #{__FILE__}: " \
      "#{error.class}: #{error.message}"
    )
    exit(1)
  end
end
