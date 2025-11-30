

import mariadb  # DB connector
import sys
from datetime import datetime
import pytz  # timezone


def verify_login(data):
   return 0 










def get_time():

    pst = pytz.timezone("America/Los_Angeles")  # local time
    now = datetime.now(pst)

    return now.replace(tzinfo=None, microsecond=0)

def get_connection():
    
    try:
        conn = mariadb.connect(
            user="datawatch",       # user
            password="datawatch2025",  # password
            host="127.0.0.1",       # localhost
            port=3306,
            database="datawatch"    # db name
        )
        return conn
    
    except mariadb.Error as e:
        print(f"Error connecting to MariaDB: {e}")
        sys.exit(1)


#------------------------------#
#  ---- Stored procedures ---- #
#------------------------------#

def add_user(username, email, password_hash):

    conn = get_connection()  # open connection
   
    try:
        cur = conn.cursor()  # create cursor
        created_at = get_time()  # timestamp

        cur.callproc("add_user", (username, email, password_hash, created_at))  # call procedure
        conn.commit()  # commit changes
   
    except mariadb.IntegrityError:
        print(f"User {username} or email {email} already exists.")  # duplicate
   
    finally:
        cur.close()  # close cursor
        conn.close()  # close connection
   
    print(f"\n[add_user] Added user: {username} at {created_at}")


def add_data_source(name, type_, base_url, api_key):
    
    conn = get_connection()
    
    try:
        cur = conn.cursor()
        cur.callproc("add_data_source", (name, type_, base_url, api_key))
        conn.commit()
    
    finally:
        cur.close()
        conn.close()
    
    print(f"\n[add_data_source] Added source: {name}")


def add_location(city, country, lat, lon, zip_code):

    conn = get_connection()

    try:
        cur = conn.cursor()
        cur.callproc("add_location", (city, country, lat, lon, zip_code))  # call proc
        conn.commit()

    finally:
        cur.close()
        conn.close()

    print(f"\n[add_location] Added location: {city}, {country}, {zip_code}")


def log_api_call(source_id, user_id, call_type, status):
   
    conn = get_connection()
    call_id = None
    
   
    try:
        cur = conn.cursor()
        cur.execute("SET time_zone = '-08:00'")
        cur.callproc("log_api_call", (source_id, user_id, call_type, status))  # call proc
        
        # fetch result
        call_id = cur.fetchone()[0]  # get last insert id
        
        # clear remaining results
        while cur.nextset():
            pass
        
        conn.commit()
        print(f"\n[log_api_call] New call_id = {call_id}")
    
    finally:
        cur.close()
        conn.close()
    
    return call_id


def insert_weather_data(source_id, location_id, user_id, temperature, humidity, wind_speed, recorded_at, call_id):
    
    conn = get_connection()  
    weather_id = None
    
    try:
        cur = conn.cursor()  
        cur.execute("SET time_zone = '-08:00'")
        cur.callproc(
            "insert_weather_data",
            (source_id, location_id, user_id, temperature, humidity, wind_speed, recorded_at, call_id)
        ) 

        cur.execute("SELECT LAST_INSERT_ID()")
        row = cur.fetchone()
        
        if row:
            weather_id = row[0]

        conn.commit()
        #print(f"\n[insert_weather_data] New weather_id = {weather_id}")

    finally:
        cur.close()
        conn.close()  # close connection

    return weather_id


def insert_earthquake_data(source_id, location_id, user_id, magnitude, depth, recorded_at, call_id):
   
    conn = get_connection()
    earthquake_id = None
   
    try:
        cur = conn.cursor()
        cur.execute("SET time_zone = '-08:00'")
        cur.callproc(
            "insert_earthquake_data",
            (source_id, location_id, user_id, magnitude, depth, recorded_at, call_id)
        )

        cur.execute("SELECT LAST_INSERT_ID()")
        row = cur.fetchone()
   
        if row:
            earthquake_id = row[0]

        conn.commit()
        print(f"\n[insert_earthquake_data] New earthquake_id = {earthquake_id}")

    finally:
        cur.close()
        conn.close()

    return earthquake_id


def insert_earthquake_data(source_id, location_id, user_id, magnitude, depth, recorded_at, call_id):
    
    conn = get_connection()
    earthquake_id = None
    
    try:
        cur = conn.cursor()
        cur.execute("SET time_zone = '-08:00'")
        cur.callproc(
            "insert_earthquake_data",
            (source_id, location_id, user_id, magnitude, depth, recorded_at, call_id)
        )

        cur.execute("SELECT LAST_INSERT_ID()")
        row = cur.fetchone()
       
        if row:
            earthquake_id = row[0]

        conn.commit()
        print(f"\n[insert_earthquake_data] New earthquake_id = {earthquake_id}")

    finally:
        cur.close()
        conn.close()

    return earthquake_id


def log_weather_error(call_id, error_type, error_message):

    conn = get_connection()
    error_id = None

    try:
        cur = conn.cursor()
        cur.callproc("log_weather_error", (call_id, error_type, error_message))

        cur.execute("SELECT LAST_INSERT_ID()")
        row = cur.fetchone()

        if row:
            error_id = row[0]

        conn.commit()
        print(f"\n[log_weather_error] New error_id = {error_id}")

    finally:
        cur.close()
        conn.close()

    return error_id

def log_earthquake_error(call_id, error_type, error_message):
   
    conn = get_connection()
    error_id = None
   
    try:
        cur = conn.cursor()
        cur.callproc("log_earthquake_error", (call_id, error_type, error_message))

        cur.execute("SELECT LAST_INSERT_ID()")
        row = cur.fetchone()
   
        if row:
            error_id = row[0]

        conn.commit()
        print(f"\n[log_earthquake_error] New error_id = {error_id}")

    finally:
        cur.close()
        conn.close()

    return error_id


def log_dataflow(source_db, destination_db, table_name, record_count, user_id):
   
    conn = get_connection()
    flow_id = None
   
    try:
        cur = conn.cursor()
        cur.callproc("log_dataflow", (source_db, destination_db, table_name, record_count, user_id))

        cur.execute("SELECT LAST_INSERT_ID()")
        row = cur.fetchone()
   
        if row:
            flow_id = row[0]


        conn.commit()
        print(f"\n[log_dataflow] New flow_id = {flow_id}")

    finally:
        cur.close()
        conn.close()

    return flow_id


def update_api_call_status(call_id, status):
   
    conn = get_connection()
    affected = 0
   
    try:
        cur = conn.cursor()
        cur.callproc("update_api_call_status", (call_id, status))
        
        row = cur.fetchone()
        if row:
            affected = row[0]

        while cur.nextset():
            pass

        conn.commit()
        print(f"[update_api_call_status] Rows affected = {affected}")

    finally:
        cur.close()
        conn.close()

    return affected

def get_data_source_by_name(name):
   
    conn = get_connection()
    source = None

    try:

        cur = conn.cursor(dictionary=True)
        cur.execute("select * from data_sources where name = ?", (name,))
        source = cur.fetchone()

    finally:

        cur.close()
        conn.close()

    return source

def get_all_locations():

    conn = get_connection()
    locations = []

    try:

        cur = conn.cursor(dictionary=True)
        cur.execute("select * from locations")
        locations = cur.fetchall()
    
    finally:
        cur.close()
        conn.close()

    return locations



#------------------------------#
# ---- Testing procedures ---- #
#------------------------------#
if __name__ == "__main__":
    print("=== testing stored procedures ===\n")

    # add a user
    add_user("test_user", "test@gmail.com", "password123")
    
    # add location
    add_location("Los Angeles", "USA", 34.0239, -118.172, "90210")

    # add api source
    add_data_source("OpenWeather", "weather", "https://api.openweathermap.org/data/2.5/weather", "apikey_1234")

    # log api call and temporarily store latest call id for later usage
    call_id = log_api_call(1, 1, "weather", "pending") 
    print(f"Logged API call with call_id = {call_id}")

    
    # insert weather data
    weather_id = insert_weather_data(
        source_id = 1, # would remain the same based on the sources (weather or earthquake)
        location_id = 1, # stored before making the call
        user_id = 1, # would be received from the user currently logged in
        temperature = 72.5,
        humidity = 45.0,
        wind_speed = 5.2,
        recorded_at = None,  # let procedure default to NOW()
        call_id = call_id
    )

    # insert earthquake data
    earthquake_id = insert_earthquake_data(
        source_id = 1,
        location_id = 1,
        user_id = 1,
        magnitude = 4.5,
        depth = 10.2,
        recorded_at = None,
        call_id=call_id
    )
 
    # log weather error
    error_id = log_weather_error(
        call_id = call_id,
        error_type = "TemperatureError",
        error_message = "Temperature sensor returned N/A"
    )

    # log earthquake error
    error_id = log_earthquake_error(
        call_id = call_id,
        error_type = "MagnitudeError",
        error_message = "Magnitude value out of expected range"
    )

    # log sample dataflow
    flow_id = log_dataflow(
        source_db = "maria_db",
        destination_db = "mongo_db",
        table_name = "weather_data",
        record_count = 15, # number rows being transferred
        user_id = 1 # user making the transfer (necessary?)
    )

    # update status of api call based on temporarily stored call_id (most recent call)
    rows_updated = update_api_call_status(call_id, "success")

    print("=== Done testing ===")
