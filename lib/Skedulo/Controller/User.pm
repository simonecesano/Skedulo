package Skedulo::Controller::User;

use Mojo::Base 'Mojolicious::Controller';
use Skedulo::Util qw/pp_xml xml_to_hash/;
use Data::Dump qw/dump/;

sub setup_folder {
    my $c = shift;

    my $url = Mojo::URL->new($c->app->config->{ews});
    $url->userinfo(join ':', $c->session('user'), $c->session('password'));
    my $ua  = Mojo::UserAgent->new();

    # $c->app->log->info($url->userinfo);
    $c->app->log->info($c->cookie('user'));

    my $xml = $c->render_to_string(template => 'outlook/folder_search', format => "xml");
    my $tx = $ua->post($url => {'Content-Type' => 'text/xml', 'Accept-Encoding' => 'None' } => $xml);
    my $dom = $tx->res->dom;
    $c->app->log->info('setting up calendar');
    $c->app->log->info('$dom->at("FolderId")->attr("Id")');    
    $c->app->log->info($dom->at('FolderId')->attr('Id'));
    $c->session('calendar', $dom->at('FolderId')->attr('Id'));
    $c->app->log->info('calendar');
    $c->app->log->debug($c->session('calendar'));
    $c->render( json => xml_to_hash($dom) );
};

sub post_login {
    my $c = shift;

    if ($c->param('user') && $c->param('password')) {
	$c->stash('name', $c->param('user'));
	# $c->app->log->info($c->param('user'), $c->param('password'));

	my $tx = $c->get_ews('outlook/whois', $c->param('user'), $c->param('password'));

	my $dom = $tx->res->dom;

	# $c->app->log->info($dom);

	if ($tx->res->is_success) {
	    
	    my $json = xml_to_hash($dom->at('Contact'));
	    $c->session('email', $json->{Mailbox}->{EmailAddress});
	    $c->session('password', $c->param('password'));
	    $c->session('user', $c->param('user'));
	    $c->session('given_name', $json->{GivenName});	
	    $c->cookie('user' => $c->param('user'));
	    # app->log->info(dumper $c->req->params->to_hash);
	    
	    $c->redirect_to('/me');
	} else {
	    $c->app->log->info($c->res->message);
	    $c->flash('error', 'login error');
	    $c->flash('dom', $tx->res->dom);	    
	    $c->redirect_to('/error');
	}
	# return $c->render( json => xml_to_hash($dom->at('Contact')) );
    } else {
	$c->redirect_to('/login');
    }
};

1;
