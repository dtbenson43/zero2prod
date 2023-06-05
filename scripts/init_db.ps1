$ErrorActionPreference = 'Stop'

if (!(Get-Command 'psql' -ErrorAction SilentlyContinue)) {
    Write-Host "Error: psql is not installed."
    exit 1
}

if (!(Get-Command 'sqlx' -ErrorAction SilentlyContinue)) {
    Write-Host "Error: sqlx is not installed."
    Write-Host "Use:"
    Write-Host "    cargo install --version='~0.6' sqlx-cli --no-default-features --features rustls,postgres"
    Write-Host "to install it."
    exit 1
}

# Check if a custom user has been set, otherwise default to 'postgres'
$DB_USER = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { 'postgres' }
# Check if a custom password has been set, otherwise default to 'password'
$DB_PASSWORD = if ($env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD } else { 'password' }
# Check if a custom database name has been set, otherwise default to 'newsletter'
$DB_NAME = if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { 'newsletter' }
# Check if a custom port has been set, otherwise default to '5432'
$DB_PORT = if ($env:POSTGRES_PORT) { $env:POSTGRES_PORT } else { '5432' }
# Check if a custom host has been set, otherwise default to 'localhost'
$DB_HOST = if ($env:POSTGRES_HOST) { $env:POSTGRES_HOST } else { 'localhost' }

# Allow to skip Docker if a dockerized Postgres database is already running
if ([string]::IsNullOrEmpty($env:SKIP_DOCKER)) {
    # if a postgres container is running, print instructions to kill it and exit
    $RUNNING_POSTGRES_CONTAINER = docker ps --filter 'name=postgres' --format '{{.ID}}'
    if (![string]::IsNullOrEmpty($RUNNING_POSTGRES_CONTAINER)) {
        Write-Host "there is a postgres container already running, kill it with"
        Write-Host "    docker kill ${RUNNING_POSTGRES_CONTAINER}"
        exit 1
    }
    # Launch postgres using Docker
    docker run `
      -e POSTGRES_USER=$DB_USER `
      -e POSTGRES_PASSWORD=$DB_PASSWORD `
      -e POSTGRES_DB=$DB_NAME `
      -p "${DB_PORT}:5432" `
      -d `
      --name "postgres_$(Get-Date -UFormat '%s')" `
      postgres -N 1000
      # ^ Increased maximum number of connections for testing purposes
}

# Keep pinging Postgres until it's ready to accept commands
do {
    try {
        $env:PGPASSWORD=$DB_PASSWORD; psql -h $DB_HOST -U $DB_USER -p $DB_PORT -d "postgres" -c '\q'
        $ready = $true
    }
    catch {
        Write-Host "Postgres is still unavailable - sleeping"
        Start-Sleep -s 1
    }
} until ($ready -eq $true)

Write-Host "Postgres is up and running on port ${DB_PORT} - running migrations now!"

$env:DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
$env:DATABASE_URL
sqlx database create
sqlx migrate run

Write-Host "Postgres has been migrated, ready to go!"
