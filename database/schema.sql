CREATE DATABASE IF NOT EXISTS mailserver;
USE mailserver;
CREATE TABLE users (
  id INT NOT NULL AUTO_INCREMENT,
  username VARCHAR(255) NOT NULL,
  domain VARCHAR(255) NOT NULL,
  password VARCHAR(255) NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE virtual_alias_maps (
  id INT NOT NULL AUTO_INCREMENT,
  destination VARCHAR(255) NOT NULL,
  source VARCHAR(255) NOT NULL,
  PRIMARY KEY (id)
);

CREATE DATABASE `sogo` CHARACTER SET='utf8';
CREATE VIEW sogo.users AS SELECT CONCAT(username, '@', domain) AS c_uid, username AS c_name, password AS c_password, username AS c_cn, CONCAT(username, '@', domain) AS mail, domain AS domain FROM users;
