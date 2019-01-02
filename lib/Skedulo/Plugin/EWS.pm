package Skedulo::Plugin::EWS;

use Mojo::Base 'Mojolicious::Plugin';
use Date::Parse;
use DateTime;
use DateTime::Format::ISO8601;
use Data::Dump qw/dump/;
use DateTime::Format::Strptime;

sub register {
    my ($self, $app, $conf) = @_;
    my $strp = DateTime::Format::Strptime->new(
					       pattern => '%Y-%m-%dT%H:%M:%S%z',
					       on_error => sub { my ($o, $e) = @_; $app->log->info("Error parsing date: " . $e ) }
					      );

    $app->helper('get_ews' => sub {
		     my $c = shift;
		     my $template = shift;
		     my ($user, $password) = @_;
		     my $url = Mojo::URL->new($c->app->config->{ews});
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
			 $c->app->log->info($tx->res->code);
		     }
		     return $tx;

		 });

    $app->helper('set_dates' => sub {
		     my $c = shift;
		     my $start;
		     my ($tz) = map { $_->value } grep { $_->name eq 'TZName' } @{$c->req->cookies};
		     $tz ||= 'UTC';
		     
		     $c->app->log->info('#' x 120);
		     $c->app->log->info($c->req->url);
		     $c->app->log->info($tz);

		     for (qw/start end/) {
			 my $date;
			 $c->app->log->info(join ': ', $_, $c->stash($_));
			 
			 if ($c->stash($_) =~ /^(\+|\-)(\d+)(.*)/) {
			     my ($sign, $qty, $what) = ($1, $2, $3);
				 $what ||= 'days';
			     if ($sign eq '+') {
				 $date = ($start || DateTime->today(time_zone => $tz))->add( $what => $qty)
			     } else {
				 $date = ($start || DateTime->today(time_zone => $tz))->subtract( $what => $qty)
			     }
			 } elsif ($c->stash($_) =~ /today|now/) {
			     my $f = $c->stash($_);
			     $date = DateTime->$f(time_zone => $tz);
			     # $date->set_time_zone( $tz );
			 } else {
			     # might be better 
			     
			     # my $strp = DateTime::Format::Strptime->new( pattern => '%Y-%m-%dT%H:%M:%S%z' );
			     $c->app->log->info(join ': ', $_, $c->stash($_));
			     $date = $strp->parse_datetime($c->stash($_));
			     $c->app->log->info($date or $@);
			     $date->set_time_zone( $tz );
			 }
			 # my $iso8601 = DateTime::Format::ISO8601->new;
			 # $date->set_formatter($iso8601);
			 # my $strp = DateTime::Format::Strptime->new( pattern   => '%Y-%m-%dT%H:%M:%S%z' );
			 $date->set_formatter($strp);
			 # $date = $strp->format_datetime($date);
			 $c->app->log->info('-' x 120);
			 
			 $c->app->log->info(join ': ', $_, $date);
			 
			 $c->stash($_, $date)
		     }
		     return $c;
		 });

    $app->helper('set_user' => sub {
		     my $c = shift;
		     $c->stash('user', $c->session('user')) if $c->stash('who') eq 'me';
		     $c->stash('who', $c->session('user')) if $c->stash('who') eq 'me';
		     return $c;
		 });
    $app->helper('params_to_stash' => sub {
		     my $c = shift;
		     my @params = @_;
		     # $c->app->log->info(dump \@_);
		     for (@params) {
			 $c->app->log->info("processing $_");
			 (defined $c->stash($_)) && do {
			     $c->app->log->info("$_ is defined");
			 };
			 s/\{\}$// && do {
			     $c->app->log->info($_);
			     $c->app->log->info('hash');			     
			     $c->stash($_, $c->req->param($_ . '{}') || {});
			     next;
			 };
			 s/\[\]$// && do {
			     $c->app->log->info($_);
			     $c->app->log->info('array');
			     $c->stash($_,
				       ref $c->param($_ . '[]') eq 'ARRAY'
				       ? $c->param($_ . '[]')
				       : [ $c->param($_ . '[]') ]);
			     next;
			 };
			 /^json$/i && do {
			     # parse as json
			 };
			 $c->stash($_, $c->param($_) || '');
		     }
		     $c->app->log->info(dump $c->stash('categories'));
		     $c->app->log->info('-' x 80);		     
		     return $c;
		 });
}

1
