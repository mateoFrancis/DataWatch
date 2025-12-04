
# work in progress..

import eventlet
eventlet.monkey_patch()

from datetime import datetime
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), "APIS"))  # So Python can find openWeatherApi.py
import requests

from flask_socketio import SocketIO, emit
from flask import Flask, jsonify, request
#import pandas as pd
#from api_openWeatherMap import fetch_weather
import tools

from flask_cors import CORS

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
import atexit

import openWeather
import data_validation  # for c3 emmit



connected_clients = set()
background_started = False


app = Flask(__name__)
#CORS(app)
CORS(app, resources={r"/api/*": {"origins": "*"}})

app.config['SECRET_KEY'] = 'secret'  # needed by Socket.IO sessions

socketio = SocketIO(app, host="0.0.0.0", port="5000", cors_allowed_origins="*", async_mode="eventlet")



def c1_loop():
    
    while True:
        db_status = "ok"
        api_status = "ok"
        socket_status = "ok"

        print("[C1_LOOP] Emitting C1 status") 

        # DB check
        try:
            conn = tools.get_connection()
            conn.close()
        except Exception:
            db_status = "down"

        # penWeather check
        try:
            source = tools.get_data_source_by_name("OpenWeather")
            test_url = source["base_url"]
            test_key = source["api_key"]

            response = requests.get(
                test_url,
                params={
                    "zip": "90001,US",
                    "appid": test_key,
                    "units": "imperial"
                },
                timeout=10
            )
            response.raise_for_status()
        except Exception:
            api_status = "down"

        # socket test
        try:
            socketio.emit("c1_test", {"message": "socket alive"})
        except Exception:
            socket_status = "error"

        # emit c1 
        socketio.emit("c1", {
            "database": db_status,
            "api": api_status,
            "socket": socket_status
        })

        print(f"[C1] DB={db_status}, API={api_status}, SOCKET={socket_status}")

        # wait 60 seconds
        socketio.sleep(60)


def c2_loop():
    
    while True:

        try:
            openWeather.run_weather_sync_job(socketio)
            print("[C2_LOOP] Weather sync job emitted c2")
        
        except Exception as e:
            print("[C2_LOOP] Error:", e)
        
        socketio.sleep(180)  # wait 60 seconds before next run


def c3_loop():
  
    while True:

        try:
            data_validation.run_c3_validation(socketio)
            print("[C3_LOOP] Validation job emitted c3")
        
        except Exception as e:
            print("[C3_LOOP] Error:", e)
        
        socketio.sleep(185)  # wait 60 seconds before next run



# Home route
@app.route("/")
def home():
    return "Hello, World!"


@app.route("/api/login", methods=['POST'])
def login_data():
    #verify_login(data)
    data = request.get_json()

    if not data:
        return jsonify({"message": "Invalid json"}), 400
    
    username = data.get("username")
    password = data.get("password")

    print(f"username: {username}, password: {password}")
    
    return jsonify({"message": "Received", "username": username}), 200


@socketio.on("connect")
def handle_connect(_):

    global background_started

    connected_clients.add(request.sid)
    print(f"Client connected: {request.sid} (total {len(connected_clients)})")
    
    # start background loops (only onece)
    if not background_started:
        socketio.start_background_task(c1_loop)
        socketio.start_background_task(c2_loop)
        socketio.start_background_task(c3_loop)
        background_started = True
        print("Background tasks started for c1, c2, c3")
    
    print(f"Client connected: {request.sid} (total {len(connected_clients)})")



if __name__ == "__main__":
    
    #if os.environ.get("WERKZEUG_RUN_MAIN") == "true":

        # only start scheduler in the actual child process
        #scheduler.start()
        
        #socketio.start_background_task(c1_loop)
        

    #socketio.start_background_task(c1_loop)

    socketio.run(app, debug=True)

