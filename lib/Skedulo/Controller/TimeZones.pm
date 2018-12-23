package Skedulo::Controller::TimeZones;

use Mojo::Base 'Mojolicious::Controller';
use Skedulo::Util qw/pp_xml xml_to_hash/;
use Data::Dump qw/dump/;
use Mojo::File qw/path/;


my $geo_key = $ENV{GOOGLE_GEO_KEY};
my $tz_key  = $ENV{GOOGLE_TZ_KEY};
my $cache = 1;

#---------------------------------------------------------------------------------

sub _get_latlon {
    my $c = shift;

    my $loc = $c->param('q') || $c->stash('q');
    
    if ($cache && (my $json = $c->chi->get('location::' . $loc))) {
	my $json = $json->{results}->[0]->{geometry}->{location};
    	return $json;
    }
    
    my $ua  = Mojo::UserAgent->new();
    my $url = Mojo::URL->new('https://maps.googleapis.com/maps/api/geocode/json');

    $url->query({ address => $loc, key => $geo_key });
    my $tx = $ua->get($url);
    
    $c->chi->set('location::' . $loc, $tx->res->json);
    # $c->app->log->info(dump $tx->res->json);
    my $json = $tx->res->json->{results}->[0]->{geometry}->{location};

    
    return $json

}

sub get_latlon {
    my $c = shift;
    $c->render(json => $c->_get_latlon() );
};

#---------------------------------------------------------------------------------

sub _get_timezone {
    my $c = shift;

    my $timestamp = $c->param('time') || time();

    if ($cache && (my $json = $c->chi->get((join '::', 'timezone', $c->param('location'))))) {
    	$c->app->log->info(sprintf "timezone %s cached", $c->param('location'));
    	return $json;
    }
    
    my $ua  = Mojo::UserAgent->new();
    my $url = Mojo::URL->new('https://maps.googleapis.com/maps/api/timezone/json');
    $url->query({ location => $c->param('location'), timestamp => $timestamp, key => $tz_key });

    my $tx = $ua->get($url);

    my $json = $tx->res->json;

    for (qw/dstOffset rawOffset status/) { delete $json->{$_} }
    
    $c->chi->set((join '::', 'timezone', $c->param('location')), $json);
    return $json;
};

sub get_timezone {
    my $c = shift;
    $c->render(json => $c->_get_timezone() );
};

#---------------------------------------------------------------------------------

sub set_timezone_for_user {
    my $c = shift;

    if ($c->param('tz') && $c->cookie('user') || $c->param('who')) {
	my $json = $c->tz_id_to_name($c->param('tz'));
	
	$c->chi->set((join '::', 'timezone', $c->cookie('user') || $c->param('who')), $json);
	
	$c->app->log->info($c->param('tz'));
	$c->app->log->info($c->cookie('user'));
	$c->app->log->info(dump $c->tz_id_to_name($c->param('tz')));

	$c->render(json => { user => $c->cookie('user') || $c->param('user'), tz => $c->param('tz') });
    } else {
	$c->render(json => { error => 'user or timezone missing' });
    }
}

sub get_timezone_for_user {
    my $c = shift;

    if ($cache && (my $json = $c->chi->get((join '::', 'timezone', $c->param('who'))))) {
    	$c->app->log->info(sprintf "timezone %s cached", $c->param('who'));
	return $c->render(json => $json );
    } 
    
    $c->stash('name', $c->param('who'));
    my $tx = $c->get_ews('outlook/whois');
    my $dom = $tx->res->dom;

    my $city = xml_to_hash($dom->at('City'));

    $c->stash('q', $city);

    my $json = $c->_get_latlon();
    $c->param('location', join ',', $json->{lat}, $json->{lng}); 
    $json = $c->_get_timezone();

    $c->chi->set((join '::', 'timezone', $c->param('who')), $json) if $json->{timeZoneId} && $json->{timeZoneName};

    return $c->render(json => $json );
};


sub get_timezone_for_location {
    my $c = shift;

    $c->stash('q', $c->param('location'));

    my $json = $c->_get_latlon();

    $c->param('location', join ',', $json->{lat}, $json->{lng}); 

    $json = $c->_get_timezone();

    $c->chi->set((join '::', 'timezone', $c->param('location')), $json) if $json->{timeZoneId} && $json->{timeZoneName};

    return $c->render(json => $json );
}

sub tz_id_to_name {
    my $c = shift;
    my $id = shift;
    
    state $xml = Mojo::DOM->new(path('windowsZones.xml')->slurp);
    
    my $j = xml_to_hash($xml->at(join '', '[type="', $id, '"]'));
    $j->{timeZoneId} = delete $j->{type};
    $j->{timeZoneName} = delete $j->{other};
    delete $j->{territory};
    return $j;
};

sub tz_check {
    my $c = shift;
    $c->app->log->info($c->param('now'));
    $c->app->log->info($c->param('dateyyyymmdd'));

    my $pattern = '%Y-%m-%d';
    $c->app->log->info($pattern);

    my $dt = DateTime::Format::ISO8601->parse_datetime( $c->param('dateyyyymmddhhmm'));

    my $dtz = $dt->clone->set_time_zone( 'Europe/Berlin' );
    
    return $c->render( json => {
				now => $c->param('now'),
				date => $c->param('date'),
				dateyyyymmdd => $c->param('dateyyyymmdd'),
				dateparsed => $dt,
				datetz => $dtz,
				tzl => $dtz->time_zone_long_name(),
				epoch => $dtz->epoch(),
				utc => $dtz->clone->set_time_zone( 'UTC' )
			       })
}



1;


my $u = sub {
    my $c = shift;
    $c->app->log->info($c->param('tz'));
    $c->app->log->info($c->cookie('user'));
    $c->render(json => { user => $c->cookie('user'), tz => $c->param('tz') });
};


use Mojo::File qw/path/;

sub timezones_ews {
    my $c = shift;
    my $tx = $c->get_ews('outlook/get_timezones');
    my $dom = $tx->res->dom;

    path('timezones.xml')->spurt($dom);
    
    if ($c->stash('format') eq 'xml' || $c->param('format') eq 'xml') {
	$c->res->headers->content_type('text/xml');
	my $id = 'W. Europe Standard Time';

	$dom->find('TimeZoneDefinition');
	    # ->each(sub{
	    # 	     my $s = shift;
	    # 	     $s->remove unless $s->matches(join '', '[Id="', $id, '"]')
	    # 	 });

	$c->app->log->info($dom->find('TimeZoneDefinition')->size);
	$c->render(text => $dom )
    } else {
	my $json = xml_to_hash($dom->find('TimeZoneDefinition'));
	$c->render(json => $json )
    }
};

1;

__DATA__

use Mojo::File qw/path/;

get '/timezone/:region/*location' => sub {
    my $c = shift;
    my $xml = Mojo::DOM->new(path('windowsZones.xml')->slurp);

    my $id = join '/', $c->stash('region'), $c->stash('location');
    
    my $j = xml_to_hash($xml->at(join '', '[type="', $id, '"]'));
    $j->{timeZoneId} = delete $j->{type};
    $j->{timeZoneName} = delete $j->{other};
    
    $c->render( json => $j || 'none' );
};

1;

__DATA__
