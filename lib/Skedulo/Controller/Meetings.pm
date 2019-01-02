package Skedulo::Controller::Meetings;

use Mojo::Base 'Mojolicious::Controller';
use Skedulo::Util qw/pp_xml xml_to_hash/;
use Skedulo::DateTime;
use Data::Dump qw/dump/;

use POSIX qw/floor/;

sub mins_to_hour {
    my $m = shift;
    my $h = floor($m / 60);
    $m = $m % 60;
    return sprintf '%02d:%02d', $h, $m;
}

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
		$c->app->log->debug($tx->req->body);
		$c->app->log->debug($dom);
		
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

sub schedule_meeting {
    my $c = shift;

    $c->set_user();
    $c->set_dates();
    $c->params_to_stash(qw/subject location sensitivity body attendees[] categories[]/);

    my $tx = $c->get_ews('outlook/schedule_meeting');
    my $dom = $tx->res->dom;
    
    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		# $c->app->log->info($dom);
		$json = xml_to_hash($dom->at('ResponseCode'));
		return $c->render( json => { start => $c->stash('start'), end => $c->stash('end'), freebusy => $json } )
	    } else {
		$c->res->code(500);
		$json = { message => $dom->at('ResponseCode')->all_text };
		return $c->render( json => $json )
	    }
	}	    
    }
}

sub get_freebusy {
    my $c = shift;

    $c->set_dates();
    $c->set_user();

    if ($c->stash('format') =~/(^$)|(html$)/) { return $c->render(template => 'freebusy') }

    $c->stash('interval', 60) unless $c->stash('interval');
    
    my $tx = $c->get_ews('outlook/freebusy');

    my $req = $tx->req->body;
    my $dom = $tx->res->dom;

    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json;
	    if ($tx->res->is_success) {
		my $fb = xml_to_hash($dom->at('MergedFreeBusy'))->{content};
		my $wp = xml_to_hash($dom->at('WorkingPeriod'));

		$wp->{days} = [ (split /\s+/, delete $wp->{DayOfWeek}) ]; # =~ s/ /, /gr;
		$wp->{start} = mins_to_hour(delete $wp->{StartTimeInMinutes});
		$wp->{end} = mins_to_hour(delete $wp->{EndTimeInMinutes});

		return $c->render( json => {
					    start => $c->stash('start')->set_time_zone('Europe/Berlin'),
					    interval => $c->stash('interval'),
					    freebusy => $fb,
					    working_time => $wp
					   } )
	    } else {
		$c->res->code(500);
		$c->app->log->debug($req);
		my $json = { message => eval { $dom->at('ResponseCode')->all_text } || 'N/A', res => $dom, req => $req };
		return $c->render( json => $json )
	    }
	}	    
    }

};

1;

# get '/q' => { controller => 'Org', action => 'multi_tree' };
    
