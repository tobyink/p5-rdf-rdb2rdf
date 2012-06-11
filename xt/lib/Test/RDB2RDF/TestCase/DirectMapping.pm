package Test::RDB2RDF::TestCase::DirectMapping;

use 5.010;
use strict;
use base qw[ Test::RDB2RDF::TestCase ];
use utf8;

use RDF::Trine '0.135';
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];

my ($TEST, $RTEST, $DC);
BEGIN
{
	$TEST  = RDF::Trine::Namespace->new('http://www.w3.org/2006/03/test-description#');
	$RTEST = RDF::Trine::Namespace->new('http://purl.org/NET/rdb2rdf-test#');
	$DC    = RDF::Trine::Namespace->new('http://purl.org/dc/elements/1.1/');
}

sub mapping
{
	return RDF::RDB2RDF::DirectMapping->new(
		prefix   => 'http://example.com/base/',
		#rdfs     => 1,
		#warn_sql => 1,
	);
}

sub expected_output
{
	my ($self) = @_;
	my ($output) = $self->model->objects($self->iri, $RTEST->output);
	my $filename = $self->manifest->relative_file($output);
	
	my $parser = RDF::Trine::Parser->new($filename =~ /\.nq$/ ? 'NQuads' : 'Turtle');
	my $model  = RDF::Trine::Model->new;
	$parser->parse_file_into_model('http://example.com/base/', $filename, $model);
	
	return $model;
}

sub database
{
	my ($self) = @_;
	my $dbh = $self->SUPER::database;
	return [ $dbh, 'public' ]
		if $self->manifest->suite->isa('Test::RDB2RDF::Suite::PostgreSQL');
	return $dbh;
}

1