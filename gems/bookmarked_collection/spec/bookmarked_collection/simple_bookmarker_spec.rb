#
# Copyright (C) 2013 Instructure, Inc.
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

require 'spec_helper'

describe BookmarkedCollection::SimpleBookmarker do

  before do
    @example_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'examples'
    end

    BookmarkedCollection.best_unicode_collation_key_proc = lambda { |col|
      return "lower(#{col})"
    }

    @bookmarker = BookmarkedCollection::SimpleBookmarker.new(@example_class, :name, :id)
    @bob = @example_class.create!(name: "bob")
    @bob2 = @example_class.create!(name: "Bob")
    @joe = @example_class.create!(name: "joe")
    @bobby = @example_class.create!(name: "bobby")
    @bill = @example_class.create!(name: "BILL!")
  end

  context "#bookmark_for" do
    it "should be comparable" do
      @bookmarker.bookmark_for(@bob).should be_respond_to(:<=>)
    end

    it "should match the columns, in order" do
      @bookmarker.bookmark_for(@bob).should == [@bob.name, @bob.id]
    end
  end

  context "#validate" do
    it "should validate the bookmark and its contents" do
      @bookmarker.validate({name: "bob", id: 1}).should be_false
      @bookmarker.validate(["bob"]).should be_false
      @bookmarker.validate(["bob", "1"]).should be_false
      @bookmarker.validate(["bob", 1]).should be_true
    end
  end

  context "#restrict_scope" do
    it "should order correctly" do
      pager = double(current_bookmark: nil)
      @bookmarker.restrict_scope(@example_class, pager).should ==
        [@bill, @bob, @bob2, @bobby, @joe]
    end

    it "should start after the bookmark" do
      bookmark = @bookmarker.bookmark_for(@bob2)
      pager = double(current_bookmark: bookmark, include_bookmark: false)
      @bookmarker.restrict_scope(@example_class, pager).should ==
        [@bobby, @joe]
    end

    it "should include the bookmark iff include_bookmark" do
      bookmark = @bookmarker.bookmark_for(@bob2)
      pager = double(current_bookmark: bookmark, include_bookmark: true)
      @bookmarker.restrict_scope(@example_class, pager).should ==
        [@bob2, @bobby, @joe]
    end
  end
end
