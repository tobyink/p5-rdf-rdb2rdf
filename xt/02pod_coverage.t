use Test::More skip_all => 'We can but hope';
use Test::Pod::Coverage;

my @modules = qw(RDF::RDB2RDF RDF::RDB2RDF::DirectMapping RDF::RDB2RDF::Simple RDF::RDB2RDF::R2RML);
pod_coverage_ok($_, "$_ is covered")
	foreach @modules;
done_testing(scalar @modules);

