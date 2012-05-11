module Delayed
class Periodic
  attr_reader :name, :cron

  yaml_as "tag:ruby.yaml.org,2002:Delayed::Periodic"

  def to_yaml(opts = {})
    YAML.quick_emit(self.object_id, opts) { |out| out.scalar(taguri, @name) }
  end

  def self.yaml_new(klass, tag, val)
    self.scheduled[val] || raise(ArgumentError, "job #{val} is no longer scheduled")
  end

  cattr_accessor :scheduled
  self.scheduled = {}

  # throws an error if any cron override in config/periodic_jobs.yml is invalid
  def self.audit_overrides!
    overrides = Setting.from_config('periodic_jobs') || {}
    overrides.each do |name, cron_line|
      # throws error if the line is malformed
      Rufus::CronLine.new(cron_line)
    end
  end

  def self.load_periodic_jobs_config
    require Rails.root+'config/periodic_jobs'

    # schedule the built-in unlocking job
    self.cron('Unlock Expired Jobs', '*/5 * * * *') do
      Delayed::Job.unlock_expired_jobs
    end
  end

  STRAND = 'periodic scheduling'

  def self.cron(job_name, cron_line, job_args = {}, &block)
    raise ArgumentError, "job #{job_name} already scheduled!" if self.scheduled[job_name]
    override = (Setting.from_config('periodic_jobs') || {})[job_name]
    cron_line = override if override
    self.scheduled[job_name] = self.new(job_name, cron_line, job_args, block)
  end

  def self.audit_queue
    if 0 == Delayed::Job.count(:conditions => ['tag = ? and failed_at is null', 'Delayed::Periodic.perform_audit!'])
      # this isn't running in a delayed job, so there are race conditions -- but
      # that's ok, because having the audit performed twice is safe (due to the
      # strand), just a bit of extra work.
      self.send_later_enqueue_args(:perform_audit!, { :strand => STRAND })
    end
  end

  # make sure all periodic jobs are scheduled for their next run in the job queue
  # this auditing should run on the strand
  def self.perform_audit!
    self.scheduled.each do |name, periodic|
      if 0 == Delayed::Job.count(:conditions => ['tag = ? and failed_at is null', periodic.tag])
        periodic.enqueue
      end
    end
  end

  def initialize(name, cron_line, job_args, block)
    @name = name
    @cron = Rufus::CronLine.new(cron_line)
    @job_args = { :priority => Delayed::LOW_PRIORITY }.merge(job_args.symbolize_keys)
    @block = block
  end

  def enqueue
    Delayed::Job.enqueue(self, @job_args.merge(:max_attempts => 1, :run_at => @cron.next_time))
  end

  def perform
    @block.call()
  ensure
    begin
      enqueue
    rescue
      # double fail! the auditor will have to catch this.
      Rails.logger.error "Failure enqueueing periodic job! #{@name} #{$!.inspect}"
    end
  end

  def tag
    "periodic: #{@name}"
  end
  alias_method :display_name, :tag
end
end
