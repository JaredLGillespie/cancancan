require 'spec_helper'
require 'benchmark/ips'
require 'activerecord-import/base'
ActiveRecord::Import.require_adapter(:postgresql)

RSpec.xdescribe 'query performance' do
  before :each do
    require 'pg'

    # conn = PG.connect(dbname: 'postgres')
    # conn.exec("CREATE DATABASE cancancan_test")
    ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: 'cancancan_test')
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Schema.define do
      create_table(:users, force: true) do |t|
        t.string :name
        t.timestamps null: false
      end

      create_table(:proposals, force: true) do |t|
        t.string :name
        t.boolean :private
        t.boolean :area_private
        t.boolean :visible_outside
        t.references :user
        t.timestamps null: false
      end

      create_table(:groups, force: true) do |t|
        t.string :name
        t.references :user
        t.timestamps null: false
      end

      create_table(:group_proposals, force: true) do |t|
        t.references :proposal
        t.references :group
        t.timestamps null: false
      end

      create_table(:group_participations, force: true) do |t|
        t.references :user
        t.references :group
        t.timestamps null: false
      end

      create_table(:areas, force: true) do |t|
        t.string :name
        t.references :group
        t.timestamps null: false
      end

      create_table(:area_participations, force: true) do |t|
        t.references :user
        t.references :area
        t.timestamps null: false
      end
    end

    class Proposal < ActiveRecord::Base
      belongs_to :user
      has_many :group_proposals
      has_many :groups, through: :group_proposals
    end

    class Group < ActiveRecord::Base
      belongs_to :user
      has_many :group_proposals
      has_many :proposals, through: :group_proposals
      has_many :group_participations
      has_many :participants, through: :group_participations
      has_many :areas
    end

    class GroupProposal < ActiveRecord::Base
      belongs_to :proposal
      belongs_to :group
    end

    class GroupParticipation < ActiveRecord::Base
      belongs_to :user
      belongs_to :group
    end

    class User < ActiveRecord::Base
      has_many :proposals
      has_many :groups
      has_many :group_participations
      has_many :participations, through: :group_participations, source: :group
    end

    class Area < ActiveRecord::Base
      belongs_to :group
      has_many :area_participations
      has_many :participants, through: :area_participations, source: :user
    end

    class AreaParticipation < ActiveRecord::Base
      belongs_to :user
      belongs_to :area
    end

    users = Array.new(15_000) do |i|
      User.new(name: "User #{i}")
    end

    User.import(users, validate: false)

    proposals = Array.new(5000) do |i|
      Proposal.new(name: "Proposal #{i}", user: users.sample)
    end

    Proposal.import(proposals, validate: false)

    groups = Array.new(1500) do |i|
      Group.new(name: "Group #{i}", user: users.sample)
    end

    Group.import(groups, validate: false)

    group_proposals = groups.flat_map do |group|
      proposals.sample(3).map do |proposal|
        GroupProposal.new(group: group, proposal: proposal)
      end
    end

    GroupProposal.import(group_proposals, validate: false)

    group_participations = groups.flat_map do |group|
      users.sample(10).map do |participant|
        GroupParticipation.new(group: group, user: participant)
      end
    end

    GroupParticipation.import(group_participations, validate: false)


    areas = Array.new(1000) do |i|
      Area.new(name: "Area #{i}", group: groups.sample)
    end

    Area.import(areas, validate: false)

    area_participations = Array.new(5000) do |i|
      AreaParticipation.new(area: areas.sample, user: users.sample)
    end

    AreaParticipation.import(area_participations, validate: false)
  end

  describe '#accessible_by' do
    it 'has different performances depending on the number of rules' do
      report = Benchmark.ips do |x|
        user_ids = User.all.pluck(:id)
        x.report('easy') do
          (@ability = double).extend(CanCan::Ability)
          @ability.can :read, Proposal
          Proposal.accessible_by(@ability).all
        end

        x.report('cannot') do
          (@ability = double).extend(CanCan::Ability)
          @ability.cannot :read, Proposal
          Proposal.accessible_by(@ability).all
        end

        x.report('simple filter') do
          (@ability = double).extend(CanCan::Ability)
          @ability.can :read, Proposal, user_id: user_ids.sample
          Proposal.accessible_by(@ability).all
        end

        x.report('one join') do
          (@ability = double).extend(CanCan::Ability)
          @ability.can :read, Proposal, user_id: user_ids.sample
          @ability.can :read, Proposal, groups: { user_id: user_ids.sample }
          Proposal.accessible_by(@ability).all
        end

        x.report('two joins') do
          (@ability = double).extend(CanCan::Ability)
          @ability.can :read, Proposal, user_id: user_ids.sample
          @ability.can :read, Proposal, groups: { user_id: user_ids.sample }
          @ability.can :read, Proposal, groups: { group_participations: { user_id: user_ids.sample } }
          Proposal.accessible_by(@ability).all
        end

        x.report('three joins') do
          (@ability = double).extend(CanCan::Ability)
          @ability.can :read, Proposal, user_id: user_ids.sample
          @ability.can :read, Proposal, groups: { user_id: user_ids.sample }
          @ability.can :read, Proposal, groups: { group_participations: { user_id: user_ids.sample } }
          @ability.can :read, Proposal, groups: { areas: { area_participations: { user_id: user_ids.sample } } }
          Proposal.accessible_by(@ability).all
        end
      end
    end
  end
end
