package Skedulo::Controller::Meetings;

use Mojo::Base 'Mojolicious::Controller';
use Skedulo::Util qw/pp_xml xml_to_hash/;
use Data::Dump qw/dump/;

sub dates {
    my $c = shift;
    $c->set_dates()->set_user();

    $c->render(text => join ' ', $c->stash('start'), $c->stash('end'), $c->stash('user')); 
};

sub meetings_list {
    my $c = shift;

    $c->set_dates()->set_user();

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
		# $c->res->headers->cache_control('private, max-age=120');
		return $c->render( json => { meetings => $json } )
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text };
		return $c->render( json => $json )
	    }
	}	    
    }
}

sub calendar_item {
    my $c = shift;

    if ($c->stash('format') =~/(^$)|(html$)/) {
	return $c->render(template => 'calendar_item')
    }

    my $tx = $c->get_ews('outlook/item');
    my $dom = $tx->res->dom;
  
    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		$json = xml_to_hash($dom->at('CalendarItem'));
		# $c->res->headers->cache_control('private, max-age=120');
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text }
	    }
	    return $c->render( json => $json )
	}	    
    }
};

sub calendar_action {
    my $c = shift;

    $c->app->log->info(dump $c->req->params->to_hash);
    
    return $c->render(text => 'null') if $c->param('action') eq 'null';
    my $tx = $c->get_ews('outlook/accept_decline');

    my $dom = $tx->res->dom;
    return $c->render( text => $dom );

};

1;

# get '/q' => { controller => 'Org', action => 'multi_tree' };
    
