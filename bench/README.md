# Ecto Benchmarks

Ecto has a benchmark suite to track performance of sensitive operations. Benchmarks
are run using the [Benchee](https://github.com/PragTob/benchee) library and
need PostgreSQL and MySQL up and running.

To run the benchmarks tests just type in the console:

```
# POSIX-compatible shells
$ MIX_ENV=bench mix run bench/bench_helper.exs
```

```
# other shells
$ env MIX_ENV=bench mix run bench/bench_helper.exs
```

Benchmarks are inside the `scripts/` directory and are divided into two
categories:

* `micro benchmarks`: Operations that don't actually interface with the database,
but might need it up and running to start the Ecto agents and processes.

* `macro benchmarks`: Operations that are actually run in the database. This are
more likely to integration tests.

You can also run a benchmark individually by giving the path to the benchmark
script instead of `bench/bench_helper.exs`.