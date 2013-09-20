package Test::RDB2RDF::Suite;

use 5.010;
use strict;
use utf8;

use DateTime;
use RDF::RDB2RDF;
use RDF::Trine qw(statement iri literal blank);
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
		[failed => qq [RefObjectMap not fully implemented (yet).]];

	$excuses{R2RMLTC0010c} =
		[failed => qq [Bug in RDF::Trine::Turtle::Parser], q<https://rt.cpan.org/Ticket/Display.html?id=77747>];
	
	$excuses{DirectGraphTC0014} =
	$excuses{DirectGraphTC0022} =
	$excuses{DirectGraphTC0025} =
		[cantTell => qq [RDF-RDB2RDF prefers to skolemize where possible, so graphs don't match (they have IRIs where blank nodes are expected).]];
	
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
	$dbh->{PrintWarn} = $dbh->{PrintError} = 0;
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
		
		foreach my $collection (qw< R2RML DirectMapping >)
		{
			my %tests = $manifest->tests($collection);
			TEST: foreach my $i (sort keys %tests)
			{
				SKIP: {
					my $test = $tests{$i}; $count++;
					
					skip sprintf("%s: %s", $test->identifier, $excuses{$test->identifier}[1]), 1
						if exists $excuses{$test->identifier};
					
					ok($test->successful, $test->id_and_title);
				}
			}
		}		
	}
	
	return $count;
}

sub run_earl
{
	my $self = shift;

	my %excuses   = $self->excuses;
	my @manifests = $self->manifests;

	my ($rdf, $rdfs, $dcterms, $earl, $xsd, $doap) =
		do {
			no warnings;
			map { RDF::Trine::Namespace->new($_) }
			qw[
				http://www.w3.org/1999/02/22-rdf-syntax-ns#
				http://www.w3.org/2000/01/rdf-schema#
				http://purl.org/dc/terms/
				http://www.w3.org/ns/earl#
				http://www.w3.org/2001/XMLSchema#
				http://usefulinc.com/ns/doap#
			]
		};
		
	my $model = shift || RDF::Trine::Model->new;
	my $st    = sub { $model->add_statement(statement(@_)) };
	my $date  = sub { literal(DateTime->now(time_zone=>'UTC')->iso8601.'Z', undef, $xsd->dateTime) };
	my $lib   = blank();
	my $me    = blank();
	my $txt;

	HARNESS_DESCRIPTION: {
		$st->($me, $rdf->type, $earl->Software);
		$st->($me, $doap->name, literal(ref($self)));
	}

	SOFTWARE_DESCRIPTION: {
		(my $version = RDF::RDB2RDF->VERSION) =~ s/\./-/g;
		my $db = blank();
		my ($database_engine) = (ref($self) =~ m/^Test::RDB2RDF::Suite::(.+)$/);
		$st->($lib, $rdf->type, $earl->Software);
		$st->($lib, $doap->description, literal("This resource is the aggregation of RDF-RDB2RDF with a relational database management system."));
		$st->($lib, $dcterms->hasPart, iri('http://purl.org/NET/cpan-uri/dist/RDF-RDB2RDF/v_'.$version));
		$st->($lib, $dcterms->hasPart, $db);
		$st->($db, $doap->name, literal($database_engine));
	}
	
	my $ASSERT = sub
	{
		my ($test, $assertion, $result) = @_;
		$st->($assertion, $rdf->type, $earl->Assertion);
		$st->($assertion, $earl->assertedBy, $me);
		$st->($assertion, $earl->subject, $lib);
		$st->($assertion, $earl->test, $test->iri);
		$st->($assertion, $earl->mode, $earl->automatic);
		$st->($assertion, $earl->result, $result);
	};
	
	my $PASS = sub
	{
		my $test      = shift;
		my $assertion = blank();
		my $result    = blank();
		$st->($result, $rdf->type, $earl->TestResult);
		$st->($result, $earl->outcome, $earl->passed);
		$st->($result, $dcterms->date, $date->());
		$ASSERT->($test, $assertion, $result);
	};

	my $FAIL = sub
	{
		my $test      = shift;
		my $assertion = blank();
		my $result    = blank();
		$st->($result, $rdf->type, $earl->TestResult);
		$st->($result, $earl->outcome, $earl->failed);
		$st->($result, $earl->info, literal($txt));
		$st->($result, $dcterms->date, $date->());
		$ASSERT->($test, $assertion, $result);
	};

	my $SKIP = sub
	{
		my $test      = shift;
		my $assertion = blank();
		my $result    = blank();
		my ($outcome, $explanation, $seeAlso) = @{$excuses{$test->identifier}};
		$st->($result, $rdf->type, $earl->TestResult);
		$st->($result, $earl->outcome, $earl->$outcome);
		$st->($result, $earl->info, literal($explanation));
		$st->($result, $rdfs->seeAlso, iri($seeAlso)) if $seeAlso;
		$st->($result, $dcterms->date, $date->());
		$ASSERT->($test, $assertion, $result);
	};
	
	my $DO_TEST = sub
	{
		my $test = shift;
		$txt = '';
		
		if (exists $excuses{$test->identifier})
			{ $SKIP->($test) }
		elsif ($test->successful)
			{ $PASS->($test) }
		else
			{ $FAIL->($test) }
	};

	MANIFEST: foreach (@manifests)
	{	
		my $manifest = Test::RDB2RDF::Manifest->new(
			sprintf('xt/rdb2rdf-tests/%s/manifest.ttl', $_),
			$self,
		);
		
		$manifest->output = sub { $txt .= shift };
		
		foreach my $collection (qw< R2RML DirectMapping >)
		{
			my %tests = $manifest->tests($collection);
			foreach my $id (sort keys %tests)
				{ $DO_TEST->($tests{$id}) }
		}
	}
	
	return $model;
}

1