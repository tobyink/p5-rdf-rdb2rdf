package Test::RDB2RDF::Suite;

use 5.010;
use strict;

use RDF::RDB2RDF;
use Test::More;
use Test::RDB2RDF::Manifest;
use Test::RDB2RDF::TestCase::R2RML;
use Test::RDB2RDF::TestCase::DirectMapping;

sub new
{
	my ($class, %args) = @_;
	bless { %args }, $class;
}

sub output :lvalue { $_[0]->{output} }

sub excuses
{
	my %excuses;

	$excuses{R2RMLTC0008b} =
	$excuses{R2RMLTC0009a} =
	$excuses{R2RMLTC0009b} =
	$excuses{R2RMLTC0014b} =
	$excuses{R2RMLTC0014c} =
		qq [RefObjectMap not fully implemented (yet).];

	$excuses{R2RMLTC0010c} =
		qq [I'll puzzle this one out later!];

	$excuses{R2RMLTC0016e} =
		qq [I'll puzzle this one out later!];
		
	$excuses{DirectGraphTC0017} =
		qq [I'll puzzle this one out later! (Evil Unicode one)];

	$excuses{DirectGraphTC0014} =
	$excuses{DirectGraphTC0022} =
	$excuses{DirectGraphTC0025} =
		qq [RDF-RDB2RDF prefers to skolemize where possible, so graphs don't match.];	

	return %excuses;
}

sub manifests
{
	sort
	map { s{^.+rdb2rdf-tests/}{}; $_ }
	<xt/rdb2rdf-tests/D*>;
}

sub blank_db
{
	my ($self, $num, $iri) = @_;
	
	my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:");
	$dbh->do('PRAGMA foreign_keys = ON;');
	return $dbh;
}

sub run_tap
{
	my $self  = shift;
	my $count = 0;
	
	my %excuses   = $self->excuses;
	my @manifests = $self->manifests;
	
	MANIFEST: foreach (@manifests)
	{	
		my $filename = sprintf('xt/rdb2rdf-tests/%s/manifest.ttl', $_);
		my $manifest = Test::RDB2RDF::Manifest->new($filename, $self);
		$manifest->output = $self->output;
		
		my %tests = $manifest->tests;
		TEST: foreach my $i (sort keys %tests)
		{
			SKIP: {
				my $test = $tests{$i}; $count++;
				
				skip sprintf("%s: %s", $test->identifier, $excuses{$test->identifier}), 1
					if exists $excuses{$test->identifier};
				
				ok($test->successful, $test->id_and_title);
			}
		}

		my %dtests = $manifest->tests('DirectMapping');
		TEST: foreach my $i (sort keys %dtests)
		{
			SKIP: {
				my $test = $dtests{$i}; $count++;
				
				skip sprintf("%s: %s", $test->identifier, $excuses{$test->identifier}), 1
					if exists $excuses{$test->identifier};
				
				ok($test->successful, $test->id_and_title);
			}
		}
	}
	
	return $count;
}

1