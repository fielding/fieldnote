%w(rubygems dm-core dm-migrations dm-sqlite-adapter gollum haml oa-oauth sinatra sinatra/base ./lib/credentials.rb).each { |dependency| require dependency }
#%w(rubygems dm-core dm-migrations dm-sqlite-adapter gollum haml sinatra sinatra/base).each { |dependency| require dependency }

use Rack::Session::Cookie

DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/db/database.db")

class User
  include DataMapper::Resource
  property :id,           Serial
  property :uid,          String
  property :name,         String
  property :nickname,     String
  property :created_at,   DateTime
#  property :location,     String
#  property :image,        String
#  property :description,  String
end

DataMapper.finalize
DataMapper.auto_upgrade!

use OmniAuth::Strategies::Twitter, settings.twitter_consumer_key, settings.twitter_consumer_secret


set :static, true
set :views, 'view'
set :public_directory, 'pub'
set :site_name, 'justFielding'
set :site_description, 'HONKY DO THA jiveJerky!'
set :author, 'Fielding'
set :notes_path, '/home/fielding/git/notes.git'

helpers do
  def current_user
    @current_user ||= User.get(session[:user_id]) if session[:user_id]
  end
end

get '/' do
    haml :index, :format => :html5
end

get '/auth/:provider/callback' do
  auth = request.env["omniauth.auth"]
  user = User.first_or_create({ :uid => auth["uid"]}, {
    :uid => auth["uid"],
  #  :nickame => auth["user_info"]["nickname"],
    :name => auth["user_info"]["name"],
    :created_at => Time.now })
  session[:user_id] = user.id
  redirect '/'
end

["/sign_in/?", "/signin/?", "/log_in/?", "/login/?",  "/sign_up/?", "/signup/?"].each do |path|
  get path do
    redirect '/auth/twitter'
  end
end

["/sign_out/?", "/signout/?", "/log_out/?", "/logout/?"].each do |path|
  get path do
    session[:user_id] = nil
    redirect '/'
  end
end

get '/notes' do
  if current_user
    note_repo = Gollum::Wiki.new(settings.notes_path)
    @ref = note_repo.ref
    @index = note_repo.pages
    @index_filename = note_repo.tree_map_for(@ref)

    haml :notes, :format => :html5
  else
    redirect '/noauth'
  end
end

get '/noauth' do
  if !current_user
    haml :noauth
  else
    redirect '/'
  end
end

get '/debug' do
  if current_user
    haml :debug
  else
    redirect '/noauth'
  end
end

#get '/*' do
#  if current_user
#    wiki = Gollum::Wiki.new(settings.notes_path)
#    if params[:splat].first
#    end
#  else
# redirect '/noauth'
#  end
#end

