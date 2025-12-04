

import requests
from datetime import datetime
import pytz

import sys
sys.path.append("/srv/shared/DataWatch")
import tools

system_user_id = 1
"""
try:
    from app import socketio
except:
    socketio = None
"""

def run_weather_sync_job(socketio):

    try:

        # get source data
        source = tools.get_data_source_by_name("OpenWeather")
        base_url = source["base_url"]
        api_key = source["api_key"]
        source_id = source["source_id"]

        # api call started
        api_call_id = tools.log_api_call(
            source_id = source_id,
            user_id = system_user_id,
            call_type = "weather",
            status = "STARTED"
        )

        # get all locations (zip codes)
        locations = tools.get_all_locations()

        pst = pytz.timezone("America/Los_Angeles")
        
        success_count = 0
        failure_count = 0

        for loc in locations:

            location_id = loc["location_id"]
            zip_code = loc["zip_code"]

            params = {
                "zip": f"{zip_code},US",
                "appid": api_key,
                "units": "imperial"
            }

            try:
                response = requests.get(base_url, params=params, timeout=10)
                response.raise_for_status()
                data = response.json()

                temp = data.get("main", {}).get("temp")
                humidity = data.get("main", {}).get("humidity")
                wind_speed = data.get("wind", {}).get("speed")

                # convert timestamp
                dt_utc = datetime.utcfromtimestamp(data["dt"])
                dt_pst = dt_utc.replace(tzinfo=pytz.utc).astimezone(pst)
                recorded_at = dt_pst.strftime("%Y-%m-%d %H:%M:%S")

                # insert weather data
                tools.insert_weather_data(
                    source_id,
                    location_id,
                    system_user_id,
                    temp,
                    humidity,
                    wind_speed,
                    recorded_at,
                    api_call_id
                )

                success_count += 1

            except Exception as e:

                failure_count += 1

                tools.log_weather_error(
                    call_id = api_call_id,
                    error_type = "WeatherFetchError",
                    error_message = f"Location {location_id}: {str(e)}"
                )


        # determine final status
        final_status = "SUCCESS" if failure_count == 0 else (
            "FAILED" if success_count == 0 else "PARTIAL"
        )

        tools.update_api_call_status(
            call_id = api_call_id,
            status = final_status
        )

        # c2 emmit start
        total_locations = len(locations)

        # mongoDB transfer funciton call (work in progress...)
        # recent_data = tools.get_recent_weather_data(api_call_id)
        # mongo_transfer_status = transfer_to_mongo(recent_data)

        mongo_transfer_status = False  # placeholder for now

        c2_data = {
            "source": "weather",
            "read": 2 + total_locations,     # db reads + api fetches
            "create": success_count,         # inserts into weather table
            "update": 1,                     # update_api_call_status
            "delete": 0,                     # no deletes yet
            "success": success_count,
            "failed": failure_count,
            "mongo_transfer_status": mongo_transfer_status
        }

        if socketio:
            socketio.emit("c2", c2_data)

        #print(f"[C2] {c2_data}")
        

        return "\nWeather sync completed"

    except Exception as fatal_error:

        # fatal failure
        tools.update_api_call_status(
            call_id = api_call_id,
            status = "FAILED"
        )

        # C2 emit on fatal failure
        c2_data = {
            "source": "weather",
            "read": 0,
            "create": 0,
            "update": 0,
            "delete": 0,
            "success": 0,
            "failed": len(tools.get_all_locations()),  # or total expected operations
            "mongo_transfer_status": False,
            "error": str(fatal_error)
        }

        if socketio:
            socketio.emit("c2", c2_data)

        #print(f"[C2 - FATAL] {c2_data}")

        return "Weather sync failed"
        


# if __name__ == "__main__":
#     print(run_weather_sync_job())
