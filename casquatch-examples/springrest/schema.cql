CREATE KEYSPACE springrest WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'}  AND durable_writes = true;

CREATE TABLE springrest.table_name (
    key_one int,
    key_two int,
    col_one text,
    col_two text,
    PRIMARY KEY (key_one, key_two)
);