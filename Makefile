.PHONY: help up down restart ps logs psql psql-bouncer psql-admin redis-cli seed reset stats test

# Default target
help:
	@echo "======================================================================"
	@echo "  Database Fundamentals (DB 101) Lab - Command Center"
	@echo "======================================================================"
	@echo "  make up                 Start Postgres, PgBouncer, and Redis in background"
	@echo "  make down               Stop all services"
	@echo "  make restart            Restart all services"
	@echo "  make ps                 Check container status and health"
	@echo "  make logs               Tail container logs"
	@echo "  ------------------------------------------------------------------"
	@echo "  make psql               Interactive psql direct to PostgreSQL (port 5432)"
	@echo "  make psql-bouncer       Interactive psql through PgBouncer (port 6432)"
	@echo "  make psql-admin         Interactive psql to PgBouncer admin console"
	@echo "  make redis-cli          Interactive redis-cli session"
	@echo "  ------------------------------------------------------------------"
	@echo "  make seed               Seed database with 400k+ realistic records"
	@echo "  make reset              Tear down volumes, recreate, and re-seed clean lab"
	@echo "  make stats              Show active connections, cache hit ratio & tables"
	@echo "  make test               Verify all services are responding healthy"
	@echo "======================================================================"

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

ps:
	docker compose ps

logs:
	docker compose logs -f

psql:
	docker compose exec -e PGPASSWORD=postgres_password postgres psql -U postgres -d db_fundamentals

psql-bouncer:
	docker compose exec -e PGPASSWORD=postgres_password postgres psql -h pgbouncer -p 5432 -U postgres -d db_fundamentals

psql-admin:
	docker compose exec -e PGPASSWORD=postgres_password postgres psql -h pgbouncer -p 5432 -U postgres -d pgbouncer

redis-cli:
	docker compose exec redis redis-cli -a redis_password

seed:
	@echo "==> Seeding database..."
	docker compose exec -T postgres psql -U postgres -d db_fundamentals -f /dev/stdin < scripts/seed_data.sql

reset:
	@echo "==> Wiping containers and data volumes..."
	docker compose down -v
	@echo "==> Starting fresh containers..."
	docker compose up -d
	@echo "==> Waiting for PostgreSQL to be healthy..."
	@until docker compose exec -T postgres pg_isready -U postgres -d db_fundamentals > /dev/null 2>&1; do sleep 1; done
	@echo "==> Seeding dataset..."
	$(MAKE) seed
	@echo "==> Lab reset successfully!"

test:
	@echo "==> Checking PostgreSQL direct connection..."
	@docker compose exec -T postgres psql -U postgres -d db_fundamentals -c "SELECT 'PostgreSQL 16 OK' AS postgres_check;"
	@echo "==> Checking PgBouncer connection..."
	@docker compose exec -T -e PGPASSWORD=postgres_password postgres psql -h pgbouncer -p 5432 -U postgres -d db_fundamentals -c "SELECT 'PgBouncer OK' AS pgbouncer_check;"
	@echo "==> Checking Redis connection..."
	@docker compose exec -T redis redis-cli -a redis_password ping
	@echo "==> All services OK!"

stats:
	@echo "-------------------- Active Connections --------------------"
	@docker compose exec -T postgres psql -U postgres -d db_fundamentals -c \
		"SELECT count(*) AS total_conns, state FROM pg_stat_activity GROUP BY state;"
	@echo "-------------------- Cache Hit Ratio -----------------------"
	@docker compose exec -T postgres psql -U postgres -d db_fundamentals -c \
		"SELECT sum(heap_blks_read) AS heap_read, sum(heap_blks_hit) AS heap_hit, \
		 round(sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read) + 0.0001) * 100, 2) AS ratio_pct \
		 FROM pg_statio_user_tables;"
	@echo "-------------------- Top Table Sizes -----------------------"
	@docker compose exec -T postgres psql -U postgres -d db_fundamentals -c \
		"SELECT relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) AS total_size \
		 FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 5;"
