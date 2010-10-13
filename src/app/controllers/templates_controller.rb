require 'util/repository_manager'

class TemplatesController < ApplicationController
  before_filter :require_user
  before_filter :check_permission, :except => [:index, :builds]

  def section_id
    'build'
  end

  def index
    # TODO: add template permission check
    require_privilege(Privilege::IMAGE_VIEW)
    @order_dir = params[:order_dir] == 'desc' ? 'desc' : 'asc'
    @order_field = params[:order_field] || 'name'
    @templates = Template.find(
      :all,
      :include => :images,
      :order => @order_field + ' ' + @order_dir
    )
  end

  def action
    if params[:new_template]
      redirect_to :action => 'new'
    elsif params[:assembly]
      redirect_to :action => 'assembly'
    elsif params[:deployment_definition]
      redirect_to :action => 'deployment_definition'
    elsif params[:delete]
      redirect_to :action => 'delete', :ids => params[:ids].to_a
    elsif params[:edit]
      redirect_to :action => 'new', :id => get_selected_id
    elsif params[:build]
      redirect_to :action => 'build_form', 'image[template_id]' => get_selected_id
    else
      raise "Unknown action"
    end
  end

  # Since the template form submission can mean multiple things,
  # we dispatch based on form parameters here
  def dispatch
    if params[:save]
      create

    elsif params[:cancel]
      redirect_to :action => 'index'

    elsif params[:add_software_form]
      content_selection

    elsif pkg = params.keys.find { |k| k =~ /^remove_package_(.*)$/ }
      # actually remove the package from list
      params[:packages].delete($1) if params[:packages]
      new

    elsif params[:add_selected]
      new

    elsif params[:cancel_add_software]
      params[:packages] = params[:selected_packages]
      new

    end
  end

  # FIXME at some point split edit/update out from new/create
  # to conform to web standards
  def new
    # can't use @template variable - is used by compass (or something other)
    @id  = params[:id]
    @tpl = @id.blank? ? Template.new : Template.find(@id)
    @tpl.attributes = params[:tpl] unless params[:tpl].nil?
    get_selected_packages(@tpl)
    render :action => :new
  end

  def create
    @id  = params[:tpl][:id]
    @tpl = @id.blank? || @id == "" ? Template.new(params[:tpl]) : Template.find(@id)

    @tpl.xml.clear_packages

    params[:groups].to_a.each   { |group| @tpl.xml.add_group(group) }
    params[:packages].to_a.each { |pkg|   @tpl.xml.add_package(pkg) }

    # this is crazy, but we have most attrs in xml and also in model,
    # synchronize it at first to xml
    @tpl.update_xml_attributes(params[:tpl])

    if @tpl.save
      flash[:notice] = "Template saved."
      @tpl.set_complete
      redirect_to :action => 'index'
    else
      get_selected_packages(@tpl)
      render :action => 'new'
    end
  end

  def content_selection
    @repository_manager = RepositoryManager.new
    @id  = params[:id]
    @tpl = @id.blank? ? Template.new : Template.find(@id)
    @tpl.attributes = params[:tpl] unless params[:tpl].nil?
    @packages = []
    @packages = params[:packages].collect{ |p| { :name => p } } if params[:packages]
    @groups = @repository_manager.all_groups_with_tagged_selected_packages(@packages, params[:repository])
    @embed  = params[:embed]
    if @embed
      render :layout => false
    else
      render :action => :content_selection
    end
  end

  def managed_content
    get_selected_packages
    render :layout => false
  end

  def build_form
    raise "select template to build" unless params[:image] and params[:image][:template_id]
    @image = Image.new(params[:image])
    @all_targets = Image.available_targets
  end

  def build
    if params[:cancel]
      redirect_to :action => 'index'
      return
    end

    #FIXME: The following functionality needs to come out of the controller
    @image = Image.new(params[:image])
    @image.template.upload_template unless @image.template.uploaded
    # FIXME: this will need to re-render build with error messages,
    # just fails right now if anything is wrong (like no target selected).
    params[:targets].each do |target|
      i = Image.new_if_not_exists(
        :name => "#{@image.template.xml.name}/#{target}",
        :target => target,
        :template_id => @image.template_id,
        :status => Image::STATE_QUEUED
      )
      # FIXME: This will need to be enhanced to handle multiple
      # providers of same type, only one is supported right now
      if i
        image = Image.find_by_template_id(params[:image][:template_id],
                                :conditions => {:target => target})
        ReplicatedImage.create!(
          :image_id => image.id,
          :provider_id => Provider.find_by_cloud_type(target)
        )
      end
    end
    redirect_to :action => 'builds'
  end

  def builds
    @running_images = Image.all(:include => :template, :conditions => ['status IN (?)', Image::ACTIVE_STATES])
    @completed_images = Image.all(:include => :template, :conditions => {:status => Image::STATE_COMPLETE})
    @failed_images = Image.all(:include => :template, :conditions => {:status => Image::STATE_FAILED})
    require_privilege(Privilege::IMAGE_VIEW)
  end

  def delete
    ids = params[:ids].to_a
    raise "No Template Selected" if ids.empty?
    Template.destroy(ids)
    redirect_to :action => 'index'
  end

  def assembly
  end

  def deployment_definition
    @all_targets = Image.available_targets
  end

  private

  def check_permission
    require_privilege(Privilege::IMAGE_MODIFY)
  end

  def get_selected_id
    ids = params[:ids].to_a
    if ids.size != 1
      raise "No Template Selected" if ids.empty?
      raise "You can select only one template" if ids.size > 1
    end
    return ids.first
  end

  def get_selected_packages(tpl=nil)
    @repository_manager = RepositoryManager.new
    @groups = @repository_manager.all_groups(params[:repository])

    if params[:packages]
      @selected_packages = params[:packages]
    elsif params[:selected_packages]
      @selected_packages = params[:selected_packages]
    elsif !tpl.nil?
      @selected_packages = tpl.xml.packages.collect { |p| p[:name] }
    else
      @selected_packages = []
    end

    [:selected_groups, :groups].each do |pg|
      if params[pg]
        params[pg].each { |grp|
          fg = @groups.find { |gk, gv| gk == grp }
          fg[1][:packages].each { |pk, pv|
            @selected_packages << pk
          } unless fg.nil?
        }
      end
    end

    @selected_packages.uniq!
  end
end
