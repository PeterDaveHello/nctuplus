class UserController < ApplicationController

	include ApiHelper
	include CourseHelper
	include CourseMapsHelper 

	
    before_filter :checkTopManager, :only=>[:manage, :permission]
	before_filter :checkLogin, :only=>[:add_course,  :special_list, :select_dept, :statistics_table]
    before_filter :checkE3Login, :only=>[:import_course]
	layout false, :only => [:add_course, :statistics_table]#, :all_courses2]
	def update_all_cs_sem_id
		@new_sem_ids=[0,1,2,4,5,7,8,10,11,13]
		CourseSimulation.all.each do |cs|
			cs.semester_id=@new_sem_ids[cs.semester_id]
			cs.save
		end
	end
	def update_all_sem_and_dept
		@new_dep_ids={}
		OldDepartment.where(:dept_type=>['dept']).each do |olddept|
			new_dept=Department.where(:degree=>olddept.degree.to_i, :dep_id=>olddept.real_id).take
			if new_dept
				@new_dep_ids[olddept.id.to_s]=new_dept.id
			end
		end
		@new_dep_ids["145"]=494
		@new_dep_ids["146"]=495
		@new_dep_ids["147"]=496
		#3*(n-2)+1
		@new_sem_ids=[]
		@new_sem_ids[1]=1
		@new_sem_ids[3]=4
		@new_sem_ids[5]=7
		@new_sem_ids[7]=10
		@new_sem_ids[9]=13

		User.where("department_id != 0").each do |user|
			user.department_id=@new_dep_ids[user.department_id.to_s]
			user.semester_id=@new_sem_ids[user.semester_id]
			user.save
		end
	end
	def this_sem
		@user=getUserByIdForManager(params[:uid])
		render :layout=>false
	end
	def get_user_courses
		@user=getUserByIdForManager(params[:uid])
		if request.format=="json"
			if params[:type]=="all"
			cs_agree=@user.courses_agreed.map{|cs|{
				:name=>cs.course.ch_name,
				:credit=>cs.course.credit,
				:cos_type=>cs.course_detail.cos_type,
				:cf_name=>cs.course_field ? cs.course_field.name : ""
			}}
			cs_taked=convert_to_json(@user.courses_taked)
			elsif params[:type]=="this_sem"
				cs_taked=convert_to_json(@user.all_courses.where("semester_id=?",latest_semester.id))
				cs_agree=[]
			end
			result={
				:pass_score=>@user.pass_score,
				:last_sem_id=>latest_semester.id,
				:agreed=>cs_agree,
				:taked=>cs_taked,
				:list_type=>params[:type]
			}
		end
		respond_to do |format|
			format.json{render json:result}
		end
		
	end

	def change_role
		user = User.find(params[:uid])
		user.role = params[:role].to_i
		user.save!
		
		render :layout=>false, :nothing=> true, :status=>200, :content_type => 'text/html'
	end
	
	def special_list
		@ls=latest_semester
		@user=getUserByIdForManager(params[:uid])
		
		if @user.course_maps.empty?  
			cm=CourseMap.where(:department_id=>@user.department_id, :semester_id=>@user.semester_id).take
			if cm
				UserCoursemapship.create(:user_id=>@user.id, :course_map_id=>cm.id)
				if !@user.course_simulations.empty?
					update_cs_cfids(cm,@user)
				end
			end
		end
		@cs_this=@user.course_simulations.includes(:course_detail,:course,:teacher).where("semester_id = ?",@ls.id)#, :course, :teacher)


	end
	def all_courses
		@user=getUserByIdForManager(params[:uid])
		render :layout=>false
	end

	def select_cs_cf
		cs=CourseSimulation.find(params[:cs_id])
		cs.course_field_id=params[:cf_id]
		cs.save!
		render :nothing => true, :status => 200, :content_type => 'text/html'
	end
	def statistics2
		@user=getUserByIdForManager(params[:uid])

		
		if request.format=="json"
			ls=latest_semester
			
			course_map=@user.course_maps.first

			#update_cs_cfids(course_map,@user)

			if course_map
				course_map_res=get_cm_res(course_map)
			end
			res={
				:user_id=>@user.id,
				:pass_score=>@user.pass_score,
				:last_sem_id=>latest_semester.id,
				:user_courses=>{
					:success=>@user.courses_json,
					:fail=>@user.course_simulations.where('course_detail_id = 0').map{|cs| cs.memo2}
				},
				:course_map=>course_map_res||nil,
				#:user_fails=> @user.course_simulations.where('course_detail_id = 0').map{|cs| cs.memo2} ,
			}
		end
		
		respond_to do |format|
			format.html{render :layout=>false}
			format.json{render json:res}
		end
	end

	def import_course_2

		
	end
	
	def import_course
		if request.post?
			if params[:user_agreement].to_i == 0
				redirect_to :root_url
				return
			else
				current_user.agree = (params[:user_agreement].to_i==1) ? true : false 
				current_user.save!
			end
			score=params[:course][:score]
			res=parse_scores(score)
			agree=res[:agreed]
			normal=res[:taked]
			student_id=res[:student_id]
			student_name=res[:student_name]
			dept=res[:dept]

			if student_id!=current_user.student_id
				msg="成績驗證錯誤，請匯入自己的成績，謝謝!"
				redirect_to :action =>"special_list", :msg=>msg
				return
			end

			@pass_score=current_user.pass_score
			has_added=0
			@success_added=0
			@fail_added=0
			fail_course_name=[]
			@no_pass=0
			@pass=0
			if normal.length>0
				#CourseSimulation.where("user_id = ? AND semester_id != ? ",current_user.id,Semester.last.id).destroy_all
				current_user.course_simulations.destroy_all
			
			else
				msg="匯入失敗!"
				redirect_to :action=>"import_course_2", :msg=>msg
				return
			end
			tcss=TempCourseSimulation.where(:student_id=>current_user.student_id)
			if !tcss.empty?
				tcss.each do |tcs|
					tcs.has_added=1
					tcs.save!
					CourseSimulation.create(:user_id=>current_user.id, :course_detail_id=>tcs.course_detail_id, :semester_id=>tcs.semester_id, :course_field_id=>0, :score=>tcs.score, :memo=>tcs.memo, :memo2=>tcs.memo2)
					if tcs.score=="通過" || tcs.score.to_i>=@pass_score
						@pass+=1
					else
						@no_pass+=1
					end
				end
				@success_added=tcss.select{|tcs|tcs.course_detail_id!=0}.length
				@fail_added=tcss.select{|tcs|tcs.course_detail_id==0}.length
			else
			
				agree.each do |a|
					#Rails.logger.debug "[debug] "+Course.where(:real_id=>a).take.ch_name
					
					course=Course.where(:real_id=>a[:real_id]).take
					if !course.nil?
						Rails.logger.debug "[debug] "+course.ch_name
						cd_temp=course.course_details.take#.where(:credit=>a[:credit]).first
						CourseSimulation.create(:user_id=>current_user.id, :course_detail_id=>cd_temp.id, :semester_id=>0, :score=>"通過", :memo=>a[:memo], :import_fail=>0)
						@success_added+=1
					else
					
						CourseSimulation.create(:user_id=>current_user.id, :course_detail_id=>0, :semester_id=>0, :score=>"通過", :memo=>a[:memo], :memo2=>a[:real_id]+"/"+a[:credit].to_s+"/"+a[:name], :import_fail=>1)
						@fail_added+=1
					end
				end

				normal.each do |n|
					#dept_id=Department.select(:id).where(:ch_name=>n['dept_name']).take
					if n['score']=="通過" || n['score'].to_i>=@pass_score
						@pass+=1
					else
						@no_pass+=1
					end
					sem=n['sem']
					sem=Semester.where(:year=>sem[0..sem.length-2].to_i, :half=>sem[sem.length-1].to_i).take
					if sem
						cds=CourseDetail.where(:semester_id=>sem.id, :temp_cos_id=>n['cos_id']).take
						if cds	
							CourseSimulation.create(:user_id=>current_user.id, :course_detail_id=>cds.id, :semester_id=>cds.semester_id, :score=>n['score'], :course_field_id=>0)
							@success_added+=1
						else
							#fail_course_name.append()
							@fail_added+=1
						end
					else
						@fail_added+=1
					end
				end
			end
			
			cm=current_user.course_maps.includes(:course_groups, :course_fields).take
			#if cm
			update_cs_cfids(cm,current_user)
			#end
			msg="匯入完成! 共新增 #{@success_added} 門課 失敗:#{@fail_added} 通過:#{@pass} 未通過:#{@no_pass}"
			redirect_to :action=>"import_course_2", :msg=>msg
		end
	end
	
	#def select_cf
	#	
	#end
	
	def select_dept
		degree=params[:degree_select].to_i
		grade=params[:grade_select].to_i
		if degree==2
			dept=params[:dept_grad_select].to_i
		else
			dept=params[:dept_under_select].to_i
		end
		current_user.update_attributes(:semester_id=>grade,:department_id=>dept)
		UserCoursemapship.where(:user_id=>current_user.id).destroy_all#.each do |uc|
			#uc.destroy!
		#end
		cm=CourseMap.where(:department_id=>current_user.department_id, :semester_id=>current_user.semester_id).take
		if cm
			UserCoursemapship.create(:course_map_id=>cm.id, :user_id=>current_user.id)
		end
		update_cs_cfids(cm,current_user)
		redirect_to :controller=> "user", :action=>"special_list"
	end
  def manage
    @users=User.includes(:semester, :department, :course_simulations, :course_maps).page(params[:page]).per(20)#limit(50)
	#@top_managers=TopManager.all.pluck(:user_id)
  end
  def select_cm
		
		
		user=User.find(params[:uid])
		#user.course_mapships.destroy_all
		UserCoursemapship.where(:user_id=>params[:uid]).destroy_all
		UserCoursemapship.create(:course_map_id=>params[:cm_id], :user_id=>params[:uid])
		#course_map=CourseMap.find(params[:map_id])
		update_cs_cfids(CourseMap.find(params[:cm_id]),user)
		if request.get?
			redirect_to :back
		else
			render :nothing => true, :status => 200, :content_type => 'text/html'
		end
  end
  def permission
    @user=User.find_by(params[:id])
	@departments=Department.all
    if request.post?
			CourseManager.destroy_all(:user_id=>@user.id)
			if params[:department]
				params[:department][:checked].each do |key,value|
					@course_manager=CourseManager.new(:user_id=>@user.id)
					@course_manager.department_id=key
					@course_manager.save!
				end
			end
		end
	end
  
  def statistics_table
		user = nil
		course_map = nil
		if request.xhr? 				
			user = (params[:user_id].presence and checkTopManagerNoReDirect) ? getUserByIdForManager(params[:user_id]) : current_user
			course_map = user.course_maps.last 
			data1 = (course_map.presence) ? get_cm_tree(course_map) : nil
			if data1.presence
				data2 = user.all_courses.map{
				|cs| 
				{
				 :id=> cs.course.id,
				 :uni_id=> cs.id,
				 :name=>cs.course.ch_name, 
				 :credit=>cs.course.credit,
				 :score=>cs.score,
				 :cos_type=>cs.course_detail.cos_type,
				 :sem=>((cs.semester_id==0) ? {:year=>0, :half=>0} : {:year=>cs.semester.year, :half=>cs.semester.half}),
				 :cf_id=>cs.course_field_id,
				 :memo=>cs.memo||"",
				 :degree=>cs.course.department.degree,
				}}
				# if has course_map, user must have semester, dept
				user_info = {
							:sem=>{:year=>user.semester.year, :half=>user.semester.half}, 
							:degree=>user.department.degree, 
							:sem_now=>{:year=>103, :half=>1}, 
							:map_name=>course_map.name,
							:student_id=>user.student_id 
							}
			else
				data2 = nil
				user_info = nil
			end
		end
		
		respond_to do |format|
			format.html {  }
			format.json { render :text => {:user_info=>user_info, :course_map=>data1, :user_courses=>data2 }.to_json}
		end
	end
  
  private

	def convert_to_json(courses)
		return courses.map{|cs|{
			:name=>cs.course.ch_name,
			:cos_type=>cs.course_detail.cos_type,
			:cos_id=>cs.course.id,
			:ct_id=>cs.course_teachership.id,
			:sem_id=>cs.semester_id,
			:t_id=>0,
			:t_name=>cs.course_detail.teacher_name,
			:cf_name=>cs.course_field ? cs.course_field.name : "",
			:credit=>cs.course.credit,
			:temp_cos_id=>cs.course_detail.temp_cos_id,
			:file_count=>cs.course_teachership.file_infos.count.to_s,
			:discuss_count=>cs.course_teachership.discusses.count.to_s,
			:score=>cs.score
		}}
	end
	

	
	
	
	
	def get_cm_cfs(course_map)
		return course_map.course_fields.includes(:courses, :child_cfs).map{|cf|
			cf.field_type < 3 ? 
				_get_bottom_node(cf) : 
				_get_middle_node(cf,cf.child_cfs.includes(:courses).map{|child_cf|get_cf_tree(child_cf)})
		}
	end
	
	def check_passed(cs,user)
		return cs.semester_id!=latest_semester.id&&(cs.score=="通過"||cs.score.to_i > user.pass_score)
	end

  def user_params
    params.require(:user).permit(:email)
  end
  
end
