package RDF::RDB2RDF::DatatypeMapper; # this is a mixin

use 5.010;
use common::sense;

use DBI;
use DBIx::Admin::TableInfo;
use RDF::Trine qw[literal];
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];
use Scalar::Util qw[refaddr blessed];
use URI::Escape qw[uri_escape];

our $VERSION = '0.006';

sub datatyped_literal
{
	my ($self, $value, $sql_datatype) = @_;

	given ($sql_datatype)
	{
		when (undef)
			{ return literal($value); }
		when (/^(char|varchar|string|text|note|memo)/i)
			{ return literal($value); }
		when (/^(int|smallint|bigint)/i)
			{ return literal($value, undef, $XSD->integer->uri); }
		when (/^(decimal|numeric)/i)
			{ return literal($value, undef, $XSD->decimal->uri); }
		when (/^(float|real|double)/i)
			{ return literal($value, undef, $XSD->float->uri); }
		when (/^(binary)/i)
		{
			$value    = MIME::Base64::encode_base64($value);
			return literal($value, undef, $XSD->base64Binary->uri);
		}
		when (/^(bool)/i)
		{
			$value = ($value and $value =~ /^[nf]/i) ? 'true' : 'false';
			return literal($value, undef, $XSD->boolean->uri);
		}
		when (/^(timestamp|datetime)/i)
		{
			$value =~ s/ /T/;
			return literal($value, undef, $XSD->dateTime->uri);
		}
		when (/^(date)/i)
			{ return literal($value, undef, $XSD->date->uri); }
		when (/^(time)/i)
			{ return literal($value, undef, $XSD->time->uri); }
		default
			{ return literal($value, undef, $self->_dt_uri($sql_datatype)); }
	}		

	literal($value);
}

sub _dt_uri
{
	sprintf('tag:buzzword.org.uk,2011:rdb2rdf:datatype:%s', uri_escape($_[0]));
}

1;