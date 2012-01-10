module UserContent
  def self.escape(str)
    html = Nokogiri::HTML::DocumentFragment.parse(str)
    html.css('object,embed').each_with_index do |obj, idx|
      styles = {}
      params = {}
      obj.css('param').each do |param|
        params[param['key']] = param['value']
      end
      (obj['style'] || '').split(/\;/).each do |attr|
        key, value = attr.split(/\:/).map(&:strip)
        styles[key] = value
      end
      width = css_size(obj['width'])
      width ||= css_size(params['width'])
      width ||= css_size(styles['width'])
      width ||= '400px'
      height = css_size(obj['height'])
      height ||= css_size(params['height'])
      height ||= css_size(styles['height'])
      height ||= '300px'

      uuid = UUIDSingleton.instance.generate
      child = Nokogiri::XML::Node.new("iframe", html)
      child['class'] = 'user_content_iframe'
      child['name'] = uuid
      child['style'] = "width: #{width}; height: #{height}"
      child['frameborder'] = '0'

      form = Nokogiri::XML::Node.new("form", html)
      form['action'] = "//#{HostUrl.file_host(@domain_root_account || Account.default)}/object_snippet"
      form['method'] = 'post'
      form['class'] = 'user_content_post_form'
      form['target'] = uuid
      form['id'] = "form-#{uuid}"

      input = Nokogiri::XML::Node.new("input", html)
      input['type'] = 'hidden'
      input['name'] = 'object_data'
      snippet = Base64.encode64(obj.to_s).gsub("\n", '')
      input['value'] = snippet
      form.add_child(input)

      s_input = Nokogiri::XML::Node.new("input", html)
      s_input['type'] = 'hidden'
      s_input['name'] = 's'
      s_input['value'] = Canvas::Security.hmac_sha1(snippet)
      form.add_child(s_input)

      obj.replace(child)
      child.add_next_sibling(form)
    end
    html.css('img.equation_image').each do |node|
      mathml = Nokogiri::HTML::DocumentFragment.parse('<span class="hidden-readable">' + Ritex::Parser.new.parse(node.delete('alt').value) + '</span>') rescue next
      node.add_next_sibling(mathml)
    end

    html.to_s.html_safe
  end

  def self.css_size(val)
    res = val.to_f
    res = nil if res == 0
    res = (res + 10).to_s + "px" if res && res.to_s == val
    res
  end

  class HtmlRewriter
    AssetTypes = {
      'assignments' => Assignment,
      'announcements' => Announcement,
      'calendar_events' => CalendarEvent,
      'discussion_topics' => DiscussionTopic,
      'collaborations' => Collaboration,
      'files' => Attachment,
      'conferences' => WebConference,
      'quizzes' => Quiz,
      'groups' => Group,
      'wiki' => WikiPage,
      'grades' => nil,
      'users' => nil,
      'external_tools' => nil,
      'file_contents' => nil,
      'modules' => ContextModule,
    }
    DefaultAllowedTypes = AssetTypes.keys

    def initialize(context, user)
      raise(ArgumentError, "context required") unless context
      @context = context
      @user = user
      # capture group 1 is the object type, group 2 is the object id, if it's
      # there, and group 3 is the rest of the url, including any beginning '/'
      @toplevel_regex = %r{/#{context.class.name.tableize}/#{context.id}/(\w+)(?:/(\d+))?(/[^\s"]*)?}
      @handlers = {}
      @default_handler = nil
      @unknown_handler = nil
      @allowed_types = DefaultAllowedTypes
    end

    attr_reader :user, :context

    class UriMatch < Struct.new(:url, :type, :obj_class, :obj_id, :rest)
    end

    # specify a url type like "assignments" or "file_contents"
    def set_handler(type, &handler)
      @handlers[type] = handler
    end

    def set_default_handler(&handler)
      @default_handler = handler
    end

    def set_unknown_handler(&handler)
      @unknown_handler = handler
    end

    def allowed_types=(new_types)
      @allowed_types = Array(new_types)
    end

    def translate_content(html)
      return html if html.blank?

      asset_types = AssetTypes.reject { |k,v| !@allowed_types.include?(k) }

      html.gsub(@toplevel_regex) do |relative_url|
        type = $1
        obj_id = $2.to_i
        rest = $3
        if asset_types.key?(type)
          match = UriMatch.new(relative_url, type, asset_types[type], (obj_id > 0 ? obj_id : nil), rest)
          handler = @handlers[type] || @default_handler
          (handler && handler.call(match)) || relative_url
        else
          match = UriMatch.new(relative_url, type)
          (@unknown_handler && @unknown_handler.call(match)) || relative_url
        end
      end
    end

    # if content is nil, it'll query the block for the content if needed (lazy content load)
    def user_can_view_content?(content = nil, &get_content)
      return true unless user
      # if user given, check that the user is allowed to manage all
      # context content, or read that specific item (and it's not locked)
      @manage_content ||= context.grants_right?(user, :manage_content)
      return true if @manage_content
      content ||= get_content.call
      allow = true if content.respond_to?(:grants_right?) && content.grants_right?(user, :read)
      allow = false if allow && content.respond_to?(:locked_for?) && content.locked_for?(user)
      return allow
    end
  end
end
