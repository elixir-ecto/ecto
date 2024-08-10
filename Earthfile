VERSION 0.6

all:
    BUILD \
        --build-arg ELIXIR_BASE=1.15.6-erlang-25.3.2.6-alpine-3.18.4 \
        --build-arg ELIXIR_BASE=1.15.6-erlang-24.3.4.14-alpine-3.18.4 \
        +integration-test

integration-test-base:
    ARG ELIXIR_BASE=1.15.6-erlang-25.3.2.6-alpine-3.18.4
    ARG TARGETARCH
    FROM hexpm/elixir:$ELIXIR_BASE
    RUN apk add --no-progress --update git build-base
    RUN mix local.rebar --force
    RUN mix local.hex --force
    ENV ELIXIR_ASSERT_TIMEOUT=10000
    WORKDIR /src/ecto
    RUN apk add --no-progress --update docker docker-compose git postgresql-client mysql-client

    RUN apk add --no-cache curl gnupg --virtual .build-dependencies -- && \
        curl -O https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/msodbcsql18_18.3.2.1-1_${TARGETARCH}.apk && \
        curl -O https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/mssql-tools18_18.3.1.1-1_${TARGETARCH}.apk && \
        echo y | apk add --allow-untrusted msodbcsql18_18.3.2.1-1_${TARGETARCH}.apk mssql-tools18_18.3.1.1-1_${TARGETARCH}.apk && \
        apk del .build-dependencies && rm -f msodbcsql*.sig mssql-tools*.apk
    ENV PATH="/opt/mssql-tools18/bin:${PATH}"

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
    WITH DOCKER --pull "$PG_IMG" --pull "$MCR_IMG" --pull "$MYSQL_IMG" --platform linux/amd64
        RUN set -e; \
            timeout=$(expr $(date +%s) + 60); \

            # start databases
            docker run --name mssql --network=host -d -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=some!Password' "$MCR_IMG"; \
            docker run --name pg --network=host -d -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=postgres "$PG_IMG"; \
            docker run --name mysql --network=host -d -e MYSQL_ROOT_PASSWORD=root "$MYSQL_IMG"; \

            # wait for mssql to start
            while ! sqlcmd -C -S tcp:127.0.0.1,1433 -U sa -P 'some!Password' -Q "SELECT 1" >/dev/null 2>&1; do \
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
