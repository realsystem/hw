# Foreman Docker Build

Custom Foreman container image for development and testing.

## Components

- **Base**: Debian 12 (Bookworm)
- **Foreman**: Version 3.9 from official repositories
- **Database**: PostgreSQL 15 (separate container)
- **Configuration**: Production-ready settings

## Files

- `Dockerfile` - Container image definition
- `entrypoint.sh` - Startup script (database init, migrations, seed)
- `database.yml` - Database connection configuration
- `foreman-settings.yaml` - Foreman application settings

## Build Process

The Dockerfile:
1. Installs Foreman from official APT repository
2. Configures database connection via environment variables
3. Sets up required directories and permissions
4. Exposes ports 3000 (Web UI) and 8443 (Smart Proxy)

## Environment Variables

- `DB_HOST` - PostgreSQL hostname (default: postgres)
- `DB_PORT` - PostgreSQL port (default: 5432)
- `DB_NAME` - Database name (default: foreman)
- `DB_USER` - Database user (default: foreman)
- `DB_PASSWORD` - Database password (default: foreman123)
- `FOREMAN_ADMIN_USER` - Admin username (default: admin)
- `FOREMAN_ADMIN_PASSWORD` - Admin password (default: changeme123)

## First Run

On first startup, the entrypoint script:
1. Waits for PostgreSQL to be ready
2. Runs database migrations
3. Seeds initial data
4. Creates admin user
5. Starts Rails server

## Access

- Web UI: http://localhost:3000
- API: http://localhost:3000/api/v2
- Credentials: admin / changeme123

## Notes

- Built from official Foreman packages (not Docker-native)
- Suitable for testing and development
- For production, install Foreman directly on host (see FOREMAN_SETUP_GUIDE.md)
