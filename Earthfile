all:
    BUILD +all-test
    BUILD +all-integration-test
    BUILD +lint


all-test:
    BUILD \
        --build-arg ELIXIR_BASE=1.11.0-erlang-23.1.1-alpine-3.13.1 \
        --build-arg ELIXIR_BASE=1.11.0-erlang-21.3.8.21-alpine-3.13.1 \
        --build-arg ELIXIR_BASE=1.10.4-erlang-21.3.8.24-alpine-3.13.3 \
        +test


test:
    FROM +setup-base
    COPY mix.exs mix.lock .formatter.exs ./
    RUN mix deps.get

    RUN MIX_ENV=test mix deps.compile
    COPY --dir lib integration_test examples test ./

    RUN mix deps.get --only test
    RUN mix deps.compile
    RUN mix test


lint:
    FROM +test
    RUN mix deps.get
    RUN mix deps.unlock --check-unused
    RUN mix compile --warnings-as-errors


all-integration-test:
    BUILD \
        --build-arg ELIXIR_BASE=1.11.0-erlang-23.1.1-alpine-3.13.1 \
        --build-arg ELIXIR_BASE=1.11.0-erlang-21.3.8.21-alpine-3.13.1 \
        +integration-test


setup-base:
    ARG ELIXIR_BASE=1.11.0-erlang-23.1.1-alpine-3.13.1
    FROM hexpm/elixir:$ELIXIR_BASE
    RUN apk add --no-progress --update git build-base
    RUN mix local.rebar --force
    RUN mix local.hex --force
    ENV ELIXIR_ASSERT_TIMEOUT=10000
    WORKDIR /src/ecto


integration-test-base:
    FROM +setup-base
    RUN apk add --no-progress --update docker docker-compose git postgresql-client mysql-client

    RUN apk add --no-cache curl gnupg --virtual .build-dependencies -- && \
        curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/msodbcsql17_17.5.2.1-1_amd64.apk && \
        curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/mssql-tools_17.5.2.1-1_amd64.apk && \
        echo y | apk add --allow-untrusted msodbcsql17_17.5.2.1-1_amd64.apk mssql-tools_17.5.2.1-1_amd64.apk && \
        apk del .build-dependencies && rm -f msodbcsql*.sig mssql-tools*.apk
    ENV PATH="/opt/mssql-tools/bin:${PATH}"

    GIT CLONE https://github.com/elixir-ecto/ecto_sql.git /src/ecto_sql
    WORKDIR /src/ecto_sql
    RUN mix deps.get


integration-test:
    FROM +integration-test-base
    WORKDIR /src/ecto
    COPY mix.exs mix.lock .formatter.exs ./
    RUN mix deps.get

    COPY --dir lib integration_test examples test ./
    RUN mix test

    WORKDIR /src/ecto_sql

    ARG PG_IMG="postgres:11.11"
    ARG MCR_IMG="mcr.microsoft.com/mssql/server:2017-latest"
    ARG MYSQL_IMG="mysql:5.7"

    # then run the tests
    WITH DOCKER --pull "$PG_IMG" --pull "$MCR_IMG" --pull "$MYSQL_IMG"
        RUN set -e; \
            timeout=$(expr $(date +%s) + 60); \

            # start databases
            docker run --name mssql --network=host -d -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=some!Password' "$MCR_IMG"; \
            docker run --name pg --network=host -d -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=postgres "$PG_IMG"; \
            docker run --name mysql --network=host -d -e MYSQL_ROOT_PASSWORD=root "$MYSQL_IMG"; \

            # wait for mssql to start
            while ! sqlcmd -S tcp:127.0.0.1,1433 -U sa -P 'some!Password' -Q "SELECT 1" >/dev/null 2>&1; do \
                test "$(date +%s)" -le "$timeout" || (echo "timed out waiting for mysql"; exit 1); \
                echo "waiting for mssql"; \
                sleep 1; \
            done; \

            # wait for postgres to start
            while ! pg_isready --host=127.0.0.1 --port=5432 --quiet; do \
                test "$(date +%s)" -le "$timeout" || (echo "timed out waiting for postgres"; exit 1); \
                echo "waiting for postgres"; \
                sleep 1; \
            done; \

            # wait for mysql to start
            while ! mysqladmin ping --host=127.0.0.1 --port=3306 --protocol=TCP --silent; do \
                test "$(date +%s)" -le "$timeout" || (echo "timed out waiting for mysql"; exit 1); \
                echo "waiting for mysql"; \
                sleep 1; \
            done; \

            # run test
            MSSQL_URL='sa:some!Password@127.0.0.1' MYSQL_URL='root:root@127.0.0.1' PG_URL='postgres:postgres@127.0.0.1' ECTO_PATH='/src/ecto' mix test.all;
    END
