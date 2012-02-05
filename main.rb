%w(dm-core dm-migrations dm-sqlite-adapter gollum haml maruku oa-oauth sinatra/base log4r flickraw rockstar active_diigo twitter-text time-ago-in-words fieldmatter).each { |dependency| require dependency }

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

class FieldNote < Sinatra::Base

  require_relative 'etc/config'
  require_relative 'lib/twitTwat'
  use Rack::Session::Cookie
  set :static, true
  set :views, 'view'
  set :public_directory, 'pub'
  set :site_name, 'justFielding'
  set :site_description, 'HONKY DO THA jiveJerky:!!'
  set :author, 'Fielding Johnston'

  use OmniAuth::Strategies::Twitter, settings.twitter_consumer_key, settings.twitter_consumer_secret

  FlickRaw.api_key = settings.flickr_api_key
  FlickRaw.shared_secret = settings.flickr_shared_secret

  ActiveDiigo.api_key = settings.diigo_api_key
  ActiveDiigo.username = settings.diigo_username
  ActiveDiigo.password = settings.diigo_password

  logger = Log4r::Logger.new('auth')
  logger.outputters << Log4r::Outputter.stdout
  logger.outputters << Log4r::FileOutputter.new('auth', :filename => 'log/auth.log')
  logger.info('fieldnote initialized')

  helpers do
    def current_user
      @current_user ||= User.get(session[:user_id]) if session[:user_id]
    end

    def partial(page, variables={})
      haml page.to_sym, {layout:false}, variables
    end

    def accessControl(frontMatter)
      logger = Log4r::Logger['auth']
      if frontMatter[:publish] == 'Read'
        logger.info("Unknown[#{request.ip} accessed #{frontMatter[:title]}")
        return true
      elsif current_user && current_user.id == 1
        logger.info("#{current_user.name} accessed #{frontMatter[:title]} as root user")
        return true
      elsif frontMatter[:publish] != 'Read' && current_user
        logger.warn("#{current_user.name} attempted to access #{frontMatter[:title]}")
        return false
      else
        logger.warn("Unknown[#{request.ip}] tried to access #{frontMatter[:title]}")
        return false
      end
    end

    def showcontent(name, frontMatter={}, fieldmatter={})
      repo = Gollum::Wiki.new(settings.git_repo)
      object = repo.page(name)
      if content = object.formatted_data
        @editable = true
          haml :note, :locals => {:fMatter => frontMatter, :fieldmatter => fieldmatter, :content => content}
        end
    end

    def navLogInOut # render partial for login/logout nav menu link
      if current_user
        route, display = '/logout', 'logout'
      else
        route, display = '/login', 'login'
      end
    partial :_navLogInOut, :locals => {:route => route, :display => display}
    end

    def getFrontMatter(object)
      repo = Gollum::Wiki.new(settings.git_repo)
      if object = repo.page(object)
        raw = object.raw_data
        markup = Gollum::Markup.new(object)
        markup.extract_code(raw)
        frontMatter = Maruku.new(raw).attributes
      end
    end

    def getFieldMatter(object)
      object = "#{object}.md"
      id = Ohm.redis.smembers("FieldMatter::Note:filename:#{Base64::encode64(object).chomp}").pop
      note = FieldMatter::Note[id]
    end

  end

  get '/' do
    logger.info("Somebody[#{request.ip}] accessed the front page.")
    haml :index, :format => :html5
  end

### Auth Methods 
  get '/auth/:provider/callback' do
    auth = request.env["omniauth.auth"]
    user = User.first_or_create({ :uid => auth["uid"]}, {
      :uid => auth["uid"],
      #  :nickame => auth["user_info"]["nickname"],
      :name => auth["user_info"]["name"],
      :created_at => Time.now })
      session[:user_id] = user.id
      logger.info("#{auth["user_info"]["name"]} successfully authorized from #{request.ip}")
      redirect '/'
  end

  ["/sign_in/?", "/signin/?", "/log_in/?", "/login/?",  "/sign_up/?", "/signup/?"].each do |path|
    get path do
      redirect '/auth/twitter'
    end
  end

  ["/sign_out/?", "/signout/?", "/log_out/?", "/logout/?"].each do |path|
    get path do
      logger.info("#{current_user.name} logged out")
      session[:user_id] = nil
      redirect '/'
    end
  end

  get '/noauth' do
    if !current_user
      haml :noauth, :format => :html5
    else
      redirect '/'
    end
  end

### End Auth Methods
  
  get '/about' do
    logger.info("Somebody[#{request.ip}] attempted to access /about. Perhaps you should finish it.")
    haml :about, :format => :html5
  end

  get '/blog' do
    logger.info("Somebody[#{request.ip}] attempted to access /blog. Perhaps you should finish it.")
    # Twitter Feed
    twitScrape = TwitTwat.new(settings.twitter_username)
    twitScrape = twitScrape.getJson(5)
    # Flickr Feed
    flickrFeed = flickr.photos.search(:user_id => settings.flickr_id, :per_page => 6)
    # Scrobbler
    Rockstar.lastfm = {:api_key => settings.lastfm_api_key, :api_secret => settings.lastfm_api_secret}
    scrobble = Rockstar::User.new('justfielding')
    playing = scrobble.recent_tracks[0]
    # Diigo Interwebs
    diigo = ActiveDiigo::Base.find('justfielding', :count => 6)

    haml :blog, :locals => {:twitScrape => twitScrape, :flickrFeed => flickrFeed, :playing => playing, :diigo => diigo}
  end
  
  get '/notes' do                                                                # Super ugly, really need to refactor/reclear/rethink
    if current_user
      if current_user.id == 1
        note_repo = Gollum::Wiki.new(settings.git_repo)
        ref = note_repo.ref
        @index = note_repo.pages
        @index_filename = note_repo.tree_map_for(ref)

        #getAllMeta(objects)

        logger.info("#{current_user.name} accessed note index")

        haml :notes, :format => :html5
      else
        logger.warn("#{current_user.name} attempted to access note")
        "Sorry, #{current_user.name} you do not have access to my notes"
      end
    else
      logger.warn("Unknown[#{request.ip}] attempted to access note index")
      redirect '/noauth'
    end
  end

  get '/note/*' do                                                               # Mostly happy with this
    frontMatter = getFrontMatter(params[:splat].first)
    fieldmatter = getFieldMatter(params[:splat].first)
    if accessControl(frontMatter)
      showcontent(params[:splat].first, frontMatter, fieldmatter)
    else
      redirect '/noauth'
    end
  end

  get '/debug' do
    if current_user
      logger.info("#{current_user.name} accessed deug")
      haml :debug, :format => :html5
    else
      logger.warn("Unknown[#{request.ip}] attempted to access debug")
      redirect '/noauth'
    end
  end
end
