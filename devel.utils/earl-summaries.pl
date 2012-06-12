#! perl

use HTML::HTML5::Builder ':standard';
use PerlX::Perform;
use RDF::Query;
use RDF::RDB2RDF;
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
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?case ?db ?outcome ?info ?link
WHERE {
	?assert earl:test ?case .
	?assert earl:subject [ dc:hasPart [ doap:name ?db ] ] .
	?assert earl:result ?result .
	?result earl:outcome ?outcome .
	OPTIONAL { ?result earl:info ?info . }
	OPTIONAL { ?result rdfs:seeAlso ?link . }
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
	my $link             = perform { $_->uri } wherever $row->{link};
	
	$data{$case}{$db} = {
		outcome     => $outcome,
		info        => $info,
		link        => $link,
		case_uri    => $row->{case}->uri,
	};
}

my $version = RDF::RDB2RDF->VERSION;

print html(
	head(
		title("EARL Summaries for RDF-RDB2RDF $version"),
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
				table td a:link,
				table td a:visited {
					text-decoration: none;
					color: yellow;
					font-size: smaller;
					padding: 0.5em 0;
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
		h1("EARL Summaries for RDF-RDB2RDF $version"),
		p("The following table shows how RDF-RDB2RDF $version fares against the RDB2RDF working group test suite, with PostgreSQL and SQLite databases."),
		p("In most browsers, you should be able to hover over non-passing results to show a brief explanation. Some results have a question mark that can be clicked to reveal a relevant bug report. Clicking on the database column headings should take you to the full EARL report (in Turtle)."),
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
								(
									defined $r->{link}
										? (q[ ], a(-href => $r->{link}, '?'))
										: ()
								),
							)
						} qw(PostgreSQL SQLite)
					)
				} sort keys %data
			),
		),
	),
);
