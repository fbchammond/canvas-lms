class PurgeDuplicateDeletedSisEnrollments < ActiveRecord::Migration
  self.transactional = false

  def self.up
    while true
      pairs = Enrollment.connection.select_rows("
          SELECT user_id, course_section_id, type
          FROM enrollments
          WHERE workflow_state='deleted' AND sis_source_id IS NOT NULL
          GROUP BY user_id, course_section_id, type
          HAVING count(*) > 1 LIMIT 1000")
      break if pairs.empty?
      pairs.each do |(user_id, course_section_id, type)|
        scope = Enrollment.scoped(:conditions => ["user_id=? AND course_section_id=? AND type=? AND sis_source_id IS NOT NULL AND workflow_state='deleted'", user_id.to_i, course_section_id.to_i, type])
        keeper = scope.first(:select => :id)
        scope.delete_all(["id<>?", keeper.id])
      end
    end
  end

  def self.down
  end
end
