

import tools


# add test user
try:
    tools.add_user("system", "system@datawatch.local", "systemAdmin")
except Exception as e:
    print(f"[setup] User already exists or error: {e}")


# add data sources
try:
    tools.add_data_source(
        name = "OpenWeather",
        type_ = "weather",
        base_url = "https://api.openweathermap.org/data/2.5/weather",
        api_key = "a2344ccdb157cfc507fc6589b8a7893a"
    )
except Exception as e:
    print(f"[setup] Data source already exists or error: {e}")


# add locations
##zip_codes = ["90210", "10001", "60601"]

locations_info = [
    {"city": "Beverly Hills", "country": "US", "lat": 34.0736, "lon": -118.4004, "zip_code": "90210"},
    {"city": "New York", "country": "US", "lat": 40.7128, "lon": -74.0060, "zip_code": "10001"},
    {"city": "Chicago", "country": "US", "lat": 41.8781, "lon": -87.6298, "zip_code": "60601"},
    {"city": "Los Angeles", "country": "US", "lat": 34.0522, "lon": -118.2437, "zip_code": "90001"},
    {"city": "San Francisco", "country": "US", "lat": 37.7749, "lon": -122.4194, "zip_code": "94102"},
    {"city": "Seattle", "country": "US", "lat": 47.6062, "lon": -122.3321, "zip_code": "98101"},
    {"city": "Boston", "country": "US", "lat": 42.3601, "lon": -71.0589, "zip_code": "02108"},
    {"city": "Miami", "country": "US", "lat": 25.7617, "lon": -80.1918, "zip_code": "33101"},
    {"city": "Houston", "country": "US", "lat": 29.7604, "lon": -95.3698, "zip_code": "77001"},
    {"city": "Phoenix", "country": "US", "lat": 33.4484, "lon": -112.0740, "zip_code": "85001"},
    {"city": "Philadelphia", "country": "US", "lat": 39.9526, "lon": -75.1652, "zip_code": "19101"},
    {"city": "San Diego", "country": "US", "lat": 32.7157, "lon": -117.1611, "zip_code": "92101"},
    {"city": "Denver", "country": "US", "lat": 39.7392, "lon": -104.9903, "zip_code": "80201"},
    {"city": "Atlanta", "country": "US", "lat": 33.7490, "lon": -84.3880, "zip_code": "30301"},
    {"city": "Dallas", "country": "US", "lat": 32.7767, "lon": -96.7970, "zip_code": "75201"},
    {"city": "Detroit", "country": "US", "lat": 42.3314, "lon": -83.0458, "zip_code": "48201"},
    {"city": "Minneapolis", "country": "US", "lat": 44.9778, "lon": -93.2650, "zip_code": "55401"},
    {"city": "Portland", "country": "US", "lat": 45.5152, "lon": -122.6784, "zip_code": "97201"},
    {"city": "Las Vegas", "country": "US", "lat": 36.1699, "lon": -115.1398, "zip_code": "89101"},
    {"city": "Orlando", "country": "US", "lat": 28.5383, "lon": -81.3792, "zip_code": "32801"}
]



for loc in locations_info:
   
    try:
        tools.add_location(
            city = loc["city"],
            country = loc["country"],
            lat = loc["lat"],
            lon = loc["lon"],
            zip_code = loc["zip_code"]
        )
    except Exception as e:
        print(f"[setup] Location already exists or error: {e}")

