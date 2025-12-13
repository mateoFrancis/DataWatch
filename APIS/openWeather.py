# APIS/openWeather.py

import requests
from datetime import datetime
import tools  # uses your existing tools.py

USER_ID = 1  # "system" user created in setup.py


def fetch_openweather_for_location(loc, source):
    """
    Call OpenWeather for a single location.

    loc:  dict from tools.get_all_locations():
          {location_id, city, country, lat, lon, zip_code}
    source: dict from tools.get_data_source_by_name("OpenWeather"):
            {source_id, name, type, base_url, api_key, ...}
    """
    base_url = source["base_url"]
    api_key = source["api_key"]
    zip_code = loc.get("zip_code")
    country = loc.get("country") or "US"

    # Choose zip if available, else lat/lon
    if zip_code:
        params = {
            "zip": f"{zip_code},{country}",
            "appid": api_key,
            "units": "imperial",
        }
    else:
        params = {
            "lat": loc["lat"],
            "lon": loc["lon"],
            "appid": api_key,
            "units": "imperial",
        }

    resp = requests.get(base_url, params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()


def run_weather_sync_job():
    """
    Scheduled by server.py every minute.

    Steps:
      - get OpenWeather data source
      - get all locations
      - for each location:
          * log_api_call
          * call OpenWeather
          * insert into weather_data using location_id
          * on error, log_weather_error
    """
    print("\n[openWeather] Starting weather sync job...")

    # 1. Find the OpenWeather source row
    source = tools.get_data_source_by_name("OpenWeather")
    if not source:
        print("[openWeather] ERROR: data_sources entry 'OpenWeather' not found.")
        return "OpenWeather source missing"

    source_id = source["source_id"]

    # 2. Get all locations
    locations = tools.get_all_locations()
    if not locations:
        print("[openWeather] No locations found in 'locations' table.")
        return "No locations found"

    for loc in locations:
        loc_id = loc["location_id"]
        city = loc["city"]

        call_id = None
        try:
            # 3. Log the API call as 'pending'
            call_id = tools.log_api_call(
                source_id=source_id,
                user_id=USER_ID,
                call_type="weather",
                status="pending",
            )

            # 4. Fetch from OpenWeather
            data = fetch_openweather_for_location(loc, source)

            main = data.get("main", {})
            wind = data.get("wind", {})

            temperature = float(main.get("temp")) if main.get("temp") is not None else None
            humidity = float(main.get("humidity")) if main.get("humidity") is not None else None
            wind_speed = float(wind.get("speed")) if wind.get("speed") is not None else None

            # Use API time if provided, else let DB default NOW()
            dt = data.get("dt")  # epoch seconds
            recorded_at = datetime.utcfromtimestamp(dt) if dt else None

            # 5. Insert into weather_data via stored procedure
            weather_id = tools.insert_weather_data(
                source_id=source_id,
                location_id=loc_id,
                user_id=USER_ID,
                temperature=temperature,
                humidity=humidity,
                wind_speed=wind_speed,
                recorded_at=recorded_at,
                call_id=call_id,
            )

            print(f"[openWeather] Stored weather_id={weather_id} for {city}")

        except Exception as e:
            print(f"[openWeather] ERROR for {city}: {e}")
            try:
                # 6. Log error
                tools.log_weather_error(
                    call_id=call_id,
                    error_type="OpenWeatherError",
                    error_message=str(e),
                )
            except Exception as e2:
                print(f"[openWeather] Failed to log weather error: {e2}")

    return "Weather sync completed"


if __name__ == "__main__":
    print(run_weather_sync_job())
