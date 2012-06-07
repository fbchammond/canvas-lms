define [
  'jquery'
  'underscore'
  'Backbone'
  'compiled/str/splitAssetString'
], ($, _, Backbone, splitAssetString) ->

  class CalendarEvent extends Backbone.Model

    urlRoot: '/api/v1/calendar_events/'

    dateAttributes: ['created_at', 'end_at', 'start_at', 'updated_at']

    _filterAttributes: (obj) ->
      filtered = _(obj).pick 'start_at', 'end_at', 'title',
                             'description', 'context_code'
      if obj.use_section_dates && obj.child_event_data
        filtered.child_event_data = _.chain(obj.child_event_data)
          .compact()
          .filter(@_hasValidInputs)
          .map(@_filterAttributes)
          .value()
      filtered

    _hasValidInputs: (o) ->
      # has a date, and either has both a start and end time or neither
      o.start_date && (!!o.start_time == !!o.end_time)

    toJSON: (forView) ->
      json = super
      if forView
        json
      else
        {calendar_event: @_filterAttributes(json)}

    fetch: (options = {}) ->
      options =  _.clone(options)
      model = this

      success = options.success
      delete options.success

      error = Backbone.wrapError(options.error, model, options)
      delete options.error

      if @get('id')
        syncDfd = (this.sync || Backbone.sync).call(this, 'read', this, options)
      if @get('sections_url')
        sectionsDfd = $.getJSON @get('sections_url')

      combinedSuccess = (syncArgs=[], sectionArgs=[]) ->
        [syncResp, syncStatus, syncXhr] = syncArgs
        [sectionsResp] = sectionArgs
        calEventData = CalendarEvent.mergeSectionsIntoCalendarEvent(syncResp, sectionsResp)
        return false unless model.set(model.parse(calEventData, syncXhr), options)
        success?(model, calEventData)

      $.when(syncDfd, sectionsDfd)
        .fail(error)
        .done(combinedSuccess)

    @mergeSectionsIntoCalendarEvent = (eventData = {}, sections) ->
      eventData.course_sections =  sections
      eventData.use_section_dates = !!eventData.child_events?.length
      _(eventData.child_events).each (child, index) ->
        # 'parse' turns string dates into Date objects
        child = eventData.child_events[index] = CalendarEvent::parse(child)
        sectionId = splitAssetString(child.context_code)[1]
        section = _(sections).find (section) -> section.id == sectionId
        section.event = child
      eventData

