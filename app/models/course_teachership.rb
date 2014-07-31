class CourseTeachership < ActiveRecord::Base
  has_many :course_details, :dependent=> :destroy
	has_many :course_teacher_ratings, :dependent=> :destroy
	has_many :discusses
	has_many :file_infos
  has_one :course_teacher_page_content
	
  belongs_to :course
  belongs_to :teacher
	
end
