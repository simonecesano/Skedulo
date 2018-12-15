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
push @{app->routes->namespaces}, 'Skedulo::Controller';
push @{app->plugins->namespaces}, 'Skedulo::Plugin';



plugin 'Config';
plugin 'EWS';
plugin 'Localizer';

sub startup {
    my $c = shift;
    $c->app->log->info('Starting...');
    return $c
}

plugin 'CHI' => { default => { driver => 'DBI',
			       dbh => DBI->connect("dbi:SQLite:dbname=$Bin/cache.db"),
			       global => 1,
			       expires_in => 3600 } };

hook (before_dispatch => sub {
	  my $c = shift;

	  unless (($c->req->url =~ /login|static/) || ($c->session('user') && $c->session('password'))) {
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
		$json = xml_to_hash($dom->find('MergedFreeBusy'));
		return $c->render( json => {
					    start => $c->stash('start'),
					    interval => $c->stash('interval'),
					    freebusy => $json->[0]->{content}
					   } )
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text };
		return $c->render( json => $json )
	    }
	}	    
    }
};



get '/timezone'            => { controller => 'TimeZones', action => 'get_timezone' };

get '/timezone/*location'  => { controller => 'TimeZones', action => 'get_timezone' };

get '/latlon'              => { controller => 'TimeZones', action => 'get_latlon' };

get '/latlon/*q'           => { controller => 'TimeZones', action => 'get_latlon' };

get '/setup';

get '/tz' => sub { my $c = shift; $c->stash('date' => DateTime->now) };



get '/whois'        => { controller => 'User', action => 'get_whois' };

get '/whois/*name'  => { controller => 'User', action => 'get_whois' };



get '/help' => sub {
    my $c = shift;
    $c->stash('referrer', Mojo::URL->new($c->req->headers->referrer)->path =~ s/\///r );
};

app->start;

__DATA__

