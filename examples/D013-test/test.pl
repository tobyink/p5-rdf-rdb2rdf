#!/usr/bin/perl

use 5.010;

# copied from xt\rdb2rdf-tests\D013-1table1primarykey3columns2rows1nullvalue

use lib "../../lib"; # use patched version
# Without this line, also outputs this triple, which it MUST NOT
# <http://example.com/Person/1/Alice-> ex:BirthDay "" .

use RDF::RDB2RDF::R2RML;

my $dbh    = DBI->connect("dbi:SQLite:dbname=db.sqlite");
my $mapper = RDF::RDB2RDF->new('R2RML', <<'R2RML');

@base <http://mappingpedia.org/rdb2rdf/r2rml/tc/> .
@prefix rr: <http://www.w3.org/ns/r2rml#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix ex: <http://example.com/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<TriplesMap1>
  a rr:TriplesMap;
  rr:logicalTable [ rr:tableName "\"Person\"" ];
  rr:subjectMap [ rr:template "http://example.com/Person/{\"ID\"}/{\"Name\"}-{\"DateOfBirth\"}";  ];
  rr:predicateObjectMap [ 
      rr:predicate		ex:BirthDay ;
      rr:objectMap		[ rr:column "\"DateOfBirth\"" ]
    ] .
R2RML

print $mapper->process_turtle ($dbh, (no_r2rml => 1, no_json => 1));
