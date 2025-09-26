

DROP TABLE IF EXISTS `dataflow_logs`;
DROP TABLE IF EXISTS `weather_error_logs`;
DROP TABLE IF EXISTS `earthquake_error_logs`;
DROP TABLE IF EXISTS `weather_data`;
DROP TABLE IF EXISTS `earthquake_data`;
DROP TABLE IF EXISTS `api_calls`;
DROP TABLE IF EXISTS `locations`;
DROP TABLE IF EXISTS `data_sources`;
DROP TABLE IF EXISTS `users`;

CREATE TABLE `users` (
  `user_id` int PRIMARY KEY AUTO_INCREMENT,
  `username` varchar(255),
  `email` varchar(255),
  `password_hash` varchar(255),
  `created_at` datetime
);

CREATE TABLE `data_sources` (
  `source_id` int PRIMARY KEY AUTO_INCREMENT,
  `name` varchar(255),
  `type` varchar(255),
  `base_url` varchar(255),
  `created_at` datetime
);

CREATE TABLE `api_calls` (
  `call_id` int PRIMARY KEY AUTO_INCREMENT,
  `source_id` int,
  `user_id` int,
  `call_type` varchar(255),
  `status` varchar(255),
  `timestamp` datetime
);

CREATE TABLE `locations` (
  `location_id` int PRIMARY KEY AUTO_INCREMENT,
  `city` varchar(255),
  `country` varchar(255),
  `lat` float,
  `lon` float
);

CREATE TABLE `weather_data` (
  `weather_id` int PRIMARY KEY AUTO_INCREMENT,
  `source_id` int,
  `location_id` int,
  `user_id` int,
  `temperature` float,
  `humidity` float,
  `wind_speed` float,
  `recorded_at` datetime
);

CREATE TABLE `earthquake_data` (
  `earthquake_id` int PRIMARY KEY AUTO_INCREMENT,
  `source_id` int,
  `location_id` int,
  `user_id` int,
  `magnitude` float,
  `depth` float,
  `recorded_at` datetime
);

CREATE TABLE `weather_error_logs` (
  `error_id` int PRIMARY KEY AUTO_INCREMENT,
  `call_id` int,
  `error_type` varchar(255),
  `error_message` text,
  `timestamp` datetime
);

CREATE TABLE `earthquake_error_logs` (
  `error_id` int PRIMARY KEY AUTO_INCREMENT,
  `call_id` int,
  `error_type` varchar(255),
  `error_message` text,
  `timestamp` datetime
);

CREATE TABLE `dataflow_logs` (
  `flow_id` int PRIMARY KEY AUTO_INCREMENT,
  `source_db` varchar(255),
  `destination_db` varchar(255),
  `table_name` varchar(255),
  `record_count` int,
  `transfer_time` datetime,
  `user_id` int
);

ALTER TABLE `api_calls` ADD FOREIGN KEY (`source_id`) REFERENCES `data_sources` (`source_id`);

ALTER TABLE `api_calls` ADD FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`);

ALTER TABLE `weather_data` ADD FOREIGN KEY (`source_id`) REFERENCES `data_sources` (`source_id`);

ALTER TABLE `weather_data` ADD FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`);

ALTER TABLE `weather_data` ADD FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`);

ALTER TABLE `earthquake_data` ADD FOREIGN KEY (`source_id`) REFERENCES `data_sources` (`source_id`);

ALTER TABLE `earthquake_data` ADD FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`);

ALTER TABLE `earthquake_data` ADD FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`);

ALTER TABLE `weather_error_logs` ADD FOREIGN KEY (`call_id`) REFERENCES `api_calls` (`call_id`);

ALTER TABLE `earthquake_error_logs` ADD FOREIGN KEY (`call_id`) REFERENCES `api_calls` (`call_id`);

ALTER TABLE `dataflow_logs` ADD FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`);
