package RDF::RDB2RDF;

use 5.008;
use common::sense;

use RDF::RDB2RDF::Simple;
use RDF::RDB2RDF::R2RML;

our $VERSION = '0.002';

1;

=head1 NAME

RDF::RDB2RDF - map relational database to RDF declaratively

=head1 SYNOPSIS

 print RDF::RDB2RDF::R2RML->new($r2rml)->process_turtle($dbh);

=head1 DESCRIPTION

It's quite common to want to map legacy relational (SQL) data to RDF. This is
usually quite simple to do by looping through database tables and spitting out
triples. Nothing wrong with that; I've done that in the past, and that's what
RDF::RDB2RDF does under the hood.

But it's nice to be able to write your mapping declaratively. This distribution
provides two modules to enable that:

=over

=item * L<RDF::RDB2RDF::Simple> - map relational database to RDF easily

=item * L<RDF::RDB2RDF::R2RML> - map relational database to RDF using R2RML

=back

=head1 SEE ALSO

L<RDF::Trine>, L<RDF::RDB2RDF::Simple>, L<RDF::RDB2RDF::R2RML>.

L<http://perlrdf.org/>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2011 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
