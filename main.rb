%w(rubygems dm-core dm-migrations dm-sqlite-adapter gollum haml oa-oauth sinatra sinatra/base ./etc/config.rb log4r).each { |dependency| require dependency }
#%w(rubygems dm-core dm-migrations dm-sqlite-adapter gollum haml sinatra sinatra/base).each { |dependency| require dependency }

if RUBY_PLATFORM.downcase.include?("linux")
  RubyPython.configure :python_exe => 'python2.7'
end

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
set :site_description, 'HONKY DO THA jiveJerky:!!'
set :author, 'Fielding'

logger = Log4r::Logger.new('authlog')
logger.outputters << Log4r::Outputter.stdout
logger.outputters << Log4r::FileOutputter.new('logtest', :filename => 'log/authlog.log')
logger.info('authlog: fieldnote initialized')

helpers do
  def current_user
    @current_user ||= User.get(session[:user_id]) if session[:user_id]
  end

  def partial(page, variables={})
    haml page.to_sym, {layout:false}, variables
  end

  def showcontent(name)
    repo = Gollum::Wiki.new(settings.git_repo)
    if @content = repo.page(name).formatted_data
      @editable = true
      haml :note, :format => :html5
    end
  end

  def getMeta(object)
    repo = Gollum::Wiki.new(settings.git_repo)
    if object = repo.page(object)
      raw = object.raw_data
      markup = Gollum::Markup.new(object)
      markup.extract_code(raw)
      @meta = Maruku.new(raw).attributes
    end
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
  logger.info("authlog: #{auth["user_info"]["name"]} successfully authorized")
  redirect '/'
end

["/sign_in/?", "/signin/?", "/log_in/?", "/login/?",  "/sign_up/?", "/signup/?"].each do |path|
  get path do
    redirect '/auth/twitter'
  end
end

["/sign_out/?", "/signout/?", "/log_out/?", "/logout/?"].each do |path|
  get path do
    logger.info("authlog: #{current_user.name} logging out")
    session[:user_id] = nil
    redirect '/'
  end
end

get '/notes' do
  if current_user
    note_repo = Gollum::Wiki.new(settings.git_repo)
    ref = note_repo.ref
    @index = note_repo.pages
    @index_filename = note_repo.tree_map_for(ref)
   #getAllMeta(objects)
    logger.info("authlog: #{current_user.name} accessed notes")

    haml :notes, :format => :html5
  else
    redirect '/noauth'
  end
end

get '/noauth' do
  if !current_user
    haml :noauth, :format => :html5
  else
    redirect '/'
  end
end

get '/debug' do
  if current_user
    haml :debug, :format => :html5
  else
    redirect '/noauth'
  end
end

get '/note/*' do
  if current_user
    getMeta(params[:splat].first)
    showcontent(params[:splat].first)
  else
 redirect '/noauth'
  end
end
