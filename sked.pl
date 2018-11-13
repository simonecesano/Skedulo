#!/usr/bin/env perl
use Mojolicious::Lite;
use XML::LibXML::PrettyPrint;
use XML::LibXML;
use XML::XML2JSON;
use XML::Hash::XS;
use XML::Hash;

use Mojo::Util qw/dumper/;

plugin 'Config';

hook (before_dispatch => sub {
	  my $c = shift;
	  $c->session('user', $ENV{EWS_USER})        ; # unless $c->session('user');
	  $c->session('password', $ENV{EWS_PASSWORD}); # unless $c->session('password');
	  $c;
      });

get '/setup/:folder' => sub {
    my $c = shift;

    my $url = Mojo::URL->new(app->config->{ews});
    $url->userinfo(join ':', $c->session('user'), $c->session('password'));
    my $ua  = Mojo::UserAgent->new();

    my $xml = $c->render_to_string(template => 'outlook/outin', format => "xml");
    my $tx = $ua->post($url => {'Content-Type' => 'text/xml', 'Accept-Encoding' => 'None' } => $xml);
    my $dom = $tx->res->dom;

    app->log->info($dom->at('FolderId')->attr('Id'));
    $c->session('calendar', $dom->at('FolderId')->attr('Id'));
    app->log->info($c->session('calendar'));
    $c->render( json => xml_to_hash($dom) );
};


helper 'get_ews' => sub {
    my $c = shift;
    my $template = shift;
    my $url = Mojo::URL->new(app->config->{ews});
    $url->userinfo(join ':', $c->session('user'), $c->session('password'));

    my $ua  = Mojo::UserAgent->new();
    
    my $xml = $c->render_to_string(template => $template, format => "xml");
    my $tx = $ua->post($url => {'Content-Type' => 'text/xml', 'Accept-Encoding' => 'None' } => $xml);

    return $tx;
};

    
get '/meet/me/:start/:end' => sub {
    my $c = shift;

    if ($c->stash('format') =~/(^$)|(html$)/) {
	return $c->render(template => 'meeting_list')
    }

    # $c->session('calendar', 'AAMkADFjYjZkZGU0LWNmNmItNGQ4Zi05MTYwLTdiYmI2MjEzYmFhYwAuAAAAAAD6rjBKU2HOQIPedGnOV9WZAQAyz/enT3JNSZihjENeCkrFAAAAIQIOAAA=');
    # $c->stash('calendar', 'AAMkADFjYjZkZGU0LWNmNmItNGQ4Zi05MTYwLTdiYmI2MjEzYmFhYwAuAAAAAAD6rjBKU2HOQIPedGnOV9WZAQAyz/enT3JNSZihjENeCkrFAAAAIQIOAAA=');
    
    my $tx = $c->get_ews('outlook/meetings');
    my $dom = $tx->res->dom;

    # app->log->info($dom);
    # app->log->info($c->session('calendar'));

    
    for ($c->stash('format')) {
	/xml/i && do {
	    return $c->render( text => pp_xml($dom) )
	};
	/json/i && do {
	    my $json = xml_to_hash($dom->find('CalendarItem'));
	    return $c->render( json => { meetings => $json } )
	}	    
    }
};

get '/item/*id' => sub {
    my $c = shift;

    my $tx = $c->get_ews('outlook/item');
    my $dom = $tx->res->dom;
    
    my $json = xml_to_hash($dom->at('CalendarItem'));
    return $c->render( json => $json )
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
	for ($dom) { s/<\w+?:/</g; s/<\/\w+?:/<\//g }
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

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
