#!/usr/bin/env python3
import json
import random
from datetime import datetime, timedelta

DAYS_TOTAL = 29
WINDOWS = [
    (8, 11),   # 8am - 11am
    (11, 14),  # 11am - 2pm
    (18, 21),  # 6pm - 9pm
]

WEEKEND_DAYS = {"Saturday", "Sunday"}

random.seed()

def pick_time(windows=WINDOWS):
    start, end = random.choice(windows)
    hour = random.randint(start, end - 1)
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
    return hour, minute, second

def format_time(h, m, s):
    return f"{h:02d}:{m:02d}:{s:02d}"

def get_day_name(d: datetime):
    return d.strftime("%A")

def pick_two_times():
    h1, m1, s1 = pick_time()
    h2, m2, s2 = pick_time()
    while abs((h2 + m2/60) - (h1 + m1/60)) < 2:
        h2, m2, s2 = pick_time()
    return sorted([format_time(h1, m1, s1), format_time(h2, m2, s2)])

def main():
    start_date = datetime(2026, 5, 10, 22, 15, 53) + timedelta(days=1)
    dates = [start_date + timedelta(days=i) for i in range(DAYS_TOTAL)]

    # Base schedule: 1 post per day
    schedule = []
    for d in dates:
        h, m, s = pick_time()
        schedule.append({
            "date": d.strftime("%Y-%m-%d"),
            "day": get_day_name(d),
            "time": format_time(h, m, s),
            "posts": 1
        })

    double_indices = set()

    # --- Every weekend: pick Sat OR Sun for double post ---
    # Group dates by weekend (Sat-Sun pairs)
    weekends = []
    current_weekend = []
    for i, d in enumerate(dates):
        day = get_day_name(d)
        if day in WEEKEND_DAYS:
            current_weekend.append(i)
            if day == "Sunday" or i == len(dates) - 1:
                weekends.append(current_weekend)
                current_weekend = []
        else:
            if current_weekend:
                weekends.append(current_weekend)
                current_weekend = []
    if current_weekend:
        weekends.append(current_weekend)

    for weekend in weekends:
        chosen = random.choice(weekend)
        double_indices.add(chosen)

    # --- One random weekday double post, not adjacent to any double-post day ---
    weekday_indices = [i for i, d in enumerate(dates) if get_day_name(d) not in WEEKEND_DAYS]
    forbidden = set()
    for idx in double_indices:
        if idx > 0:
            forbidden.add(idx - 1)
        if idx < len(dates) - 1:
            forbidden.add(idx + 1)
    valid_weekdays = [i for i in weekday_indices if i not in forbidden and i not in double_indices]

    if valid_weekdays:
        weekday_double = random.choice(valid_weekdays)
        double_indices.add(weekday_double)

    # Apply double posts
    for idx in double_indices:
        schedule[idx]["posts"] = 2
        schedule[idx]["time"] = pick_two_times()

    # Flatten output
    output = []
    for entry in schedule:
        if isinstance(entry["time"], list):
            for t in entry["time"]:
                output.append({
                    "date": entry["date"],
                    "day": entry["day"],
                    "time": t
                })
        else:
            output.append({
                "date": entry["date"],
                "day": entry["day"],
                "time": entry["time"]
            })

    output.sort(key=lambda x: (x["date"], x["time"]))
    print(json.dumps(output, indent=2))

if __name__ == "__main__":
    main()
