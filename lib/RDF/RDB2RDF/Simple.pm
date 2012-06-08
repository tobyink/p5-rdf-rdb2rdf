package RDF::RDB2RDF::Simple;

use 5.010;
use common::sense;

use Carp qw[carp croak];
use Data::UUID;
use Digest::MD5 qw[md5_hex];
use DBI;
use JSON qw[];
use overload qw[];
use RDF::Trine qw[statement blank literal];
use RDF::Trine::Namespace qw[rdf rdfs owl xsd];
use Scalar::Util qw[blessed];
use URI::Escape qw[uri_escape];

use namespace::clean;
use parent qw[RDF::RDB2RDF RDF::RDB2RDF::DatatypeMapper];

our $VERSION = '0.006';

sub new
{
	my ($class, %mappings) = @_;
	my $ns   = delete($mappings{-namespaces}) // +{};
	my $base = delete($mappings{-base})       // 'http://example.com/base/';
	while (my ($k, $v) = each %$ns)
	{
		$ns->{$k} = RDF::Trine::Namespace->new($v)
			unless (blessed($v) and $v->isa('RDF::Trine::Namespace'));
	}
	bless {
		mappings   => \%mappings,
		namespaces => $ns,
		base       => $base,
	}, $class; 
}

sub mappings
{
	my ($self) = @_;
	return $self->{mappings};
}

sub namespaces
{
	my ($self) = @_;
	my %NS;
	
	%NS = %{ $self->{namespaces} }
		if (ref $self->{namespaces} eq 'HASH' or blessed($self->{namespaces}));
		
	%NS = (
		owl  => "$owl",
		rdf  => "$rdf",
		rdfs => "$rdfs",
		xsd  => "$xsd",
		) unless %NS;
	
	return %NS;
}

sub template
{
	my ($self, $template, %data) = @_;
	
	if (blessed($template) and $template->isa('RDF::Trine::Node'))
	{
		return $template;
	}
	
	$self->{uuid} = Data::UUID->new unless $self->{uuid};
	$data{'+uuid'} = $self->{uuid}->create_str;
	
	foreach my $key (sort keys %data)
	{
		my $replacement = $data{$key};
		
		foreach my $placeholder (sprintf('{%s}', $key), sprintf('{"%s"}', $key))
		{
			$template =~ s!\Q$placeholder!$replacement!g;
		}
	}
	
	$template =~ s!\\([\\{}])!\1!g;
	
	return $template;
}

sub template_irisafe
{
	my ($self, $template, %data) = @_;
	
	if (blessed($template) and $template->isa('RDF::Trine::Node'))
	{
		return $template;
	}
	
	$self->{uuid} = Data::UUID->new unless $self->{uuid};
	$data{'+uuid'} = $self->{uuid}->create_str;
	
	foreach my $key (sort keys %data)
	{
		my $replacement = uri_escape($data{$key});
		
		foreach my $placeholder (sprintf('{%s}', $key), sprintf('{"%s"}', $key))
		{
#			if ($placeholder eq $template) {
#				$template = $data{$key};
#				last;
#			}
			$template =~ s!\Q$placeholder!$replacement!g;
		}
	}
	
	$template =~ s!\\([\\{}])!\1!g;
	
	return $template;
}

sub iri
{
	my ($self, $iri, $graph) = @_;
	
	return $iri
		if blessed($iri) && $iri->isa('RDF::Trine::Node');
	return blank()
		if $iri eq '[]';
	
	if ($iri =~ /^_:(.*)$/)
	{
		my $ident = $1;
		$ident =~ s/([^0-9A-Za-wyz])/sprintf('x%04X', ord($1))/eg;
		if ($graph)
		{
			$ident = md5_hex("$graph").$ident;
		}
		return blank($ident);
	}
	
	return RDF::Trine::Node::Resource->new("$iri", $self->{base});
}

sub process
{
	my ($self, $dbh, $model) = @_;
	$model = RDF::Trine::Model->temporary_model unless defined $model;	
	my $callback = (ref $model eq 'CODE')
		? $model
		: sub { my $st = shift; $model->add_statement($st) if $st->rdf_compatible };
	
	my $mappings = $self->mappings;
	TABLE: foreach my $table (keys %$mappings)
	{
		$self->handle_table($dbh, $callback, $table);
	}

	return $model;
}

# make a template from a literal string
sub mktemplate 
{
	my ($self, $string) = @_;
	$string =~ s!([\\{}])!\\\1!g;
	return $string;
}

sub _get_types
{
	my ($self, $sth) = @_;
	
	my %types;
	@types{ @{$sth->{NAME}} } = map
		{ /^\d+$/ ? (scalar $sth->dbh->type_info($_)->{TYPE_NAME}) : $_ }
		@{$sth->{TYPE}};
	
#	use Data::Dumper;
#	warn Dumper \%types;
	
	return \%types;
}

sub handle_table
{
	my ($self, $dbh, $model, $table) = @_;
	$model = RDF::Trine::Model->temporary_model unless defined $model;	
	my $callback = (ref $model eq 'CODE')?$model:sub{$model->add_statement(@_)};
	
	my $mappings = $self->mappings;
	my $tmap     = $mappings->{$table};
	
	# ->{from}
	my $from = $tmap->{from} || $table;

	# ->{select}
	my $select = $tmap->{select} || '*';
	
	# ->{sql}
	my $sql    = "SELECT $select FROM $from";
	$sql = $tmap->{sql} if $tmap->{sql};# =~ /^\s*SELECT/i;
	
	### Re-jig mapping structure.
	{
		$tmap->{-maps}  = [];
		$tmap->{-jmaps} = [];
		
		my %c = %{$tmap->{columns}};
		while (my ($col, $list) = each %c)
		{
			push @{ $tmap->{-maps} },
				map  { {%$_, column => $col}; }
				grep { !defined $_->{join} }
				@$list;
			push @{ $tmap->{-jmaps} },
				grep { defined $_->{join} }
				@$list;
		}
	}
	
	my $sth = $dbh->prepare($sql) or return;
	$sth->execute;
	my $types = $self->_get_types($sth);
	
	my $row_count = 0;
	ROW: while (my $row = $sth->fetchrow_hashref)
	{
		$row_count++;
		$self->handle_row($dbh, $callback, $table, $row, $types, $row_count);
	}
	
	JMAP: foreach my $map (@{ $tmap->{-jmaps} })
	{
		my $method = lc $map->{method};
		$method ||= 'subquery' if $map->{join} =~ /^\s*SELECT/i;
		$method ||= 'table'    if $map->{join} =~ /^[A-Za-z0-9_]+$/i;
		croak sprintf("Cannot join to '' without method.", $map->{join})
			unless $method eq 'subquery' || $method eq 'table';
		
		my $evil_sql = sprintf('SELECT * FROM %s AS "r2r_join_parent", %s AS "r2r_join_child"',
			sprintf(($method eq 'subquery' ? '(%s)' : '"%s"'), $map->{join}),
			($tmap->{sql} or $tmap->{select}) ? "($sql)" : $from,
			);
		
		if (@{ $map->{on} })
		{
			$evil_sql .= ' WHERE ' .
				join ' AND ',
				map { sprintf('"r2r_join_parent"."%s"="r2r_join_child"."%s"', $_->{parent}, $_->{child}) }
				@{ $map->{on} };
		}
		
		my $evil_sth = $dbh->prepare($evil_sql);
		$sth->execute;
		my $types = $self->_get_types($sth);
		
		my $evil_row_count = 0;
		ROW: while (my $evil_row = $evil_sth->fetchrow_hashref)
		{
			$evil_row_count++;
			$self->handle_jmap($dbh, $callback, $table, $map, $evil_row, $types, $evil_row_count);
		}
	}
	
	delete $tmap->{-maps};
	delete $tmap->{-jmaps};
	return $callback;
}

sub handle_row
{
	my ($self, $dbh, $model, $table, $row, $types, $row_count) = @_;
	$model = RDF::Trine::Model->temporary_model unless defined $model;	
	my $callback = (ref $model eq 'CODE')?$model:sub{$model->add_statement(@_)};
	
	my $mappings = $self->mappings;
	my $tmap     = $mappings->{$table};	
	
	# ->{graph}
	my $graph = undef;
	$graph = $self->iri( $self->template_irisafe($tmap->{graph}, %$row) )
		if defined $tmap->{graph};
	
	# ->{about}
	my $subject;
	if ($tmap->{about} and $tmap->{_about_is_template})
	{
		$subject = $self->template_irisafe($tmap->{about}, %$row);
	}
	elsif ($tmap->{about} and $tmap->{about} =~ m< ^ {\"? ([^}]+?) \"?} $ >x)
	{
		$subject = $row->{$1};
	}
	$subject //= ($tmap->{about} // '[]');
	
	# ->{typeof}
	foreach (@{ $tmap->{typeof} })
	{
		$_ = $self->iri($_, $graph) unless ref $_;
		$callback->(statement($self->iri($subject, $graph), $rdf->type, $_));
	}

	foreach (@{ $tmap->{-maps} })
	{
		# use Data::Dumper; warn Dumper($_);
		$self->handle_map($dbh, $model, $table, $row, $types, $row_count, $_, $graph, $subject);
	}			
}

sub handle_jmap
{
	my ($self, $dbh, $model, $table, $jmap, $row, $types, $row_count) = @_;
	$model = RDF::Trine::Model->temporary_model unless defined $model;	
	my $callback = (ref $model eq 'CODE')?$model:sub{$model->add_statement(@_)};
	
	my $mappings = $self->mappings;
	my $tmap     = $mappings->{$table};
	
	# ->{graph}
	my $graph = undef;
	$graph = $self->iri( $self->template_irisafe($tmap->{graph}, %$row) )
		if defined $tmap->{graph};
	
	# ->{about}
	my $subject;
	if ($tmap->{about})
	{
		$subject = $self->template_irisafe($tmap->{about}, %$row);
	}
	$subject ||= '[]';
	
	$self->handle_map($dbh, $model, $table, $row, $types, $row_count, $jmap, $graph, $subject);
}

{ 
my $parsers = {};
sub handle_map
{
	my ($self, $dbh, $model, $table, $row, $types, $row_count, $map, $graph, $subject) = @_;
	
	$model = RDF::Trine::Model->temporary_model unless defined $model;	
	my $callback = (ref $model eq 'CODE')?$model:sub{$model->add_statement(@_)};
	
	my $mappings = $self->mappings;
	my $tmap     = $mappings->{$table};	
	my %row      = %$row;
	my $column   = $map->{column};
	
	my ($predicate, $value);
	$value = $row{$column} if defined $row{$column};
	
	my $lgraph = defined $map->{graph}
		? $self->iri($self->template_irisafe($map->{graph}, %row))
		: $graph;
	
	if (defined $map->{parse} and uc $map->{parse} eq 'TURTLE')
	{
		return unless length $value;
		
		my %NS = $self->namespaces;
		my $turtle = join '', map { sprintf("\@prefix %s: <%s>.\n", $_, $NS{$_}) } keys %NS;
		$turtle .= sprintf("\@base <%s>.\n", $subject->uri);
		$turtle .= "$value\n";
		eval {
			$parsers->{ $map->{parse} } = RDF::Trine::Parser->new($map->{parse});
			if ($lgraph)
			{
				$parsers->{ $map->{parse} }->parse($subject, $turtle, sub { $callback->($_[0], $lgraph); });
			}
			else
			{
				$parsers->{ $map->{parse} }->parse($subject, $turtle, $callback);
			}
		};
		return;
	}

	if ($map->{rev} || $map->{rel})
	{
		$predicate = $map->{rev} || $map->{rel};
		
		if ($map->{resource})
		{
			$value = $self->template_irisafe($map->{resource}, %row, '_' => $value);
		}
		$value = $self->iri($value, $lgraph);
	}
	
	elsif ($map->{property})
	{
		$predicate = $map->{property};
		
		if ($map->{content})
		{
			$value = $self->template($map->{content}, %row, '_' => $value);
		}
		
		if ($map->{lang})
		{
			$value = literal($value, $map->{lang});
		}
		else
		{
			if ($map->{datatype})
			{
				$value = literal($value, undef, $map->{datatype});
			}
			elsif (!defined $map->{content})
			{
				$value = $self->datatyped_literal($value, $types->{$column});
			}
			else
			{
				$value = literal($value);
			}
		}
	}
	
	if (defined $predicate and defined $value)
	{
		unless (ref $predicate)
		{
			$predicate = $self->template_irisafe($predicate, %row, '_' => $value);							
			$predicate = $self->iri($predicate, $lgraph) ;
		}
		
		my $lsubject = $self->iri($subject, $lgraph);
		if ($map->{about})
		{
			$lsubject = $self->iri($self->template_irisafe($map->{about}, %row), $lgraph);
		}

		my $st = $map->{rev}
			? statement($value, $predicate, $lsubject) 
			: statement($lsubject, $predicate, $value);
			
		if ($lgraph)
		{
			$callback->($st, $lgraph);
		}
		else
		{
			$callback->($st);
		}
	}
} # /sub handle_map
} # /scope for $parsers

sub process_turtle
{
	my ($self, $dbh, %options) = @_;

	my $rv;
	unless ($options{no_json})
	{
		my $json = $self->to_json(canonical=>1, pretty=>1);
		$json =~ s/^/# /gm;
		$json = "# MAPPING\n#\n${json}\n";
		$rv .= $json;
	}

	$rv .= $self->SUPER::process_turtle($dbh, namespaces => {$self->namespaces});
	$rv;
}

sub to_hashref
{
	my ($self) = @_;
	
	return {
		-namespaces => $self->_export( {$self->namespaces} ),
		%{ $self->_export( $self->mappings ) },
		};
}

*TO_JSON = \&to_hashref;

sub to_json
{
	my ($self, %opts) = (exists $_[1] and ref $_[1] eq 'HASH') ? ($_[0], %{ $_[1] }) : @_;
	$opts{convert_blessed} = 1;
	JSON::to_json($self, {%opts});
}

sub _export
{
	my ($self, $thingy) = @_;
	
	return undef unless defined $thingy;
	
	if (ref $thingy eq 'HASH' or (blessed($thingy) and $thingy->isa('RDF::Trine::NamespaceMap')))
	{
		my $hash = {};
		while (my ($k, $v) = each %$thingy)
		{
			$hash->{$k} = ref $v ? $self->_export($v) : $v;
		}
		return $hash;
	}

	if (ref $thingy eq 'ARRAY')
	{
		return [ map { ref $_ ? $self->_export($_) : $_ } @$thingy ];
	}
	
	if (blessed($thingy) and $thingy->isa('RDF::Trine::Node::Resource'))
	{
		return $self->mktemplate($thingy->uri);
	}

	if (blessed($thingy) and $thingy->isa('RDF::Trine::Node::BlankNode'))
	{
		return '_:'.$self->mktemplate($thingy->identifier);
	}

	if (blessed($thingy) and $thingy->isa('RDF::Trine::Node::Literal'))
	{
		warn "This shouldn't happen!";
		return $self->mktemplate($thingy->literal_value);
	}
	
	if (blessed($thingy) and $thingy->isa('RDF::Trine::Namespace'))
	{
		return $self->mktemplate($thingy->uri->uri);
	}
	
	warn "This shouldn't happen either!" if ref $thingy;
	return "$thingy";
}

1;

=head1 NAME

RDF::RDB2RDF::Simple - map relational database to RDF easily

=head1 SYNOPSIS

 my $mapper = RDF::RDB2RDF->new('Simple', %mappings, -namespaces => \%ns);
 print $mapper->process_turtle($dbh);

=head1 DESCRIPTION

This module makes it reasonably easy to dump a relational SQL database as
an RDF graph.

=head2 Constructor

=over 

=item * C<< RDF::RDB2RDF::Simple->new(%mappings [, -namespaces=>\%ns]) >>

=item * C<< RDF::RDB2RDF->new('Simple', %mappings [, -namespaces=>\%ns]) >>

The constructor takes a hash of mappings. (See MAPPINGS below.) You may also
pass a reference to a set of namespaces. This can be a hashref, or an
L<RDF::Trine::NamespaceMap>.

=back

=head2 Methods

=over

=item * C<< process($dbh [, $destination]) >>

Given a database handle, produces RDF data. Can optionally be passed a
destination for triples: either an existing model to add data to, or a
reference to a callback function.

Returns a L<RDF::Trine::Model>.

=item * C<< process_turtle($dbh, %options) >>

As per C<process>, but returns a string in Turtle format.

The mapping is included as a JSON comment at the top of the Turtle. Passing
C<< no_json => 1 >> can disable that feature.

Returns a string.

=item * C<< to_hashref >>

Creates a hashref of the mappings and namespaces, which can later be fed
back to the constructor to re-produce this object.

Returns a hashref.

=item * C<< to_json(%options) >>

Produces the JSON equivalent of C<to_hashref>. Any valid options for the
L<JSON> module's C<to_json> function can be passed.

Returns a string.

=item * C<< namespaces >>

The namespaces known about by the object.

Returns a hash.

=item * C<< mappings >>

The mappings.

Returns a hashref.

=back

=head1 MAPPINGS

It's best just to show you...

 use RDF::Trine::Namespace qw[rdf rdfs owl xsd];
 my $foaf = RDF::Trine::Namespace->new('http://xmlns.com/foaf/0.1/');
 my $bibo = RDF::Trine::Namespace->new('http://purl.org/ontology/bibo/');
 my $dc   = RDF::Trine::Namespace->new('http://purl.org/dc/terms/');
 my $skos = RDF::Trine::Namespace->new('http://www.w3.org/2004/02/skos/core#');

 my %simple_mapping = (
 
   -namespaces => {
     bibo  => "$bibo",
     dc    => "$dc",
     foaf  => "$foaf",
     rdfs  => "$rdfs",
     skos  => "$skos",
     },
 
   books => {
     about     => 'http://example.net/id/book/{book_id}',
     typeof    => [$bibo->Book],
     columns   => {
       title    => [{property => $rdfs->label, lang=>'en'},
                    {property => $dc->title, lang=>'en'}],
       turtle   => [{parse => 'Turtle'}],
       },
     },
 
   authors => {
     select    => "*, forename||' '||surname AS fullname",
     about     => 'http://example.net/id/author/{author_id}',
     typeof    => [$foaf->Person],
     columns   => {
       forename => [{property => $foaf->givenName}],
       surname  => [{property => $foaf->familyName}],
       fullname => [{property => $rdfs->label},
                    {property => $foaf->name}],
       turtle   => [{parse => 'Turtle'}],
       },
     },
 
   topics => {
     about     => 'http://example.net/id/topic/{topic_id}',
     typeof    => [$skos->Concept],
     columns   => {
       label    => [{property => $rdfs->label, lang=>'en'},
                    {property => $skos->prefLabel, lang=>'en'}],
       turtle   => [{parse => 'Turtle'}],
       },
     },
 
   book_authors => {
     about     => 'http://example.net/id/book/{book_id}',
     columns   => {
       author_id=> [{rel => $dc->creator,
                     resource => 'http://example.net/id/author/{author_id}'},
                    {rel => $foaf->maker,
                     resource => 'http://example.net/id/author/{author_id}'},
                    {rev => $foaf->made,
                     resource => 'http://example.net/id/author/{author_id}'},
                    {rel => $bibo->author,
                     resource => 'http://example.net/id/author/{author_id}'}],
       },
     },
 
   book_topics => {
     about     => ['http://example.net/id/book/{book_id}'],
     columns   => {
       topic_id => [{rel => $dc->subject,
                     resource => 'http://example.net/id/topic/{topic_id}'}],
       },
     },
   );
	
Looking at the "books" mapping alone for now, we see:

     about     => 'http://example.net/id/book/{book_id}',

This tells us that for each row of the "books" table in the database, generate
a subject URI using the template C<< http://example.net/id/book/{book_id} >>. Note 
that column names appearing in curly braces get substituted for the relevent
values.

Generating blank nodes is easy: either use a template along the lines of
C<< _:book{book_id} >> or simply omit the "about" line altogether.

     typeof    => [$bibo->Book],

This is a shorthand for assigning classes to the subject URI.

     columns   => {
       title    => [{property => $rdfs->label, lang=>'en'},
                    {property => $dc->title, lang=>'en'}],

This says to map the "title" column of the table to rdfs:label and dc:title.
These will be literals, with language tag "en".

       turtle   => [{parse => 'Turtle'}],
       },

This last bit is somewhat weird and experimental. If you have a varchar/text
column in your database that includes chunks of Turtle, these can be parsed
into the model too. They are parsed using the current namespace map, with
a base URI corresponding to the URI from "about".

In addition to the "about", "typeof" and "columns" options there are also
"select" and "from" options allowing you to fine tune exactly what data the
mapping is processing. And indeed, there is an "sql" option which overrides
both. An example of "select" is shown in the authors mapping above.

Note that within:

  {property => $dc->title, lang=>'en'}

there is a whole lot of interesting stuff going on. The object of the triple
here is a literal. If it were a URI, we'd do this:

  {rel => $dc->title}

Note that these correspond with the meanings of "property" and "rel" in RDFa.
Like RDFa, there is also "rev" which reverses the subject and object of the
triple. An example can be seen in the "book_authors" mapping above for
foaf:made.

For literals "lang" and "datatype" further qualify them.

Usually, the contents of the database field are used. For example:

     columns   => {
	    book_id   => [{ property => $dc->identifier }],
       },

However, sometimes you might want to slot the data from the database into
a template:

     columns   => {
	    book_id   => [{ property => $dc->identifier,
		                 content  => 'urn:example:book:{book_id}' }],
       },

In these cases, the column mapping key becomes pretty irrelevent. The following
will still work fine on the same database:

     columns   => {
	    foobar    => [{ property => $dc->identifier,
		                 content  => 'urn:example:book:{book_id}' }],
       },

When "rel" or "rev" are used (i.e. not "property"), then "resource" should be
used (i.e. not "content").

Pretty much anywhere where a URI or literal value is expected, you can either
give a string, or an L<RDF::Trine::Node>. In cases of strngs, they will be
interpolated as templates. L<RDF::Trine::Node>s are not interpolated.

=head1 SEE ALSO

L<RDF::Trine>, L<RDF::RDB2RDF>, L<RDF::RDB2RDF::R2RML>.

L<http://www.perlrdf.org/>.

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

