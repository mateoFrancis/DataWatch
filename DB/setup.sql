SET foreign_key_checks = 0;

source DataWatchDB.sql;

source procedures.sql;

Show procedure status where Db = 'datawatch';

Show tables;

\! php ./public_html/Project_Jarf/tools.php

SET foreign_key_checks = 1;
