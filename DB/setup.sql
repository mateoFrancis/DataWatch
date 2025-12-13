SET foreign_key_checks = 0;

source DB/DataWatchDB.sql;
source DB/procedures.sql;

SHOW PROCEDURE STATUS WHERE Db = 'datawatch';
SHOW TABLES;

\! python3 setup.py

SET foreign_key_checks = 1;
