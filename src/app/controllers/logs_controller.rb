#
#   Copyright 2012 Red Hat, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

class LogsController < ApplicationController
  before_filter :require_user

  def index
    clear_breadcrumbs
    save_breadcrumb(logs_path)

    params[:view] = "filter" if params[:view].nil?
    @view = params[:view]

    load_options
    load_events
    load_headers unless @view == "pretty"
    generate_graph if @view == "pretty"

    respond_to do |format|
      format.html { @partial = filter_view? ? 'filter_view' : 'pretty_view' }
      format.js { render :partial => filter_view? ?
        'filter_view' :
        'pretty_view' }
    end
  end

  def filter
    redirect_to_original({ "source_type" => params[:source_type],
                           "pool_select" => params[:pool_select],
                           "provider_select" => params[:provider_select],
                           "owner_id" => params[:owner_id],
                           "state" => params[:state],
                           "from_date" => params[:from_date],
                           "to_date" => params[:to_date],
                           "order" => params[:order],
                           "group" => params[:group],
                           "view" => params[:view] })
  end

  def export_logs
    load_events
    load_headers

    csvm = Object.const_defined?(:FasterCSV) ? FasterCSV : CSV
    csv_string = csvm.generate(:col_sep => ";", :row_sep => "\r\n") do |csv|
      csv << @header.map {|header| header[:name].capitalize }

      unless @events.nil?
        @events.each do |event|
          source = event.source
          provider_account = source.nil? ? nil : source.provider_account
          csv << [ event.event_time.strftime("%d-%b-%Y %H:%M:%S"),
                   source.nil? ? t('logs.index.not_available') : source.name,
                   source.nil? ? t('logs.index.not_available') : source.state,
                   source.nil? ?
                     t('logs.index.not_available') :
                     source.pool_family.name + "/" + source.pool.name,
                   provider_account.nil? ?
                     t('logs.index.not_available') :
                     provider_account.provider.name + "/" +
                       provider_account.name,
                   source.nil? ?
                     t('logs.index.not_available') :
                     source.owner.login,
                   event.summary ]
        end
      end
    end

    send_data(csv_string,
              :type => 'text/csv; charset=utf-8; header=present',
              :filename => "export.csv")
  end

  protected

  def load_events
    @source_type = params[:source_type].nil? ? "" : params[:source_type]
    @pool_select = params[:pool_select].nil? ? "" : params[:pool_select]
    @provider_select =
      params[:provider_select].nil? ? "" : params[:provider_select]
    @owner_id = params[:owner_id].nil? ? "" : params[:owner_id]
    @state = params[:state].nil? ? "" : params[:state]
    @order = params[:order].nil? ? t('logs.options.time_order') : params[:order]
    @from_date = params[:from_date].nil? ? Date.today - 7.days :
      Date.civil(params[:from_date][:year].to_i,
                 params[:from_date][:month].to_i,
                 params[:from_date][:day].to_i)
    @to_date = params[:to_date].nil? ? Date.today + 1.days :
      Date.civil(params[:to_date][:year].to_i,
                 params[:to_date][:month].to_i,
                 params[:to_date][:day].to_i)

    # modify parameters for pretty view
    if @view == "pretty"
      @state = ""
      @pool_select = ""
      @provider_select = ""
      @owner_id = ""
      @order = t('logs.options.time_order')
      @source_type = "Deployment" if @source_type == ""
    end

    if @source_type.present?
      conditions = ["event_time between ? and ? and source_type = ?",
                    @from_date.to_datetime.beginning_of_day,
                    @to_date.to_datetime.end_of_day,
                    @source_type]
    else
      conditions = ["event_time between ? and ?",
                    @from_date.to_datetime.beginning_of_day,
                    @to_date.to_datetime.end_of_day]
    end

    @events = Event.unscoped.find(:all,
                                  :include =>
                                  {:source => [:pool_family, :pool, :owner]},
                                  :conditions => conditions,
                                  :order => "event_time asc"
                                  )
    deployments = Deployment.unscoped.list_for_user(current_session,
                                                    current_user,
                                                    Privilege::VIEW)
    instances = Instance.unscoped.list_for_user(current_session,
                                                current_user, Privilege::VIEW)

    pool_option, pool_option_id = @pool_select.split(":")
    provider_option, provider_option_id = @provider_select.split(":")

    @events = @events.find_all{|event|
      source = event.source
      source_class = source.class.name

      # permission checks
      next if source_class == "Deployment" and !deployments.include?(source)
      next if source_class == "Instance" and !instances.include?(source)

      # filter by user
      next if @owner_id.present? && source.owner_id.to_s != @owner_id

      # filter by state
      if @state.present?
        next if source.state != @state
      end

      # filter by pool
      if @pool_select.present?
        next if (pool_option == "pool_family" &&
                 source.pool_family_id.to_s != pool_option_id)
        next if pool_option == "pool" && source.pool_id.to_s != pool_option_id
      end

      # filter by provider
      if @provider_select.present?
        event_provider_account = source.provider_account
        next if event_provider_account.nil?
        next if (provider_option == "provider" &&
                 source.provider_account.provider.id.to_s != provider_option_id)
        next if (provider_option == "provider_account" &&
                 source.provider_account.id.to_s != provider_option_id)
      end

      true
    }

    case @order
    when t('logs.options.deployment_instance_order')
      @events = @events.sort_by {|event|
        (event.source.nil? ? "" : event.source.name)}
    when t('logs.options.state_order')
      @events = @events.sort_by {|event|
        (event.source.nil? ? "" :
         (event.source.state.nil? ? "" : event.source.state))}
    when t('logs.options.pool_order')
      @events = @events.sort_by {|event|
        (event.source.nil? ? "" : event.source.pool_family.name)}
    when t('logs.options.provider_order')
      @events = @events.sort_by {|event|
        (event.source.nil? ? "" : event.source.provider_account.name)}
    when t('logs.options.owner_order')
      @events = @events.sort_by {|event|
        (event.source.nil? ? "" : event.source.owner.login)}
    end

    @paginated_events = paginate_collection(@events, params[:page], PER_PAGE)
  end

  def load_options
    if @view == "pretty"
      @source_type_options = [t('logs.options.deployment_event_type'),
                              t('logs.options.instance_event_type')]
      @group_options = [[t('logs.options.default_group_by'), ""],
                        t('logs.index.pool'),
                        t('logs.index.provider'),
                        t('logs.index.owner')]
    else
      @source_type_options = [[t('logs.options.default_event_types'), ""],
                              t('logs.options.deployment_event_type'),
                              t('logs.options.instance_event_type')]
      @pool_options = [[t('logs.options.default_pools'), ""]]
      PoolFamily.list_for_user(current_session, current_user, Privilege::VIEW).
        find(:all, :include => :pools, :order => "name",
             :select => ["id", "name"]).each do |pool_family|
        @pool_options << [pool_family.name,
                          "pool_family:" + pool_family.id.to_s]
        @pool_options += pool_family.pools.
          map{|x| [" -- " + x.name, "pool:" + x.id.to_s]}
      end
      @provider_options = [[t('logs.options.default_providers'), ""]]
      Provider.list_for_user(current_session, current_user, Privilege::VIEW).
        find(:all, :include => :provider_accounts, :order => "name",
             :select => ["id", "name"]).each do |provider|
        @provider_options << [provider.name, "provider:" + provider.id.to_s]
        @provider_options += provider.provider_accounts.
          map{|x| [" -- " + x.name, "provider_account:" + x.id.to_s]}
      end
      @owner_options = [[t('logs.options.default_users'), ""]] +
        User.find(:all, :order => "login",
                  :select => ["id", "login"]).map{|x| [x.login, x.id]}
      @order_options = [t('logs.options.time_order'),
                        t('logs.options.deployment_instance_order'),
                        t('logs.options.state_order'),
                        t('logs.options.pool_order'),
                        t('logs.options.provider_order'),
                        t('logs.options.owner_order')]
      @state_options = ([[t('logs.options.default_states'), ""]] +
                        Deployment::STATES + Instance::STATES).uniq
    end
  end

  def load_headers
    @header = [
      { :name => t('logs.index.event_time'), :sortable => false },
      { :name => t('logs.index.deployment'), :sortable => false },
      { :name => t('logs.index.state'), :sortable => false },
      { :name => t('logs.index.pool'), :sortable => false },
      { :name => t('logs.index.provider'), :sortable => false },
      { :name => t('logs.index.owner'), :sortable => false },
      { :name => t('logs.index.summary'), :sortable => false },
      { :name => "", :sortable => false },
    ]
  end

  def generate_graph
    @group = params[:group].nil? ? "" : params[:group]

    start_code = (@source_type == 'Deployment' ? 'first_running' : 'running')
    end_code = (@source_type == 'Deployment' ? 'all_stopped' : 'stopped')

    initial_conditions = ["exists (select 1 from events
                                   where source_type = '" + @source_type + "'
                                   and source_id = " + @source_type + "s.id
                                   and status_code = '" + start_code + "'
                                   and event_time <= ?) 
                           and not exists (select 1 from events
                                      where source_type = '" + @source_type + "'
                                      and source_id = " + @source_type + "s.id
                                      and status_code = '" + end_code + "'
                                      and event_time <= ?)",
                          @from_date.to_datetime.beginning_of_day,
                          @from_date.to_datetime.beginning_of_day]

    if @source_type == "Deployment"
      @initial_sources = Deployment.unscoped.
        list_for_user(current_session, current_user, Privilege::VIEW).
        find(:all, :conditions => initial_conditions)
    else 
      @initial_sources = Instance.unscoped.
        list_for_user(current_session, current_user, Privilege::VIEW).
        find(:all, :conditions => initial_conditions)
    end

    @datasets = Hash.new
    counts = Hash.new

    counts["All"] = @initial_sources.count

    if @group_options.include?(@group) 
      @initial_sources.each do |source|
        label = get_source_label(source, @group)

        if counts.has_key?(label)
          counts[label] = counts[label] + 1
        else
          counts[label] = 1
        end
      end
    end

    counts.each.map{ |label,count|
      @datasets[label] = [[@from_date.to_datetime.beginning_of_day.to_i * 1000,
                           count]]
    }

    @events.each do |event|
      event_timestamp = event.event_time.to_i * 1000

      if event.status_code == start_code || event.status_code == end_code
        increment = (event.status_code == end_code) ? -1 : 1

        add_dataset_point("All", event_timestamp, increment, counts)

        if @group_options.include?(@group) 
          label = get_source_label(event.source, @group)
          add_dataset_point(label, event_timestamp, increment, counts)
        end
      end
    end

    counts.each.map{ |label,count|
      @datasets[label] << [@to_date.to_datetime.end_of_day.to_i * 1000, count]
    }
  end

  def get_source_label(source, label_type)
    label = "Unknown"
    case @group
    when t('logs.index.pool')
      label = source.pool.name unless source.pool.nil?
    when t('logs.index.provider')
      label = source.provider_account.name unless source.provider_account.nil?
    when t('logs.index.owner')
      label = source.owner.name unless source.owner.nil?
    end

    label
  end

  def add_dataset_point(label, timestamp, increment, counts)
    if !@datasets.has_key?(label)
      counts[label] = 0
      @datasets[label] = [ [timestamp - 1, 0] ]
    end

    @datasets[label] << [timestamp - 1, counts[label]]
    counts[label] = counts[label] + increment
    @datasets[label] << [timestamp, counts[label]]
  end
end