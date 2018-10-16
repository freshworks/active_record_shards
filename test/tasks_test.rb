# frozen_string_literal: true
require_relative 'helper'

# ActiveRecordShards overrides some of the ActiveRecord tasks, so
# ActiveRecord needs to be loaded first.
Rake::Application.new.rake_require("active_record/railties/databases")
require 'active_record_shards/tasks'
task :environment do
  # Only required as a dependency
end

describe "Database rake tasks" do
  def capture_stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = STDERR
  end

  let(:config) { Phenix.load_database_config('test/database_tasks.yml') }
  let(:primary_name) { config['test']['database'] }
  let(:replica_name) { config['test']['replica']['database'] }
  let(:shard_names) { config['test']['shards'].values.map { |v| v['database'] } }
  let(:database_names) { shard_names + [primary_name, replica_name] }

  before do
    if ActiveRecord::VERSION::MAJOR >= 4
      ActiveRecord::Tasks::DatabaseTasks.database_configuration = config
      ActiveRecord::Tasks::DatabaseTasks.env = RAILS_ENV
      ActiveRecord::Tasks::DatabaseTasks.migrations_paths = '/app/migrations'
    else
      # It uses Rails.application.config to config ActiveRecord
      Rake::Task['db:load_config'].clear
      ActiveRecord::Base.configurations = config
    end
  end

  after do
    Phenix.configure
    Phenix.burn!
  end

  describe "db:create" do
    it "creates the database and all shards" do
      rake('db:create')
      databases = show_databases(config)

      assert_includes databases, primary_name
      refute_includes databases, replica_name
      shard_names.each do |name|
        assert_includes databases, name
      end
    end
  end

  describe "db:drop" do
    it "drops the database and all shards" do
      rake('db:create')
      rake('db:drop')
      databases = show_databases(config)

      refute_includes databases, primary_name
      shard_names.each do |name|
        refute_includes databases, name
      end
    end

    it "does not fail when db is missing" do
      rake('db:create')
      rake('db:drop')
      show_databases(config).wont_include primary_name
    end

    it "fails loudly when unknown error occurs" do
      ActiveRecordShards::Tasks.stubs(:root_connection).raises(ArgumentError)
      out = capture_stderr { rake('db:drop') }
      out.must_include "Couldn't drop "
      out.must_include "test/helper.rb"
    end
  end
end
