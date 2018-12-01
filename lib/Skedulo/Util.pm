package Skedulo::Util;

use Exporter 'import';

@EXPORT_OK = qw(pp_xml xml_to_hash);  # symbols to export on request

use Mojo::DOM;
use XML::LibXML::PrettyPrint;
use XML::LibXML;
use XML::Hash::XS;

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

1;
