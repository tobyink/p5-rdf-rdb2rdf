package RDF::RDB2RDF::DirectMapping;

use 5.008;
use common::sense;

use DBI;
use DBIx::Admin::TableInfo;
use MIME::Base64 qw[];
use RDF::Trine qw[iri blank literal statement];
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];
use Scalar::Util qw[refaddr blessed];
use URI::Escape qw[];

use base qw[RDF::RDB2RDF];

our $VERSION = '0.003';

sub new
{
	my ($class, %args) = @_;
	$args{prefix} = '' unless defined $args{prefix};
	bless {%args}, $class;
}

sub uri_escape
{
	my $str = URI::Escape::uri_escape(@_);
	$str =~ s/\%20/+/g;
	return $str;
}

sub prefix :lvalue { $_[0]->{prefix} }
sub rdfs   :lvalue { $_[0]->{rdfs} }

sub layout
{
	my ($self, $dbh, $schema) = @_;

	unless ($self->{layout}{refaddr($dbh).'|'.$schema})
	{
		my $rv     = {};
		my $info   = DBIx::Admin::TableInfo->new(dbh => $dbh, schema => $schema)->info;	
		
		foreach my $table (keys %$info)
		{
			$rv->{$table}{columns} ||= [];
			$rv->{$table}{keys}    ||= {};
			$rv->{$table}{refs}    ||= {};
			
			foreach my $column (sort {$a->{ORDINAL_POSITION} <=> $b->{ORDINAL_POSITION}} values %{ $info->{$table}{columns} })
			{
				push @{ $rv->{$table}{columns} }, {
					column => $column->{COLUMN_NAME},
					type   => $column->{TYPE_NAME},
					order  => $column->{ORDINAL_POSITION}
					};
			}
			foreach my $p (sort {$a->{KEY_SEQ} <=> $b->{KEY_SEQ}} values %{ $info->{$table}{primary_keys} })
			{
				push @{ $rv->{$table}{keys}{ $p->{PK_NAME} }{columns} }, $p->{COLUMN_NAME};
				$rv->{$table}{keys}{ $p->{PK_NAME} }{primary} = 1;
			}
			
			# DBIx::Admin::TableInfo's foreign key info is pretty useless.
			my $sth = $dbh->foreign_key_info(undef, $schema, undef, undef, $schema, $table);
			if ($sth)
			{
				my @r;
				while (my $result = $sth->fetchrow_hashref)
				{
					push @r, $result;
				}
				@r = sort { $a->{ORDINAL_POSITION} <=> $b->{ORDINAL_POSITION} } @r;
				foreach my $f (@r)
				{
					push @{ $rv->{$table}{refs}{ $f->{FK_NAME} }{columns} }, $f->{FK_COLUMN_NAME};
					push @{ $rv->{$table}{refs}{ $f->{FK_NAME} }{target_columns} }, $f->{UK_COLUMN_NAME};
					$rv->{$table}{refs}{ $f->{FK_NAME} }{target_table} = $f->{UK_TABLE_NAME};
				}
			}
			
			my $sth = $dbh->statistics_info(undef, $schema, $table, 1, 0);
			if ($sth)
			{
				my @r;
				while (my $result = $sth->fetchrow_hashref)
				{
					next if $result->{FILTER_CONDITION};
					next if $result->{NON_UNIQUE};
					next if $rv->{$table}{keys}{ $result->{INDEX_NAME} };
					push @r, $result;
				}
				@r = sort { $a->{ORDINAL_POSITION} <=> $b->{ORDINAL_POSITION} } @r;
				foreach my $f (@r)
				{
					push @{ $rv->{$table}{keys}{ $f->{INDEX_NAME} }{columns} }, $f->{COLUMN_NAME};
				}
			}
		}

		$self->{layout}{refaddr($dbh).'|'.$schema} = $rv;
	}

	$self->{layout}{refaddr($dbh).'|'.$schema};
}

sub process
{
	my ($self, $dbh, $model) = @_;
	
	$model = RDF::Trine::Model->temporary_model unless defined $model;
	my $callback = (ref $model eq 'CODE')?$model:sub{$model->add_statement(@_)};	
	my $schema;
	($dbh, $schema) = ref($dbh) eq 'ARRAY' ? @$dbh : ($dbh, undef);

	my $layout = $self->layout($dbh, $schema);
	foreach my $table (keys %$layout)
	{
		$self->handle_table([$dbh, $schema], $callback, $table);
	}
	
	return $model;
}

sub handle_table
{
	my ($self, $dbh, $model, $table, $where) = @_;
	
	$model = RDF::Trine::Model->temporary_model unless defined $model;
	my $callback = (ref $model eq 'CODE')?$model:sub{$model->add_statement(@_)};		
	my $schema;
	($dbh, $schema) = ref($dbh) eq 'ARRAY' ? @$dbh : ($dbh, undef);
	
	my $layout = $self->layout($dbh, $schema);
	
	$self->handle_table_rdfs([$dbh, $schema], $callback, $table)
		unless $where;
	
	my $sql = $schema
		? sprintf('SELECT * FROM "%s"."%s"', $schema, $table)
		: sprintf('SELECT * FROM "%s"', $table);
	
	my @values;
	if ($where)
	{
		my @w;
		while (my ($k,$v) = each %$where)
		{
			push @w, sprintf('%s = ?', $k);
			push @values, $v;
		}
		$sql .= ' WHERE ' . (join ' AND ', @w);
	}
	my $sth = $dbh->prepare($sql);
	$sth->execute(@values);
		
	while (my $row = $sth->fetchrow_hashref)
	{
		my ($pkey_uri) =
			map  { $self->make_key_uri($table, $_->{columns}, $row); }
			grep { $_->{primary}; }
			values %{ $layout->{$table}{keys} };
		my @key_uris =
			map  { $self->make_key_uri($table, $_->{columns}, $row); }
			grep { !$_->{primary}; }
			values %{ $layout->{$table}{keys} };
		
		my $subject = $pkey_uri ? iri($pkey_uri) : blank();
		
		# rdf:type
		$callback->(statement($subject, $RDF->type, iri($self->prefix.$table)));
		
		# owl:sameAs
		$callback->(statement($subject, $OWL->sameAs, iri($_)))
			foreach @key_uris;
		
		# p-o for columns
		foreach my $column (@{ $layout->{$table}{columns} })
		{
			next unless defined $row->{ $column->{column} };
			
			my $predicate = iri($self->prefix.$table.'#'.$column->{column});
			my $value     = $row->{ $column->{column} };
			my $datatype;
			
			if ($column->{type} =~ /^(int|smallint|bigint)/i)
			{
				$datatype = $XSD->integer;
			}
			elsif ($column->{type} =~ /^(decimal|numeric)/i)
			{
				$datatype = $XSD->decimal;
			}
			elsif ($column->{type} =~ /^(float|real|double)/i)
			{
				$datatype = $XSD->float;
			}
			elsif ($column->{type} =~ /^(binary)/i)
			{
				$datatype = $XSD->base64Binary;
				$value    = MIME::Base64::encode_base64($value);
			}
			# need to handle BOOLEAN, DATE, TIME and TIMESTAMP.
			
			my $object = literal($value, undef, $datatype);
			$callback->(statement($subject, $predicate, $object));
		}
		
		# foreign keys
		foreach my $ref (values %{ $layout->{$table}{refs} })
		{
			my $predicate = iri($self->make_ref_uri($table, $ref));
			my $object    = iri($self->make_ref_dest_uri($table, $ref, $row));
			$callback->(statement($subject, $predicate, $object));
		}
	}
}

sub handle_table_rdfs
{
	my ($self, $dbh, $model, $table) = @_;
	
	$model = RDF::Trine::Model->temporary_model unless defined $model;
	my $callback = (ref $model eq 'CODE')?$model:sub{$model->add_statement(@_)};		
	my $schema;
	($dbh, $schema) = ref($dbh) eq 'ARRAY' ? @$dbh : ($dbh, undef);

	my $layout = $self->layout($dbh, $schema);

	if ($self->rdfs)
	{
		$callback->(statement(iri($self->prefix.$table), $RDF->type, $OWL->Class));
		$callback->(statement(iri($self->prefix.$table), $RDFS->label, literal($table)));

		foreach my $column (@{ $layout->{$table}{columns} })
		{
			my $predicate = iri($self->prefix.$table.'#'.$column->{column});
			my $datatype;
			if ($column->{type} =~ /^(int|smallint|bigint)/i)
			{
				$datatype = $XSD->integer;
			}
			elsif ($column->{type} =~ /^(decimal|numeric)/i)
			{
				$datatype = $XSD->decimal;
			}
			elsif ($column->{type} =~ /^(float|real|double)/i)
			{
				$datatype = $XSD->float;
			}
			elsif ($column->{type} =~ /^(binary)/i)
			{
				$datatype = $XSD->base64Binary;
			}
			$callback->(statement($predicate, $RDF->type, $OWL->DatatypeProperty));
			$callback->(statement($predicate, $RDFS->label, literal($column->{column})));
			$callback->(statement($predicate, $RDFS->domain, iri($self->prefix.$table)));
			$callback->(statement($predicate, $RDFS->range, $datatype)) if $datatype;
		}
		
		foreach my $ref (values %{ $layout->{$table}{refs} })
		{
			my $predicate = iri($self->make_ref_uri($table, $ref));
			$callback->(statement($predicate, $RDF->type, $OWL->ObjectProperty));
			$callback->(statement($predicate, $RDFS->domain, iri($self->prefix.$table)));
			$callback->(statement($predicate, $RDFS->range, iri($self->prefix.$ref->{target_table})));
		}
	}
}

sub process_turtle
{
	my ($self, @args) = @_;
	return $self->SUPER::process_turtle(@args, base_uri=>$self->prefix);
}

sub make_ref_uri
{
	my ($self, $table, $ref) = @_;
	
	return $self->prefix .
		$table . "#ref-" .
		(join '.', map
			{ uri_escape($_); }
			@{$ref->{columns}});
}

sub make_ref_dest_uri
{
	my ($self, $table, $ref, $data) = @_;
	
	my $map;
	for (my $i = 0; exists $ref->{columns}[$i]; $i++)
	{
		$map->{ $ref->{target_columns}[$i] } = $ref->{columns}[$i];
	}
	
	return $self->prefix .
		$ref->{target_table} . "/" .
		(join '.', map
			{ sprintf('%s-%s', uri_escape($_), uri_escape($data->{$map->{$_}})); }
			@{$ref->{target_columns}});
}

sub make_key_uri
{
	my ($self, $table, $columns, $data) = @_;
	
	return $self->prefix .
		$table . "/" .
		(join '.', map
			{ sprintf('%s-%s', uri_escape($_), uri_escape($data->{$_})); }
			@$columns);
}

1;

=head1 NAME

RDF::RDB2RDF::DirectMapping - map relational database to RDF directly

=head1 SYNOPSIS

 my $mapper = RDF::RDB2RDF->new('DirectMapping',
   prefix => 'http://example.net/data/');
 print $mapper->process_turtle($dbh);

=head1 DESCRIPTION

This module makes it stupidly easy to dump a relational SQL database as
an RDF graph, but at the cost of flexibility. Other than providing a base
prefix for class, property and instance URIs, all mapping is done automatically,
with very little other configuration at all.

This class offers support for the W3C Direct Mapping, based on the 20 Sept 2011
working draft.

=head2 Constructor

=over 

=item * C<< RDF::RDB2RDF::DirectMapping->new([prefix => $prefix_uri] [, %opts]) >>

=item * C<< RDF::RDB2RDF->new('DirectMapping' [, prefix => $prefix_uri] [, %opts]) >>

=back

The prefix defaults to the empty string - i.e. relative URIs.

One extra option is supported: C<rdfs> which controls whether extra Tbox
statements are included in the mapping.

=head2 Methods

=over

=item * C<< process($source [, $destination]) >>

Given a database handle, produces RDF data. Can optionally be passed a
destination for triples: either an existing model to add data to, or a
reference to a callback function.

$source can be a DBI database handle, or an arrayref pair of a handle plus
a schema name.

  $destination = sub {
    print $_[0]->as_string . "\n";
  };
  $dbh    = DBI->connect('dbi:Pg:dbname=mytest');
  $schema = 'fred';
  $mapper->process([$dbh, $schema], $destination);

Returns the destination.

=item * C<< process_turtle($dbh, %options) >>

As per C<process>, but returns a string in Turtle format.

Returns a string.

=back

=head1 SEE ALSO

L<RDF::Trine>, L<RDF::RDB2RDF>.

L<http://perlrdf.org/>.

L<http://www.w3.org/TR/2011/WD-rdb-direct-mapping-20110920/>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2011 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
