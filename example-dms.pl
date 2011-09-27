#!/usr/bin/perl

use 5.010;
use lib "lib";
use RDF::Trine qw[iri statement literal];
use RDF::RDB2RDF::DirectMapping;
use RDF::RDB2RDF::DirectMapping::Store;
use RDF::TrineShortcuts;

my $dbh    = DBI->connect('dbi:Pg:dbname=mytest3');
my $mapper = RDF::RDB2RDF->new('DirectMapping', prefix=>'http://id.example.net/', rdfs=>1);
my $store  = RDF::RDB2RDF::DirectMapping::Store->new([$dbh, 'public'], $mapper);

sub sayit
{
	say $_[0]->as_string;
}

$store->get_statements(
	iri('http://id.example.net/contacts/contact_id-3'),
	iri('http://id.example.net/contacts#forename'),
	literal('Jill'),
	)->each(\&sayit);
print "----\n";

$store->get_statements(
	iri('http://id.example.net/contacts'),
	undef,
	undef,
	)->each(\&sayit);
print "----\n";

$store->get_statements(
	iri('http://id.example.net/contacts#contact_id'),
	undef,
	undef,
	)->each(\&sayit);
print "----\n";