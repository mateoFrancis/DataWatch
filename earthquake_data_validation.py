import statistics
import montools

# default number of historical rows to consider
history_size = 500  
# number of latest readings to check for anomalies
check_size = 20  

def run_c3_validation(socketio, thresholds=None):

    if thresholds is None:
        thresholds = {"magnitude": 1, "depth": 5}

    # fetch historical data (whatever exists)
    rows = montools.get_earthquake_rows(history_size)
    if not rows:
        print("[C3] No data to validate")
        return
    

    # extract metric lists
    magnitude = [r["magnitude"] for r in rows]
    depth = [r["depth"] for r in rows]

    # compute mean
    avg_magnitude = statistics.mean(magnitude)
    avg_depth = statistics.mean(depth)

    # compute standard deviation safely
    std_magnitude = statistics.stdev(magnitude) if len(magnitude) > 1 else 0.1
    std_depth = statistics.stdev(depth) if len(depth) > 1 else 0.1

    # only check the latest N readings
    recent_rows = rows[-check_size:]

    warnings = []

    for r in recent_rows:
        magnitude_dev = abs(r["magnitude"] - avg_magnitude)
        depth_dev = abs(r["depth"] - avg_depth)

        magnitude_flag = magnitude_dev > thresholds["magnitude"] * std_magnitude
        depth_flag = depth_dev > thresholds["depth"] * std_depth

        if magnitude_flag or depth_flag:
            warnings.append({
                "earthquake_id": r["earthquake_id"],
                "magnitude": r["magnitude"],
                "depth": r["depth"],
                "magnitude_dev": round(magnitude_dev, 2),
                "depth_dev": round(depth_dev, 2)
            })

    status = "ok" if not warnings else "WARNING"

    c3_data = {
        "source": "earthquake",
        "status": status,
        "thresholds": thresholds,
        "warnings": warnings,
        "avg": {
            "magnitude": round(avg_magnitude, 2),
            "depth": round(avg_depth, 2),
        }
    }

    socketio.emit("c3", c3_data)
    print(f"[C3] Validation complete: {status}, {len(warnings)} warnings")
