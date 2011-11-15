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
  run "ln -s #{shared_path}/database.yml #{release_path}/config/database.yml"
end

namespace :deploy do
  task :start, :roles => :app do
    restart
  end

  task :restart, :roles => :app do
    run "touch #{File.join(current_path, "tmp", "restart.txt")}"
  end
end