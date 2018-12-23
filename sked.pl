#!/usr/bin/env perl
use FindBin qw($Bin);
use lib "$Bin/lib";
use Mojolicious::Lite;
use Date::Parse;
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


any '/make/me/:start/:end' => sub {
    my $c = shift;

    $c->params_to_stash(qw/subject location sensitivity body attendees[] categories[]/);

    $c->app->log->info($c->stash('start'), $c->stash('end')); 
    $c->stash('subject', '');
    
    my $tx = $c->get_ews('outlook/schedule_meeting');
    
    my $dom = $tx->res->dom;
    
    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		$json = xml_to_hash($dom->at('ResponseCode'));
		return $c->render( json => { freebusy => $json } )
	    } else {
		$c->res->code(500);
		$c->app->log->info($dom);
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

    $c->app->log->info($c->stash('who'));

    $c->app->log->info(dump $c->req->cookies);
    
    if ($c->stash('format') =~/(^$)|(html$)/) { return $c->render(template => 'freebusy') }

    $c->stash('interval', 60) unless $c->stash('interval');
    
    my $tx = $c->get_ews('outlook/freebusy');
    my $dom = $tx->res->dom;

    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		my $fb = (xml_to_hash($dom->find('MergedFreeBusy')))->[0]->{content};
		my $wp = (xml_to_hash($dom->find('WorkingPeriodArray')))->[0]->{WorkingPeriod};
		
		$c->app->log->info(dump $wp);
		$wp->{days} = [ (split /\s+/, delete $wp->{DayOfWeek}) ]; # =~ s/ /, /gr;
		$wp->{start} = mins_to_hour(delete $wp->{StartTimeInMinutes});
		$wp->{end} = mins_to_hour(delete $wp->{EndTimeInMinutes});

		$c->app->log->info(ref $c->stash('start'));
		$c->app->log->info($c->stash('start'));
		$c->app->log->info($c->stash('start')->format_cldr('yyyy-MM-ddThh:mm:ssZZZZZ'));
		return $c->render( json => {
					    start => $c->stash('start')->format_cldr('yyyy-MM-ddThh:mm:ssZZZZZ'),
					    interval => $c->stash('interval'),
					    freebusy => $fb,
					    working_time => $wp
					   } )
	    } else {
		$c->res->code(500);
		my $json = { message => $dom->at('ResponseCode')->all_text };
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

get '/thing' => sub {
    my $c = shift;

    $c->stash('tz_info', $c->ews_tz_definition('UTC') );

    $c->res->headers->content_type('text/plain');
    $c->render(inline => '<%== $tz_info %>' )
};


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

