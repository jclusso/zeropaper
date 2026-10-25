namespace :site do
  desc "Build the project website's stylesheet (docs/assets/site.css) from the app's Tailwind theme"
  task :css do
    require "tailwindcss/ruby"

    input = Rails.root.join("docs/assets/site.tailwind.css").to_s
    output = Rails.root.join("docs/assets/site.css").to_s
    system(Tailwindcss::Ruby.executable, "--cwd", Rails.root.join("docs").to_s, "-i", input, "-o", output, "--minify", exception: true)
  end
end
