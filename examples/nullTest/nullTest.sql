create table CODES (
  ObjectProperty text,
  subPropertyOf  text,
  Concept        text,
  label          text
);
insert into CODES values("http://example.com/ontology/broaderGeneric", "http://www.w3.org/2004/02/skos/core#broader", null, "Broader Generic");
insert into CODES values("http://example.com/ontology/historicFlag", null, null, "Historic flag");
insert into CODES values(null, null, "http://example.com/thesaurus/historic/Current", "Current");
