class CourseSimulation < ActiveRecord::Base
	belongs_to :user
	belongs_to :course_detail
	
	has_one :course, :through=>:course_detail
	delegate :credit, :ch_name, :to=>:course
	
	has_one :teacher, :through=>:course_detail
	has_one :course_teachership, :through=>:course_detail
	belongs_to :semester
	belongs_to :course_field
	
	scope :import_success,->{where "course_detail_id != 0"}
	scope :agreed,->{where "semester_id = 0"}
	scope :normal,->{where "semester_id != 0"}
	
	def to_basic_json
		{
			:name=>self.ch_name,
			:credit=>self.credit,
			:cos_type=>self.cos_type=="" ? self.course_detail.cos_type : self.cos_type,
			:cf_name=>self.course_field ? self.course_field.name : ""
		}
	end
	def to_advance_json
		self.to_basic_json.merge({			
			:cos_id=>self.course.id,
			:cd_id=>self.course_detail_id,
			:sem_id=>self.semester_id,
			:t_id=>0,
			:t_name=>self.course_detail.teacher_name,
			:temp_cos_id=>self.course_detail.temp_cos_id,
			:file_count=>self.course_teachership.past_exams.count.to_s,
			:discuss_count=>self.course_teachership.discusses.count.to_s,
			:score=>self.score
		})
	end
	
	def to_simulated
		{
			"name"=>CourseDetail.find(read_attribute(:course_detail_id)).course_teachership.course.ch_name,
			"time"=>CourseDetail.find(read_attribute(:course_detail_id)).time_and_room.partition("-")[0]
		}
	end
	
end
