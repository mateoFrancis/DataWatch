
# work in progress..

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


app = Flask(__name__)
#CORS(app)
CORS(app, resources={r"/api/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*")


def check_c1_status():

    db_status = "ok"
    api_status = "ok"
    socket_status = "ok"

    # db connection check
    try:
        conn = tools.get_connection()
        conn.close()
   
    except Exception:
        db_status = "down"

    # openWeather connection check (test with an api call)
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



    # socket connection check
    try:
        socketio.emit("c1_test", {"message": "socket alive"})
    except Exception:
        socket_status = "error"

    # Send c1 event
    socketio.emit("c1", {
        "database": db_status,
        "api": api_status,
        "socket": socket_status
    })

    print(f"[C1] DB={db_status}, API={api_status}, SOCKET={socket_status}")




scheduler = BackgroundScheduler()

# run the job every n minutes
scheduler.add_job(
    func = openWeather.run_weather_sync_job,
    trigger = IntervalTrigger(minutes = 1),
    id = 'weather_sync_job',
    name = 'Run weather sync every minute',
    replace_existing = True,
    next_run_time = datetime.now()  # start immediately
)

scheduler.add_job(
    func = check_c1_status,
    trigger = IntervalTrigger(minutes = 1),
    id = "connection_check_job",
    name = "Check connections every minute",
    replace_existing = True,
    next_run_time = datetime.now()
)




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
def handle_connect():

    print("Client connected")

    socketio.emit("c1", {
        "database": "unknown",
        "api": "unknown",
        "socket": "ok"
    })
    #ex for later usage: weather/earthquake sync job, db connection test-
    #- API calls, and data validation. 


if __name__ == "__main__":
    
    if os.environ.get("WERKZEUG_RUN_MAIN") == "true":

        # only start scheduler in the actual child process
        scheduler.start()
        
        print("Scheduler started. Weather sync job will run every n minutes.")
        atexit.register(lambda: scheduler.shutdown())

    socketio.run(app, debug=True)

