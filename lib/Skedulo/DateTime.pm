package Skedulo::DateTime;

sub DateTime::ews {
    return shift->set_time_zone('UTC')->strftime('%Y-%m-%dT%H:%M:%SZ');
}

sub DateTime::parse_sked {
    my ($class, $string, $tz, $on_error) = @_;

    my $date;

    for ($string) {
	# (ref $_ eq '') && do {
	#     $c->app->log->info("scalar");
	# };
	/^\d+$/ && do {
	    $date = DateTime->from_epoch(epoch => $_ / 1000);
	    last;
	};
	/^\d{4,4}\-\d{2,2}\-\d{2,2}$/ && do {
	    my $strp = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d', on_error => $on_error );
	    $date = $strp->parse_datetime($_);
	    last;
	};
	/^\d{4,4}\-\d{2,2}\-\d{2,2}T\d{2,2}:\d{2,2}/ && do {
	    s/:(\d{2,2})$/$1/;
	    my $strp = DateTime::Format::Strptime->new( pattern => '%Y-%m-%dT%H:%M:%S%z', on_error => $on_error );
	    $date = $strp->parse_datetime($_);
	    last;
	};
	/^today$|^now$/ && do {
	    $date = DateTime->$_( time_zone => $tz );
	    last;
	};
	/^[a-z]{3,3} [a-z]{3,3} \d{2,2} \d{4,4} \d{2,2}:\d{2,2}:\d{2,2}/i && do {
	    $date = DateTime::Format::JavaScript->new->parse_datetime($_);
	    last;
	};
	/^([+-])(\d+)$/ && do {
	    my ($sign, $days) = ($1, $2);
	    $date = DateTime->today( time_zone => $tz );
	    $date = $sign eq '-' ? $date->subtract(days => $days) : $date->add(days => $days);
	};
    }
    $date->set_time_zone('UTC')->set_formatter(DateTime::Format::Strptime->new(pattern => '%Y-%m-%dT%H:%M:%S%z'));
    return $date;
}


1;
