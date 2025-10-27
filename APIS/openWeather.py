

import requests

def fetch_weather(zip_codes):

    records = []

    api_key = "" # to be stored in DB
    country_code = "US"

    lat = 34.0239
    lon = -118.172
    city_id = "5344994"

    for zip_code in zip_codes:
      
        #url = f"https://api.openweathermap.org/data/2.5/weather?zip={zip_code},{country_code}&appid={api_key}&units=imperial"
        #url = f"https://api.openweathermap.org/data/2.5/weather?id={city_id}&appid={api_key}"
        
        url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={api_key}"
        
        try:
      
            response = requests.get(url)
            response.raise_for_status()
            data = response.json()    # JSON directly
            records.append(data)      # store it
      
        except requests.RequestException as e:
            print(f"Request Error for {zip_code}: {e}")

    return records  # return list of JSON objects
