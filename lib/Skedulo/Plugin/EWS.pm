package Skedulo::Plugin::EWS;

use Mojo::Base 'Mojolicious::Plugin';
use Date::Parse;
use DateTime;
use Data::Dump qw/dump/;

sub register {
    my ($self, $app, $conf) = @_;

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
		     
		     for (qw/start end/) {
			 my $date;
			 
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
		     
		     for (@params) {
			 next if defined $c->stash($_);
			 s/\{\}$// && do {
			     $c->stash($_, $c->param($_) || {});
			     next;
			 };
			 s/\[\]$// && do {
			     $c->stash($_, $c->param($_) || []);
			     next;
			 };
			 $c->stash($_, $c->param($_) || '');
		     }
		     return $c;
		 });
}

1
