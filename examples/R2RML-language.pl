#!/usr/bin/perl

use 5.010;
use lib "../lib";
use RDF::Trine qw[iri statement literal variable];
use RDF::RDB2RDF::R2RML;

my $dbh    = DBI->connect("dbi:SQLite:dbname=../t/library.sqlite");
my $mapper = RDF::RDB2RDF->new('R2RML', <<'R2RML');

@base         <http://id.example.net/>.
@prefix rr:   <http://www.w3.org/ns/r2rml#>.
@prefix rrx:  <http://purl.org/r2rml-ext/>.
@prefix bibo: <http://purl.org/ontology/bibo/>.
@prefix dc:   <http://purl.org/dc/elements/1.1/>.

[] rr:logicalTable [rr:tableName "books"];
  rr:subjectMap [rr:class bibo:Book; rr:template "book/{book_id}"];
  rr:predicateObjectMap [
    rr:predicate dc:title;
    rr:objectMap [
      rr:column "title";
      rrx:languageColumn "title_lang";
      rr:language "en"  # default
   ]].

R2RML

print $mapper->process_turtle($dbh);

