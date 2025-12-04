import tools
import statistics

# default number of historical rows to consider
history_size = 500  
# number of latest readings to check for anomalies
check_size = 20  

def run_c3_validation(socketio, thresholds=None):
    """
    Runs weather validation based on historical deviations.
    Emits 'c3' event with warnings if anomalies are detected.
    
    :param socketio: the Flask-SocketIO instance
    :param thresholds: optional dict with 'temperature', 'humidity', 'wind_speed' multipliers for std dev
    """
    if thresholds is None:
        thresholds = {"temperature": 3, "humidity": 3, "wind_speed": 3}  # 3 std deviations

    # fetch historical data (whatever exists)
    rows = tools.get_weather_rows(history_size)
    if not rows:
        print("[C3] No data to validate")
        return

    # extract metric lists
    temps = [r["temperature"] for r in rows]
    hums = [r["humidity"] for r in rows]
    winds = [r["wind_speed"] for r in rows]

    # compute mean
    avg_temp = statistics.mean(temps)
    avg_hum = statistics.mean(hums)
    avg_wind = statistics.mean(winds)

    # compute standard deviation safely
    std_temp = statistics.stdev(temps) if len(temps) > 1 else 0.1
    std_hum = statistics.stdev(hums) if len(hums) > 1 else 0.1
    std_wind = statistics.stdev(winds) if len(winds) > 1 else 0.1

    # only check the latest N readings
    recent_rows = rows[-check_size:]

    warnings = []

    for r in recent_rows:
        temp_dev = abs(r["temperature"] - avg_temp)
        hum_dev = abs(r["humidity"] - avg_hum)
        wind_dev = abs(r["wind_speed"] - avg_wind)

        temp_flag = temp_dev > thresholds["temperature"] * std_temp
        hum_flag = hum_dev > thresholds["humidity"] * std_hum
        wind_flag = wind_dev > thresholds["wind_speed"] * std_wind

        if temp_flag or hum_flag or wind_flag:
            warnings.append({
                "weather_id": r["weather_id"],
                "temperature": r["temperature"],
                "humidity": r["humidity"],
                "wind_speed": r["wind_speed"],
                "temperature_dev": round(temp_dev, 2),
                "humidity_dev": round(hum_dev, 2),
                "wind_dev": round(wind_dev, 2)
            })

    status = "ok" if not warnings else "WARNING"

    c3_data = {
        "status": status,
        "thresholds": thresholds,
        "warnings": warnings,
        "avg": {
            "temperature": round(avg_temp, 2),
            "humidity": round(avg_hum, 2),
            "wind_speed": round(avg_wind, 2)
        }
    }

    socketio.emit("c3", c3_data)
    print(f"[C3] Validation complete: {status}, {len(warnings)} warnings")
