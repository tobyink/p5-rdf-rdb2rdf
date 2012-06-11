package Test::RDB2RDF::Manifest;

use 5.010;
use strict;
use utf8;

use RDF::Trine;
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
	no warnings;
	open my($fh), sprintf('<:encoding(%s)', ($_[1] // 'UTF-8')), $_[0];
	local $/ = <$fh>;
}

sub new
{
	my ($class, $filename, $suite) = @_;	
	my $parser = RDF::Trine::Parser->new('Turtle');
	my $model  = RDF::Trine::Model->new;
	$parser->parse_file_into_model('http://tests.invalid/', $filename, $model);
	
	bless {
		filename => $filename,
		model    => $model,
		output   => undef,
		suite    => $suite,
	} => $class;
}

sub model    :lvalue { $_[0]->{model} }
sub suite    :lvalue { $_[0]->{suite} }
sub filename :lvalue { $_[0]->{filename} }
sub output   :lvalue { $_[0]->{output} }

sub relative_file
{
	my ($self, $name) = @_;
	$name = $name->literal_value if ref $name;
	my $return = $self->filename;
	$return =~ s/manifest\.ttl$/$name/;
	return $return;
}

sub databases
{
	my ($self) = @_;
	
	my $i = 0;
	unless ($self->{databases})
	{
		$self->{databases} = {};
			
		$self->model->subjects($RDF->type, $RTEST->DataBase)->each(sub
		{
			my ($iri)    = @_;
			my ($script) = $self->model->objects($iri, $RTEST->sqlScriptFile);
			my $encoding;
			$script = slurp($self->relative_file($script), $encoding);
			my @script = split /\;\s*$/m, $script;
			
			my $dbh = $self->suite->blank_db($i++, $iri->uri);
			foreach (@script)
			{
				$dbh->do($_);
			}
			$self->{databases}{$iri} = $dbh;
		});
	}
	
	return %{ $self->{databases} };
}

sub tests
{
	my ($self, $type) = @_;
	$type ||= 'R2RML';

	unless ($self->{tests}{$type})
	{
		$self->{tests}{$type} = {};
			
		$self->model->subjects($RDF->type, $RTEST->$type)->each(sub
		{
			my ($iri) = @_;
			my $class = 'Test::RDB2RDF::TestCase::'.$type;
			$self->{tests}{$type}{$iri} = $class->new($iri, $self);
		});
	}
	
	return %{ $self->{tests}{$type} };
}

1