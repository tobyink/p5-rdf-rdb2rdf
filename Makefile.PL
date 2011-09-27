use strict;
use warnings;

use inc::Module::Install;

my $dist = 'RDF-RDB2RDF';
my $fn   = "lib/$dist.pm"; $fn =~ s#-#/#g;

name                $dist;
perl_version_from   $fn;
version_from        $fn;
abstract_from       $fn;
readme_from         $fn;
author              'Toby Inkster <tobyink@cpan.org>';
license             'perl';

requires            'Carp'               => 0;
requires            'common::sense'      => 0;
requires            'Data::UUID'         => 0;
test_requires       'DBD::SQLite'        => 0;
requires            'DBI'                => 0;
requires            'DBIx::Admin::TableInfo' => 0;
requires            'JSON'               => 0;
requires            'MIME::Base64'       => 0;
requires            'namespace::clean'   => 0;
requires            'RDF::Trine'         => '0.133';
requires            'Scalar::Util'       => 0;
requires            'Storable'           => 0;
test_requires       'Test::More'         => '0.61';
requires            'URI::Escape'        => 0;

resources(
	'homepage'   => "https://metacpan.org/release/$dist",
	'repository' => "http://goddamn.co.uk/svn-web/perlmods/browse/$dist/",
	'bugtracker' => "http://rt.cpan.org/Dist/Display.html?Queue=$dist",
	);

keywords(qw"Perl RDF Turtle R2RML RDB2RDF SQL Database");
	
write_doap_changes;
write_doap_changes_xml;

auto_install;
WriteAll(
	'meta' => 1,
	'sign' => 1,
	);
