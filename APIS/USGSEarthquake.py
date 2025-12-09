import requests
from datetime import datetime
import pytz

import sys
sys.path.append("/srv/shared/DataWatch")
import montools

system_user_id = 1
"""
try:
    from app import socketio
except:
    socketio = None
"""

def run_earthquake_sync_job(socketio):

    try:

        # get source data
        source = montools.get_data_source_by_name("USGSEarthquake")
        base_url = source["base_url"]
        source_id = source["source_id"]

        # api call started
        api_call_id = montools.log_api_call(
            source_id = source_id,
            user_id = system_user_id,
            call_type = "earthquake",
            status = "STARTED"
        )

        # get all locations (zip codes)
        locations = montools.get_all_locations()

        pst = pytz.timezone("America/Los_Angeles")
        
        success_count = 0
        failure_count = 0

        for loc in locations:

            location_id = loc["location_id"]

            params = {
                "format": "geojson",
                "minmagnitude": 1,
                "mindepth": 10,
                "starttime": "2020-01-01",
                "endtime": "2025-12-31",
                "minlatitude": loc["lat"] - 0.5,
                "maxlatitude": loc["lat"] + 0.5,
                "minlongitude": loc["lon"] - 0.5,
                "maxlongitude": loc["lon"] + 0.5
            }

            try:
                response = requests.get(base_url, params=params, timeout=10)
                response.raise_for_status()
                data = response.json()

                for feature in data.get("features", []):
                    magnitude = feature["properties"]["mag"]
                    depth = feature ["geometry"]["coordinates"][2]
                    recorded_at = datetime.utcfromtimestamp(feature["properties"]["time"] / 1000).strftime("%Y-%m-%d %H:%M:%S")

                    # insert earthquake data
                    montools.insert_earthquake_data(
                        source_id,
                        location_id,
                        system_user_id,
                        magnitude,
                        depth,
                        recorded_at,
                        api_call_id
                    )

                    success_count += 1

            except Exception as e:

                failure_count += 1

                montools.log_earthquake_error(
                    call_id = api_call_id,
                    error_type = "EarthquakeFetchError",
                    error_message = f"Location {location_id}: {str(e)}"
                )


        # determine final status
        final_status = "SUCCESS" if failure_count == 0 else (
            "FAILED" if success_count == 0 else "PARTIAL"
        )

        montools.update_api_call_status(
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
            "source": "earthquake",
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
        

        return "\nEarthquake sync completed"

    except Exception as fatal_error:

        # fatal failure
        montools.update_api_call_status(
            call_id = api_call_id,
            status = "FAILED"
        )

        # C2 emit on fatal failure
        c2_data = {
            "source": "earthquake",
            "read": 0,
            "create": 0,
            "update": 0,
            "delete": 0,
            "success": 0,
            "failed": len(montools.get_all_locations()),  # or total expected operations
            "mongo_transfer_status": False,
            "error": str(fatal_error)
        }

        if socketio:
            socketio.emit("c2", c2_data)

        #print(f"[C2 - FATAL] {c2_data}")

        return "Earthquake sync failed"
        


# if __name__ == "__main__":
#     print(run_earthquake_sync_job())
