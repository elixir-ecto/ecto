# Ecto Benchmarks

Ecto has a benchmark suite to track performance of sensitive operations. Benchmarks
are run using the [Benchee](https://github.com/PragTob/benchee) library and
need `Postgres` and `MySQL` up and running.

To run the benchmarks tests just type in the console:

```
# POSIX-compatible shells
$ BENCHMARKS_OUTPUT_PATH=bench/results mix run bench/bench_helper.exs
```

```
# other shells
$ env BENCHMARKS_OUTPUT_PATH=bench/results mix run bench/bench_helper.exs
```

Benchmarks are inside the benchmarks/ directory and are divided into two
categories:

`micro benchmarks`: Operations that don't actually interface with the database,
but might need it up and running to start the Ecto agents and processes.

`macro benchmarks`: Operations that are actually run in the database. This are
more likely to integration tests.

Ecto benchmarks will (soon) be automatically run by the [ElixirBench](http://elixirbench.org)
service.
