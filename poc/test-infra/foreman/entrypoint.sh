#!/bin/bash
set -e

echo "Waiting for PostgreSQL..."
until PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c '\q'; do
  echo "PostgreSQL is unavailable - sleeping"
  sleep 2
done

echo "PostgreSQL is up - setting up Foreman"

cd /usr/share/foreman

# Initialize database if needed
if ! PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 FROM schema_migrations LIMIT 1" 2>/dev/null; then
  echo "Initializing database..."
  sudo -u foreman RAILS_ENV=production bundle exec rake db:migrate
  sudo -u foreman RAILS_ENV=production bundle exec rake db:seed

  # Create admin user
  echo "Creating admin user..."
  sudo -u foreman RAILS_ENV=production bundle exec rake permissions:reset \
    SEED_ADMIN_USER="${FOREMAN_ADMIN_USER:-admin}" \
    SEED_ADMIN_PASSWORD="${FOREMAN_ADMIN_PASSWORD:-changeme123}"
fi

echo "Starting Foreman..."
exec sudo -u foreman RAILS_ENV=production bundle exec rails server -b 0.0.0.0 -p 3000
