require File.expand_path(File.dirname(__FILE__) + '/common')

describe "course wizard" do
  it_should_behave_like "in-process server selenium tests"

  before do
    setup_permissions(true, true, true)
  end

  VALID_EMAILS = ["jake@example.com", "test@example.com", "hey@example.com", "new@example.com", "what@example.com"]

  def setup_permissions(is_open_registration, is_no_enrollments_can_create_courses, can_teachers_create_courses)
    account = Account.default
    account.settings = {:open_registration => is_open_registration,
                        :no_enrollments_can_create_courses => is_no_enrollments_can_create_courses,
                        :teachers_can_create_courses => can_teachers_create_courses
    }
    account.save!
  end

  def start_course
    expected_text = 'Unnamed'
    course_with_teacher_logged_in
    get "/getting_started?fresh=1"
    course_name = driver.find_element(:css, '#course_name')
    short_course_name = driver.find_element(:css, '#course_course_code')
    course_name.clear
    short_course_name.clear
    expected_text
  end

  def add_assignment(num_to_add)
    expect {
      num_to_add.times do
        driver.find_element(:css, '.add_assignment_link').click
        driver.find_element(:css, '#add_assignment_form').submit
        wait_for_ajax_requests
      end
    }.to change(Assignment, :count).by(num_to_add)
    driver.find_element(:css, '.no_assignments_message').should_not be_displayed
  end

  def fill_out_add_students_text(text_to_add)
    user_list = driver.find_element(:css, '.user_list')
    continue_button = driver.find_element(:css, '.verify_syntax_button')
    if (text_to_add.kind_of? Array)
      user_list.clear
      text_to_add.each do |el|
        user_list.send_keys(el)
        user_list.send_keys(:return)
      end
    else
      user_list.clear
      user_list.send_keys(text_to_add)
    end
    continue_button.click
    wait_for_ajax_requests
  end

  def add_students
    expect {
      fill_out_add_students_text(VALID_EMAILS)
      driver.find_element(:css, '.add_users_button').click
      wait_for_ajax_requests
    }.to change(User, :count).by(VALID_EMAILS.size)
    VALID_EMAILS.size
  end

  it "should add an assignment to the course" do
    start_course
    get "/getting_started/assignments"
    add_assignment(1)
  end

  def validate_assignment_addition
    driver.find_element(:css, '.no_assignments_message').should_not be_displayed
  end

  it "should create an assignment group and add a new assignment to it" do
    #adding new assignment group
    group_name = 'Group Test'
    start_course
    get "/getting_started/assignments"

    expect {
      driver.find_element(:css, '.add_group_link').click
      group_text = driver.find_element(:css, '#assignment_group_name')
      group_text.clear
      group_text.send_keys(group_name)
      driver.find_element(:css, '#add_group_form').submit
      wait_for_ajax_requests
    }.to change(AssignmentGroup, :count).by(1)

    #adding assignment to new group
    add_assignment(1)
  end

  it "should not create two assignments when using more options in the wizard" do
    start_course
    expect {
      expect_new_page_load { driver.find_element(:css, ".next_step_button").click }
      driver.find_element(:css, ".add_assignment_link").click
      expect_new_page_load { driver.find_element(:css, ".more_options_link").click }
      expect_new_page_load { driver.find_element(:css, "#edit_assignment_form button[type='submit']").click }
    }.to change(Assignment, :count).by(1)
    validate_assignment_addition
  end

  it "should validate xss doesn't happen when adding students'" do
    xss_text = "<b>testing@test.com</b>"

    start_course
    get "/getting_started/students"

    #xss test
    fill_out_add_students_text(xss_text)

    driver.find_element(:css, '#user_list_no_valid_users').should be_displayed
  end

  it "should not allow invalid email addresses when adding students" do
    invalid_emails = ["jake", "hey", "what", "who"]

    start_course
    get "/getting_started/students"

    #invalid email
    fill_out_add_students_text(invalid_emails)

    driver.find_element(:css, '#user_list_no_valid_users').should be_displayed
  end

  it "should verify that valid emails were added as students" do
    start_course
    get "/getting_started/students"

    #normal add
    add_students
  end

  it "should add students and verify the removal a student" do
    start_course
    get "/getting_started/students"
    num_students_added = add_students
    find_with_jquery('.unenroll_user_link:visible').click
    driver.switch_to.alert.accept
    driver.switch_to.default_content
    wait_for_ajaximations
    num_students_added -= 1
    expect_new_page_load { driver.find_element(:css, '.next_step_button').click }
    student_table_rows = driver.find_element(:css, '#student_list .summary').find_elements(:css, 'tr').length

    #have to do -1 because there is no better way to get the rows with css
    num_students_added.should == student_table_rows - 1
  end

  it "should add students go to the next page and go back to add more students" do
    pending("Bug where students are deleted from student list when going back to the add students page")
    start_course
    get "/getting_started/students"
    num_students_added = add_students
    expect_new_page_load { driver.find_element(:css, '.next_step_button').click }
    expect_new_page_load { driver.find_element(:css, '.previous_step_button').click }
    student_count = driver.find_element(:css, '.student_count').text
    student_count.to_i.should == num_students_added
  end

  it "should navigate directly to the last page, save course, and verify course creation" do
    expected_text = 'Course-101'
    start_course
    get "/getting_started/setup"
    expect_new_page_load { driver.find_element(:css, '#publish_course_url').submit }
    driver.find_element(:css, '#section-tabs-header').text.should == expected_text
  end

  it "should click the save and skip on the first page and verify course creation" do
    expected_text = start_course
    expect_new_page_load { driver.find_element(:css, '.save_button').click }
    driver.find_element(:css, '#section-tabs-header').text.should == expected_text
  end

  it "should validate false for teacher can create course account permission" do
    setup_permissions(true, true, false)
    course_with_teacher_logged_in
    get "/"
    driver.find_elements(:link, 'Start a New Course').should be_empty
  end

  it "should validate false for open registration account permission" do
    setup_permissions(false, true, true)
    start_course
    get "/getting_started/students"
    expect {
      fill_out_add_students_text(VALID_EMAILS)
      driver.find_element(:css, '#user_list_no_valid_users').should be_displayed
    }.to change(User, :count).by(0)
  end

  it "should validate false for no enrollments can create courses account permission" do
    setup_permissions(true, false, true)
    user_logged_in
    get "/"
    driver.find_elements(:link, 'Start a New Course').should be_empty
  end
end