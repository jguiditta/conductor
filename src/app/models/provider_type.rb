# == Schema Information
# Schema version: 20110223132404
#
# Table name: provider_types
#
#  id              :integer         not null, primary key
#  name            :string(255)     not null
#  ssh_user        :string(255)
#  home_dir        :string(255)
#  build_supported :boolean
#  created_at      :datetime
#  updated_at      :datetime
#

class ProviderType < ActiveRecord::Base

  has_many :providers
  has_many :images

  validates_presence_of :name
  validates_uniqueness_of :name
  validates_presence_of :codename
  validates_uniqueness_of :codename

end
