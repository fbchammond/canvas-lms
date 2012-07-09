require 'bundler/capistrano'

set :application, "canvas-lms"

set :gateway, 'root@dog.hylesanderson.edu'
set :scm, :git
set :repository,  "https://github.com/fbchammond/canvas-lms.git"
set :branch, "ilesi"
set :repository_cache, "git_cache"
set :deploy_via, :remote_cache
set :deploy_to, "/var/www/ilesi_canvas"

role :web, "root@newt.hylesanderson.edu" # Your HTTP server, Apache/etc
role :app, "root@newt.hylesanderson.edu" # This may be the same as your `Web` server
role :db,  "root@newt.hylesanderson.edu", :primary => true # This is where Rails migrations will run

set :use_sudo, false

after "deploy:update_code" do
  %w{ amazon_s3 cache_store database delayed_jobs domain file_store outgoing_mail security }.each do |f|
    run "ln -s #{shared_path}/#{f}.yml #{release_path}/config/#{f}.yml"
  end
  
  run "ln -s #{shared_path}/files #{release_path}/tmp/files"
  
  #run "ln -s #{shared_path}/google2248bfbba38f2b28.html #{release_path}/public/google2248bfbba38f2b28.html"
  
  # The Facebook icon is missing so symlink on deploy -- when the symlink fails it presumably means that the problem is fixed
  #run "ln -s #{release_path}/public/images/email_big.png #{release_path}/public/images/conversation_message_icon.png"
  
  run "chown ilesi_canvas:ilesi_canvas #{release_path}/config/environment.rb"
  run "chown ilesi_canvas:ilesi_canvas #{release_path}/db"
  run "chown ilesi_canvas:ilesi_canvas #{release_path}/tmp"
  
  run "cd #{release_path} && RAILS_ENV=assets bundle exec rake canvas:compile_assets"
  run "cd #{release_path} && RAILS_ENV=assets bundle exec rake canvas:compress_assets"
end

after "deploy:start" do
  # restart worker
  run "service ilesi_canvas_init restart"
end

namespace :deploy do
  task :start, :roles => :app do
    restart
  end

  task :restart, :roles => :app do
    run "touch #{File.join(current_path, "tmp", "restart.txt")}"
  end
end