use File::Monitor;
use Data::Dump qw/dump/;
use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options
    (
     'watch.pl %o files_or_directories',
     [ 'kill|k=i', "kill process id" ],
     [ 'shell|s=s', "execute shell command" ],     
     [],
     [ 'verbose|v',  "print extra stuff"            ],
     [ 'help',       "print usage message and exit", { shortcircuit => 1 } ],
    );

print($usage->text), exit if $opt->help;

$\ = "\n"; $, = "\t";

my $monitor = File::Monitor->new();

if ($opt->kill) {
    for $file (@ARGV) {
	$monitor->watch({ name     => $file,
			  recurse  => 1,
			  callback => {
				       change => sub {
					   my ($name, $event, $change) = @_;
					   print STDERR $name, $event, $change->new_mtime;
					   my $kill = $opt->kill;
					   qx|kill -s HUP $kill|;
				   }
				      }
			});
    };
};

if ($opt->shell) {
    for $file (@ARGV) {
	$monitor->watch({ name     => $file,
			  recurse  => 1,
			  callback => {
				       change => sub {
					   my ($name, $event, $change) = @_;
					   print STDERR $name, $event, $change->new_mtime;
					   my $qx = $opt->shell =~ s/\{\}/$name/gr;
					   print STDERR $qx;
					   qx|$qx|;
				   }
				      }
			});
    };
};


while (1) {
    $monitor->scan;
    sleep 3;
}
