# frozen_string_literal: true

# Translates repository-scoped Git checks into true, false, or an error.
class GitIgnoreChecker
  def initialize(command_runner:)
    @command_runner = command_runner
  end

  def ignored?(project_root:)
    _output, diagnostic, status = @command_runner.capture3(
      { 'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1' },
      'git', '-C', project_root, 'check-ignore', '--', 'wr/'
    )

    case status.exitstatus
    when 0
      true
    when 1
      false
    else
      raise(
        GitIgnoreError,
        "Check ignore rules in #{project_root}: " \
        "#{status}: #{diagnostic.strip}"
      )
    end
  rescue SystemCallError, IOError => error
    raise(
      GitIgnoreError,
      "Check ignore rules in #{project_root}: " \
      "#{error.class}: #{error.message}"
    )
  end
end
