# RubyLLM logs whole request and response bodies, which carry document text,
# whenever its logger is at debug. Its lines go to the Rails log through this
# logger, which never drops below info, so RAILS_LOG_LEVEL=debug does not
# turn that on.
class RubyLLMLogger < Logger
  def initialize(target)
    super(nil, progname: "RubyLLM", level: :info)
    @target = target
  end

  def level
    [ super, Logger::INFO ].max
  end

  def add(severity, message = nil, progname = nil, &)
    severity ||= Logger::UNKNOWN
    return true if severity < level

    @target.add(severity, message, progname || self.progname, &)
  end
  alias_method :log, :add
end
