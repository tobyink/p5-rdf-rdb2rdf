package RDF::RDB2RDF::R2RML;

use 5.010;
use common::sense;

use Digest::MD5 qw[md5_hex];
use RDF::Trine qw[statement blank literal];
use RDF::Trine::Namespace qw[rdf rdfs owl xsd];
use Scalar::Util qw[blessed];
use Storable qw[dclone];

use namespace::clean;

our $rr = RDF::Trine::Namespace->new('http://www.w3.org/ns/r2rml#');

use parent qw[RDF::RDB2RDF::Simple];

our $VERSION = '0.005';

sub new
{
	my ($class, $r2rml) = @_;
	my $self           = $class->SUPER::new();
	$self->_r2rml($r2rml);
	return $self;
}

sub process_turtle
{
	my ($self, $dbh, %options) = @_;
	my $rv = $self->SUPER::process_turtle($dbh, %options);
	
	unless ($options{no_r2rml})
	{
		my $r2rml = RDF::Trine::Serializer
			->new('Turtle', namespaces => { $self->namespaces })
			->serialize_model_to_string($self->{r2rml});
		$r2rml =~ s/^/# /gm;
		$rv = "# R2RML\n#\n${r2rml}\n${rv}";
	}
}

sub _r2rml
{
	my ($self, $r2rml) = @_;
	
	unless (blessed($r2rml) and $r2rml->isa('RDF::Trine::Model'))
	{
		$self->{namespaces} = RDF::Trine::NamespaceMap->new;
		my $parser = RDF::Trine::Parser->new('Turtle', namespaces=>$self->{namespaces});
		my $model  = RDF::Trine::Model->temporary_model;
		$parser->parse_into_model('http://example.com/', $r2rml, $model);
		$r2rml = $model;
	}
	
	my @TMC = values %{ {
			map { $_->as_ntriples => $_ }
			(
				$r2rml->subjects($rdf->type, $rr->TriplesMap),
				$r2rml->subjects($rdf->type, $rr->TriplesMapClass),
				$r2rml->subjects($rr->subjectMap, undef),
			)
		} };
		
	foreach my $tmc (@TMC)
	{
		$self->_r2rml_TriplesMapClass($r2rml, $tmc);
	}
	
	$self->{r2rml} = $r2rml;
}

sub _r2rml_TriplesMapClass
{
	my ($self, $r2rml, $tmc) = @_;
	my $mapping = {};
		
	if ( $self->{tmc}{$tmc} )
	{
		return $self->{tmc}{$tmc};
	}
	
	my ($tablename, $sqlquery);
	foreach ($r2rml->objects_for_predicate_list($tmc, $rr->SQLQuery, $rr->sqlQuery))
	{
		next unless $_->is_literal;
		$sqlquery = $_->literal_value;
		last;
	}
	if ($sqlquery)
	{
		$tablename = sprintf('+q%s', md5_hex($sqlquery));
		$mapping->{sql} = $sqlquery;
	}
	else
	{
		foreach ($r2rml->objects($tmc, $rr->tableName))
		{
			next unless $_->is_literal;
			$tablename = $_->literal_value;
			last;
		}
		if ($tablename)
		{
			foreach ($r2rml->objects($tmc, $rr->tableOwner))
			{
				next unless $_->is_literal;
				$tablename = sprintf('%s.%s', $_->literal_value, $tablename);
				last;
			}
		}
	}
	
	unless ($tablename)
	{
		LOGICALTABLE: foreach my $lt ($r2rml->objects($tmc, $rr->logicalTable))
		{
			next LOGICALTABLE if $lt->is_literal;

			foreach ($r2rml->objects_for_predicate_list($lt, $rr->sqlQuery, $rr->SQLQuery))
			{
				next unless $_->is_literal;
				$sqlquery = $_->literal_value;
				last;
			}
			if ($sqlquery)
			{
				$tablename = sprintf('+q%s', md5_hex($sqlquery));
				$mapping->{sql} = $sqlquery;
				last LOGICALTABLE;
			}

			TABLENAME: foreach ($r2rml->objects($lt, $rr->tableName))
			{
				next TABLENAME unless $_->is_literal;
				$tablename = $_->literal_value;
				last TABLENAME;
			}
			if ($tablename)
			{
				TABLEOWNER: foreach ($r2rml->objects($tmc, $rr->tableOwner))
				{
					next TABLEOWNER unless $_->is_literal;
					$tablename = sprintf('%s.%s', $_->literal_value, $tablename);
					last TABLEOWNER ;
				}
				last LOGICALTABLE;
			}
		}
	}
	
	return unless $tablename;
	$self->{tmc}{$tmc} = $mapping;
	$mapping->{from} = $tablename unless defined $mapping->{sql};
	
	foreach ($r2rml->objects($tmc, $rr->subjectMap))
	{
		next if $_->is_literal;
		$self->_r2rml_SubjectMapClass($r2rml, $_, $mapping);
		last;
	}
	
	unless ($mapping->{about})
	{
		($mapping->{about}) = grep { !$_->is_literal } $r2rml->objects_for_predicate_list($tmc, $rr->subject);
	}

	foreach ($r2rml->objects($tmc, $rr->predicateObjectMap))
	{
		next if $_->is_literal;
		$self->_r2rml_PredicateObjectMapClass($r2rml, $_, $mapping);
	}	

	my $key = $tablename;
	while (defined $self->{mappings}{$key})
	{
		$key = sprintf('+t%s', md5_hex($key));
	}
	
	$self->{mappings}{$key} = $mapping;
	
	return $mapping;
}

sub _r2rml_graph
{
	my ($self, $r2rml, $thing) = @_;
	
	my ($graph) =
		map { $_->is_resource ? $_->uri : $_->as_ntriples }
		grep { !$_->is_literal }
		$r2rml->objects($thing, $rr->graph);
	return $graph if $graph;

	foreach my $map ($r2rml->objects($thing, $rr->graphMap))
	{
		($graph) =
			map { $_->is_resource ? $_->uri : $_->as_ntriples }
			grep { !$_->is_literal }
			$r2rml->objects_for_predicate_list($thing, $rr->constant, $rr->graph);
		return $graph if $graph;
		
		($graph) =
			map { sprintf('{%s}', $_->literal_value) }
			grep { $_->is_literal }
			$r2rml->objects($thing, $rr->column);
		return $graph if $graph;

		($graph) =
			map { $_->literal_value }
			grep { $_->is_literal }
			$r2rml->objects($thing, $rr->template);
		return $graph if $graph;
	}
	
	return;
}

sub _r2rml_SubjectMapClass
{
	my ($self, $r2rml, $smc, $mapping) = @_;
	
	# the easy bit
	$mapping->{typeof} = [ grep { !$_->is_literal } $r2rml->objects($smc, $rr->class) ];
	
	# graph
	$mapping->{graph} = $self->_r2rml_graph($r2rml, $smc);

	# subject
	($mapping->{about}) =
		map { $_->is_resource ? $_->uri : $_->as_ntriples }
		grep { !$_->is_literal }
		$r2rml->objects_for_predicate_list($smc, $rr->constant, $rr->subject);
	unless ($mapping->{about})
	{
		my ($col) = grep { $_->is_literal } $r2rml->objects($smc, $rr->column);
		$mapping->{about} = sprintf('{%s}', $col->literal_value) if $col;
	}
	unless ($mapping->{about})
	{
		my ($tmpl) = grep { $_->is_literal } $r2rml->objects($smc, $rr->template);
		$mapping->{about} = $tmpl->literal_value if $tmpl;
	}
	
	# termtype
	my ($termtype) =
		map {
				if ($_->as_ntriples =~ /(uri|iri|blank|blanknode|literal).?$/i)
					{ { uri=>'IRI', iri=>'IRI', blank=>'BlankNode', blanknode=>'BlankNode', literal=>'Literal' }->{lc $1} }
				else
					{ $_->as_ntriples }
			}
		$r2rml->objects_for_predicate_list($smc, $rr->termType, $rr->termtype);
	if ($mapping->{about} and $termtype =~ /^blank/i)
	{
		$mapping->{about} = sprintf('_:%s', $mapping->{about})
			unless $mapping->{about} =~ /^_:/;
	}
}

sub _r2rml_PredicateObjectMapClass
{
	my ($self, $r2rml, $pomc, $mapping) = @_;
	
	# graph
	my $graph = $self->_r2rml_graph($r2rml, $pomc);

	# predicates
	my @predicates;
	foreach ($r2rml->objects($pomc, $rr->predicateMap))
	{
		next if $_->is_literal;
		push @predicates, $self->_r2rml_PredicateMapClass($r2rml, $_);
	}

	push @predicates,
		map { $_->uri } 
		grep { $_->is_resource }
		$r2rml->objects_for_predicate_list($pomc, $rr->predicate);

	# objects
	my @objects;
	foreach ($r2rml->objects($pomc, $rr->objectMap))
	{
		next if $_->is_literal;
		my $obj = $self->_r2rml_ObjectMapClass($r2rml, $_);
		push @objects, $obj if defined $obj;
	}

	push @objects,
		map {
				my $x = {};
				if ($_->is_literal)
				{
					$x->{content}  = $_->literal_value;
					$x->{lang}     = $_->literal_value_language;
					$x->{datatype} = $_->literal_datatype;
					$x->{kind}     = 'property';
				}
				elsif ($_->is_resource)
				{
					$x->{resource} = $_->uri;
					$x->{kind}     = 'rel';
				}
				elsif ($_->is_blank)
				{
					$x->{resource} = $_->as_ntriples;
					$x->{kind}     = 'rel';
				}
				$x;
			} 
		$r2rml->objects_for_predicate_list($pomc, $rr->object);

	foreach ($r2rml->objects($pomc, $rr->refObjectMap))
	{
		next if $_->is_literal;
		my $obj = $self->_r2rml_RefObjectMapClass($r2rml, $_);
		push @objects, $obj if defined $obj;
	}

	foreach my $obj (@objects)
	{
		foreach my $p (@predicates)
		{
			my $o = dclone($obj);
			my $column = delete $o->{column} || '_';
			my $kind   = delete $o->{kind}   || 'property';
			$o->{$kind} = $p;
			
			push @{ $mapping->{columns}{$column} }, $o;
		}
	}
}

sub _r2rml_PredicateMapClass
{
	my ($self, $r2rml, $pmc) = @_;
	
	my ($p) = map { $_->uri } grep { $_->is_resource } $r2rml->objects_for_predicate_list($pmc, $rr->constant, $rr->predicate);
	unless ($p)
	{
		my ($col) = grep { $_->is_literal } $r2rml->objects($pmc, $rr->column);
		$p = sprintf('{%s}', $col->literal_value) if $col;
	}
	unless ($p)
	{
		my ($tmpl) = grep { $_->is_literal } $r2rml->objects($pmc, $rr->template);
		$p = $tmpl->literal_value if $tmpl;
	}

	return ($p);
}

sub _r2rml_ObjectMapClass
{
	my ($self, $r2rml, $omc) = @_;
	
	my ($datatype, $language, $termtype, $column);
	my ($o) = map {
			if ($_->is_resource)   { $termtype = 'IRI'; $_->uri; }
			elsif ($_->is_blank)   { $termtype = 'BlankNode'; $_->as_ntriples; }
			elsif ($_->is_literal) { $datatype = $_->literal_datatype; $language = $_->literal_value_language; $termtype = 'Literal'; $_->literal_value; }
			else                   { $_->as_ntriples; }
		}
		$r2rml->objects_for_predicate_list($omc, $rr->constant, $rr->object);
	unless ($o)
	{
		my ($col) = grep { $_->is_literal } $r2rml->objects($omc, $rr->column);
		$o        = sprintf('{%s}', $col->literal_value) if $col;
		$column   = $col->literal_value if $col;
	}
	unless ($o)
	{
		my ($tmpl) = grep { $_->is_literal } $r2rml->objects($omc, $rr->template);
		$o = $tmpl->literal_value if $tmpl;
	}

	($datatype) =
		map { $_->uri }
		grep { $_->is_resource }
		$r2rml->objects($omc, $rr->datatype)
		unless $datatype;
	($language) =
		map { $_->literal_value }
		grep {  $_->is_literal }
		$r2rml->objects($omc, $rr->language)
		unless $language;
	($termtype) =
		map {
				if ($_->as_ntriples =~ /(uri|iri|blank|blanknode|literal).?$/i)
					{ { uri=>'IRI', iri=>'IRI', blank=>'BlankNode', blanknode=>'BlankNode', literal=>'Literal' }->{lc $1} }
				else
					{ $_->as_ntriples }
			}
		$r2rml->objects_for_predicate_list($omc, $rr->termType, $rr->termtype)
		unless $termtype;
	
	$termtype ||= 'Literal' if $datatype||$language;
	$termtype ||= 'IRI';
	
	$o = sprintf('_:%s', $o)
		if (!ref $o) && $termtype =~ /^blank/i && $o !~ /^_:/;
		
	my $map = {};
	
	if ($column)
	{
		$map->{column} = $column;
	}
	else
	{
		my $x = ($termtype =~ /literal/i) ? 'content' : 'resource';
		$map->{$x} = $o;
	}
	
	$map->{datatype} = $datatype if $datatype;
	$map->{lang}     = $language if $language;
	$map->{kind}     = ($termtype =~ /literal/i) ? 'property' : 'rel';

	return $map;
}

sub _r2rml_RefObjectMapClass
{
	my ($self, $r2rml, $romc) = @_;
		
	my $parent;
	PARENT: foreach my $ptm ($r2rml->objects($romc, $rr->parentTriplesMap))
	{
		next PARENT if $ptm->is_literal;
		$parent = $self->_r2rml_TriplesMapClass($r2rml, $ptm);
		last PARENT if $parent;
	}
	return unless $parent;
	
	my $joins = [];
	JOIN: foreach my $jc ($r2rml->objects($romc, $rr->joinCondition))
	{
		my ($p) = grep { $_->is_literal }
			$r2rml->objects($jc, $rr->parent);
		my ($c) = grep { $_->is_literal }
			$r2rml->objects($jc, $rr->child);
		
		if ($p && $c)
		{
			push @$joins, { parent => $p->literal_value, child => $c->literal_value };
		}
	}
	
	return {
		column   => '_',
		join     => $parent->{sql} || $parent->{from},
		on       => $joins,
		resource => $parent->{about},
		method   => $parent->{sql} ? 'subquery' : 'table',
		};
}

1;

=head1 NAME

RDF::RDB2RDF::R2RML - map relational database to RDF using R2RML

=head1 SYNOPSIS

 my $mapper = RDF::RDB2RDF->new('R2RML', $r2rml);
 print $mapper->process_turtle($dbh);

=head1 DESCRIPTION

This class offers support for W3C R2RML, based on the 20 Sept 2011 working
draft. See the BUGS section below for a list on unimplemented areas.

This is a subclass of RDF::RDB2RDF::Simple. Differences noted below...

=head2 Constructor

=over 

=item * C<< RDF::RDB2RDF::R2RML->new($r2rml) >>

=item * C<< RDF::RDB2RDF->new('R2RML', $r2rml) >>

A single parameter is expected, this can either be an R2RML document as a
Turtle string, or an L<RDF::Trine::Model> containing R2RML data. If a Turtle
string, then the namespaces from it are also kept.

=back

=head2 Methods

=over

=item * C<< process_turtle($dbh, %options) >>

The mapping is included as an R2RML comment at the top of the Turtle. Passing
C<< no_r2rml => 1 >> can disable that feature.

=back

=head1 BUGS

Limitations

=over

=item * rr:RefObjectMap, rr:parentTriplesMap, rr:joinCondition,
rr:JoinCondition, rr:child, rr:parent are only partially working.

=item * rr:defaultGraph is not understood.

=item * Datatype conversions probably not done correctly.

=back

=head1 SEE ALSO

L<RDF::Trine>, L<RDF::RDB2RDF>, L<RDF::RDB2RDF::Simple>.

L<http://perlrdf.org/>.

L<http://www.w3.org/TR/2011/WD-r2rml-20110920/>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2011 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
