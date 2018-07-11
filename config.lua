local config = require('lapis.config')

config({'development', 'staging', 'production', 'test'}, {
    postgres = {
        host = os.getenv('DATABASE_URL') or '127.0.0.1:5432',
        user = os.getenv('DATABASE_USERNAME') or 'cloud',
        password = os.getenv('DATABASE_PASSWORD') or 'snap-cloud-password',
        database = os.getenv('DATABASE_NAME') or 'snapcloud'
    },
    session_name = 'snapsession',

    -- Change to the relative (or absolute) path of your disk storage
    -- directory.  Note that the user running Lapis needs to have
    -- read & write permissions to that path.
    store_path = 'store',

    -- for sending email
    mail_user = os.getenv('MAIL_SMTP_USER'),
    mail_password = os.getenv('MAIL_SMTP_PASSWORD'),
    mail_server = os.getenv('MAIL_SMTP_SERVER'),
    mail_from_name = "Snap!Cloud",
    mail_from = "postmaster@snap-cloud.cs10.org",
    mail_footer = "<br/><br/><p><small>Please do not reply to this email. This message was automatically generated by the Snap!Cloud. To contact an actual human being, please write to <a href='mailto:snap-support@bjc.berkeley.edu'>snap-support@bjc.berkeley.edu</a></small></p>",

    discourse_sso_secret = os.getenv('DISCOURSE_SSO_SECRET'),
    worker_connections = os.getenv('WORKER_CONNECTIONS') or 1024,

    hostname = os.getenv('HOSTNAME') or 'localhost',
    secondary_hostname = os.getenv('SECONDARY_HOSTNAME') or 'localhost'
})

config({'development', 'test'}, {
    use_daemon = 'off',
    site_name = 'dev | Snap Cloud',
    port = os.getenv('PORT') or 8080,
    dns_resolver = 'localhost',
    code_cache = 'off',
    num_workers = 1,
    log_directive = 'stderr notice',
    logging = {
        queries = true,
        requests = true
    },
    secret = os.getenv('SESSION_SECRET_BASE') or 'this is a secret',
    measure_performance = true,

    -- development needs no special SSL or cert config.
    primary_nginx_config = 'locations.conf',
    secondary_nginx_config = 'locations.conf'
})

config({'production', 'staging'}, {
    use_daemon = 'on',
    port = os.getenv('PORT') or 80,
    dns_resolver = '67.207.67.2 ipv6=off',

    secret = os.getenv('SESSION_SECRET_BASE'),
    code_cache = 'on',

    log_directive = 'logs/error.log warn',

    -- TODO: See if we can turn this on without a big hit
    measure_performance = false
})

config('production', {
    site_name = 'Snap Cloud',
    num_workers = 8,
    primary_nginx_config = 'berkeley-production.conf',
    secondary_nginx_config = 'cs10.org-production.conf'
})

config('staging', {
    site_name = 'staging | Snap Cloud',
    -- the staging server is a low-cpu server.
    num_workers = 2,
    primary_nginx_config = 'berkeley-staging.conf',
    secondary_nginx_config = 'cs10.org-staging.conf'
})
