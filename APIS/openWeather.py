

import requests
from datetime import datetime
import pytz 

def fetch_weather(zip_codes):

    records = []

    api_key = "a2344ccdb157cfc507fc6589b8a7893a" # to be stored in DB
    country_code = "US"

    lat = 34.0239
    lon = -118.172
    city_id = "5344994"
    pst = pytz.timezone("America/Los_Angeles") 

    for zip_code in zip_codes:
      
        url = f"https://api.openweathermap.org/data/2.5/weather?zip={zip_code},{country_code}&appid={api_key}&units=imperial"
        #url = f"https://api.openweathermap.org/data/2.5/weather?id={city_id}&appid={api_key}"
        
        #url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={api_key}"
        
        try:
      
            response = requests.get(url)
            response.raise_for_status()
            data = response.json()    # json directly
            #records.append(data)      # store it

            temp = data.get("main", {}).get("temp")
            humidity = data.get("main", {}).get("humidity")
            wind_speed = data.get("wind", {}).get("speed")
            dt_utc = datetime.utcfromtimestamp(data.get("dt"))
            dt_pst = dt_utc.replace(tzinfo=pytz.utc).astimezone(pst)

            record = {
                "p_temperature": temp,
                "p_humidity": humidity,
                "p_wind_speed": wind_speed,
                "p_recorded_at": dt_pst.strftime("%Y-%m-%d %H:%M:%S")
            }

            records.append(record)
      
        except requests.RequestException as e:
            print(f"Request Error for {zip_code}: {e}")

    return records  # return list of JSON objects


zip_codes = ["90001", "10001"]  # LA and NY
weather_data = fetch_weather(zip_codes)

for record in weather_data:
    print(record)



"""
# later user
params = {
    "zip": "90210,US",
    "appid": data_source_row["api_key"],
    "units": "imperial"
}

# request handles url encoding
response = requests.get(data_source_row["base_url"], params=params) 

"""