#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require 'iconv'

class ErrorReport < ActiveRecord::Base
  belongs_to :user
  belongs_to :account
  serialize :http_env
  # misc key/value pairs with more details on the error
  serialize :data, Hash

  before_save :guess_email

  define_callbacks :on_send_to_external

  attr_accessible

  def send_to_external
    run_callbacks(:on_send_to_external)
  end

  class Reporter
    include ActiveSupport::Callbacks
    define_callbacks :on_log_error

    attr_reader :opts, :exception

    def log_error(category, opts)
      opts[:category] = category.to_s
      @opts = opts
      # sanitize invalid encodings
      @opts[:message] = Iconv.conv('UTF-8//IGNORE', 'UTF-8', @opts[:message]) if @opts[:message]
      @opts[:exception_message] = Iconv.conv('UTF-8//IGNORE', 'UTF-8', @opts[:exception_message]) if @opts[:exception_message]
      run_callbacks :on_log_error
      create_error_report(opts)
    end

    def log_exception(category, exception, opts)
      category ||= exception.class.name
      opts[:message] ||= exception.to_s
      opts[:backtrace] = exception.backtrace.try(:join, "\n")
      opts[:exception_message] = exception.to_s
      @exception = exception
      log_error(category, opts)
    end

    def create_error_report(opts)
      report = ErrorReport.new
      report.assign_data(opts)
      report.save
      report
    # rescue
      # we're really hosed here
    end
  end

  # returns the new error report
  def self.log_error(category, opts = {})
    Reporter.new.log_error(category, opts)
  # rescue
  end

  # returns the new error report
  def self.log_exception(category, exception, opts = {})
    Reporter.new.log_exception(category, exception, opts)
  # rescue
  end

  # assigns data attributes to the column if there's a column with that name,
  # otherwise goes into the general data hash
  def assign_data(data = {})
    self.data ||= {}
    data.each do |k,v|
      if respond_to?(:"#{k}=")
        self.send(:"#{k}=", v)
      else
        self.data[k.to_s] = v
      end
    end
  end

  def backtrace=(val)
    if !val || val.length < self.class.maximum_text_length
      write_attribute(:backtrace, val)
    else
      write_attribute(:backtrace, val[0,self.class.maximum_text_length])
    end
  end

  def comments=(val)
    if !val || val.length < self.class.maximum_text_length
      write_attribute(:comments, val)
    else
      write_attribute(:comments, val[0,self.class.maximum_text_length])
    end
  end
  
  def guess_email
    self.email = nil if self.email && self.email.empty?
    self.email ||= self.user.email rescue nil
    unless self.email
      domain = HostUrl.outgoing_email_domain.gsub(/[^a-zA-Z0-9]/, '-')
      # example.com definitely won't exist
      self.email = "unknown-#{domain}@instructure.example.com"
    end
    self.email
  end

  # delete old error reports before a given date
  # returns the number of destroyed error reports
  def self.destroy_error_reports(before_date)
    self.delete_all(['created_at < ?', before_date])
  end

  def self.useful_http_env_stuff_from_request(request)
    stuff = request.env.slice( *["HTTP_ACCEPT", "HTTP_ACCEPT_ENCODING", "HTTP_COOKIE", "HTTP_HOST", "HTTP_REFERER",
                         "HTTP_USER_AGENT", "PATH_INFO", "QUERY_STRING", "REMOTE_HOST",
                         "REQUEST_METHOD", "REQUEST_PATH", "REQUEST_URI", "SERVER_NAME", "SERVER_PORT",
                         "SERVER_PROTOCOL", "action_controller.request.path_parameters"] )
    stuff['REMOTE_ADDR'] = request.remote_ip # ActionController::Request#remote_ip has proxy smarts
    stuff
  end

  def self.categories
    distinct('category')
  end

  on_send_to_external do |error_report|
    config = Canvas::Plugin.find('error_reporting').try(:settings) || {}

    message_type = (error_report.backtrace || "").split("\n").first.match(/\APosted as[^_]*_([A-Z]*)_/)[1] rescue nil
    message_type ||= "ERROR"
    
    body = %{From #{error_report.email}, #{(error_report.user.name rescue "")}
#{message_type} #{error_report.comments + "\n" if error_report.comments}
#{"url: " + error_report.url + "\n" if error_report.url }

#{"user_id: " + (error_report.user_id.to_s) + "\n" if error_report.user_id}
error_id: #{error_report.id}

#{error_report.message + "\n" if error_report.message}
}

    if config[:action] == 'post' && config[:url] && config[:subject_param] && config[:body_param]
      params = {}
      params[config[:subject_param]] = error_report.subject
      params[config[:body_param]] = body
      Net::HHTP.post_form(URI.parse(config[:url]), params)
    elsif config[:action] == 'email' && config[:email]
      Message.create!(
        :to => config[:email],
        :from => "#{error_report.email}",
        :subject => "#{error_report.subject} (#{message_type})",
        :body => body,
        :delay_for => 0,
        :context => error_report
      )
    end
  end
end
