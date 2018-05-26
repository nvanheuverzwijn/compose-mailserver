#!/bin/bash
cat > docker-compose.yml <<EOF
version: '3'
services:
  mariadb:
    image: mariadb
    ports:
      - "3306"
    volumes:
      - ./database/data/:/var/lib/mysql:rw
      - ./database/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro
    environment:
      MYSQL_ALLOW_EMPTY_PASSWORD: "yes"
  letsencrypt:
    image: blacklabelops/letsencrypt
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt
    environment:
      LETSENCRYPT_DOMAIN1: ${DOMAIN}
  dovecot:
    image: nvanheuverzwijn/dovecot
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /etc/ssl:/etc/ssl:ro
      - /var/mail:/var/mail:rw
    ports:
      - "12000:12000"
      - "12001:12001"
      - "110:110"
      - "143:143"
      - "993:993"
      - "995:995"
    environment:
      DOVECOT_DOVECOT_CONF: |
        protocols = imap lmtp
        first_valid_uid = 5000
        last_valid_uid = 5000
        !include conf.d/*.conf
        !include_try local.conf
      DOVECOT_DOVECOT_SQL_CONF_EXT: |
        driver = mysql
        connect = host=mariadb dbname=mailserver
        default_pass_scheme = plain
        password_query = SELECT CONCAT(username, '@', domain) AS user, password FROM users WHERE username = '%n' AND domain = '%d'
        iterate_query = SELECT username, domain AS user FROM users
      DOVECOT_10_AUTH: |
        auth_cache_size = 10M
        auth_cache_ttl = 1 hour
        auth_cache_negative_ttl = 1 hour
        auth_mechanisms = plain
        passdb {
          driver = sql
          args =/etc/dovecot/dovecot-sql.conf.ext
        }
        userdb {
          driver = static
          args = uid=vmail gid=vmail home=/var/mail/%d/%n
        }
      DOVECOT_10_MAIL: |
        mail_home = /var/mail/%d/%n
        mail_location = mdbox:~/mdbox
        namespace inbox {
          separator = /
          inbox = yes
        }
        mail_privileged_group = vmail
        mail_attachment_dir = /var/mail/attachments
        mail_attachment_min_size = 64k
      DOVECOT_10_MASTER: |
        mail_fsync = never
        service imap-login {
          inet_listener imap {
            address = 127.0.0.1
          }
          service_count = 0
          process_min_avail = 1
          vsz_limit = 256M
        }
        service pop3-login {
          inet_listener pop3 {
            port = 0
          }
          inet_listener pop3s {
            port = 0
          }
        }
        service imap {
          service_count = 256
          process_min_avail = 1
        }
        service lmtp {
         inet_listener lmtp {
           address = *
           port = 12001
          }
        }
        service auth {
          inet_listener authentication {
            address = *
            port = 12000
          }
        }
        service auth-worker {
          user = vmail
        }
      DOVECOT_10_SSL: |
        ssl = required
        ssl_cert = </etc/letsencrypt/live/${DOMAIN}/fullchain.pem
        ssl_key = </etc/letsencrypt/live/${DOMAIN}/privkey.pem
        ssl_dh_parameters_length = 2048
        ssl_protocols = !SSLv3 !TLSv1 !TLSv1.1 TLSv1.2
        ssl_cipher_list = ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256
        ssl_prefer_server_ciphers = yes
      DOVECOT_15_LDA: |
        protocol lda {
          mail_fsync = optimized
          mail_plugins = \$\$mail_plugins sieve
        }
      DOVECOT_15_MAILBOXES: |
        namespace inbox {
          mailbox Drafts {
            auto = subscribe
            special_use = \Drafts
          }
          mailbox Junk {
            auto = create
            special_use = \Junk
          }
          mailbox Trash {
            auto = create
            special_use = \Trash
          }
          mailbox Archive {
            auto = subscribe
            special_use = \Archive
          }
          mailbox Sent {
            auto = subscribe
            special_use = \Sent
          }
        }
      DOVECOT_20_IMAP: |
        imap_idle_notify_interval = 29 mins
        protocol imap {
          mail_max_userip_connections = 50
          mail_plugins = \$\$mail_plugins imap_sieve
        }
      DOVECOT_20_LMTP: |
        protocol lmtp {
          mail_fsync = optimized
          mail_plugins = \$\$mail_plugins sieve
        }
      DOVECOT_20_MANAGESIEVE: |
        protocols = \$\$protocols sieve
      DOVECOT_90_SIEVE: |
        plugin {
          sieve = file:~/sieve;active=~/.dovecot.sieve
          sieve_before = /etc/dovecot/sieve-before.d
          sieve_after  = /etc/dovecot/sieve-after.d
          recipient_delimiter = +
          sieve_quota_max_storage = 50M
        }

  postfix:
    image: nvanheuverzwijn/postfix
    ports:
      - "25:25"
      - "465:465"
      - "587:587"
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /etc/ssl:/etc/ssl:ro
    environment:
      POSTFIX_CONFIG_MAIN_CF: |
        compatibility_level = 2
        biff = no
        mail_spool_directory = /var/mail/local
        myhostname = ${DOMAIN}
        mydestination = ${DOMAIN}, localhost.${DOMAIN}, localhost
        myorigin = ${DOMAIN}
        disable_vrfy_command = yes
        strict_rfc821_envelopes = yes
        show_user_unknown_table_name = no
        message_size_limit = 51200000
        mailbox_size_limit = 51200000
        allow_percent_hack = no
        swap_bangpath = no
        recipient_delimiter = +
        smtpd_tls_cert_file = /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
        smtpd_tls_key_file = /etc/letsencrypt/live/${DOMAIN}/privkey.pem
        smtp_tls_CAfile=/etc/ssl/certs/ca-certificates.crt
        smtp_tls_security_level = may
        smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1, TLSv1.2
        smtpd_tls_mandatory_ciphers = high
        tls_high_cipherlist = ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256
        smtpd_tls_security_level = may
        tls_ssl_options = no_ticket, no_compression
        smtpd_tls_dh512_param_file  = /etc/ssl/dh512.pem
        smtpd_tls_dh1024_param_file = /etc/ssl/dh2048.pem
        smtpd_tls_session_cache_database = btree:\$\${data_directory}/smtpd_tlscache
        smtp_tls_session_cache_database  = btree:\$\${data_directory}/smtp_tlscache
        smtpd_sasl_auth_enable = yes
        smtpd_sasl_path = inet:dovecot:12000
        smtpd_sasl_type = dovecot
        smtpd_tls_auth_only = yes
        smtpd_sasl_security_options = noanonymous, noplaintext
        smtpd_sasl_tls_security_options = noanonymous
        smtpd_tls_received_header = yes
        smtpd_helo_required = yes
        smtpd_client_restrictions =
          permit_mynetworks,
          permit_sasl_authenticated,
          reject_unknown_reverse_client_hostname,
          reject_unauth_pipelining
        smtpd_helo_restrictions =
          permit_mynetworks,
          permit_sasl_authenticated,
          reject_invalid_helo_hostname,
          reject_non_fqdn_helo_hostname,
          reject_unauth_pipelining
        smtpd_sender_restrictions =
          permit_mynetworks,
          permit_sasl_authenticated,
          reject_non_fqdn_sender,
          reject_unknown_sender_domain,
          reject_unauth_pipelining
        smtpd_relay_restrictions =
          permit_mynetworks,
          permit_sasl_authenticated,
          reject_unauth_destination
        smtpd_recipient_restrictions =
          permit_mynetworks,
          permit_sasl_authenticated,
          reject_non_fqdn_recipient,
          reject_unknown_recipient_domain,
          reject_unauth_pipelining,
          reject_unverified_recipient
        smtpd_data_restrictions =
          permit_mynetworks,
          permit_sasl_authenticated,
          reject_multi_recipient_bounce,
          reject_unauth_pipelining
        virtual_transport = lmtp:dovecot:12001
        virtual_mailbox_domains = mysql:/etc/postfix/virtual_mailbox_domains.cf
        virtual_mailbox_maps = mysql:/etc/postfix/virtual_mailbox_maps.cf
        virtual_alias_maps = mysql:/etc/postfix/virtual_alias_maps.cf
      POSTFIX_CONFIG_MASTER_CF: |
        smtp      inet  n       -       y       -       -       smtpd
          -o smtpd_sasl_auth_enable=no
        submission inet n       -       n       -       -       smtpd
          -o smtpd_tls_security_level=encrypt
          -o tls_preempt_cipherlist=yes
        pickup    unix  n       -       y       60      1       pickup
        cleanup   unix  n       -       y       -       0       cleanup
        qmgr      unix  n       -       n       300     1       qmgr
        tlsmgr    unix  -       -       y       1000?   1       tlsmgr
        rewrite   unix  -       -       y       -       -       trivial-rewrite
        bounce    unix  -       -       y       -       0       bounce
        defer     unix  -       -       y       -       0       bounce
        trace     unix  -       -       y       -       0       bounce
        verify    unix  -       -       y       -       1       verify
        flush     unix  n       -       y       1000?   0       flush
        proxymap  unix  -       -       n       -       -       proxymap
        proxywrite unix -       -       n       -       1       proxymap
        smtp      unix  -       -       y       -       -       smtp
        relay     unix  -       -       y       -       -       smtp
        showq     unix  n       -       y       -       -       showq
        error     unix  -       -       y       -       -       error
        retry     unix  -       -       y       -       -       error
        discard   unix  -       -       y       -       -       discard
        local     unix  -       n       n       -       -       local
        virtual   unix  -       n       n       -       -       virtual
        lmtp      unix  -       -       y       -       -       lmtp
        anvil     unix  -       -       y       -       1       anvil
        scache    unix  -       -       y       -       1       scache
        maildrop  unix  -       n       n       -       -       pipe
          flags=DRhu user=vmail argv=/usr/bin/maildrop -d \$\${recipient}
        uucp      unix  -       n       n       -       -       pipe
          flags=Fqhu user=uucp argv=uux -r -n -z -a\$\$sender - \$\$nexthop!rmail (\$\$recipient)
        ifmail    unix  -       n       n       -       -       pipe
          flags=F user=ftn argv=/usr/lib/ifmail/ifmail -r \$\$nexthop (\$\$recipient)
        bsmtp     unix  -       n       n       -       -       pipe
          flags=Fq. user=bsmtp argv=/usr/lib/bsmtp/bsmtp -t\$\$nexthop -f\$\$sender \$\$recipient
        scalemail-backend unix  -       n       n       -       2       pipe
          flags=R user=scalemail argv=/usr/lib/scalemail/bin/scalemail-store \$\${nexthop} \$\${user} \$\${extension}
        mailman   unix  -       n       n       -       -       pipe
          flags=FR user=list argv=/usr/lib/mailman/bin/postfix-to-mailman.py
          \$\${nexthop} \$\${user}
      POSTFIX_VIRTUAL_MAILBOX_DOMAINS_CF: |
        user = root
        password =
        hosts = mariadb
        dbname = mailserver
        query = SELECT 1 FROM users WHERE domain = '%s'
      POSTFIX_VIRTUAL_MAILBOX_MAPS_CF: |
        user = root
        password = 
        hosts = mariadb
        dbname = mailserver
        query = SELECT 1 FROM users WHERE CONCAT(\`username\`, '@', \`domain\`) = '%s'
      POSTFIX_VIRTUAL_ALIAS_MAPS_CF: |
        user = root
        password = 
        hosts = mariadb
        dbname = mailserver
        query = SELECT destination FROM virtual_alias_maps WHERE source = '%s'
EOF
