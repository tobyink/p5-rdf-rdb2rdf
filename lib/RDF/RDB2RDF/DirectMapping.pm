package RDF::RDB2RDF::DirectMapping;

use 5.010;
use common::sense;

use Carp qw[carp croak];
use DBI;
use MIME::Base64 qw[];
use RDF::Trine qw[iri blank literal statement];
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];
use Scalar::Util qw[refaddr blessed];
use URI::Escape qw[];

use parent qw[RDF::RDB2RDF RDF::RDB2RDF::DatatypeMapper];

our $VERSION = '0.006';

sub new
{
	my ($class, %args) = @_;
	
	$args{prefix}        = '' unless defined $args{prefix};
	$args{rdfs}          = 0  unless defined $args{rdfs};
	$args{warn_sql}      = 0  unless defined $args{warn_sql};
	$args{ignore_tables} = [] unless defined $args{ignore_tables};
	
	bless {%args}, $class;
}

sub uri_escape
{
	my $str = URI::Escape::uri_escape(@_);
	$str =~ s/\%20/+/g;
	return $str;
}

sub prefix        :lvalue { $_[0]->{prefix} }
sub rdfs          :lvalue { $_[0]->{rdfs} }
sub ignore_tables :lvalue { $_[0]->{ignore_tables} }
sub warn_sql      :lvalue { $_[0]->{warn_sql} }

sub _unquote_identifier
{
	my $i = shift;
	return $1 if $i =~ /^\"(.+)\"$/;
	return $i;
}

sub rowmap (&$)
{
	my ($coderef, $iter) = @_;
	my @results = ();
	local $_;
	my $i = 0;
	while ($_ = $iter->fetchrow_hashref)
	{
		push @results, $coderef->($coderef, $iter, $_, ++$i);
	}
	wantarray ? @results : scalar(@results);
}

sub layout
{
	my ($self, $dbh, $schema) = @_;

	unless ($self->{layout}{refaddr($dbh).'|'.$schema})
	{
		carp sprintf('READ SCHEMA "%s"', $schema||'%') if $self->warn_sql;
		
		my $rv     = {};
		my @tables = rowmap {
			_unquote_identifier($_->{TABLE_NAME})
		} $dbh->table_info(undef, $schema, undef, undef);

		foreach my $table (@tables)
		{
			if ($table =~ /^sqlite_/ and $dbh->get_info(17) =~ /sqlite/i)
			{
				next;
			}
			
			$rv->{$table}{columns} ||= [];
			$rv->{$table}{keys}    ||= {};
			$rv->{$table}{refs}    ||= {};
			
			$rv->{$table}{columns} = [
				sort { $a->{ORDINAL_POSITION} <=> $b->{ORDINAL_POSITION} }
				rowmap {
					my $type = ($_->{TYPE_NAME} =~ /^char$/i and defined $_->{COLUMN_SIZE})
						? sprintf('%s(%d)', $_->{TYPE_NAME}, $_->{COLUMN_SIZE})
						: $_->{TYPE_NAME};
					+{
						column   => _unquote_identifier($_->{COLUMN_NAME}),
						type     => $type,
						order    => $_->{ORDINAL_POSITION},
						nullable => $_->{NULLABLE},
					}
				}
				$dbh->column_info(undef, $schema, $table, undef)
			];
			
			my $pkey_name;
			my @pkey_cols = 
				map {
					$pkey_name = $_->{PK_NAME};
					$_->{COLUMN_NAME};
				}
				sort { $a->{KEY_SEQ} <=> $b->{KEY_SEQ} }
				rowmap {
					+{ %$_ };
				}
				$dbh->primary_key_info(undef, $schema, $table, undef);
			
			$rv->{$table}{keys}{$pkey_name} = {
				columns => \@pkey_cols,
				primary => 1,
			} if @pkey_cols;

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
	my $callback = (ref $model eq 'CODE')
		? $model
		: sub{ $model->add_statement(@_) };
	my $schema;
	($dbh, $schema) = ref($dbh) eq 'ARRAY' ? @$dbh : ($dbh, undef);

	my $layout = $self->layout($dbh, $schema);
	foreach my $table (keys %$layout)
	{
		$table =~ s/^"(.+)"$/$1/;
		$self->handle_table([$dbh, $schema], $callback, $table);
	}
	
	return $model;
}

sub handle_table
{
	my ($self, $dbh, $model, $table, $where, $cols) = @_;
	return if $table ~~ $self->ignore_tables;
	
	$model = RDF::Trine::Model->temporary_model unless defined $model;
	my $callback = (ref $model eq 'CODE')?$model:sub{$model->add_statement(@_)};		
	my $schema;
	($dbh, $schema) = ref($dbh) eq 'ARRAY' ? @$dbh : ($dbh, undef);
	$cols = [$cols] if (defined $cols and !ref $cols and length $cols);
	
	my $layout = $self->layout($dbh, $schema);
	
	if (ref $cols eq 'ARRAY')
	{
		my ($pkey) = grep { $_->{primary} } values %{ $layout->{$table}{keys} };
		my %cols   = map { $_ => 1 } (@{ $pkey->{columns} }, @$cols);
		$cols      = join ',', map { $dbh->quote_identifier($_) } sort keys %cols;
	}
	else
	{
		$cols = '*';
	}

	$self->handle_table_rdfs([$dbh, $schema], $callback, $table)
		if ($cols eq '*' and !defined $where);	

	my $sql = $schema
		? sprintf('SELECT %s FROM %s.%s', $cols, $dbh->quote_identifier($schema), $dbh->quote_identifier($table))
		: sprintf('SELECT %s FROM %s', $cols, $dbh->quote_identifier($table));
	
	my @values;
	if ($where)
	{
		my @w;
		while (my ($k,$v) = each %$where)
		{
			push @w, sprintf('%s = ?', $dbh->quote_identifier($k));
			push @values, $v;
		}
		$sql .= ' WHERE ' . (join ' AND ', @w);
	}

	carp($sql) if $self->warn_sql;
	my $sth = $dbh->prepare($sql);
	$sth->execute(@values);
		
	while (my $row = $sth->fetchrow_hashref)
	{
#		use Data::Dumper;
#		print Dumper($layout, $row, $table);
		my ($pkey_uri) =
			map  { $self->make_key_uri($table, $_->{columns}, $row); }
			grep { $_->{primary}; }
			values %{ $layout->{$table}{keys} };		
		my $subject = $pkey_uri ? iri($pkey_uri) : blank();
		
		# rdf:type
		$callback->(statement($subject, $RDF->type, iri($self->prefix.$table)));
		
		# owl:sameAs
		if ($cols eq '*')
		{
			my @key_uris =
				map  { $self->make_key_uri($table, $_->{columns}, $row); }
				grep { !$_->{primary}; }
				values %{ $layout->{$table}{keys} };
			$callback->(statement($subject, $OWL->sameAs, iri($_)))
				foreach @key_uris;
		}
		
		# p-o for columns
		foreach my $column (@{ $layout->{$table}{columns} })
		{
			next unless defined $row->{ $column->{column} };
			
			my $predicate = iri($self->prefix.$table.'#'.$column->{column});
			my $object    = $self->datatyped_literal(
				$row->{ $column->{column} },
				$column->{type},
				);
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
	return if $table ~~ $self->ignore_tables;
	
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
			my $dummy     = $self->datatyped_literal('DUMMY', $column->{type});
			my $datatype  = $dummy->has_datatype ? iri($dummy->literal_datatype) : $RDFS->Literal;
			
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

sub _uri_escape
{
	my $s = uri_escape(shift);
	$s =~ s/\+/%20/g;
	$s;
}

sub make_ref_uri
{
	my ($self, $table, $ref) = @_;
	
	return $self->prefix .
		$table . "#ref=" .
		(join '.', map
			{ _uri_escape($_); }
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
			{ sprintf('%s-%s', _uri_escape($_), _uri_escape($data->{$map->{$_}})); }
			@{$ref->{target_columns}});
}

sub make_key_uri
{
	my ($self, $table, $columns, $data) = @_;
	
	return $self->prefix .
		$table . "/" .
		(join ';', map
			{ sprintf('%s=%s', _uri_escape($_), _uri_escape($data->{$_})); }
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

Three extra options are supported: C<rdfs> which controls whether extra Tbox
statements are included in the mapping; C<warn_sql> carps statements to
STDERR whenever the database is queried (useful for debugging);
C<ignore_tables> specifies tables to ignore (smart match is used, so the
value of ignore_tables can be a string, regexp, coderef, or an arrayref
of all of the above).

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

=item * C<< handle_table($source, $destination, $table, [\%where], [\@cols]) >>

As per C<process> but must always be passed an explicit destination (doesn't
return anything useful), and only processes a single table.

If %where is provided, selects only certain rows from the table. Hash keys
are column names, hash values are column values.

If @cols is provided, selects only particular columns. (The primary key columns
will always be selected.)

This method allows you to generate predictable subsets of the mapping output.
It's used fairly extensively by L<RDF::RDB2RDF::DirectMapping::Store>.

=item * C<< handle_table_sql($source, $destination, $table) >>

As per C<handle_table> but only generates the RDFS/OWL schema data. Note that
C<handle_table> already includes this data (unless %where or @cols was passed
to it).

If the C<rdfs> option passed to the constructor was not true, then there will
be no RDFS/OWL schema data generated.

=back

=head1 SEE ALSO

L<RDF::Trine>, L<RDF::RDB2RDF>.

L<RDF::RDB2RDF::DirectMapping::Store>.

L<http://www.perlrdf.org/>.

L<http://www.w3.org/TR/2011/WD-rdb-direct-mapping-20110920/>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2011 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

