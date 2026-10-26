# frozen_string_literal: true

class QuestionSetupHook
  def initialize(setup_skill_path:)
    unless setup_skill_path.is_a?(String) && setup_skill_path.start_with?('/')
      raise(ArgumentError, 'Setup skill path must be absolute.')
    end

    @setup_skill_path = setup_skill_path
  end

  def call(payload:)
    unless payload.is_a?(Hash)
      raise(ArgumentError, 'Hook input must be a JSON object.')
    end

    event = payload.fetch('hook_event_name')
    unless event.is_a?(String)
      raise(ArgumentError, 'Hook event name must be a string.')
    end
    return nil unless event == 'UserPromptSubmit'

    prompt = payload.fetch('prompt')
    unless prompt.is_a?(String)
      raise(ArgumentError, 'Hook prompt must be a string.')
    end
    return nil unless prompt.match?(/\A\s*@orch:question(?=\s|\z)/)

    {
      'hookSpecificOutput' => {
        'hookEventName' => 'UserPromptSubmit',
        'additionalContext' => setup_instructions
      }
    }
  end

  private

  def setup_instructions
    "Before Question intake, read #{@setup_skill_path.dump} in its " \
      'entirety and execute the Setup skill workflow. Reading alone ' \
      'does not execute Setup. Follow the target project permissions ' \
      'and Setup instructions for authorization, waiting, and stopping. ' \
      'Preserve the supplied Question verbatim. Resume this same ' \
      'Question invocation only after Setup succeeds; do not ask the ' \
      'Human to invoke Setup separately or submit the Question again.'
  end
end
