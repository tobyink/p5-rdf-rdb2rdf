package Test::RDB2RDF::TestCase;

use 5.010;
use strict;

use JSON qw[to_json];
use RDF::Trine '0.135';
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];

our ($TEST, $RTEST, $DC);
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

sub new
{
	my ($class, $iri, $manifest) = @_;
	bless { iri => $iri, manifest => $manifest }, $class;
}

sub model    :lvalue { $_[0]->{manifest}->model }
sub iri      :lvalue { $_[0]->{iri} }
sub manifest :lvalue { $_[0]->{manifest} }
sub mapping          { die; }

sub identifier
{
	my ($self) = @_;
	my ($identifier) = $self->model->objects($self->iri, $DC->identifier);	
	return undef unless $identifier;
	return $identifier->literal_value;
}

sub title
{
	my ($self) = @_;
	my ($identifier) = $self->model->objects($self->iri, $DC->title);
	return undef unless $identifier;
	return $identifier->literal_value;
}

sub id_and_title
{
	my ($self) = @_;
	return sprintf('%s: %s', $self->identifier, $self->title);
}

sub database
{
	my ($self) = @_;
	
	my ($dbiri) = $self->model->objects($self->iri, $RTEST->database);
	my %dbs     = $self->manifest->databases;
	my $dbh     = $dbs{ $dbiri };
	
	return $dbh;
}

sub actual_output
{
	my ($self) = @_;
	return $self->mapping->process(
		$self->database
	);
}

sub expected_output
{
	my ($self) = @_;
	my ($output) = $self->model->objects($self->iri, $RTEST->output);
	my $filename = $self->manifest->relative_file($output);
	
	my $parser = RDF::Trine::Parser->new($filename =~ /\.nq$/ ? 'NQuads' : 'Turtle');
	my $model  = RDF::Trine::Model->new;
	$parser->parse_file_into_model($self->iri->uri, $filename, $model);
	
	return $model;
}

sub successful
{
	my ($self) = @_;

	my $actual   = RDF::Trine::Graph->new( $self->actual_output );
	my $expected = RDF::Trine::Graph->new( $self->expected_output );
	
	my $pass = $expected->is_subgraph_of($actual);
	
	if (defined $self->manifest->output and !$pass)
	{
		$self->manifest->output->(sprintf("Failed '%s'. Actual graph was:\n", $self->identifier));
		my $ser = RDF::Trine::Serializer->new('rdfjson');
		$self->manifest->output->($ser->serialize_model_to_string($actual->{model}));
		if ($self->mapping->can('to_json'))
		{
			$self->manifest->output->("JSON mapping was:\n");
			$self->manifest->output->($self->mapping->to_json(pretty=>1, canonical=>1));
		}
		if ($self->mapping->can('layout'))
		{
			$self->manifest->output->("Database layout was:\n");
			my $dbh = $self->database;
			$self->manifest->output->(
				to_json(
					$self->mapping->layout(ref($dbh) eq 'ARRAY' ? @$dbh : $dbh),
					{pretty=>1, canonical=>1},
				),
			);
		}
	}
	
	return $pass;
}

1