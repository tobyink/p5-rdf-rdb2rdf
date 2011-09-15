package RDF::RDB2RDF::R2RML;

use 5.008;
use common::sense;

use Digest::MD5 qw[md5_hex];
use RDF::Trine qw[statement blank literal];
use RDF::Trine::Namespace qw[rdf rdfs owl xsd];
use Scalar::Util qw[blessed];
use Storable qw[dclone];

use namespace::clean;

our $rr = RDF::Trine::Namespace->new('http://www.w3.org/ns/r2rml#');

use base qw[RDF::RDB2RDF::Simple];

our $VERSION = '0.002';

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
		$parser->parse_into_model(undef, $r2rml, $model);
		$r2rml = $model;
	}
	
	foreach my $tmc ($r2rml->subjects($rdf->type, $rr->TriplesMapClass))
	{
		$self->_r2rml_TriplesMapClass($r2rml, $tmc);
	}
	
	$self->{r2rml} = $r2rml;
}

sub _r2rml_TriplesMapClass
{
	my ($self, $r2rml, $tmc) = @_;
	my $mapping = {};
	
	my ($tablename, $sqlquery);
	foreach ($r2rml->objects($tmc, $rr->SQLQuery))
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
	return unless $tablename;
	
	foreach ($r2rml->objects($tmc, $rr->subjectMap))
	{
		next if $_->is_literal;
		$self->_r2rml_SubjectMapClass($r2rml, $_, $mapping);
		last;
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
		$mapping->{from} = $tablename;
	}
	$self->{mappings}{$key} = $mapping;
	return $mapping;
}

sub _r2rml_SubjectMapClass
{
	my ($self, $r2rml, $smc, $mapping) = @_;
	
	# the easy bit
	$mapping->{typeof} = [ grep { !$_->is_literal } $r2rml->objects($smc, $rr->class) ];
	
	# graph
	($mapping->{graph}) = grep { $_->is_resource } $r2rml->objects($smc, $rr->graph);
	unless ($mapping->{graph})
	{
		my ($col) = grep { $_->is_literal } $r2rml->objects($smc, $rr->graphColumn);
		$mapping->{graph} = sprintf('{%s}', $col->literal_value) if $col;
	}
	unless ($mapping->{graph})
	{
		my ($tmpl) = grep { $_->is_literal } $r2rml->objects($smc, $rr->graphTemplate);
		$mapping->{graph} = $tmpl->literal_value if $tmpl;
	}

	# subject
	($mapping->{about}) = grep { !$_->is_literal } $r2rml->objects($smc, $rr->subject);
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
	if ($mapping->{about}
	and grep { !$_->is_literal and $_->literal_value =~ /^blank(node)?/i } $r2rml->objects($smc, $rr->termtype))
	{
		$mapping->{about} = sprintf('_:%s', $mapping->{about})
			unless $mapping->{about} =~ /^_:/;
	}
}

sub _r2rml_PredicateObjectMapClass
{
	my ($self, $r2rml, $pomc, $mapping) = @_;
	
	# graph
	my ($graph) = grep { $_->is_resource } $r2rml->objects($pomc, $rr->graph);
	unless ($graph)
	{
		my ($col) = grep { $_->is_literal } $r2rml->objects($pomc, $rr->graphColumn);
		$graph = sprintf('{%s}', $col->literal_value) if $col;
	}
	unless ($graph)
	{
		my ($tmpl) = grep { $_->is_literal } $r2rml->objects($pomc, $rr->graphTemplate);
		$graph = $tmpl->literal_value if $tmpl;
	}

	# predicates
	my @predicates;
	foreach ($r2rml->objects($pomc, $rr->predicateMap))
	{
		next if $_->is_literal;
		push @predicates, $self->_r2rml_PredicateMapClass($r2rml, $_);
	}
	
	# objects
	my @objects;
	foreach ($r2rml->objects($pomc, $rr->objectMap))
	{
		next if $_->is_literal;
		my $obj = $self->_r2rml_ObjectMapClass($r2rml, $_);
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
	
	my ($p) = grep { $_->is_resource } $r2rml->objects($pmc, $rr->predicate);
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
	
	my $column;
	my ($o) = grep { $_->is_resource } $r2rml->objects($omc, $rr->object);
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

	my ($datatype) = grep { !$_->is_literal } $r2rml->objects($omc, $rr->datatype);
	my ($language) = grep {  $_->is_literal } $r2rml->objects($omc, $rr->language);
	my ($termtype) = grep {  $_->is_literal } $r2rml->objects($omc, $rr->termtype);
	
	$termtype = $termtype->literal_value if $termtype;
	$termtype ||= 'literal';
	
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
	
	$map->{datatype} = $datatype->uri if $datatype;
	$map->{lang}     = $language->literal_value if $language;
	$map->{kind}     = ($termtype =~ /literal/i) ? 'property' : 'rel';

	return $map;
}

1;

=head1 NAME

RDF::RDB2RDF::R2RML - map relational database to RDF using R2RML

=head1 SYNOPSIS

 my $mapper = RDF::RDB2RDF::R2RML->new($r2rml);
 print $mapper->process_turtle($dbh);

=head1 DESCRIPTION

This class offers support for W3C R2RML, based on the 24 March 2011 working
draft. B<It does not yet support the "ref" stuff for generating triples based
on foreign keys.>

This is a subclass of RDF::RDB2RDF::Simple. Differences noted below...

=head2 Constructor

=over 

=item * C<< new($r2rml)>>

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

=head1 SEE ALSO

L<RDF::Trine>, L<RDF::RDB2RDF>, L<RDF::RDB2RDF::Simple>.

L<http://perlrdf.org/>.

L<http://www.w3.org/TR/2011/WD-r2rml-20110324/>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2011 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
