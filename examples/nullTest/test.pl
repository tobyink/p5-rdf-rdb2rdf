#!/usr/bin/perl

use 5.010;
use lib "../../lib";
use RDF::Trine qw[iri statement literal variable];
use RDF::RDB2RDF::R2RML;

my $dbh    = DBI->connect("dbi:SQLite:dbname=nullTest.sqlite");
my $mapper = RDF::RDB2RDF->new('R2RML', <<'R2RML');

@prefix rr:    <http://www.w3.org/ns/r2rml#>.
@prefix rdfs:  <http://www.w3.org/2000/01/rdf-schema#>.
@prefix owl:   <http://www.w3.org/2002/07/owl#>.
@prefix skos:  <http://www.w3.org/2004/02/skos/core#>.

<#ObjectPropertyMap>
  rr:logicalTable [rr:tableName "CODES"];
  rr:subjectMap [rr:class owl:ObjectProperty; rr:column "ObjectProperty"];
  rr:predicateObjectMap [rr:predicate rdfs:subPropertyOf; rr:objectMap [rr:column "subPropertyOf"; rr:termType rr:IRI]];
  rr:predicateObjectMap [rr:predicate rdfs:label; rr:objectMap [rr:column "label"]].

<#ConceptMap>
  rr:logicalTable [rr:tableName "CODES"];
  rr:subjectMap [rr:class skos:Concept; rr:column "Concept"];
  rr:predicateObjectMap [rr:predicate skos:prefLabel; rr:objectMap [rr:column "label"]].

R2RML

print $mapper->process_turtle($dbh, no_r2rml => 1, no_json => 1);

