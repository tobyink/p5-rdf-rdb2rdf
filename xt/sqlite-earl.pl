use 5.010;
use lib "xt/lib";
use strict;
use RDF::Trine;
use Test::More;
use Test::RDB2RDF::Suite::SQLite;

my $suite = Test::RDB2RDF::Suite::SQLite->new;
my $earl  = $suite->run_earl;
my $ser   = RDF::Trine::Serializer->new(
	'Turtle',
	namespaces => {
		rdf        => q <http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
		rdfs       => q <http://www.w3.org/2000/01/rdf-schema#>,
		dcterms    => q <http://purl.org/dc/terms/>,
		earl       => q <http://www.w3.org/ns/earl#>,
		xsd        => q <http://www.w3.org/2001/XMLSchema#>,
		case       => q <http://www.w3.org/2001/sw/rdb2rdf/test-cases/>,
		doap       => q <http://usefulinc.com/ns/doap#>,
	},
);

print $ser->serialize_model_to_string($earl);
