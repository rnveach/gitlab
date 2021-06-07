# frozen_string_literal: true

# Prevent StateMachine warnings from outputting during a cron task
StateMachines::Machine.ignore_method_conflicts = true if ENV['CRON']

task :gitlab_environment do
  Rake::Task[:environment].invoke unless ENV['SKIP_RAKE_ENV_LOADING']

  extend SystemCheck::Helpers
end
