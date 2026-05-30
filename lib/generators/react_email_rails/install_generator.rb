module ReactEmailRails; end
module ReactEmailRails::Generators; end

class ReactEmailRails::Generators::InstallGenerator < Rails::Generators::Base
  source_root(File.expand_path("templates", __dir__))

  def copy_initializer
    template("initializer.rb", "config/initializers/react_email_rails.rb")
  end
end
