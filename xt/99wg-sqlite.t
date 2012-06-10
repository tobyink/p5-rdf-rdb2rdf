use 5.010;
use lib "xt/lib";
use strict;
use Test::More;
use Test::RDB2RDF::Suite::SQLite;

my $suite = Test::RDB2RDF::Suite::SQLite->new(
	output   => sub { diag shift },
);
done_testing( $suite->run_tap );
