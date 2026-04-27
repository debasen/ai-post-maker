import json
import re
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.dirname(script_dir)
file_path = os.path.join(repo_root, 'project-2', 'grok_prompts.json')

with open(file_path, 'r') as f:
    data = json.load(f)
prompts = data['prompts']

edgy_replacements = {
    "vibrant": "neon-drenched, sultry",
    "playful glance": "piercing, seductive stare",
    "soft smile": "sultry look",
    "playfully": "sultrily",
    "joyful": "mischievous",
    "softly": "sultrily",
    "dreamily": "seductively",
    "cool, confident stare": "fierce, confident stare",
    "Smiling warmly": "Smiling mischievously",
    "adventurous expression": "sultry, adventurous expression",
    "joyful expression": "sultry, high-energy expression",
    "thoughtfully": "seductively",
    "energetic posture": "fierce, energetic posture",
    "looking curiously": "looking seductively",
    "laughing joyfully": "laughing mischievously",
    "serene expression": "sultry, serene expression",
    "leaning casually": "leaning provocatively",
    "soft breeze": "warm breeze",
    "soft, dramatic lighting": "moody, dramatic lighting",
    "playful smile": "sultry, playful smile",
    "smiling sweetly": "smiling mischievously",
    "calm and ethereal": "sultry and ethereal",
}

for item in prompts:
    prompt = item["prompt"]
    prompt = prompt.replace(" 9:16 portrait format.", "")
    if not prompt.startswith("Imagine the exact model"):
        prompt = "Imagine the exact model in a " + prompt[0].lower() + prompt[1:]
    
    realism_clause = " The image should be ultra realistic. The image should not be cartoonish or have AI smoothened edges. 9:16 portrait format."
    if realism_clause not in prompt:
        prompt += realism_clause
        
    for old, new in edgy_replacements.items():
        prompt = prompt.replace(old, new)
    item["prompt"] = prompt

    caption = item["instagram_caption"]
    caption = re.sub(r'#\w+', '', caption).strip()
    if not caption.endswith('.'):
        caption += '.'
    
    hashtags = " #baddie #modelvibe #sultry #realisticai #fashionmodel #hotgirl #stunning #fitgirl #portraitmodel #edgyfashion"
    item["instagram_caption"] = f"{caption} 🔥😈{hashtags}"
    
    item["status"] = "pending"
    item["video_url"] = None
    item["post_url"] = None
    item["executed_at"] = None

data['prompts'] = prompts
with open(file_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"Updated {file_path} to be edgy/sassy and reset statuses.")
