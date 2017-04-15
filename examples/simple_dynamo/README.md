# SimpleDynamo
To run this example, you need to ensure postgres is up and running. Inside psql, ensure there is a database named `simple_dynamo_db` with the following table:

```sql
CREATE TABLE weather (
  id        SERIAL,
  city      varchar(40),
  temp_lo   integer,
  temp_hi   integer,
  prcp      float
);

INSERT INTO weather (city, temp_lo, temp_hi, prcp) VALUES ('Jacksonville, FL', 32, 90, 16.5);
INSERT INTO weather (city, temp_lo, temp_hi, prcp) VALUES ('New York, NY', 27, 84, 7.2);
INSERT INTO weather (city, temp_lo, temp_hi, prcp) VALUES ('Chicago, IL', 10, 80, 7.1);
```

Then, from the command line:

* `mix deps.get`
* `mix server`

Inside web browser, navigate to:

* `localhost:4000`
