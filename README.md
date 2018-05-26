# Mailserver

This project is a mail server inside docker containers orchestrated by a simple docker-compose file. This is the implementation of this guide https://www.c0ffee.net/blog/mail-server-guide with some minor change in the technology choice. 

## Install
### 1. Tools
Install `docker` and `docker-compose`. See the [docker install documentation](https://docs.docker.com/install/) and [docker-compose install documentation](https://docs.docker.com/compose/install/).

### 2. Setup your DNS
Before you can do _anything_, you need to setup your DNS records properly.

First, choose a domain name. If you want `my-name@domain.com`, you need to register `domain.com`. You will also need to register a subdomain for your mail server such as `mail.domain.com`. When those two domains are registered, you will need to add records in them.

#### Records for _domain.com_
1. `MX` record pointing to your mail server domain (`mail.domain.com` in this example)

#### Records for _mail.domain.com_
1. `A` record pointing to the ip address of your mail server.
2. `TXT` with `"v=spf1 mx -all"`.
3. Reverse DNS entry for your mail server ip address. You will usually need to ask your DNS provider to add one for you.

### 3. Generate TLS certificate
Free certificate with [letsencrypt](https://letsencrypt.org/) will be used to generate the certificate. Connect on your server and run this command. This is a one time command only.

```
ssh my.mail.server.host
sudo -i
mkdir -p /etc/letsencrypt
docker run --rm \
    -p 80:80 \
    -p 443:443 \
    --name letsencrypt \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -e "LETSENCRYPT_EMAIL=dummy@domain.com" \
    -e "LETSENCRYPT_DOMAIN1=domain.com" \
    blacklabelops/letsencrypt install
```

Your certificate will be generated in your `/etc/letsencrypt` folder.

### 4. Boot the system
Copy this repository on your server and follow the instruction below. You may use git to clone this repository or use the release gzip version on the github page.

```
git clone url
cd url
export DOMAIN=my.domain.com
./install.sh
docker-compose up
```

### 5. Add users
When everything is up and running, add a user in maridb database. The command below add the email address `username@domain.com`. Without it, you will never be able to receive any emails.

```
docker exec -it composemailserver_mariadb_1 mysql -e "use mailserver; INSERT INTO users SET username=user, domain=domain.com,password=password;"
```
