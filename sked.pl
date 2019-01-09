#!/usr/bin/env perl
use FindBin qw($Bin);
use lib "$Bin/lib";
use Mojolicious::Lite;
# use Date::Parse;
use DateTime;
use Data::Dump qw/dump/;
use Mojo::Util qw/dumper/;
use CHI;
use DBI;
use Skedulo::Util qw/pp_xml xml_to_hash/;

use DateTime::Format::HTTP;
use DateTime::Format::Strptime;
use DateTime::Format::ISO8601;


push @{app->static->paths} => './static';
push @{app->static->paths} => './node_modules';

push @{app->routes->namespaces}, 'Skedulo::Controller';
push @{app->plugins->namespaces}, 'Skedulo::Plugin';

plugin 'Config';
plugin 'EWS';
plugin 'Localizer';
plugin 'TimeZones';

plugin 'CHI' => { default => { driver => 'DBI',
			       dbh => DBI->connect("dbi:SQLite:dbname=$Bin/cache.db"),
			       global => 1,
			       expires_in => 3600 } };

hook (before_dispatch => sub {
	  my $c = shift;
	  
	  unless (
		  ('127.0.0.1' eq $c->tx->original_remote_address) || 
		  ($c->req->url =~ /login|static/)                 ||
		  ($c->session('user') && $c->session('password'))
		 ) {
	      return $c->redirect_to('/login');
	  }
	  
	  $c->stash('format', $c->param('format')) unless $c->stash('format');
	  return $c;
      });

hook (before_render => sub {
	  my $c = shift;
	  return $c;
      });


get '/login' => sub {
    my $c = shift;
    $c->stash('user', $c->cookie('user'));
    $c->render(template => 'login')
};

get '/me';

get '/error';

post '/login' => { controller => 'User', action => 'post_login' };

get '/setup/:folder' => { controller => 'User', action => 'setup_folder' };
    
get '/meet/:who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => { controller => 'Meetings', action => 'meetings_list' };

get '/blocks' => sub {
    my $c = shift;

    $c->stash('start', DateTime->today);
    $c->stash('end', DateTime->today->add(days => 7));

    my $tx = $c->get_ews('outlook/blocks');
    my $dom = $tx->res->dom;
    $c->render(json => xml_to_hash($dom->at('Items')));
};

post '/blocks/toggle' => sub {
    my $c = shift;

    $c->params_to_stash(qw/id change_key meeting_status/);

    $c->app->log->debug($c->req->url);
    $c->app->log->debug($c->stash('status'));

    my $tx = $c->get_ews('outlook/set_status');
    my $dom = $tx->res->dom;
    $c->render(json => xml_to_hash($dom));
};


post '/meeting/:start/:end' => { controller => 'Meetings', action => 'schedule_meeting' };

get '/item/*id' => { controller => 'Meetings', action => 'calendar_item' };

post '/item/*id' => { controller => 'Meetings', action => 'calendar_action' };

get  '/load/:who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => sub { my $c = shift; $c->set_dates()->set_user(); $c->render(template => 'load') };

get  '/freebusy/#who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => { controller => 'Meetings', action => 'get_freebusy' };

get  '/timezone'            => { controller => 'TimeZones', action => 'get_timezone' };

get  '/timezone/*who'      => [ who  => qr/.*\@.+/ ] => { controller => 'TimeZones', action => 'get_timezone_for_user' };

get  '/timezone/*location' => [ location => qr/\d+\.*\d+\,\d+\.*\d+/ ] => { controller => 'TimeZones', action => 'get_timezone' };

get  '/timezone/*location' => { controller => 'TimeZones', action => 'get_timezone_for_location' };
    
post '/timezone' => { controller => 'TimeZones', action => 'set_timezone_for_user' };

get '/timezones/ews' => { controller => 'TimeZones', action => 'timezones_ews' };

get '/latlon'              => { controller => 'TimeZones', action => 'get_latlon' };

get '/latlon/*q'           => { controller => 'TimeZones', action => 'get_latlon' };

get '/setup';

# this is actually the working hours setup page
get '/tz'           => sub { my $c = shift; $c->stash('date' => DateTime->now) };

get '/whois'        => { controller => 'User', action => 'get_whois' };

get '/whois/*name'  => { controller => 'User', action => 'get_whois' };

get '/help' => sub {
    my $c = shift;
    $c->stash('referrer', Mojo::URL->new($c->req->headers->referrer)->path =~ s/\///r );
};


app->start;

__DATA__

