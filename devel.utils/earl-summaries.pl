#! perl

use HTML::HTML5::Builder ':standard';
use PerlX::Perform;
use RDF::Query;
use RDF::TrineX::Functions -all;

my $model = model();

parse 'meta/earl/with-sqlite.ttl',
	as   => 'Turtle',
	into => $model,
	base => 'http://example.net/';

parse 'meta/earl/with-postgres.ttl',
	as   => 'Turtle',
	into => $model,
	base => 'http://example.net/';

my $query = RDF::Query->new(<<'SPARQL');
PREFIX dc:   <http://purl.org/dc/terms/>
PREFIX doap: <http://usefulinc.com/ns/doap#>
PREFIX earl: <http://www.w3.org/ns/earl#>
SELECT ?case ?db ?outcome ?info
WHERE {
	?assert earl:test ?case .
	?assert earl:subject [ dc:hasPart [ doap:name ?db ] ] .
	?assert earl:result ?result .
	?result earl:outcome ?outcome .
	OPTIONAL {
		?result earl:info ?info .
	}
}
SPARQL

my %data;
my $results = $query->execute($model);
while (my $row = $results->next)
{
	my (undef, $case)    = $row->{case}->qname;
	my $db               = $row->{db}->literal_value;
	my (undef, $outcome) = $row->{outcome}->qname;
	my $info             = perform { $_->literal_value } wherever $row->{info};
	
	$data{$case}{$db} = {
		outcome     => $outcome,
		info        => $info,
		case_uri    => $row->{case}->uri,
	};
}

print html(
	head(
		title('EARL Summaries for RDF-RDB2RDF'),
		style(
			-type => 'text/css',
			q{
				table th {
					color: white;
					background: #666;
					text-align: center;
					width: 10em;
					padding: 0.33em;
				}
				table tbody th {
					text-align: left;
				}
				table th a:link,
				table th a:visited {
					text-decoration: none;
					color: white;
				}
				table td {
					color: white;
					background: #009;
					text-align: center;
				}
				table td.passed {
					color: white;
					background: #090;
				}
				table td.failed {
					color: white;
					background: #900;
				}
			},
		),
	),
	body(
		h1('EARL Summaries for RDF-RDB2RDF'),
		table(
			thead(
				&tr(
					th('Test Case'),
					th(a(-href => 'with-postgres.ttl', 'PostgreSQL')),
					th(a(-href => 'with-sqlite.ttl', 'SQLite')),
				),
			),
			tbody(
				map {
					my $case = $_;
					&tr(
						th(a(-href => $data{$case}{SQLite}{case_uri}, $case)),
						map {
							my $r = $data{$case}{$_};
							td(
								-class => $r->{outcome},
								-title => $r->{info},
								$r->{outcome},
							)
						} qw(PostgreSQL SQLite)
					)
				} sort keys %data
			),
		),
	),
);
