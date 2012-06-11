package URI::Escape::Optimistic;

use strict;
use utf8;

use URI::Escape;
use base qw(Exporter);
our @EXPORT    = qw(uri_escape uri_unescape uri_escape_utf8 uri_escape_optimistic);
our $AUTHORITY = "cpan:TOBYINK";
our $VERSION   = "0.001";

sub uri_escape_optimistic
{
	my $text    = shift;
	my $pattern = '^A-Za-z0-9\\-\\._~\\x{80}-\\x{10FFFF}';
	
	@_ = ($text, $pattern) and goto \&uri_escape;
}

1;
