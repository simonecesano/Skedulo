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

get '/session';

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

post '/foo/bar' => sub {
    my $c = shift;
    $c->params_to_stash(qw/id change_key status/);
    my $tx = $c->get_ews('outlook/set_status');
    my $dom = $tx->res->dom;
    $c->app->log->info($dom);
    $c->render(json => xml_to_hash($dom));
};


any '/make/me/:start/:end' => sub {
    my $c = shift;

    my $strp = DateTime::Format::Strptime->new( pattern   => '%Y-%m-%dT%H:%M:%S%z', time_zone => 'Europe/Berlin', );

    $c->set_user();
    $c->set_dates();
    $c->params_to_stash(qw/subject location sensitivity body attendees[] categories[]/);

    my $tx = $c->get_ews('outlook/schedule_meeting');
    my $dom = $tx->res->dom;
    
    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		# $c->app->log->info($dom);
		$json = xml_to_hash($dom->at('ResponseCode'));
		return $c->render( json => { start => $c->stash('start'), end => $c->stash('end'), freebusy => $json } )
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text };
		return $c->render( json => $json )
	    }
	}	    
    }
};


get '/item/*id' => { controller => 'Meetings', action => 'calendar_item' };

post '/item/*id' => { controller => 'Meetings', action => 'calendar_action' };

get '/load/:who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => sub {
    my $c = shift;
    $c->set_dates();
    $c->set_user();
    return $c->render(template => 'load')
};

get '/freebusy/#who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => sub {
    my $c = shift;

    $c->set_dates();
    $c->set_user();

    if ($c->stash('format') =~/(^$)|(html$)/) { return $c->render(template => 'freebusy') }

    $c->stash('interval', 60) unless $c->stash('interval');
    
    my $tx = $c->get_ews('outlook/freebusy');

    my $req = $tx->req->body;
    my $dom = $tx->res->dom;

    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		my $fb = xml_to_hash($dom->at('MergedFreeBusy'))->{content};
		my $wp = xml_to_hash($dom->at('WorkingPeriod'));

		$wp->{days} = [ (split /\s+/, delete $wp->{DayOfWeek}) ]; # =~ s/ /, /gr;
		$wp->{start} = mins_to_hour(delete $wp->{StartTimeInMinutes});
		$wp->{end} = mins_to_hour(delete $wp->{EndTimeInMinutes});

		return $c->render( json => {
					    start => $c->stash('start')->set_time_zone('Europe/Berlin'),
					    interval => $c->stash('interval'),
					    freebusy => $fb,
					    working_time => $wp
					   } )
	    } else {
		$c->res->code(500);
		$c->app->log->debug($req);
		my $json = { message => eval { $dom->at('ResponseCode')->all_text } || 'N/A', res => $dom, req => $req };
		return $c->render( json => $json )
	    }
	}	    
    }
};

use POSIX qw/floor/;

sub mins_to_hour {
    my $m = shift;
    my $h = floor($m / 60);
    $m = $m % 60;
    return sprintf '%02d:%02d', $h, $m;
}


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

