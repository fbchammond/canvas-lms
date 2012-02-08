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

class CommunicationChannelsController < ApplicationController
  before_filter :require_user, :only => [:create, :destroy]
  
  def create
    if params[:build_pseudonym]
      params[:pseudonym][:account] = @domain_root_account
      @pseudonym = @current_user.pseudonyms.build(params[:pseudonym])
      @pseudonym.generate_temporary_password
      return render :json => @pseudonym.errors.to_json, :status => :bad_request unless @pseudonym.valid?
    end
    @cc = @current_user.communication_channels.by_path(params[:pseudonym][:unique_id]).find_by_path_type(params[:path_type])
    @cc ||= @current_user.communication_channels.build(:path => params[:pseudonym][:unique_id], :path_type => params[:path_type])
    if (!@cc.new_record? && !@cc.retired?)
      @cc.errors.add(:path, "unique!")
      return render :json => @cc.errors.to_json, :status => :bad_request
    end

    @cc.user = @current_user
    @cc.workflow_state = 'unconfirmed'
    @cc.build_pseudonym_on_confirm = params[:build_pseudonym] == '1'
    if @cc.save
      @cc.send_confirmation!
      flash[:notice] = "Contact method registered!"
      render :json => @cc.to_json(:only => [:id, :user_id, :path, :path_type])
    else
      render :json => @cc.errors.to_json, :status => :bad_request
    end
  end

  def confirm
    nonce = params[:nonce]
    cc = CommunicationChannel.unretired.find_by_confirmation_code(nonce)
    @headers = false
    if cc
      @communication_channel = cc
      @user = cc.user
      @enrollment = @user.enrollments.find_by_uuid_and_workflow_state(params[:enrollment], 'invited') if params[:enrollment]
      @course = @enrollment && @enrollment.course
      @root_account = @course.root_account if @course
      @root_account ||= @user.pseudonyms.first.try(:account) if @user.pre_registered?
      @root_account ||= @user.enrollments.first.try(:root_account) if @user.creation_pending?
      unless @root_account
        account = @user.account_users.first.try(:account)
        @root_account = account.try(:root_account)
      end
      @root_account ||= @domain_root_account

      # logged in as an unconfirmed user?! someone's masquerading; just pretend we're not logged in at all
      if @current_user == @user && !@user.registered?
        @current_user = nil
      end

      if @user.registered? && cc.unconfirmed?
        unless @current_user == @user
          session[:return_to] = request.url
          flash[:notice] = t 'notices.login_to_confirm', "Please log in to confirm your e-mail address"
          return redirect_to login_url(:pseudonym_session => { :unique_id => @user.pseudonym.try(:unique_id) }, :expected_user_id => @user.id)
        end

        cc.confirm
        @user.touch
        flash[:notice] = t 'notices.registration_confirmed', "Registration confirmed!"
        return respond_to do |format|
          format.html { redirect_back_or_default(profile_url) }
          format.json { render :json => cc.to_json(:except => [:confirmation_code] ) }
        end
      end

      # load merge opportunities
      other_ccs = CommunicationChannel.active.by_path(cc.path).of_type(cc.path_type).find(:all, :conditions => ["communication_channels.id<>?", cc.id], :include => :user)
      merge_users = (other_ccs.map(&:user)).uniq
      merge_users << @current_user if @current_user && !@user.registered? && !merge_users.include?(@current_user)
      User.send(:preload_associations, merge_users, { :pseudonyms => :account })
      merge_users.reject! { |u| u != @current_user && u.pseudonyms.all? { |p| p.deleted? } }
      # remove users that don't have a pseudonym for this account, or one can't be created
      merge_users = merge_users.select { |u| u.find_or_initialize_pseudonym_for_account(@root_account, @domain_root_account) }
      @merge_opportunities = []
      merge_users.each do |user|
        account_to_pseudonyms_hash = {}
        user.pseudonyms.each do |p|
          next unless p.active?
          # populate reverse association
          p.user = user
          (account_to_pseudonyms_hash[p.account] ||= []) << p
        end
        @merge_opportunities << [user, account_to_pseudonyms_hash.map do |(account, pseudonyms)|
          pseudonyms.detect { |p| p.sis_user_id } || pseudonyms.sort { |a, b| a.position <=> b.position }.first
        end]
        @merge_opportunities.last.last.sort! { |a, b| a.account.name <=> b.account.name }
      end
      @merge_opportunities.sort! { |a, b| [a.first == @current_user ? 0 : 1, a.first.name] <=> [b.first == @current_user ? 0 : 1, b.first.name] }

      if @current_user && params[:confirm].present? && @merge_opportunities.find { |opp| opp.first == @current_user }
        cc.confirm
        @enrollment.accept if @enrollment
        @user.move_to_user(@current_user) if @user != @current_user
        # create a new pseudonym if necessary and possible
        pseudonym = @current_user.find_or_initialize_pseudonym_for_account(@root_account, @domain_root_account)
        pseudonym.save! if pseudonym && pseudonym.changed?
      elsif @current_user && @current_user != @user && @enrollment && @user.registered?
        if params[:transfer_enrollment].present?
          cc.active? || cc.confirm
          @enrollment.user = @current_user
          # accept will save it
          @enrollment.accept
          @user.touch
          @current_user.touch
        else
          # render
          return
        end
      elsif @user.registered?
        # render
        return unless @merge_opportunities.empty?
        failed = true
      elsif cc.active?
        # !user.registered? && cc.active? ?!?
        # This state really isn't supported; just error out
        failed = true
      else
        # Open registration and admin-created users are pre-registered, and have already claimed a CC, but haven't
        # set up a password yet
        @pseudonym = @user.pseudonyms.active.find(:first, :conditions => {:password_auto_generated => true, :account_id => @root_account.id} ) if @user.pre_registered? || @user.creation_pending?
        # Users implicitly created via course enrollment or account admin creation are creation pending, and don't have a pseudonym yet
        @pseudonym ||= @user.pseudonyms.build(:account => @root_account, :unique_id => cc.path) if @user.creation_pending?
        # We create the pseudonym with unique_id = cc.path, but if that unique_id is taken, just nil it out and make the user come
        # up with something new
        @pseudonym.unique_id = '' if @pseudonym && @pseudonym.new_record? && @root_account.pseudonyms.active.custom_find_by_unique_id(@pseudonym.unique_id)

        # Have to either have a pseudonym to register with, or be looking at merge opportunities
        return render :action => 'confirm_failed', :status => :bad_request if !@pseudonym && @merge_opportunities.empty?

        # User chose to continue with this cc/pseudonym/user combination on confirmation page
        if @pseudonym && params[:register]
          @user.attributes = params[:user]
          @pseudonym.attributes = params[:pseudonym]
          @pseudonym.communication_channel = cc

          # trick pseudonym into validating the e-mail address
          @pseudonym.account = nil
          unless @pseudonym.valid?
            return
          end
          @pseudonym.account = @root_account

          return unless @pseudonym.valid?

          # They may have switched e-mail address when they logged in; create a CC if so
          if @pseudonym.unique_id != cc.path
            new_cc = @user.communication_channels.email.by_path(@pseudonym.unique_id).first
            new_cc ||= @user.communication_channels.build(:path => @pseudonym.unique_id)
            new_cc.user = @user
            new_cc.workflow_state = 'unconfirmed' if new_cc.retired?
            new_cc.send_confirmation! if new_cc.unconfirmed?
            new_cc.save! if new_cc.changed?
            @pseudonym.communication_channel = new_cc
          end
          @pseudonym.communication_channel.pseudonym = @pseudonym

          @user.save!
          @pseudonym.save!

          if cc.confirm
            @enrollment.accept if @enrollment
            reset_session_saving_keys(:return_to)
            @user.register

            # Login, since we're satisfied that this person is the right person.
            @pseudonym_session = PseudonymSession.new(@pseudonym, true)
            @pseudonym_session.save
          else
            failed = true
          end
        else
          return # render
        end
      end
    else
      failed = true
    end
    if failed
      respond_to do |format|
        format.html { render :action => "confirm_failed", :status => :bad_request }
        format.json { render :json => {}.to_json, :status => :bad_request }
      end
    else
      flash[:notice] = t 'notices.registration_confirmed', "Registration confirmed!"
      respond_to do |format|
        format.html { @enrollment ? redirect_to(course_url(@course)) : redirect_back_or_default(dashboard_url) }
        format.json { render :json => cc.to_json(:except => [:confirmation_code] ) }
      end
    end
  end

  def re_send_confirmation
    @user = User.find(params[:user_id])
    @enrollment = params[:enrollment_id] && @user.enrollments.find(params[:enrollment_id])
    if @enrollment && (@enrollment.invited? || @enrollment.active?)
      @enrollment.re_send_confirmation!
    else
      @cc = @user.communication_channels.find(params[:id])
      @cc.send_confirmation!
    end
    render :json => {:re_sent => true}
  end

  def destroy
    @cc = @current_user.communication_channels.find_by_id(params[:id]) if params[:id]
    if !@cc || @cc.destroy
      @current_user.touch
      render :json => @cc.to_json
    else
      render :json => @cc.errors.to_json, :status => :bad_request
    end
  end
  
end
