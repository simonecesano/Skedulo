package Skedulo::Controller::TimeZones;

use Mojo::Base 'Mojolicious::Controller';
use Skedulo::Util qw/pp_xml xml_to_hash/;
use Data::Dump qw/dump/;


my $geo_key = $ENV{GOOGLE_GEO_KEY};
my $tz_key  = $ENV{GOOGLE_TZ_KEY};
my $cache = 0;

sub get_latlon {
    my $c = shift;

    my $loc = $c->param('q') || $c->stash('q');
    
    if ($cache && (my $json = $c->chi->get('location::' . $loc))) {
    	$c->app->log->info(sprintf "location %s cached", $loc);
    	$c->app->log->info(dump $json->{results}->[0]->{geometry}->{location} );
    	$c->render(json => $json->{results}->[0]->{geometry}->{location} );
    	return;
    }
    
    my $ua  = Mojo::UserAgent->new();
    my $url = Mojo::URL->new('https://maps.googleapis.com/maps/api/geocode/json');

    $url->query({ address => $loc, key => $geo_key });
    my $tx = $ua->get($url);
    $c->app->log->info("$url");
    $c->app->log->info(dump $tx->res->json);
    
    $c->chi->set('location::' . $loc, $tx->res->json);
    $c->render(json => $tx->res->json->{results}->[0]->{geometry}->{location} );
};

sub get_timezone {
    my $c = shift;

    my $timestamp = $c->param('time') || time();

    # user
    # location name
    # lat lon

    if ($cache && (my $json = $c->chi->get((join '::', 'latlng', $c->param('location'))))) {
    	$c->app->log->info(sprintf "timezone %s cached", $c->param('location'));
    	$c->app->log->info(dump $json);
    	$c->render(json => $json );
    	return;
    }
    
    my $ua  = Mojo::UserAgent->new();
    my $url = Mojo::URL->new('https://maps.googleapis.com/maps/api/timezone/json');
    $url->query({ location => $c->param('location'), timestamp => $timestamp, key => $tz_key });

    my $tx = $ua->get($url);
    $c->app->log->info($tz_key);
    $c->app->log->info(dump $tx->res->json);

    $c->chi->set((join '::', 'latlng', $c->param('location')), $tx->res->json);
    $c->render(json => $tx->res->json );
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
