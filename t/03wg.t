use Test::More;
use strict;

BEGIN { use_ok('RDF::RDB2RDF') };

my @manifests = qw(
	D000-1table0rows         
	D001-1table1row          
	D002-1table2columns1row  
	D003-1table3columns1row  
	D003-1table3columns1row  
	D004-1table2columnsprojection         
	D005-2duplicates0nulls                	
	D006-1table1primarykey1column1row     
	D007-1table1primarykey2columns1row    
	D008-1table1compositeprimarykey3columns1row
	D009-2tables1primarykey1foreingkey         
	D010-I18NnoSpecialChars                    
	D011-M2MRelations                          
	D012-2tables2duplicates0nulls
	D013-1table3columns2rows1nullvalue
	D014-3tablesExample               
	);
my $here = $0;
$here =~ s/03wg.t$//;
$here ||= '.';

my $output = sub
{
	diag($_[0]);
};

MANIFEST: foreach (@manifests)
{
	my $filename = sprintf('%s/rdb2rdf-tests/%s/manifest.ttl', $here, $_);
	my $manifest = Local::WGTest::Manifest->new($filename);
	$manifest->output = $output;
	
	my %tests = $manifest->tests;
	TEST: while (my ($i, $test) = each %tests)
	{
		SKIP: {
			skip "$1 not working yet", 1
				if $test->identifier =~ /^(R2RMLTC009|R2RMLTC014b)$/;

			ok($test->successful, $test->id_and_title);
		}
	}
}

done_testing();

#######################################################################

package Local::WGTest::Manifest;

use strict;
use File::Slurp qw[slurp];
use RDF::Trine;
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];
our ($TEST, $RTEST, $DC);
BEGIN
{
	$TEST  = RDF::Trine::Namespace->new('http://www.w3.org/2006/03/test-description#');
	$RTEST = RDF::Trine::Namespace->new('http://purl.org/NET/rdb2rdf-test#');
	$DC    = RDF::Trine::Namespace->new('http://purl.org/dc/elements/1.1/');
}

sub new
{
	my ($class, $filename) = @_;	
	my $parser = RDF::Trine::Parser->new('Turtle');
	my $model  = RDF::Trine::Model->new;
	$parser->parse_file_into_model('http://tests.invalid/', $filename, $model);
	
	bless {filename=>$filename, model=>$model, output=>undef};
}

sub model    :lvalue { $_[0]->{model} }
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
	
	unless ($self->{databases})
	{
		$self->{databases} = {};
			
		$self->model->subjects($RDF->type, $RTEST->DataBase)->each(sub
		{
			my ($iri)    = @_;
			my ($script) = $self->model->objects($iri, $RTEST->sqlScriptFile);
			$script = slurp($self->relative_file($script));
			my @script = split /\;\s*$/m, $script;
			
			my $filename = $iri->uri eq $ENV{KEEP_DATABASE} ? 'keep.db' : ':memory:';
			my $dbh = DBI->connect("dbi:SQLite:dbname=${filename}");
			$dbh->do($_) foreach @script;
			$self->{databases}{$iri} = $dbh;
		});
	}
	
	return %{ $self->{databases} };
}

sub tests
{
	my ($self, $type) = @_;
	$type ||= 'R2RML';

	unless ($self->{tests})
	{
		$self->{tests} = {};
			
		$self->model->subjects($RDF->type, $RTEST->$type)->each(sub
		{
			my ($iri) = @_;
			my $class = 'Local::WGTest::'.$type;
			$self->{tests}{$iri} = $class->new($iri, $self);
		});
	}
	
	return %{ $self->{tests} };
}

#######################################################################

package Local::WGTest::R2RML;

use strict;
use File::Slurp qw[slurp];
use RDF::Trine '0.135';
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];
our ($TEST, $RTEST, $DC);
BEGIN
{
	$TEST  = RDF::Trine::Namespace->new('http://www.w3.org/2006/03/test-description#');
	$RTEST = RDF::Trine::Namespace->new('http://purl.org/NET/rdb2rdf-test#');
	$DC    = RDF::Trine::Namespace->new('http://purl.org/dc/elements/1.1/');
}

sub new
{
	my ($class, $iri, $manifest) = @_;
	bless {iri=>$iri, manifest=>$manifest};
}

sub model    :lvalue { $_[0]->{manifest}->model }
sub iri      :lvalue { $_[0]->{iri} }
sub manifest :lvalue { $_[0]->{manifest} }

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

sub mapping
{
	my ($self) = @_;
	
	my ($r2rml) = $self->model->objects($self->iri, $RTEST->mappingDocument);
	$r2rml = slurp($self->manifest->relative_file($r2rml));	
	return RDF::RDB2RDF::R2RML->new($r2rml);
}

sub database
{
	my ($self) = @_;
	
	my ($dbiri) = $self->model->objects($self->iri, $RTEST->database);
	my %dbs     = $self->manifest->databases;
	my $dbh     = $dbs{ $dbiri };
}

sub actual_output
{
	my ($self) = @_;
	return $self->mapping->process( $self->database );
}

sub expected_output
{
	my ($self) = @_;
	my ($output) = $self->model->objects($self->iri, $RTEST->output);
	
	my $parser = RDF::Trine::Parser->new('NQuads');
	my $model  = RDF::Trine::Model->new;
	$parser->parse_file_into_model($self->iri->uri, $self->manifest->relative_file($output), $model);
	
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
		my $ser = RDF::Trine::Serializer->new('nquads');
		$self->manifest->output->($ser->serialize_model_to_string($actual->{model}));
		$self->manifest->output->("JSON mapping was:\n");
		$self->manifest->output->($self->mapping->to_json(pretty=>1, canonical=>1));
	}
	
	return $pass;
}

#######################################################################
