use 5.010;
use lib "xt/lib";
use strict;
use Test::More;
use Test::RDB2RDF::Suite::PostgreSQL;

my $suite = Test::RDB2RDF::Suite::PostgreSQL->new(
	output   => sub { diag shift },
	dsn      => 'dbi:Pg:dbname=test1',
	username => '',
	password => '',
);
done_testing( $suite->run_tap );
