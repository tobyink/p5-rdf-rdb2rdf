use 5.008;
use strict;
use Test::More tests => 12;

BEGIN { use_ok( 'RDF::RDB2RDF::R2RML' ); }

use RDF::Trine qw[iri literal];

my $rdb2rdf = new_ok('RDF::RDB2RDF::R2RML' => [<<'TURTLE'], 'Mapping');
@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix owl:  <http://www.w3.org/2002/07/owl#> .
@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .
@prefix rr:   <http://www.w3.org/ns/r2rml#>.
@prefix exa:  <http://example.com/core#>.
@prefix dept: <http://example.com/dept#>.
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix bibo: <http://purl.org/ontology/bibo/> .
@prefix dc:   <http://purl.org/dc/terms/> .
@prefix skos: <http://www.w3.org/2004/02/skos/core#> .

[]
	a rr:TriplesMapClass;
	rr:tableName "books";

	rr:subjectMap [ rr:template "http://example.com/id/book/{book_id}";
	                rr:termtype "IRI";
	                rr:class bibo:Book; 
	                rr:graph exa:BookGraph ];

	rr:predicateObjectMap
	[ 
		rr:predicateMap [ rr:predicate rdfs:label ]; 
		rr:predicateMap [ rr:predicate dc:title ]; 
		rr:objectMap    [ rr:column "title"; rr:language "en" ]
	]
.

[]
	a rr:TriplesMapClass;
	
	rr:SQLQuery """
	
		SELECT *, forename||' '||surname AS fullname
		FROM authors
		
	""" ;

	rr:subjectMap [ rr:template "http://example.com/id/author/{author_id}";
	                rr:termtype "IRI";
	                rr:class foaf:Person; 
	                rr:graph exa:AuthorGraph ];

	rr:predicateObjectMap
	[ 
		rr:predicateMap [ rr:predicate foaf:givenName ]; 
		rr:objectMap    [ rr:column "forename" ]
	];

	rr:predicateObjectMap
	[ 
		rr:predicateMap [ rr:predicate foaf:familyName ]; 
		rr:objectMap    [ rr:column "surname" ]
	];

	rr:predicateObjectMap
	[ 
		rr:predicateMap [ rr:predicate foaf:name ] ; 
		rr:predicateMap [ rr:predicate rdfs:label  ]; 
		rr:objectMap    [ rr:column "fullname" ]
	]
.

[]
	a rr:TriplesMapClass;
	rr:tableName "topics";

	rr:subjectMap [ rr:template "http://example.com/id/topic/{topic_id}" ;
	                rr:class skos:Concept ; 
	                rr:graph exa:ConceptGraph ];

	rr:predicateObjectMap
	[
		rr:predicateMap [ rr:predicate rdfs:label ]; 
		rr:predicateMap [ rr:predicate skos:prefLabel ]; 
		rr:objectMap    [ rr:column "label"; rr:language "en" ]
	]
.

[]
	a rr:TriplesMapClass;
	rr:tableName "book_authors";

	rr:subjectMap [ rr:template "http://example.com/id/book/{book_id}" ;
	                rr:graph exa:BookGraph ];

	rr:predicateObjectMap
	[
		rr:predicateMap [ rr:predicate foaf:maker ]; 
		rr:predicateMap [ rr:predicate bibo:author ]; 
		rr:predicateMap [ rr:predicate dc:creator ]; 
		rr:objectMap    [ rr:template "http://example.com/id/author/{author_id}"; rr:termtype "IRI" ]
	]
.

[]
	a rr:TriplesMapClass;
	rr:tableName "book_authors";

	rr:subjectMap [ rr:template "http://example.com/id/author/{author_id}" ;
	                rr:graph exa:BookGraph ];

	rr:predicateObjectMap
	[
		rr:predicateMap [ rr:predicate foaf:made ]; 
		rr:objectMap    [ rr:template "http://example.com/id/book/{book_id}"; rr:termtype "IRI" ]
	]
.

[]
	a rr:TriplesMapClass;
	rr:tableName "book_topics";

	rr:subjectMap [ rr:template "http://example.com/id/book/{book_id}" ;
	                rr:graph exa:BookGraph ];

	rr:predicateObjectMap
	[
		rr:predicateMap [ rr:predicate dc:subject ]; 
		rr:objectMap    [ rr:template "http://example.com/id/topic/{topic_id}"; rr:termtype "IRI" ]
	]
.


TURTLE

can_ok($rdb2rdf, 'process');
can_ok($rdb2rdf, 'process_turtle');
can_ok($rdb2rdf, 'to_json');
can_ok($rdb2rdf, 'to_hashref');

my %ns = $rdb2rdf->namespaces;
is($ns{dc}->FOO->uri, 'http://purl.org/dc/terms/FOO', 'namespaces look right');

my $mappings = $rdb2rdf->mappings;
is($mappings->{books}{about}, "http://example.com/id/book/{book_id}", 'mapping looks right');

my $dbh   = DBI->connect("dbi:SQLite:dbname=t/library.sqlite");
my $model = $rdb2rdf->process($dbh);

isa_ok($model, 'RDF::Trine::Model', 'Output');

is($model->count_statements(
		iri('http://example.com/id/book/3'),
		iri('http://purl.org/dc/terms/title'),
		literal('Zen and the Art of Motorcycle Maintenance: An Inquiry into Values', 'en'),
		), 1,
	'Simple literal triple output.'
	);

is($model->count_statements(
		iri('http://example.com/id/book/3'),
		iri('http://purl.org/dc/terms/creator'),
		iri('http://example.com/id/author/2'),
		), 1,
	'Simple non-literal triple output.'
	);

is($model->count_statements(
		iri('http://example.com/id/author/2'),
		iri('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'),
		iri('http://xmlns.com/foaf/0.1/Person'),
		), 1,
	'Simple class triple output.'
	);

# print $rdb2rdf->process_turtle($dbh);