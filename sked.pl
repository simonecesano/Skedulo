#!/usr/bin/env perl
use FindBin qw($Bin);
use lib "$Bin/lib";
use Mojolicious::Lite;
# use XML::LibXML::PrettyPrint;
# use XML::LibXML;
# use XML::XML2JSON;
# use XML::Hash::XS;
# use XML::Hash;
use Date::Parse;
use DateTime;
use Data::Dump qw/dump/;
use Mojo::Util qw/dumper/;
use CHI;
use DBI;
use Skedulo::Util qw/pp_xml xml_to_hash/;


push @{app->static->paths} => './static';
push @{app->routes->namespaces}, 'Skedulo::Controller';
push @{app->plugins->namespaces}, 'Skedulo::Plugin';

plugin 'Config';
plugin 'EWS';


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

get '/item/*id' => { controller => 'Meetings', action => 'calendar_item' };

post '/item/*id' => { controller => 'Meetings', action => 'calendar_action' };

get '/load/:who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => sub {
    my $c = shift;
    $c->set_dates();
    $c->set_user();

    return $c->render(template => 'load')
	    
};

get '/freebusy/:who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => sub {
    my $c = shift;
    $c->set_dates();
    $c->set_user();

    if ($c->stash('format') =~/(^$)|(html$)/) {
	return $c->render(template => 'freebusy')
    }

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
		return $c->render( json => { freebusy => $json->[0]->{content} } )
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text };
		return $c->render( json => $json )
	    }
	}	    
    }
};

get '/timezones' => sub {
    my $c = shift;

    my $tx = $c->get_ews('outlook/get_timezones');
    
    my $dom = $tx->res->dom;

    return $c->render( text => pp_xml($dom) )
};


app->start;

__DATA__

