alter table books add column title_lang TEXT;
update books set title="Cooking provincial français" where book_id=1;
update books set title_lang="fr" where book_id=1;
update books set title="Cibo Italiano" where book_id=2;
update books set title_lang="it" where book_id=2;
