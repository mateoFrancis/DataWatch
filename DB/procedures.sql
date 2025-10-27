

DELIMITER //

-- Add User --

DROP PROCEDURE IF EXISTS add_user;
CREATE PROCEDURE add_user (
    IN p_username VARCHAR(255),
    IN p_email VARCHAR(255),
    IN p_password_hash VARCHAR(255),
    IN P_created_at DATETIME
)
BEGIN
    INSERT INTO users (username, email, password_hash, created_at)
    VALUES (p_username, p_email, p_password_hash, P_created_at);
END //


-- Add Data Source --

DROP PROCEDURE IF EXISTS add_data_source;
CREATE PROCEDURE add_data_source (
    IN p_name VARCHAR(255),
    IN p_type VARCHAR(255),
    IN p_base_url VARCHAR(255)
)
BEGIN
    INSERT INTO data_sources (name, type, base_url, created_at)
    VALUES (p_name, p_type, p_base_url, NOW());
END //


-- Add Location --

DROP PROCEDURE IF EXISTS add_location;
CREATE PROCEDURE add_location (
    IN p_city VARCHAR(255),
    IN p_country VARCHAR(255),
    IN p_lat FLOAT,
    IN p_lon FLOAT
)
BEGIN
    INSERT INTO locations (city, country, lat, lon)
    VALUES (p_city, p_country, p_lat, p_lon);
END //


-- Log API Call--

DROP PROCEDURE IF EXISTS log_api_call;
CREATE PROCEDURE log_api_call (
    IN p_source_id INT,
    IN p_user_id INT,
    IN p_call_type VARCHAR(50),
    IN p_status VARCHAR(50)
)
BEGIN
    INSERT INTO api_calls (source_id, user_id, call_type, status, timestamp)
    VALUES (p_source_id, p_user_id, p_call_type, IFNULL(p_status,'pending'), NOW());
    SELECT LAST_INSERT_ID() AS call_id;
END //


-- Insert Weather Data --

DROP PROCEDURE IF EXISTS insert_weather_data;
CREATE PROCEDURE insert_weather_data (
    IN p_source_id INT,
    IN p_location_id INT,
    IN p_user_id INT,
    IN p_temperature FLOAT,
    IN p_humidity FLOAT,
    IN p_wind_speed FLOAT,
    IN p_recorded_at DATETIME,
    IN p_call_id INT
)
BEGIN
    INSERT INTO weather_data (source_id, location_id, user_id, temperature, humidity, wind_speed, recorded_at)
    VALUES (p_source_id, p_location_id, p_user_id, p_temperature, p_humidity, p_wind_speed, IFNULL(p_recorded_at, NOW()));
    SELECT LAST_INSERT_ID() AS weather_id;

    IF p_call_id IS NOT NULL THEN
        UPDATE api_calls
          SET status = 'success', timestamp = NOW()
          WHERE call_id = p_call_id;
    END IF;
END //


-- Insert Eearthquake Data --

DROP PROCEDURE IF EXISTS insert_earthquake_data;
CREATE PROCEDURE insert_earthquake_data (
    IN p_source_id INT,
    IN p_location_id INT,
    IN p_user_id INT,
    IN p_magnitude FLOAT,
    IN p_depth FLOAT,
    IN p_recorded_at DATETIME,
    IN p_call_id INT
)
BEGIN
    INSERT INTO earthquake_data (source_id, location_id, user_id, magnitude, depth, recorded_at)
    VALUES (p_source_id, p_location_id, p_user_id, p_magnitude, p_depth, IFNULL(p_recorded_at, NOW()));
    SELECT LAST_INSERT_ID() AS earthquake_id;

    IF p_call_id IS NOT NULL THEN
        UPDATE api_calls
          SET status = 'success', timestamp = NOW()
          WHERE call_id = p_call_id;
    END IF;
END //


-- Log Weather Err --

DROP PROCEDURE IF EXISTS log_weather_error;
CREATE PROCEDURE log_weather_error (
    IN p_call_id INT,
    IN p_error_type VARCHAR(255),
    IN p_error_message TEXT
)
BEGIN
    INSERT INTO weather_error_logs (call_id, error_type, error_message, timestamp)
    VALUES (p_call_id, p_error_type, p_error_message, NOW());
    SELECT LAST_INSERT_ID() AS error_id;

    IF p_call_id IS NOT NULL THEN
        UPDATE api_calls
          SET status = 'failed', timestamp = NOW()
          WHERE call_id = p_call_id;
    END IF;
END //


-- Log Earthquake Err --

DROP PROCEDURE IF EXISTS log_earthquake_error;
CREATE PROCEDURE log_earthquake_error (
    IN p_call_id INT,
    IN p_error_type VARCHAR(255),
    IN p_error_message TEXT
)
BEGIN
    INSERT INTO earthquake_error_logs (call_id, error_type, error_message, timestamp)
    VALUES (p_call_id, p_error_type, p_error_message, NOW());
    SELECT LAST_INSERT_ID() AS error_id;

    IF p_call_id IS NOT NULL THEN
        UPDATE api_calls
          SET status = 'failed', timestamp = NOW()
          WHERE call_id = p_call_id;
    END IF;
END //


-- Log Dataflow --

DROP PROCEDURE IF EXISTS log_dataflow;
CREATE PROCEDURE log_dataflow (
    IN p_source_db VARCHAR(255),
    IN p_destination_db VARCHAR(255),
    IN p_table_name VARCHAR(255),
    IN p_record_count INT,
    IN p_user_id INT
)
BEGIN
    INSERT INTO dataflow_logs (source_db, destination_db, table_name, record_count, transfer_time, user_id)
    VALUES (p_source_db, p_destination_db, p_table_name, p_record_count, NOW(), p_user_id);
    SELECT LAST_INSERT_ID() AS flow_id;
END //


-- Update API Call Status --

DROP PROCEDURE IF EXISTS update_api_call_status;
CREATE PROCEDURE update_api_call_status (
    IN p_call_id INT,
    IN p_status VARCHAR(50)
)
BEGIN
    IF p_call_id IS NULL THEN
        SELECT 0 AS affected;
    ELSE
        UPDATE api_calls
          SET status = p_status, timestamp = NOW()
          WHERE call_id = p_call_id;
        SELECT ROW_COUNT() AS affected;
    END IF;
END //

DELIMITER ;
