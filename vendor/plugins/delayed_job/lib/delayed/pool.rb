require 'optparse'
require 'yaml'
require 'fileutils'

module Delayed
class Pool

  attr_reader :options, :workers

  def initialize(args = ARGV)
    @args = args
    @workers = {}
    @options = {
      :config_file => expand_rails_path("config/delayed_jobs.yml"),
      :pid_folder => expand_rails_path("tmp/pids"),
      :tail_logs => true, # only in FG mode
    }
  end

  def run
    if GC.respond_to?(:copy_on_write_friendly=)
      GC.copy_on_write_friendly = true
    end

    op = OptionParser.new do |opts|
      opts.banner = "Usage #{$0} <command> <options>"
      opts.separator %{\nWhere <command> is one of:
  start      start the jobs daemon
  stop       stop the jobs daemon
  run        start and run in the foreground
  restart    stop and then start the jobs daemon
  status     show daemon status
}

      opts.separator "\n<options>"
      opts.on("-c", "--config", "Use alternate config file (default #{options[:config_file]})") { |c| options[:config_file] = c }
      opts.on("-p", "--pid", "Use alternate folder for PID files (default #{options[:pid_folder]})") { |p| options[:pid_folder] = p }
      opts.on("--no-tail", "Don't tail the logs (only affects non-daemon mode)") { options[:tail_logs] = false }
      opts.on_tail("-h", "--help", "Show this message") { puts opts; exit }
    end
    op.parse!(@args)

    command = @args.shift
    case command
    when 'start'
      daemonize
      start
    when 'stop'
      stop
    when 'run'
      start
    when 'status'
      if status
        exit 0
      else
        exit 1
      end
    when 'restart'
      stop if status(false)
      sleep(0.5) while status(false)
      daemonize
      start
    when nil
      puts op
    else
      raise("Unknown command: #{command.inspect}")
    end
  end

  protected

  def start
    load_rails
    tail_rails_log unless @daemon

    say "Started job master", :info
    $0 = "delayed_jobs_pool"
    read_config(options[:config_file])
    spawn_periodic_auditor
    spawn_all_workers
    say "Workers spawned"
    join
    say "Shutting down"
  rescue Interrupt => e
    say "Signal received, exiting", :info
  rescue Exception => e
    say "Job master died with error: #{e.inspect}\n#{e.backtrace.join("\n")}", :fatal
    raise
  ensure
    remove_pid_file
  end

  def say(msg, level = :debug)
    if defined?(Rails)
      Rails.logger.send(level, "[#{Process.pid}]P #{msg}")
    else
      puts(msg)
    end
  end

  def load_rails
    require(expand_rails_path("config/environment.rb"))
    Dir.chdir(Rails.root)
  end

  def spawn_all_workers
    ActiveRecord::Base.connection_handler.clear_all_connections!

    @config[:workers].each do |worker_config|
      worker_config = worker_config.with_indifferent_access
      (worker_config[:workers] || 1).times { spawn_worker(@config.merge(worker_config)) }
    end
  end

  def spawn_worker(worker_config)
    if worker_config[:periodic]
      return # backwards compat
    else
      queue = worker_config[:queue] || Delayed::Worker.queue
      worker_config[:parent_pid] = Process.pid
      worker = Delayed::Worker.new(worker_config)
    end

    pid = fork do
      Delayed::Job.connection.reconnect!
      Delayed::Periodic.load_periodic_jobs_config
      worker.start
    end
    workers[pid] = worker
  end

  def spawn_periodic_auditor
    return if @config[:disable_periodic_jobs]

    # audit any periodic job overrides for invalid cron lines
    # we do this here to fail as early as possible
    Delayed::Periodic.audit_overrides!

    @periodic_thread = Thread.new do
      # schedule the initial audit immediately on startup
      schedule_periodic_audit
      # initial sleep is randomized, for some staggering in the audit calls
      # since job processors are usually all restarted at the same time
      sleep(rand(15 * 60))
      loop do
        schedule_periodic_audit
        sleep(15 * 60)
      end
    end
  end

  def schedule_periodic_audit
    pid = fork do
      # we want to avoid db connections in the main pool process
      $0 = "delayed_periodic_audit_scheduler"
      Delayed::Periodic.load_periodic_jobs_config
      Delayed::Periodic.audit_queue
    end
    workers[pid] = :periodic_audit
  end

  def join
    loop do
      child = Process.wait
      if child
        worker = workers.delete(child)
        if worker.is_a?(Symbol)
          say "ran auditor: #{worker}"
        else
          say "child exited: #{child}, restarting", :info
          spawn_worker(worker.config)
        end
      end
    end
  end

  def tail_rails_log
    return if !@options[:tail_logs]
    Rails.logger.auto_flushing = true if Rails.logger.respond_to?(:auto_flushing=)
    Thread.new do
      f = File.open(Rails.configuration.log_path.presence || (Rails.root+"log/#{Rails.env}.log"), 'r')
      f.seek(0, IO::SEEK_END)
      loop do
        content = f.read
        content.present? ? STDOUT.print(content) : sleep(0.5)
      end
    end
  end

  def daemonize
    FileUtils.mkdir_p(pid_folder)
    puts "Daemonizing..."

    exit if fork
    Process.setsid
    exit if fork

    @daemon = true
    File.open(pid_file, 'wb') { |f| f.write(Process.pid.to_s) }

    # if we blow up so badly that we can't syslog the error, it has to go to
    # log/delayed_job.log
    last_ditch_logfile = expand_rails_path("log/delayed_job.log")
    STDIN.reopen("/dev/null")
    STDOUT.reopen(last_ditch_logfile, 'a')
    STDERR.reopen(STDOUT)
    STDOUT.sync = STDERR.sync = true
  end

  def pid_folder
    options[:pid_folder]
  end

  def pid_file
    File.join(pid_folder, 'delayed_jobs_pool.pid')
  end

  def remove_pid_file
    return unless @daemon
    pid = File.read(pid_file) if File.file?(pid_file)
    if pid.to_i == Process.pid
      FileUtils.rm(pid_file)
    end
  end

  def stop
    pid = File.read(pid_file) if File.file?(pid_file)
    if pid.to_i > 0
      puts "Stopping pool #{pid}..."
      begin
        Process.kill('INT', pid.to_i)
      rescue Errno::ESRCH
        # ignore if the pid no longer exists
      end
    else
      status
    end
  end

  def status(print = true)
    pid = File.read(pid_file) if File.file?(pid_file)
    alive = pid && pid.to_i > 0 && Process.kill(0, pid.to_i) rescue false
    if alive
      puts "Delayed jobs running, pool PID: #{pid}" if print
    else
      puts "No delayed jobs pool running" if print
    end
    alive
  end

  def read_config(config_filename)
    config = YAML.load_file(config_filename)
    @config = config[Rails.env] || config['default']
    # Backwards compatibility from when the config was just an array of queues
    @config = { :workers => @config } if @config.is_a?(Array)
    @config = @config.with_indifferent_access
    unless @config && @config.is_a?(Hash)
      raise ArgumentError,
        "Invalid config file #{config_filename}"
    end
    Worker::Settings.each do |setting|
      Worker.send("#{setting}=", @config[setting.to_s]) if @config.key?(setting.to_s)
    end
  end

  def expand_rails_path(path)
    File.expand_path("../../../../../../#{path}", __FILE__)
  end

end
end
