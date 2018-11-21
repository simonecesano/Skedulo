#!/usr/bin/env perl
use FindBin qw($Bin);
use lib "$Bin/lib";
use Mojolicious::Lite;
use XML::LibXML::PrettyPrint;
use XML::LibXML;
use XML::XML2JSON;
use XML::Hash::XS;
use XML::Hash;
use Date::Parse;
use DateTime;

use Mojo::Util qw/dumper/;
use CHI;
use DBI;

plugin 'Config';

push @{app->static->paths} => './static';

plugin 'CHI' => { default => { driver => 'DBI',
			       dbh => DBI->connect("dbi:SQLite:dbname=$Bin/cache.db"),
			       global => 1,
			       expires_in => 3600 } };

hook (before_dispatch => sub {
	  my $c = shift;

	  unless (($c->req->url =~ /login/) || ($c->session('user') && $c->session('password'))) {
	      return $c->redirect_to('/login');
	  }
	  
	  $c->stash('format', $c->param('format')) unless $c->stash('format');
	  return $c;
      });

hook (before_render => sub {
	  my $c = shift;
	  
	  # $c->app->log->info($c->req->url);
	  return $c;
      });

helper 'get_ews' => sub {
    my $c = shift;
    my $template = shift;
    my ($user, $password) = @_;
    my $url = Mojo::URL->new(app->config->{ews});
    $url->userinfo(join ':', $user || $c->session('user'), $password || $c->session('password'));
    my $ua  = Mojo::UserAgent->new();
    
    my $xml = $c->render_to_string(template => $template, format => "xml");

    my $tx = $ua->post($url => {'Content-Type' => 'text/xml', 'Accept-Encoding' => 'None' } => $xml);
    if ($tx->res->is_success) {
	if ($tx->res->dom->at('ResponseCode')->all_text eq 'NoError') {
	} else {
	    $tx->res->code(500)
	}
    } else {
	
    }
    return $tx;
};

helper 'set_dates' => sub {
    my $c = shift;
    my $start;

    for (qw/start end/) {
	my $date;
	app->log->info($_);
	
	if ($c->stash($_) =~ /^(\+|\-)(\d+)(.*)/) {
	    my ($sign, $qty, $what) = ($1, $2, $3);
	    $what ||= 'days';
	    if ($sign eq '+') {
		$date = ($start || DateTime->today)->add( $what => $qty)
	    } else {
		$date = ($start || DateTime->today)->subtract( $what => $qty)
	    }
	} elsif ($c->stash($_) =~ /today|now/) {
	    my $f = $c->stash($_);
	    $date = DateTime->$f;
	} else {
	    # strptime
	    $date = DateTime->from_epoch( epoch => str2time($c->stash($_)) );
	}
	$c->stash($_, $date)
    }
    return $c;
};

helper 'set_user' => sub {
    my $c = shift;
    $c->stash('user', $c->session('user')) if $c->stash('who') eq 'me';
    return $c;
};

get '/date/:who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => sub {
    my $c = shift;

    $c->set_dates()->set_user();
    
    $c->render(text => join ' ', $c->stash('start'), $c->stash('end'), $c->stash('user')); 
};

get '/login' => sub {
    my $c = shift;
    $c->stash('user', $c->cookie('user'));
    $c->render(template => 'login')
};

get '/me';

get '/error';

get '/session';



post '/login' => sub {
    my $c = shift;

    app->log->info(dumper $c->req->params->to_hash);
    
    if ($c->param('user') && $c->param('password')) {
	$c->stash('name', $c->param('user'));
	my $tx = $c->get_ews('outlook/whois', $c->param('user'), $c->param('password'));
	if ($tx->res->is_success) {
	    my $dom = $tx->res->dom;
	    my $json = xml_to_hash($dom->at('Contact'));
	    $c->session('email', $json->{Mailbox}->{EmailAddress});
	    $c->session('password', $c->param('password'));
	    $c->session('user', $c->param('user'));
	    $c->session('given_name', $json->{GivenName});	
	    $c->cookie('user' => $c->param('user'));
	    app->log->info(dumper $c->req->params->to_hash);
	    
	    $c->redirect_to('/me');
	} else {
	    $c->flash('error', 'login error');
	    $c->flash('dom', $tx->res->dom);	    
	    $c->redirect_to('/error');
	}
	# return $c->render( json => xml_to_hash($dom->at('Contact')) );
    } else {
	$c->redirect_to('/login');
    }
};


get '/setup/:folder' => sub {
    my $c = shift;

    my $url = Mojo::URL->new(app->config->{ews});
    $url->userinfo(join ':', $c->session('user'), $c->session('password'));
    my $ua  = Mojo::UserAgent->new();

    app->log->info($url->userinfo);
    app->log->info($c->cookie('user'));
    app->log->info(dumper $c->session);

    my $xml = $c->render_to_string(template => 'outlook/folder_search', format => "xml");
    my $tx = $ua->post($url => {'Content-Type' => 'text/xml', 'Accept-Encoding' => 'None' } => $xml);
    my $dom = $tx->res->dom;
    app->log->info('setting up calendar');
    app->log->info('$dom->at("FolderId")->attr("Id")');    
    app->log->info($dom->at('FolderId')->attr('Id'));
    $c->session('calendar', $dom->at('FolderId')->attr('Id'));
    app->log->info('calendar');
    app->log->debug($c->session('calendar'));
    $c->render( json => xml_to_hash($dom) );
};
    
get '/meet/:who/:start/:end' => { who => 'me', start => 'today', end => '+7' } => sub {
    my $c = shift;

    $c->set_dates()->set_user();

    app->log->info('calendar');
    app->log->info($c->session('calendar'));

    if ($c->stash('format') =~/(^$)|(html$)/) {
	return $c->render(template => 'meeting_list')
    }

    my $tx = $c->get_ews('outlook/meetings');
    my $dom = $tx->res->dom;
    
    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		$json = xml_to_hash($dom->find('CalendarItem'));
		$c->res->headers->cache_control('private, max-age=120');
		return $c->render( json => { meetings => $json } )
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text };
		return $c->render( json => $json )
	    }
	}	    
    }
};

get '/item/decline/*id' => sub {
    my $c = shift;
    my $action = $c->param('action');
    
    my $tx = $c->get_ews('outlook/accept_decline');
    my $dom = $tx->res->dom;

    return $c->render( text => $dom );

    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		$json = xml_to_hash($dom->find('CalendarItem'));
		$c->res->headers->cache_control('private, max-age=120');
		return $c->render( json => { meetings => $json } )
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text };
		return $c->render( json => $json )
	    }
	}	    
    }

    return $c->render( json => { action => $action } )
};

post '/item/*id' => sub {
    my $c = shift;
    app->log->info( dumper $c->req->params->to_hash );
    return $c->render( json => $c->req->params->to_hash );
};

get '/item/*id' => sub {
    my $c = shift;

    if ($c->stash('format') =~/(^$)|(html$)/) {
	return $c->render(template => 'calendar_item')
    }

    my $tx = $c->get_ews('outlook/item');
    my $dom = $tx->res->dom;

    # app->log->info($tx->res->is_success);
    
    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		$json = xml_to_hash($dom->at('CalendarItem'));
		$c->res->headers->cache_control('private, max-age=120');
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text }
	    }
	    return $c->render( json => $json )
	}	    
    }
    
    
    
};


sub pp_xml {
    my $string = shift;
    for ($string) { s/<\w+?:/</g; s/<\/\w+?:/<\//g }

    my $dom = XML::LibXML->load_xml(string => $string);
    my $pp = XML::LibXML::PrettyPrint->new(indent_string => "   ");
    $pp->pretty_print($dom); # modified in-place
    return $dom->toString;
}

sub xml_to_hash {
    my $xml = shift;
    if (@_) { $xml = $xml->find(shift) }

    my $s = sub { 
	my $dom = shift->to_string;
	for ($dom) {
	    # s/<\w+?:(.)/<\l$1/g;
	    # s/<\/\w+?:(.)/<\/\l$1/g;
	    s/<\w+?:(.)/<$1/g;
	    s/<\/\w+?:(.)/<\/$1/g;
	}
	return xml2hash $dom;
    };

    if ((ref $xml) =~ /Mojo::Collection/) {
	return $xml->map(sub { $s->(shift) })->to_array
    } else {
	return $s->($xml);
    }
}

app->start;

__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
<h1>Welcome to the Mojolicious real-time web framework!</h1>
To learn more, you can browse through the documentation
<%= link_to 'here' => '/perldoc' %>.

