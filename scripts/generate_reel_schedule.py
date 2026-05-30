#!/usr/bin/env python3
import json
import random
import sys
import os
from datetime import datetime, timedelta

DAYS_TOTAL = 29
WINDOWS = [
    (8, 11),   # 8am - 11am
    (11, 14),  # 11am - 2pm
    (18, 21),  # 6pm - 9pm
]

WEEKEND_DAYS = {"Saturday", "Sunday"}

random.seed()


def get_project_path(project_id, platform="facebook"):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    filename = "schedule.json" if platform == "facebook" else f"{platform}_schedule.json"
    return os.path.join(repo_root, f"project-{project_id}", filename)


def pick_time(windows=WINDOWS, platform="facebook"):
    start, end = random.choice(windows)
    hour = random.randint(start, end - 1)
    # Round minutes based on platform (15 min for YouTube, 5 min for Facebook)
    if platform == "youtube":
        minute = random.choice(range(0, 60, 15))
    else:
        minute = random.choice(range(0, 60, 5))
    second = 0
    return hour, minute, second


def format_time(h, m, s):
    return f"{h:02d}:{m:02d}:{s:02d}"


def get_day_name(d):
    return d.strftime("%A")


def pick_two_times(platform="facebook"):
    h1, m1, s1 = pick_time(platform=platform)
    h2, m2, s2 = pick_time(platform=platform)
    while abs((h2 + m2/60) - (h1 + m1/60)) < 2:
        h2, m2, s2 = pick_time(platform=platform)
    return sorted([format_time(h1, m1, s1), format_time(h2, m2, s2)])


def load_schedule(path):
    if not os.path.exists(path):
        return None
    with open(path, "r") as f:
        return json.load(f)


def all_scheduled(schedule):
    if not schedule:
        return True
    return all(entry.get("status") == "scheduled" for entry in schedule)


def generate_schedule(start_date, days_total=DAYS_TOTAL, platform="facebook"):
    dates = [start_date + timedelta(days=i) for i in range(days_total)]

    schedule = []
    for d in dates:
        h, m, s = pick_time(platform=platform)
        schedule.append({
            "date": d.strftime("%Y-%m-%d"),
            "day": get_day_name(d),
            "time": format_time(h, m, s),
            "posts": 1,
            "status": "pending"
        })

    double_indices = set()

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

    for idx in double_indices:
        schedule[idx]["posts"] = 2
        schedule[idx]["time"] = pick_two_times(platform=platform)

    output = []
    for entry in schedule:
        if isinstance(entry["time"], list):
            for t in entry["time"]:
                output.append({
                    "date": entry["date"],
                    "day": entry["day"],
                    "time": t,
                    "status": "pending"
                })
        else:
            output.append({
                "date": entry["date"],
                "day": entry["day"],
                "time": entry["time"],
                "status": "pending"
            })

    output.sort(key=lambda x: (x["date"], x["time"]))
    return output


def save_schedule(path, schedule):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(schedule, f, indent=2)


def main():
    if len(sys.argv) < 3 or sys.argv[1] != "--project":
        print("Usage: generate_reel_schedule.py --project <1|2> [--platform <facebook|youtube>]", file=sys.stderr)
        sys.exit(1)

    project_id = sys.argv[2]
    
    platform = "facebook"
    if "--platform" in sys.argv:
        idx = sys.argv.index("--platform")
        if idx + 1 < len(sys.argv):
            platform = sys.argv[idx + 1]

    schedule_path = get_project_path(project_id, platform)

    existing = load_schedule(schedule_path)
    if existing is not None and not all_scheduled(existing):
        print(f"Schedule exists with unscheduled entries: {schedule_path}")
        print(json.dumps({"regenerated": False, "path": schedule_path, "reason": "unscheduled_entries_exist"}))
        sys.exit(0)

    start_date = datetime.now().date() + timedelta(days=1)
    schedule = generate_schedule(start_date, platform=platform)
    save_schedule(schedule_path, schedule)
    print(f"Generated schedule: {schedule_path}")
    print(json.dumps({"regenerated": True, "path": schedule_path, "entries": len(schedule)}))


if __name__ == "__main__":
    main()
