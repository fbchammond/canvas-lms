require File.expand_path(File.dirname(__FILE__) + '/common')
require File.expand_path(File.dirname(__FILE__) + '/calendar2_common')

describe "calendar2" do
  it_should_behave_like "calendar2 selenium tests"

  def make_event(params = {})
    opts = {
        :context => @user,
        :start => Time.now,
        :description => "Test event"
    }.with_indifferent_access.merge(params)
    c = CalendarEvent.new :description => opts[:description],
                          :start_at => opts[:start],
                          :title => opts[:title]
    c.context = opts[:context]
    c.save!
    c
  end

  def find_middle_day
    driver.find_element(:css, '.calendar .fc-week1 .fc-wed')
  end

  def change_calendar(css_selector = '.fc-button-next')
    driver.find_element(:css, '.calendar .fc-header-left ' + css_selector).click
    wait_for_ajax_requests
  end

  def add_date(middle_number)
    find_with_jquery('.ui-datepicker-trigger:visible').click
    datepicker_current(middle_number)
  end

  def create_assignment_event(assignment_title, should_add_date = false)
    middle_number = find_middle_day.find_element(:css, '.fc-day-number').text
    find_middle_day.click
    edit_event_dialog = driver.find_element(:id, 'edit_event_tabs')
    edit_event_dialog.should be_displayed
    edit_event_dialog.find_element(:css, '.edit_assignment_option').click
    edit_assignment_form = edit_event_dialog.find_element(:id, 'edit_assignment_form')
    title = edit_assignment_form.find_element(:id, 'assignment_title')
    replace_content(title, assignment_title)
    add_date(middle_number) if should_add_date
    edit_assignment_form.submit
    wait_for_ajax_requests
    #find_with_jquery(".fc-day-number:contains(#{middle_number})").click
    keep_trying_until { driver.find_element(:css, '.fc-view-month .fc-event-title').should include_text(assignment_title) }
  end

  def create_calendar_event(event_title, should_add_date = false)
    middle_number = find_middle_day.find_element(:css, '.fc-day-number').text
    edit_event_dialog = driver.find_element(:id, 'edit_event_tabs')
    edit_event_dialog.should be_displayed
    edit_event_form = edit_event_dialog.find_element(:id, 'edit_calendar_event_form')
    title = edit_event_form.find_element(:id, 'calendar_event_title')
    replace_content(title, event_title)
    add_date(middle_number) if should_add_date
    edit_event_form.submit
    wait_for_ajax_requests
    #find_with_jquery(".fc-day-number:contains(#{middle_number})").click
    keep_trying_until { driver.find_element(:css, '.fc-view-month .fc-event-title').should include_text(event_title) }
  end


  context "as a teacher" do

    before (:each) do
      course_with_teacher_logged_in
    end

    it "should allow viewing an unenrolled calendar via include_contexts" do
      # also make sure the redirect from calendar -> calendar2 keeps the param
      unrelated_course = Course.create!(:account => Account.default, :name => "unrelated course")
      # make the user an admin so they can view the course's calendar without an enrollment
      Account.default.add_user(@user)
      CalendarEvent.create!(:title => "from unrelated one", :start_at => Time.now, :end_at => 5.hours.from_now) { |c| c.context = unrelated_course }
      get "/courses/#{unrelated_course.id}/settings"
      expect_new_page_load { driver.find_element(:css, "#course_calendar_link").click() }
      wait_for_ajax_requests
      # only the explicit context should be selected
      driver.find_element(:css, "#context-list li[data-context=course_#{unrelated_course.id}]").should have_class('checked')
      driver.find_element(:css, "#context-list li[data-context=course_#{@course.id}]").should have_class('not-checked')
      driver.find_element(:css, "#context-list li[data-context=user_#{@user.id}]").should have_class('not-checked')
    end

    describe "sidebar" do

      describe "mini calendar" do

        it "should add the event class to days with events" do
          c = make_event
          get "/calendar2"
          wait_for_ajax_requests

          events = driver.find_elements(:css, "#minical .event")
          events.size.should == 1
          events.first.text.strip.should == c.start_at.day.to_s
        end

        it "should change the main calendar's month on click" do
          title_selector = "#calendar-app .fc-header-title"
          get "/calendar2"

          orig_title = driver.find_element(:css, title_selector).text
          driver.find_element(:css, "#minical .fc-other-month").click

          orig_title.should_not == driver.find_element(:css, title_selector)
        end
      end

      describe "contexts list" do
        it "should have a menu for adding stuff" do
          get "/calendar2"

          contexts = driver.find_elements(:css, "#context-list > li")

          # first context is the user
          actions = contexts[0].find_elements(:css, "li > a")
          actions.size.should == 1
          actions.first["data-action"].should == "add_event"

          # course context
          actions = contexts[1].find_elements(:css, "li > a")
          actions.size.should == 2
          actions.first["data-action"].should == "add_event"
          actions.second["data-action"].should == "add_assignment"
        end

        it "should create an event through the context list drop down" do
          event_title = 'new event'
          get "/calendar2"
          wait_for_ajaximations

          driver.execute_script(%{$(".context_list_context:nth-child(2)").trigger('mouseenter')})
          find_with_jquery('ul#context-list li:nth-child(2) button').click
          driver.find_element(:id, "ui-menu-1-0").click
          edit_event_dialog = driver.find_element(:id, 'edit_event_tabs')
          edit_event_dialog.should be_displayed
          create_calendar_event(event_title, true)
        end

        it "should create an assignment through the context list drop down" do
          assignment_title = 'new assignment'
          get "/calendar2"
          wait_for_ajaximations

          driver.execute_script(%{$(".context_list_context:nth-child(2)").trigger('mouseenter')})
          find_with_jquery('ul#context-list li:nth-child(2) button').click
          driver.find_element(:id, "ui-menu-1-1").click
          edit_event_dialog = driver.find_element(:id, 'edit_event_tabs')
          edit_event_dialog.should be_displayed
          create_assignment_event(assignment_title, true)
        end

        it "should toggle event display when context is clicked" do
          make_event :context => @course, :start => Time.now
          get "/calendar2"

          driver.find_element(:css, '.context_list_context').click
          context_course_item = find_with_jquery('.context_list_context:nth-child(2)')
          context_course_item.should have_class('checked')
          driver.find_element(:css, '.fc-event').should be_displayed

          context_course_item.click
          context_course_item.should have_class('not-checked')
          element_exists('.fc_event').should be_false
        end

        it "should validate calendar feed display" do
          get "/calendar2"

          driver.find_element(:link, 'Calendar Feed').click
          driver.find_element(:id, 'calendar_feed_box').should be_displayed
        end
      end

      describe "undated calendar items" do
        it "should show undated events after clicking link" do
          e = make_event :start => nil, :title => "pizza party"
          get "/calendar2"

          driver.find_element(:css, ".undated-events-link").click
          wait_for_ajaximations
          undated_events = driver.find_elements(:css, "#undated-events > ul > li")
          undated_events.size.should == 1
          undated_events.first.text.should =~ /#{e.title}/
        end
      end
    end

    describe "main calendar" do

      def get_header_text
        header = driver.find_element(:css, '.calendar .fc-header .fc-header-title')
        header.text
      end

      it "should create an event through clicking on a calendar day" do
        get "/calendar2"
        find_middle_day.click
        create_calendar_event('new event')
      end

      it "should create an assignment by clicking on a calendar day" do
        get "/calendar2"
        find_middle_day.click
        create_assignment_event('new assignment')
      end

      it "more options link should go to calendar_event edit page" do
        get "/calendar2"
        find_middle_day.click
        create_calendar_event('new event')

        driver.find_element(:css, '.fc-event').click
        find_with_jquery('.popover-links-holder:visible').should_not be_nil
        f('.event-details-links .edit_event_link').click
        expect_new_page_load { f('#edit_calendar_event_form .more_options_link').click }
        f('#breadcrumbs').text.should include 'Calendar Events'
      end

      it "more options link on assignments should go to assignment edit page" do
        get "/calendar2"
        create_assignment_event('super big assignment')
        f('.fc-event.assignment').click
        f('.edit_event_link').click
        expect_new_page_load { f('.more_options_link').click }
        f('h2.title').text.should include "super big assignment"
      end

      it "editing an existing assignment should select the correct assignment group" do
        group1 = @course.assignment_groups.create!(:name => "Assignment Group 1")
        group2 = @course.assignment_groups.create!(:name => "Assignment Group 2")
        @course.active_assignments.create(:name => "Assignment 1", :assignment_group => group1, :due_at => Time.zone.now)
        assignment2 = @course.active_assignments.create(:name => "Assignment 2", :assignment_group => group2, :due_at => Time.zone.now)

        get "/calendar2"

        events = driver.find_elements(:css, '.fc-event')
        event1 = events.detect { |e| e.text =~ /Assignment 1/ }
        event2 = events.detect { |e| e.text =~ /Assignment 2/ }
        event1.should_not be_nil
        event2.should_not be_nil
        event1.should_not == event2

        event1.click
        driver.find_element(:css, '.popover-links-holder .edit_event_link').click
        select = driver.find_element(:css, '#edit_assignment_form .assignment_group')
        select = Selenium::WebDriver::Support::Select.new(select)
        select.first_selected_option.attribute(:value).to_i.should == group1.id
        close_visible_dialog

        event2.click
        driver.find_element(:css, '.popover-links-holder .edit_event_link').click
        select = driver.find_element(:css, '#edit_assignment_form .assignment_group')
        select = Selenium::WebDriver::Support::Select.new(select)
        select.first_selected_option.attribute(:value).to_i.should == group2.id
        driver.find_element(:css, 'div.ui-dialog #assignment_title').tap { |tf| tf.clear; tf.send_keys("Assignment 2!") }
        driver.find_element(:css, 'div.ui-dialog button[type=submit]').click
        wait_for_ajax_requests
        assignment2.reload.title.should == "Assignment 2!"
        assignment2.assignment_group.should == group2
      end

      it "should change the month" do
        get "/calendar2"
        old_header_title = get_header_text
        change_calendar
        old_header_title.should_not == get_header_text
      end

      it "should change the week" do
        get "/calendar2"
        header_buttons = driver.find_elements(:css, '.ui-buttonset > label')
        header_buttons[0].click
        wait_for_ajaximations
        old_header_title = get_header_text
        change_calendar('.fc-button-prev')
        old_header_title.should_not == get_header_text
      end

      it "should test the today button" do
        get "/calendar2"
        current_month_num = Time.now.month
        current_month = Date::MONTHNAMES[current_month_num]

        change_calendar
        get_header_text.should_not == current_month
        driver.find_element(:css, '.fc-button-today').click
        get_header_text.should == (current_month + ' ' + Time.now.year.to_s)
      end

      it "should show section-level events, but not the parent event" do
        @course.default_section.update_attribute(:name, "default section!")
        s2 = @course.course_sections.create!(:name => "other section!")
        date = Date.today
        e1 = @course.calendar_events.build :title => "ohai",
          :child_event_data => [
            {:start_at => "#{date} 12:00:00", :end_at => "#{date} 13:00:00", :context_code => @course.default_section.asset_string},
            {:start_at => "#{date} 13:00:00", :end_at => "#{date} 14:00:00", :context_code => s2.asset_string},
          ]
        e1.updating_user = @user
        e1.save!

        get "/calendar2"
        wait_for_ajaximations
        events = ff('.fc-event')
        events.size.should eql 2
        events.first.click

        details = f('.event-details')
        details.should_not be_nil
        details.text.should include(@course.default_section.name)
        details.find_element(:css, '.view_event_link')[:href].should include "/calendar_events/#{e1.id}" # links to parent event
      end

      context "event editing" do
        it "should allow editing appointment events" do
          create_appointment_group
          ag = AppointmentGroup.first
          student_in_course(:course => @course, :active_all => true)
          ag.appointments.first.reserve_for(@user, @user)

          get "/calendar2"
          wait_for_ajaximations

          open_edit_event_dialog
          description = 'description...'
          replace_content f('[name=description]'), description
          fj('.ui-button:contains(Update)').click
          wait_for_ajaximations

          ag.reload.appointments.first.description.should eql description
          lambda { f('.fc-event') }.should_not raise_error
        end
      end
    end

  end

  context "as a student" do

    before (:each) do
      @student = course_with_student_logged_in(:active_all => true).user
    end

    describe "contexts list" do

      it "should not allow a student to create an assignment through the context list" do
        get "/calendar2"
        wait_for_ajaximations

        keep_trying_until do
          driver.execute_script(%{$(".context_list_context:nth-child(1)").addClass('hovering')})
          find_with_jquery('ul#context-list li:nth-child(1) button').click
          driver.find_element(:id, "ui-menu-0-0").click
          edit_event_dialog = driver.find_element(:id, 'edit_event_tabs')
          edit_event_dialog.should be_displayed
        end
        tabs = find_all_with_jquery('.tab_list > li')
        tabs.count.should == 1
        tabs[0].should include_text('Event')
      end
    end

    describe "main calendar" do

      it "should validate that a student cannot edit an assignment" do
        @course.active_assignments.create(:name => "Assignment 1", :due_at => Time.zone.now)
        get "/calendar2"
        wait_for_ajaximations

        driver.find_element(:css, '.fc-event-title').click
        driver.find_element(:id, "popover-0").should be_displayed
        element_exists('.edit_event_link').should be_false
        element_exists('.delete_event_link').should be_false
      end

      it "should validate appointment group popup link functionality" do
        pending("bug 6986 - clicking on the name of an appointment group in a popup should take user to scheduler") do
          ag = create_appointment_group
          ag.appointments.first.reserve_for @student, @me
          @user = @me
          get "/calendar2"
          wait_for_ajaximations

          driver.find_element(:css, '.fc-event-title').click
          popover = driver.find_element(:id, "popover-0")
          popover.should be_displayed
          expect_new_page_load { popover.find_element(:css, '.view_event_link').click }
          wait_for_ajaximations
          is_checked('#scheduler').should be_true
          driver.find_element(:id, 'appointment-group-list').should include_text(ag.title)
        end
      end

      it "should show section-level events for the student's section" do
        @course.default_section.update_attribute(:name, "default section!")
        s2 = @course.course_sections.create!(:name => "other section!")
        date = Date.today
        e1 = @course.calendar_events.build :title => "ohai",
          :child_event_data => [
            {:start_at => "#{date} 12:00:00", :end_at => "#{date} 13:00:00", :context_code => s2.asset_string},
            {:start_at => "#{date} 13:00:00", :end_at => "#{date} 14:00:00", :context_code => @course.default_section.asset_string},
          ]
        e1.updating_user = @teacher
        e1.save!

        get "/calendar2"
        wait_for_ajaximations
        events = ff('.fc-event')
        events.size.should eql 1
        events.first.text.should include "1p"
        events.first.click

        details = f('.event-details-content')
        details.should_not be_nil
        details.text.should include(@course.default_section.name)
      end

      it "should redirect to the calendar and show the selected event" do
        event = make_event(:context => @course, :start => 2.months.from_now, :title => "future event")
        get "/courses/#{@course.id}/calendar_events/#{event.id}"
        wait_for_ajaximations

        popup_title = f('.details_title')
        popup_title.should be_displayed
        popup_title.text.should eql "future event"
      end
    end
  end
end
