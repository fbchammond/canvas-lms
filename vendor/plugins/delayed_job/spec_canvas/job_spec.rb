require File.expand_path("../spec_helper", __FILE__)

describe Delayed::Job do
  before(:all) do
    @backend = Delayed::Job
  end

  before(:each) do
    Delayed::Job.delete_all
    SimpleJob.runs = 0
  end

  it_should_behave_like 'a backend'

  it "should fail on job creation if an unsaved AR object is used" do
    story = Story.new :text => "Once upon..."
    lambda { story.send_later(:text) }.should raise_error

    reader = StoryReader.new
    lambda { reader.send_later(:read, story) }.should raise_error

    lambda { [story, 1, story, false].send_later(:first) }.should raise_error
  end

  it "should recover as well as possible from a failure failing a job" do
    Delayed::Job::Failed.stubs(:create).raises(RuntimeError)
    job = "test".send_later :reverse
    job_id = job.id
    proc { job.fail! }.should raise_error
    proc { Delayed::Job.find(job_id) }.should raise_error(ActiveRecord::RecordNotFound)
    Delayed::Job.count.should == 0
  end

  it "should use the optimized path for psql" do
    if Delayed::Job.connection.adapter_name == 'PostgreSQL'
      job = @backend.create(:payload_object => SimpleJob.new)
      Delayed::Job.expects(:find_available).never
      Delayed::Job.expects(:lock_exclusively!).never
      new_job = Delayed::Job.get_and_lock_next_available('test1', 1)
      new_job.locked_by.should == 'test1'
      new_job.locked_at.should be_present
      new_job.should == job
    end
  end
end
