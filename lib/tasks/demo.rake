namespace :demo do
  desc "Fill an empty development database with a fictional demo library (for screenshots)"
  task load: :environment do
    require Rails.root.join("script/demo/loader").to_s
    Demo::Loader.new.run
  end
end
