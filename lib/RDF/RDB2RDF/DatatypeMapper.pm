package RDF::RDB2RDF::DatatypeMapper; # this is a mixin

use 5.010;
use strict;

use Math::BigFloat;
use RDF::Trine qw[literal];
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];
use Scalar::Util qw[refaddr blessed];
use URI::Escape qw[uri_escape];

use namespace::clean;

our $VERSION = '0.006';

sub datatyped_literal
{
	my ($self, $value, $sql_datatype) = @_;

	given ($sql_datatype)
	{
		when (undef)
			{ return undef; }
		when (/^(?:bp)?char\((\d+)\)/i) # fixed width char strings.
			{ return literal(sprintf("%-$1s", "$value")); }
		when (/^(?:char|bpchar|varchar|string|text|note|memo)/i)
			{ return literal("$value"); }
		when (/^(?:int|smallint|bigint)/i)
			{ return literal("$value", undef, $XSD->integer->uri); }
		when (/^(?:decimal|numeric)/i)
			{ return literal("$value", undef, $XSD->decimal->uri); }
		when (/^(?:float|real|double)/i)
		{
			my ($m, $e) = map { "$_" } Math::BigFloat->new($value)->parts;
			while ($m >= 10.0) {
				$e++;
				$m /= 10.0;
			}
			$m = sprintf('%.8f', $m);
			$m =~ s/0+$//;
			$m =~ s/\.$/.0/;
			$m =~ s/^$/0.0/;
			return literal(sprintf('%sE%d', $m, $e), undef, $XSD->double->uri);
		}
		when (/^(?:binary|varbinary|blob|bytea)/i)
		{
			$value = uc unpack('H*' => $value);
			return literal($value, undef, $XSD->hexBinary->uri);
		}
		when (/^(?:bool)/i)
		{
			$value = ($value and $value !~ /^[nf0]/i) ? 'true' : 'false';
			return literal("$value", undef, $XSD->boolean->uri);
		}
		when (/^(?:timestamp|datetime)/i)
		{
			$value =~ s/ /T/;
			return literal("$value", undef, $XSD->dateTime->uri);
		}
		when (/^(?:date)/i)
			{ return literal("$value", undef, $XSD->date->uri); }
		when (/^(?:time)/i)
			{ return literal("$value", undef, $XSD->time->uri); }
		default
			{ return literal("$value", undef, $self->_dt_uri($sql_datatype)); }
	}		

	literal("$value");
}

sub _dt_uri
{
	my $self = shift;
	sprintf('tag:buzzword.org.uk,2011:rdb2rdf:datatype:%s', uri_escape($_[0]));
}

1;