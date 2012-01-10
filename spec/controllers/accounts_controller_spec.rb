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

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe AccountsController do
  def account_with_admin_logged_in(opts = {})
    @account = Account.default
    account_admin_user
    user_session(@admin)
  end

  def cross_listed_course
    account_with_admin_logged_in
    @account1 = Account.create!
    @account1.add_user(@user)
    @course1 = @course
    @course1.account = @account1
    @course1.save!
    @account2 = Account.create!
    @course2 = course
    @course2.account = @account2
    @course2.save!
    @course2.course_sections.first.crosslist_to_course(@course1)
  end

  context "confirm_delete_user" do
    it "should confirm deletion of canvas-authenticated users" do
      account_with_admin_logged_in
      user_with_pseudonym :account => @account
      get 'confirm_delete_user', :account_id => @account.id, :user_id => @user.id
      response.should be_success
    end

    it "should not confirm deletion of non-existent users" do
      account_with_admin_logged_in
      get 'confirm_delete_user', :account_id => @account.id, :user_id => (User.all.map(&:id).max + 1)
      response.should redirect_to(account_url(@account))
      flash[:error].should =~ /No user found with that id/
    end

    it "should confirm deletion of managed password users" do
      account_with_admin_logged_in
      user_with_managed_pseudonym :account => @account
      get 'confirm_delete_user', :account_id => @account.id, :user_id => @user.id
      response.should be_success
    end
  end

  context "remove_user" do
    it "should delete canvas-authenticated users" do
      account_with_admin_logged_in
      user_with_pseudonym :account => @account
      @user.workflow_state.should == "pre_registered"
      post 'remove_user', :account_id => @account.id, :user_id => @user.id
      flash[:notice].should =~ /successfully deleted/
      response.should redirect_to(account_users_url(@account))
      @user.reload
      @user.workflow_state.should == "deleted"
    end

    it "should do nothing for non-existent users as html" do
      account_with_admin_logged_in
      post 'remove_user', :account_id => @account.id, :user_id => (User.all.map(&:id).max + 1)
      flash[:notice].should be_nil
      response.should redirect_to(account_users_url(@account))
    end

    it "should do nothing for non-existent users as json" do
      account_with_admin_logged_in
      post 'remove_user', :account_id => @account.id, :user_id => (User.all.map(&:id).max + 1), :format => "json"
      flash[:notice].should be_nil
      json_parse(response.body).should == {}
    end

    it "should only remove users from the current account if the user exists in multiple accounts" do
      @other_account = account_model
      account_with_admin_logged_in
      user_with_pseudonym :account => @account, :username => "nobody@example.com"
      pseudonym @user, :account => @other_account, :username => "nobody2@example.com"
      @user.workflow_state.should == "pre_registered"
      @user.associated_accounts.map(&:id).include?(@account.id).should be_true
      @user.associated_accounts.map(&:id).include?(@other_account.id).should be_true
      post 'remove_user', :account_id => @account.id, :user_id => @user.id
      flash[:notice].should =~ /successfully deleted/
      response.should redirect_to(account_users_url(@account))
      @user.reload
      @user.workflow_state.should == "pre_registered"
      @user.associated_accounts.map(&:id).include?(@account.id).should be_false
      @user.associated_accounts.map(&:id).include?(@other_account.id).should be_true
    end

    it "should delete users who have managed passwords with html" do
      account_with_admin_logged_in
      user_with_managed_pseudonym :account => @account
      @user.workflow_state.should == "pre_registered"
      post 'remove_user', :account_id => @account.id, :user_id => @user.id
      flash[:notice].should =~ /successfully deleted/
      response.should redirect_to(account_users_url(@account))
      @user.reload
      @user.workflow_state.should == "deleted"
    end

    it "should delete users who have managed passwords with json" do
      account_with_admin_logged_in
      user_with_managed_pseudonym :account => @account
      @user.workflow_state.should == "pre_registered"
      post 'remove_user', :account_id => @account.id, :user_id => @user.id, :format => "json"
      flash[:notice].should =~ /successfully deleted/
      @user = json_parse(@user.reload.to_json)
      json_parse(response.body).should == @user
      @user["user"]["workflow_state"].should == "deleted"
    end
  end

  describe "SIS imports" do
    it "should set batch mode and term if given" do
      account_with_admin_logged_in
      @account.update_attribute(:allow_sis_import, true)
      post 'sis_import_submit', :account_id => @account.id, :import_type => 'instructure_csv_zip', :batch_mode => '1'
      batch = SisBatch.last
      batch.should_not be_nil
      batch.batch_mode.should be_true
      batch.batch_mode_term.should be_nil
      batch.destroy

      post 'sis_import_submit', :account_id => @account.id, :import_type => 'instructure_csv_zip', :batch_mode => '1', :batch_mode_term_id => @account.enrollment_terms.first.id
      batch = SisBatch.last
      batch.should_not be_nil
      batch.batch_mode.should be_true
      batch.batch_mode_term.should == @account.enrollment_terms.first
    end

    it "should set sis stickiness options if given" do
      account_with_admin_logged_in
      @account.update_attribute(:allow_sis_import, true)

      post 'sis_import_submit', :account_id => @account.id,
          :import_type => 'instructure_csv_zip'
      batch = SisBatch.last
      batch.should_not be_nil
      batch.options.should == {}
      batch.destroy

      post 'sis_import_submit', :account_id => @account.id,
          :import_type => 'instructure_csv_zip', :override_sis_stickiness => '1'
      batch = SisBatch.last
      batch.should_not be_nil
      batch.options.should == { :override_sis_stickiness => true }
      batch.destroy

      post 'sis_import_submit', :account_id => @account.id,
          :import_type => 'instructure_csv_zip', :override_sis_stickiness => '1',
          :add_sis_stickiness => '1'
      batch = SisBatch.last
      batch.should_not be_nil
      batch.options.should == { :override_sis_stickiness => true, :add_sis_stickiness => true }
      batch.destroy

      post 'sis_import_submit', :account_id => @account.id,
          :import_type => 'instructure_csv_zip', :override_sis_stickiness => '1',
          :clear_sis_stickiness => '1'
      batch = SisBatch.last
      batch.should_not be_nil
      batch.options.should == { :override_sis_stickiness => true, :clear_sis_stickiness => true }
      batch.destroy

      post 'sis_import_submit', :account_id => @account.id,
          :import_type => 'instructure_csv_zip', :clear_sis_stickiness => '1'
      batch = SisBatch.last
      batch.should_not be_nil
      batch.options.should == {}
      batch.destroy

      post 'sis_import_submit', :account_id => @account.id,
          :import_type => 'instructure_csv_zip', :add_sis_stickiness => '1'
      batch = SisBatch.last
      batch.should_not be_nil
      batch.options.should == {}
      batch.destroy
    end
  end

  describe "add_account_user" do
    it "should allow adding a new account admin" do
      account_with_admin_logged_in

      post 'add_account_user', :account_id => @account.id, :membership_type => 'AccountAdmin', :user_list => 'testadmin@example.com'
      response.should be_success

      new_admin = CommunicationChannel.find_by_path('testadmin@example.com').user
      new_admin.should_not be_nil
      @account.reload
      @account.account_users.map(&:user).should be_include(new_admin)
    end

    it "should allow adding an existing user to a sub account" do
      account_with_admin_logged_in(:active_all => 1)
      @subaccount = @account.sub_accounts.create!
      @munda = user_with_pseudonym(:account => @account, :active_all => 1, :username => 'munda@instructure.com')
      post 'add_account_user', :account_id => @subaccount.id, :membership_type => 'AccountAdmin', :user_list => 'munda@instructure.com', :only_search_existing_users => 1
      response.should be_success
      @subaccount.account_users.map(&:user).should == [@munda]
    end
  end

  it "should redirect to CAS if CAS is enabled" do
    account = account_with_cas({:account => Account.default})
    config = { :cas_base_url => account.account_authorization_config.auth_base }
    cas_client = CASClient::Client.new(config)
    get 'show', :id => account.id
    response.should redirect_to(cas_client.add_service_to_login_url(login_url))
  end

  it "should count total courses correctly" do
    account_with_admin_logged_in
    course
    @course.course_sections.create!
    @course.course_sections.create!
    @course.update_account_associations
    @account.course_account_associations.length.should == 3 # one for each section, and the "nil" section

    get 'show', :id => @account.id, :format => 'html'

    assigns[:associated_courses_count].should == 1
  end

  describe "update" do
    it "should allow admins to set the sis_source_id on sub accounts" do
      account_with_admin_logged_in
      @account = @account.sub_accounts.create!
      post 'update', :id => @account.id, :account => { :sis_source_id => 'abc' }
      @account.reload
      @account.sis_source_id.should == 'abc'
    end

    it "should not allow setting the sis_source_id on root accounts" do
      account_with_admin_logged_in
      post 'update', :id => @account.id, :account => { :sis_source_id => 'abc' }
      @account.reload
      @account.sis_source_id.should be_nil
    end

    it "should not allow non-site-admins to update global_includes" do
      account_with_admin_logged_in
      post 'update', :id => @account.id, :account => { :settings => { :global_includes => true } }
      @account.reload
      @account.global_includes?.should be_false
    end

    it "should allow site_admin to update global_includes" do
      user
      user_session(@user)
      @account = Account.create!
      Account.site_admin.add_user(@user)
      post 'update', :id => @account.id, :account => { :settings => { :global_includes => true } }
      @account.reload
      @account.global_includes?.should be_true
    end
  end
end
