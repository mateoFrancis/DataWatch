SET foreign_key_checks = 0;

source DataWatchDB.sql;

source procedures.sql;

Show procedure status where Db = 'datawatch';

Show tables;

--\! python3 /srv/shared/DataWatch/setup.py

SET foreign_key_checks = 1;
