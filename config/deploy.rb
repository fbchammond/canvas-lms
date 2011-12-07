require 'bundler/capistrano'

set :application, "canvas-lms"

set :scm, :git
set :repository,  "ssh://git@dev.fbchammond.com/var/git/vendor/canvas-lms.git"
set :branch, "hac"
set :repository_cache, "git_cache"
set :deploy_via, :remote_cache
set :deploy_to, "/var/www/canvas"

role :web, "root@bean.hylesanderson.edu" # Your HTTP server, Apache/etc
role :app, "root@bean.hylesanderson.edu" # This may be the same as your `Web` server
# role :db,  "root@bean.hylesanderson.edu", :primary => true # This is where Rails migrations will run

set :use_sudo, false

after "deploy:update_code" do
  %w{ amazon_s3 cache_store database delayed_jobs domain file_store outgoing_mail security }.each do |f|
    run "ln -s #{shared_path}/#{f}.yml #{release_path}/config/#{f}.yml"
  end
  
  run "ln -s #{shared_path}/files #{release_path}/tmp/files"
  
  run "ln -s #{shared_path}/google2248bfbba38f2b28.html #{release_path}/public/google2248bfbba38f2b28.html"
  
  run "chown canvas:canvas #{release_path}/config/environment.rb"
  run "chown canvas:canvas #{release_path}/db"
  run "chown canvas:canvas #{release_path}/tmp"
  
  run "cd #{release_path} && RAILS_ENV=assets bundle exec rake canvas:compile_assets"
end

after "deploy:symlink" do
  # restart worker
  run "service canvas_init restart"
end

namespace :deploy do
  task :start, :roles => :app do
    restart
  end

  task :restart, :roles => :app do
    run "touch #{File.join(current_path, "tmp", "restart.txt")}"
  end
end