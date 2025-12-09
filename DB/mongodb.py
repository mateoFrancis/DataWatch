from pymongo import MongoClient
from pymongo.errors import WriteError, CollectionInvalid, OperationFailure
from datetime import datetime

client = MongoClient("mongodb+srv://fs2002_db_user:Oxidation87@datawatch.fnxzk83.mongodb.net/?appName=DataWatch")
db = client["DataWatch"]

# Define the JSON schema
earthquake_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["earthquake_id",  "source_id", "location_id", "user_id", "magnitude", "depth", "recorded_at"],
            "properties": {
                "earthquake_id": {
                    "bsonType": "int"
                },
                "source_id": {
                    "bsonType": "int"
                },
                "location_id": {
                    "bsonType": "int"
                },
                "user_id": {
                    "bsonType": "int"
                },
                "magnitude": {
                    "bsonType": "double"
                },
                "depth": {
                    "bsonType": "double"
                },
                "recorded_at": {
                    "bsonType": "date"
                }

            }
        }
    }
}

weather_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["weather_id", "source_id", "location_id", "user_id", "temperature", "humidity",
                          "wind_speed","recorded_at"],
            "properties": {
                "weather_id": {
                    "bsonType": "int"
                },
                "source_id": {
                    "bsonType": "int"
                },
                "location_id": {
                    "bsonType": "int"
                },
                "user_id": {
                    "bsonType": "int"
                },
                "temperature": {
                    "bsonType": "double"
                },
                "humidity": {
                    "bsonType": "double"
                },
                "wind_speed": {
                    "bsonType": "double"
                },
                "recorded_at": {
                    "bsonType": "date"
                }

            }
        }
    }
}

locations_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": [ "location_id", "city", "country", "lat", "lon"],
            "properties": {
                "location_id": {
                    "bsonType": "int"
                },
                "city": {
                    "bsonType": "string"
                },
                "country": {
                    "bsonType": "string"
                },
                "lat": {
                    "bsonType": "double"
                },
                "lon": {
                    "bsonType": "double"
                },
                "zip_code": {
                    "bsonType": "string"
                }
            }
        }
    }
}

data_sources_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["source_id", "name", "type", "base_url", "created_at"],
            "properties": {
                "source_id": {
                    "bsonType": "int"
                },
                "name": {
                    "bsonType": "string"
                },
                "type": {
                    "bsonType": "string"
                },
                "base_url": {
                    "bsonType": "string"
                },
                "created_at": {
                    "bsonType": "date"
                }

            }
        }
    }
}


api_calls_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["call_id", "source_id", "user_id", "call_type", "status", "timestamp"],
            "properties": {
                "call_id": {
                    "bsonType": "int"
                },
                "source_id": {
                    "bsonType": "int"
                },
                "user_id": {
                    "bsonType": "int"
                },
                "call_type": {
                    "bsonType": "string"
                },
                "status": {
                    "bsonType": "string"
                },
                "timestamp": {
                    "bsonType": "date"
                }

            }
        }
    }
}

dataflow_logs_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["flow_id", "source_db", "destination_db", "table_name", "record_count", "transfer_time", "user_id"],
            "properties": {
                "flow_id": {
                    "bsonType": "int"
                },
                "source_db": {
                    "bsonType": "string"
                },
                "destination_db": {
                    "bsonType": "string"
                },
                "table_name": {
                    "bsonType": "string"
                },
                "record_count": {
                    "bsonType": "int"
                },
                "transfer_time": {
                    "bsonType": "string"
                },
                "user_id": {
                    "bsonType": "int"
                }
            }
        }
    }
}

earthquake_error_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["error_id", "call_id", "error_type", "error_message", "timestamp"],
            "properties": {
                "error_id":{
                    "bsonType": "int"
                },
                "call_id": {
                    "bsonType": "int"
                },
                "error_type": {
                    "bsonType": "string"
                },
                "error_message": {
                    "bsonType": "string"
                },
                "timestamp": {
                    "bsonType": "date"
                }

            }
        }
    }
}

users_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["user_id", "username", "email", "password_hash", "created_at"],
            "properties": {
                "user_id": {
                    "bsonType": "int"
                },
                "username": {
                    "bsonType": "string"
                },
                "email": {
                    "bsonType": "string"
                },
                "password_hash": {
                    "bsonType": "string"
                },
                "created_at": {
                    "bsonType": "date"
                }
            }
        }
    }
}

weather_error_schema = {
    "validator": {
        "$jsonSchema": {
            "bsonType": "object",
            "required": ["error_id", "call_id", "error_type", "error_message", "timestamp"],
            "properties": {
                "error_id":{
                    "bsonType": "int"
                },
                "call_id": {
                    "bsonType": "int"
                },
                "error_type": {
                    "bsonType": "string"
                },
                "error_message": {
                    "bsonType": "string"
                },
                "timestamp": {
                    "bsonType": "date"
                }

            }
        }
    }
}

# creates the collection
try:
    db.create_collection("earthquake_data", validator=earthquake_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "earthquake_data",
        "validator": earthquake_schema["validator"],
        "validationLevel": "moderate"
    })

db.earthquake_data.create_index("earthquake_id", unique=True)

try:
    db.create_collection("weather_data", validator=weather_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "weather_data",
        "validator": weather_schema["validator"],
        "validationLevel": "moderate"
    })

db.weather_data.create_index("weather_id", unique=True)

try:
    db.create_collection("locations", validator=locations_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "locations",
        "validator": locations_schema["validator"],
        "validationLevel": "moderate"
    })

db.locations.create_index("location_id", unique=True)

try:
    db.create_collection("data_sources", validator=data_sources_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "data_sources",
        "validator": data_sources_schema["validator"],
        "validationLevel": "moderate"
    })

db.data_sources.create_index("source_id", unique=True)

try:
    db.create_collection("api_calls", validator=api_calls_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "api_calls",
        "validator": api_calls_schema["validator"],
        "validationLevel": "moderate"
    })

db.api_calls.create_index("call_id", unique=True)

try:
    db.create_collection("dataflow_logs", validator=dataflow_logs_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "dataflow_logs",
        "validator": dataflow_logs_schema["validator"],
        "validationLevel": "moderate"
    })

db.dataflow_logs.create_index("flow_id", unique=True)

try:
    db.create_collection("earthquake_error_logs", validator=earthquake_error_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "earthquake_error_logs",
        "validator": earthquake_error_schema["validator"],
        "validationLevel": "moderate"
    })

db.earthquake_error_logs.create_index("error_id", unique=True)

try:
    db.create_collection("users", validator=users_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "users",
        "validator": users_schema["validator"],
        "validationLevel": "moderate"
    })

db.users.create_index("user_id", unique=True)
db.users.create_index("email", unique=True)

try:
    db.create_collection("weather_error_logs", validator=weather_error_schema["validator"])
except Exception:
    # it's like sql's drop table procedure
    db.command({
        "collMod": "weather_error_logs",
        "validator": weather_error_schema["validator"],
        "validationLevel": "moderate"
    })

db.weather_error_logs.create_index("error_id", unique=True)
