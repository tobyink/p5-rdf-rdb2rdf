package Test::RDB2RDF::TestCase::R2RML;

use 5.010;
use strict;
use utf8;
use base qw[ Test::RDB2RDF::TestCase ];

use RDF::Trine '0.135';
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];

my ($TEST, $RTEST, $DC);
BEGIN
{
	$TEST  = RDF::Trine::Namespace->new('http://www.w3.org/2006/03/test-description#');
	$RTEST = RDF::Trine::Namespace->new('http://purl.org/NET/rdb2rdf-test#');
	$DC    = RDF::Trine::Namespace->new('http://purl.org/dc/elements/1.1/');
}

sub slurp
{
	open my($fh), sprintf('<:encoding(%s)', ($_[1] // 'UTF-8')), $_[0];
	local $/ = <$fh>;
}

sub mapping
{
	my ($self) = @_;
	
	my ($r2rml) = $self->model->objects($self->iri, $RTEST->mappingDocument);
	$r2rml = slurp($self->manifest->relative_file($r2rml));	
	return RDF::RDB2RDF::R2RML->new($r2rml);
}

1
