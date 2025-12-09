from pymongo import MongoClient
from pymongo import errors
import sys
from datetime import datetime
import pytz

def get_time():

    pst = pytz.timezone("America/Los_Angeles")  # local time
    now = datetime.now(pst)

    return now.replace(tzinfo=None, microsecond=0)

def connect_db():
    client = MongoClient("mongodb+srv://fs2002_db_user:Oxidation87@datawatch.fnxzk83.mongodb.net/?appName=DataWatch")
    return client["DataWatch"]

def get_next_user_id(db):
    #auto increments the user id

    counter = db.counters.find_one_and_update(
        {"_id": "user_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def add_user(username, email, password_hash):
    db = connect_db()
    created_at = get_time()
    user_id = get_next_user_id(db)
    
    adduser = {
        "user_id": user_id,
        "username": username,
        "email": email,
        "password_hash": password_hash,
        "created_at": created_at
    }

    try:
        db.users.insert_one(adduser)
    except errors.DuplicateKeyError:
        print(f"[add_user] Username '{username}' or email '{email}' already exists.")
        return
    print(f"\n[add_user] Added user: '{username}' at '{created_at}'.")

def get_next_source_id(db):
    #auto increments the source id

    counter = db.counters.find_one_and_update(
        {"_id": "source_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def add_data_source(name, type_, base_url):

    db = connect_db()
    created_at = get_time()
    source_id = get_next_source_id(db)

    datasrc = {
        "source_id": source_id,
        "name": name,
        "type": type_,
        "base_url": base_url,
        "created_at": created_at
    }

    try:
        db.data_sources.insert_one(datasrc)
    except errors.DuplicateKeyError:
        print(f"[add_data_source] Source '{name}' already exists.")
        return
    print(f"\n[add_data_source] Added source: {name}")

def get_next_location_id(db):
    #auto increments the location id

    counter = db.counters.find_one_and_update(
        {"_id": "location_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def add_location(city, country, lat, lon, zip_code):

    db = connect_db()
    created_at = get_time()
    location_id = get_next_location_id(db)

    loc_doc = {
        "location_id": location_id,
        "city": city,
        "country": country,
        "lat": lat,
        "lon": lon,
        "zip_code": zip_code,
        "created_at": created_at
    }

    try:
        db.locations.insert_one(loc_doc)
        print(f"\n[add_location] Added location: '{city}', '{country}', '{zip_code}'.")
    except Exception as e:
        print(f"\n[add_location] Failed to add location: {e}")
        return None

def get_next_call_id(db):
    #auto increments the call id

    counter = db.counters.find_one_and_update(
        {"_id": "api_call_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def log_api_call(source_id, user_id, call_type, status):
    db = connect_db()
    call_id = get_next_call_id(db)

    log_api = {
        "call_id": call_id,
        "source_id": source_id,
        "user_id": user_id,
        "call_type": call_type,
        "status": status,
    }

    try: 
        db.api_calls.insert_one(log_api)
        print(f"\n[log_api_call] New call_id = '{call_id}'")    
    except Exception as e:
        print(f"\n[log_api_call] Failed to log api call: {e}")
        return None

    return call_id

def get_next_weather_id(db):
    # auto increments the weather id

    counter = db.counters.find_one_and_update(
        {"_id": "weather_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def insert_weather_data(source_id, location_id, user_id, temperature, humidity, wind_speed, recorded_at, call_id):
    db = connect_db()
    weather_id = get_next_weather_id(db)

    insert_wthr_data = {
        "weather_id": weather_id,
        "source_id": source_id,
        "location_id": location_id,
        "user_id": user_id,
        "temperature": temperature,
        "humidity": humidity,
        "wind_speed": wind_speed,
        "recorded_at": recorded_at,
        "call_id": call_id
    }

    try:
        db.weather_data.insert_one(insert_wthr_data)
    except Exception as e:
        print(f"\n[insert_weather_data] Failed to insert weather data: {e}")

    return weather_id 

def get_next_earthquake_id(db):
    #auto increments the call id

    counter = db.counters.find_one_and_update(
        {"_id": "earthquake_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def insert_earthquake_data(source_id, location_id, user_id, magnitude, depth, recorded_at, call_id):
    db = connect_db()
    earthquake_id = get_next_earthquake_id(db)
    
    insert_eq_data = {
        "earthquake_id": earthquake_id,
        "source_id": source_id,
        "location_id": location_id,
        "user_id": user_id,
        "magnitude": magnitude,
        "depth": depth,
        "recorded_at": recorded_at,
        "call_id": call_id

    }

    try:
        db.earthquake_data.insert_one(insert_eq_data)
    except Exception as e:
         print(f"\n[insert_weather_data] Failed to insert weather data: {e}")

    return earthquake_id

def get_next_weather_error_id(db):
    #auto increments the weather error id

    counter = db.counters.find_one_and_update(
        {"_id": "weather_error_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def log_weather_error(call_id, error_type, error_message):
    db = connect_db()
    weather_error_id = get_next_weather_error_id(db)
    
    weather_error = {
        "weather_error_id": weather_error_id,
        "call_id": call_id,
        "error_type": error_type,
        "error_message": error_message
    }

    try:
        db.weather_error_logs.insert_one(weather_error)
    except Exception as e:
        print(f"\n [log_weather_error] Failed to log weather error: {e}")
    
    return weather_error_id

def get_next_earthquake_error_id(db):
    #auto increments the error id

    counter = db.counters.find_one_and_update(
        {"_id": "earthquake_error_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def log_earthquake_error(call_id, error_type, error_message):
    db = connect_db()
    earthquake_error_id = get_next_earthquake_error_id(db)

    eq_error = {
        "earthquake_error_id": earthquake_error_id,
        "call_id": call_id,
        "error_type": error_type,
        "error_message": error_message
    }

    try:
        db.earthquake_error_logs.insert_one(eq_error)
    except Exception as e:
        print(f"\n [log_earthquake_error] Failed to log earthquake error: {e}")
    
    return earthquake_error_id


def get_next_flow_id(db):
    #auto increments the flow id

    counter = db.counters.find_one_and_update(
        {"_id": "flow_id"},
        {"$inc": {"value": 1}},
        upsert=True,
        return_document=True,
    )
    return counter["value"]

def log_dataflow(source_db, destination_db, table_name, record_count, user_id):
    db = connect_db()
    flow_id = get_next_flow_id(db)

    log_data_flow = {
        "flow_id": flow_id,
        "source_db": source_db,
        "destination_db": destination_db,
        "table_name": table_name,
        "record_count": record_count,
        "user_id": user_id
    }

    try:
        db.dataflow_logs.insert_one(log_data_flow)
    except Exception as e:
        print(f"\n[log_dataflow] Failed to log dataflow error: {e}")
    
    return flow_id

def update_api_call_status(call_id, status):
    db = connect_db()
    affected = 0

    try:
        result = db.api_calls.update_one(
            {"call_id": call_id},
            {"$set": {"status": status}}
        )
        affected = result.modified_count
        print(f"[update_api_call_status] Rows affected = {affected}")
    except Exception as e:
        print(f"\n[update_api_call_status] Failed to update API call status error: {e}")

    return affected

def get_data_source_by_name(name):
    db = connect_db()
    source = None

    try:
        source = db.data_sources.find_one({"name": name})
    except Exception as e:
        print(f"\n[get_data_source_by_name] Failed to get data source by name error: {e}")
    
    return source

def get_all_locations():
    db = connect_db()
    locations = []

    try:
        locations = list(db.locations.find())
    except Exception as e:
        print(f"\n[get_all_locations] Failed to get all locations error: {e}")
    
    return locations

def get_earthquake_rows(n):
    db = connect_db()
    rows = []

    try:
        rows = list(db.earthquake_data.find().sort("recorded_at", -1).limit(n))
    except Exception as e:
        print(f"\n[get_earthquake_rows] Failed to get earthquake rows error: {e}")
    
    return rows
def get_recent_earthquake_data(api_call_id):
    db = connect_db()
    earthquake_rows = []

    try:
        earthquake_rows = list(
            db.earthquake_data.find({"call_id": api_call_id}).sort("earthquake_id", 1)
        )
    except Exception as e:
        print(f"\n[get_recent_earthquake_data] Failed to get recent earthquake data error: {e}")

    return earthquake_rows
