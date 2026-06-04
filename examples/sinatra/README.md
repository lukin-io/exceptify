# Using Exception Notification with Sinatra

## Quick start

    git clone git@github.com:lukin-io/exceptify.git
    cd exceptify/examples/sinatra
    bundle install
    bundle exec foreman start


The last command starts two services, a smtp server and the sinatra app itself. Thus, visit [http://localhost:1080/](http://localhost:1080/) to check the emails sent and, in a separated tab, visit [http://localhost:3000](http://localhost:3000) and cause some errors. For more info, use the [source](https://github.com/lukin-io/exceptify/blob/main/examples/sinatra/sinatra_app.rb).
