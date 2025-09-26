
# work in progress..

import sys
import os
sys.path.append(os.path.abspath(".."))  # So Python can find openWeatherApi.py

from flask import Flask, jsonify
import pandas as pd
from api_openWeatherMap import fetch_weather


app = Flask(__name__)

# Home route
@app.route("/")
def home():
    return "Hello, World!"

# API route
@app.route("/data")   # Make sure this is NOT commented
def get_data():
    data = fetch_weather(["90001"])
    #data = fetch_weather(["Los Angeles"])
    return jsonify(data)

if __name__ == "__main__":
    app.run(debug=True)
