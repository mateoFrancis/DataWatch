

import mariadb
import sys

from datetime import datetime
import pytz

def get_time():

    pst = pytz.timezone("America/Los_Angeles")
    now = datetime.now(pst)
    return now.replace(tzinfo=None, microsecond=0)


def get_connection():

    try:
        conn = mariadb.connect(

            user = "datawatch",
            password = "datawatch2025",
            host = "127.0.0.1", 
            port = 3306,        
            database = "datawatch"
        )
        return conn
    
    except mariadb.Error as e:
        print(f"Error connecting to MariaDB: {e}")
        sys.exit(1)


# stored procedures

def add_user(username, email, password_hash):

    conn = get_connection()

    try:
        cur = conn.cursor()
        created_at = get_time()
        cur.callproc("add_user", (username, email, password_hash, created_at))
        conn.commit()
    
    except mariadb.IntegrityError:
        print(f"User {username} or email {email} already exists.")
    
    finally:
        cur.close()
        conn.close()

    print(f"[add_user] Added user: {username} at {created_at}")


def add_data_source(name, type_, base_url):

    conn = get_connection()

    try:
        cur = conn.cursor()
        cur.callproc("add_data_source", (name, type_, base_url))
        conn.commit()
    finally:
        cur.close()
        conn.close()

    print(f"[add_data_source] Added source: {name}")



def add_location(city, country, lat, lon):

    conn = get_connection()
    
    try:
        cur = conn.cursor()
        cur.callproc("add_location", (city, country, lat, lon))
        conn.commit()
    finally:
        cur.close()
        conn.close()
    print(f"[add_location] Added location: {city}, {country}")


def log_api_call(source_id, user_id, call_type, status):
    conn = get_connection()
    call_id = None
    try:
        cur = conn.cursor()
        cur.callproc("log_api_call", (source_id, user_id, call_type, status))
        for result in cur:
            call_id = result[0]
            print(f"[log_api_call] New call_id = {call_id}")
        conn.commit()
    finally:
        cur.close()
        conn.close()
    return call_id


def insert_weather_data(source_id, location_id, user_id, temperature, humidity, wind_speed, recorded_at, call_id):
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.callproc("insert_weather_data", (source_id, location_id, user_id, temperature, humidity, wind_speed, recorded_at, call_id))
        for result in cur:
            print(f"[insert_weather_data] New weather_id = {result[0]}")
        conn.commit()
    finally:
        cur.close()
        conn.close()



# Testing procedures

if __name__ == "__main__":
    print("=== testing stored procedures ===")

    # add a user
    add_user("test_user", "test@gmail.com", "password123")

    # add a data source
   # add_data_source("TestSource", "weather", "https://api.example.com")
    
    print("=== Done testing ===")
