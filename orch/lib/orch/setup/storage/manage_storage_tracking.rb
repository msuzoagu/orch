# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'storage_root_resolver'
require_relative 'storage_tracking'

class StorageTrackingEntryPoint
  def initialize(tracking:, root_resolver:, output:, errors:)
    @tracking = tracking
    @root_resolver = root_resolver
    @output = output
    @errors = errors
  end

  def run(arguments:)
    unless valid_arguments?(arguments)
      @errors.puts(
        'Usage: manage_storage_tracking.rb check PROJECT_ROOT | ' \
        'untrack PROJECT_ROOT --approved'
      )
      return 2
    end

    operation, project_root, approval = arguments
    @root_resolver.resolve(project_root:)
    paths = if operation == 'check'
              @tracking.tracked_paths(project_root:)
            else
              @tracking.untrack(
                project_root:, authorized: approval == '--approved'
              )
            end
    @output.puts(JSON.generate(paths))
    0
  rescue StoragePreparationError, SystemCallError, IOError => error
    @errors.puts("#{error.class}: #{error.message}")
    1
  end

  private

  def valid_arguments?(arguments)
    (arguments.length == 2 && ['check', 'untrack'].include?(arguments.first)) ||
      (arguments.length == 3 && arguments.first == 'untrack' &&
       arguments.last == '--approved')
  end
end

if $PROGRAM_NAME == __FILE__
  entry_point = StorageTrackingEntryPoint.new(
    tracking: StorageTracking.new(command_runner: Open3),
    root_resolver: StorageRootResolver,
    output: $stdout,
    errors: $stderr
  )
  exit(entry_point.run(arguments: ARGV))
end
