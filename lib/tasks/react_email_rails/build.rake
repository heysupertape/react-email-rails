namespace(:react_email_rails) do
  desc("Build the React Email Rails production bundle")
  task(build: :environment) { ReactEmailRails::Tasks.build }

  desc("Remove the React Email Rails production bundle")
  task(clobber: :environment) { ReactEmailRails::Tasks.clobber }

  desc("Verify the React Email Rails renderer is healthy (exits non-zero on failure)")
  task(verify: :environment) { ReactEmailRails::Tasks.verify }
end

unless ENV["SKIP_REACT_EMAIL_RAILS_BUILD"]
  if Rake::Task.task_defined?("assets:precompile")
    Rake::Task["assets:precompile"].enhance(["react_email_rails:build"])
  else
    desc("Compile assets")
    Rake::Task.define_task("assets:precompile" => "react_email_rails:build")
  end

  if Rake::Task.task_defined?("assets:clobber")
    Rake::Task["assets:clobber"].enhance(["react_email_rails:clobber"])
  else
    desc("Remove compiled assets")
    Rake::Task.define_task("assets:clobber" => "react_email_rails:clobber")
  end
end
