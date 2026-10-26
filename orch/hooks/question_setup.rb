# frozen_string_literal: true

require 'json'
require_relative '../lib/orch/hooks/question_setup_hook'

class QuestionSetupHookEntryPoint
  def initialize(hook:, input:, output:, errors:)
    @hook = hook
    @input = input
    @output = output
    @errors = errors
  end

  def run(arguments:)
    unless arguments.empty?
      @errors.puts('Usage: question_setup.rb < HOOK_INPUT_JSON')
      return 2
    end

    result = @hook.call(payload: JSON.parse(@input.read))
    @output.puts(JSON.generate(result)) unless result.nil?
    0
  rescue JSON::ParserError
    @errors.puts('Question Setup hook: invalid JSON input (JSON::ParserError).')
    2
  rescue KeyError, ArgumentError, SystemCallError, IOError => error
    @errors.puts("Question Setup hook: #{error.class}: #{error.message}")
    2
  end
end

if $PROGRAM_NAME == __FILE__
  setup_skill_path = File.expand_path('../skills/setup/SKILL.md', __dir__)
  hook = QuestionSetupHook.new(setup_skill_path: setup_skill_path)
  entry_point = QuestionSetupHookEntryPoint.new(
    hook: hook,
    input: $stdin,
    output: $stdout,
    errors: $stderr
  )
  exit(entry_point.run(arguments: ARGV))
end
