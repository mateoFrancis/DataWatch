
# work in progress..

from datetime import datetime
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), "APIS"))  # So Python can find openWeatherApi.py

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

scheduler.start()
print("Scheduler started. Weather sync job will run every n minutes.")

# stop scheduler on exit
atexit.register(lambda: scheduler.shutdown())






# Home route
@app.route("/")
def home():
    return "Hello, World!"

# API route 
#@app.route("/data")
#def get_data():
    #data = fetch_weather(["90001"])
    #data = fetch_weather(["Los Angeles"])
    #return jsonify(data)

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

if __name__ == "__main__":
    app.run(debug=True)
