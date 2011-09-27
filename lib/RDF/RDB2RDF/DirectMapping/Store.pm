package RDF::RDB2RDF::DirectMapping::Store;

use 5.008;
use common::sense;

use Carp qw[carp croak];
use RDF::Trine;
use RDF::Trine::Namespace qw[RDF RDFS OWL XSD];
use Scalar::Util qw[blessed];
use URI::Escape qw[uri_escape uri_unescape];

use base qw[RDF::Trine::Store];

our $VERSION = '0.003';

sub new
{
	my ($class, $dbh, $mapping) = @_;
	
	my $schema;
	if (ref $dbh eq 'ARRAY')
	{
		($dbh, $schema) = @$dbh;
	}
	
	my $layout = $mapping->layout($dbh, $schema);
	foreach my $table (keys %$layout)
	{
		unless ($layout->{$table}{keys}
		and grep { $_->{primary} } values %{$layout->{$table}{keys}})
		{
			croak("Table $table lacks a primary key.");
		}
	}
	
	bless {
		dbh      => $dbh,
		schema   => $schema,
		mapping  => $mapping,
		}, $class;
}

sub dbh     :lvalue { $_[0]->{dbh} }
sub schema  :lvalue { $_[0]->{schema} }
sub mapping :lvalue { $_[0]->{mapping} }

sub get_statements
{
	my ($self, $s, $p, $o, $g) = @_;
	
	$s = undef if blessed($s) && $s->is_variable;
	$p = undef if blessed($p) && $p->is_variable;
	$o = undef if blessed($o) && $o->is_variable;
	$g = undef if blessed($g) && $g->is_variable;

	my $NULL = RDF::Trine::Iterator::Graph->new();
	return $NULL if $g;
	
	my @results;
	my $check = RDF::Trine::Statement->new(
		$s || RDF::Trine::Node::Variable->new('s'),
		$p || RDF::Trine::Node::Variable->new('p'),
		$o || RDF::Trine::Node::Variable->new('o'),
		);
	my $callback = sub {
		return unless $check->subsumes($_[0]);
		push @results, $_[0];
	};	

	my $layout = $self->mapping->layout($self->dbh, $self->schema);
	my ($s_prefix, $s_table, $s_divider, $s_bit) = $self->split_uri($s);
	my ($p_prefix, $p_table, $p_divider, $p_bit) = $self->split_uri($p);
	
	my $table = undef;
	my $where = {};
	
	
	if ($self->mapping->rdfs)
	{
		my $special_namespace = '^' . join '|',
			map { quotemeta($_->uri) } ($RDF, $RDFS, $OWL, $XSD);

		my $check_rdfs = undef;

		if (blessed($p) and $p->uri =~ /$special_namespace/)
		{
			my ($o_prefix, $o_table, $o_divider);
			($o_prefix, $o_table, $o_divider) = $self->split_uri($o)
				if blessed($o) && $o->is_resource;
				
			unless ($p->equal($RDF->type) and $o_prefix)
			{
				if ($s_table)
				{
					$check_rdfs = $s_table;
				}
				elsif (!defined $s)
				{
					$check_rdfs = '*';
				}
			}
		}
		elsif (blessed($s) and $s_divider ne '/')
		{
			$check_rdfs = $s_table;
		}
		
		if ($check_rdfs eq '*')
		{
			$self->mapping->handle_table_rdfs([$self->dbh, $self->schema], $callback, $_)
				foreach keys %$layout;
			return RDF::Trine::Iterator::Graph->new(\@results);
		}
		elsif (defined $check_rdfs and defined $layout->{$check_rdfs})
		{
			$self->mapping->handle_table_rdfs([$self->dbh, $self->schema], $callback, $check_rdfs);
			return RDF::Trine::Iterator::Graph->new(\@results);
		}
	}
	
	# All subject URIs will be prefixed
	if (defined $s and !$s_prefix)
	{
		return $NULL;
	}

	if ($p_prefix)
	{
		$table = $p_table;
		return $NULL unless defined $layout->{$table};
			
		# Properties need to be the right type of URI
		return $NULL
			unless $p_divider eq '#';
			
		# TODO: better handling for "ref-".
		if ($p_bit =~ /^ref-/)
		{
			return $NULL if blessed($o) && $o->is_literal;
		}
		else
		{
			# Column needs to exist
			my ($column) =
				grep { $p_bit eq $_->{column} }
				@{$layout->{$table}{columns}};
			return $NULL unless $column;
			
			if (blessed($o))
			{
				return $NULL unless $o->is_literal;
				return $NULL if $o->has_language;

				$where->{ $column->{column} } = $o->literal_value;
			}
		}
	}
	elsif (blessed($p) and $p->equal($RDF->type))
	{
		my ($o_prefix, $o_table, $o_divider) = $self->split_uri($o);
		return $NULL unless $o_prefix;
		return $NULL if $o_divider;
		
		$table = $o_table;
	}

	if ($s_prefix)
	{
		# Individuals and properties will always belong to the same table
		return $NULL
			if defined $table && $s_table ne $table;

		$table ||= $s_table;
		return $NULL unless defined $layout->{$table};

		# Individuals need to be the right type of URI
		return $NULL
			unless $s_divider eq '/';

		# Needs to be some conditions to identify the individual.
		my $conditions = $self->handle_bit($table, $s_bit);
		return $NULL unless $conditions;

		# Add conditions to $where
		while (my ($k, $v) = each %$conditions)
		{
			# Conflicting conditions
			if (defined $where->{$k} and $where->{$k} ne $v)
			{
				return $NULL;
			}
			$where->{$k} = $v;
		}
	}

	$where = undef unless keys %$where;
	
	if ($table)
	{
		#use Data::Dumper;
		#warn ("Saved Time!\n".Dumper($table , $where));
		$self->mapping->handle_table([$self->dbh, $self->schema], $callback, $table, $where);
	}
	else
	{
		$self->mapping->process([$self->dbh, $self->schema], $callback);
	}
	
	return RDF::Trine::Iterator::Graph->new(\@results);
}

sub handle_bit
{
	my ($self, $table, $bit) = @_;
	
	my $layout = $self->mapping->layout($self->dbh, $self->schema);	
	my ($pkey) = grep { $_->{primary} } values %{$layout->{$table}{keys}};
	
	my $regex   =
		join '\.',
		map { sprintf('%s-(.*)', quotemeta(uri_escape($_))) }
		@{$pkey->{columns}};
	
#	warn "'$bit' =~ /$regex/";
	
	if (my @values = ($bit =~ /^ $regex $/x))
	{
		my $r = {};
		for (my $i=0; exists $values[$i]; $i++)
		{
			$r->{ $pkey->{columns}[$i] } = uri_unescape($values[$i]);
		}
		return $r;
	}
	
	return;
}

sub split_uri
{
	my ($self, $uri) = @_;
	return unless $uri;
	$uri = $uri->uri if blessed($uri);
	
	my $prefix = $self->mapping->prefix;
	if ($uri =~ m!^ (\Q$prefix\E)  # prefix
	                ([^#/]+)         # table name
	                (?:              # optionally...
	                  ([#/])         #   URI divider
	                  (.+)           #   other bit
	                )? $!x)
	{
		return ($1, $2, $3, $4);
	}
	
	return;
}

sub get_contexts
{
	return RDF::Trine::Iterator->new();
}

sub count_statements
{
	my $self  = shift;
	my $iter  = $self->get_statements(@_);
	my $count = 0;
	while (my $st = $iter->next)
	{
		$count++;
	}
	return $count;
}

sub add_statement
{
	croak "add_statement not implemented yet.";
}

sub remove_statement
{
	croak "remove_statement not implemented yet.";
}

sub remove_statements
{
	croak "remove_statements not implemented yet.";
}

1;

=head1 NAME

RDF::RDB2RDF::DirectMapping::Store - mapping-fu

=head1 SYNOPSIS

 my $mapper = RDF::RDB2RDF->new('DirectMapping',
   prefix => 'http://example.net/data/');
 my $store  = RDF::RDB2RDF::DirectMapping::Store->new($dbh, $mapper);

=head1 DESCRIPTION

This is pretty experimental. It provides a (for now) read-only
L<RDF::Trine::Store> based on a database handle and a 
L<RDF::RDB2RDF::DirectMapping> map.

Some queries are super-optimised; others are somewhat slower.

=head1 SEE ALSO

L<RDF::Trine>, L<RDF::RDB2RDF>, L<RDF::RDB2RDF::DirectMapping>.

L<http://perlrdf.org/>.

L<http://www.w3.org/TR/2011/WD-rdb-direct-mapping-20110920/>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2011 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
