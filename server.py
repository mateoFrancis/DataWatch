# server.py  — merged version: Socket.IO + weather + earthquake + C1 checks

from datetime import datetime
import sys
import os
import atexit
import requests

# Make sure Python can find APIS/openWeather.py and APIS/earthquake_locations.py
sys.path.append(os.path.join(os.path.dirname(__file__), "APIS"))

from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_socketio import SocketIO
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger

import tools
import openWeather             # weather pipeline
import earthquake_locations     # earthquake pipeline


app = Flask(__name__)
# Allow frontend access to /api/* from any origin for now
CORS(app, resources={r"/api/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*")


# -----------------------
#   C1 connection status
# -----------------------
def check_c1_status():
    db_status = "ok"
    api_status = "ok"
    socket_status = "ok"

    # DB connection check
    try:
        conn = tools.get_connection()
        conn.close()
    except Exception:
        db_status = "down"

    # OpenWeather connection check (simple test request)
    try:
        source = tools.get_data_source_by_name("OpenWeather")
        if not source:
            raise RuntimeError("OpenWeather source missing from data_sources")

        test_url = source["base_url"]
        test_key = source["api_key"]

        resp = requests.get(
            test_url,
            params={
                "zip": "90001,US",
                "appid": test_key,
                "units": "imperial",
            },
            timeout=10,
        )
        resp.raise_for_status()
    except Exception:
        api_status = "down"

    # Socket check
    try:
        socketio.emit("c1_test", {"message": "socket alive"})
    except Exception:
        socket_status = "error"

    # Emit C1 summary
    socketio.emit("c1", {
        "database": db_status,
        "api": api_status,
        "socket": socket_status,
    })

    print(f"[C1] DB={db_status}, API={api_status}, SOCKET={socket_status}")


# -----------------------
#   Background jobs
# -----------------------
scheduler = BackgroundScheduler()

# Weather job: run every 1 minute
scheduler.add_job(
    func=openWeather.run_weather_sync_job,
    trigger=IntervalTrigger(minutes=1),
    id='weather_sync_job',
    name='Run weather sync every minute',
    replace_existing=True,
    next_run_time=datetime.now(),  # start immediately
)

# Earthquake job: run every 5 minutes
scheduler.add_job(
    func=earthquake_locations.run_earthquake_sync_job,
    trigger=IntervalTrigger(minutes=5),
    id='earthquake_sync_job',
    name='Run earthquake sync every 5 minutes',
    replace_existing=True,
    next_run_time=datetime.now(),  # start immediately
)

# C1 connection check job: run every 1 minute
scheduler.add_job(
    func=check_c1_status,
    trigger=IntervalTrigger(minutes=1),
    id="connection_check_job",
    name="Check connections every minute",
    replace_existing=True,
    next_run_time=datetime.now(),
)


# -----------------------
#        Routes
# -----------------------

@app.route("/")
def home():
    return "DataWatch server running (weather + earthquake)."


@app.route("/api/login", methods=['POST'])
def login_data():
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

    # Initial C1 snapshot for new client
    socketio.emit("c1", {
        "database": "unknown",
        "api": "unknown",
        "socket": "ok",
    })
    # Later, the scheduled check_c1_status job will send real values


# -----------------------
#        Main
# -----------------------
if __name__ == "__main__":

    # IMPORTANT: only start the scheduler in the reloader *child* process,
    # otherwise it will start twice in debug mode.
    if os.environ.get("WERKZEUG_RUN_MAIN") == "true":
        scheduler.start()
        print("Scheduler started. Weather + Earthquake + C1 jobs are running.")
        atexit.register(lambda: scheduler.shutdown())

    socketio.run(app, debug=True)
