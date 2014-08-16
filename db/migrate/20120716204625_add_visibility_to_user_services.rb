class AddVisibilityToUserServices < ActiveRecord::Migration
  tag :predeploy

  def self.up
    add_column :user_services, :visible, :boolean
  end

  def self.down
    remove_column :user_services, :visible
  end
end
