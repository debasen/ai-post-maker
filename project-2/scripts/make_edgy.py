import json
import re

with open('/Users/dsen/Projects/ai-post-maker/project-2/grok_prompts.json', 'r') as f:
    prompts = json.load(f)

edgy_replacements = {
    "vibrant": "neon-drenched, sultry",
    "playful glance": "piercing, seductive stare",
    "delicate white floral mini dress": "sheer black lace cut-out mini dress",
    "soft smile": "fierce smirk",
    "sunlit": "moody, dramatically lit",
    "pristine white sand beach": "secluded, wild black sand beach at midnight",
    "colorful tropical print": "strappy, bold snakeskin print",
    "chic beige pleated": "distressed black denim micro",
    "pastel pink": "crimson red latex",
    "gazing dreamily": "giving a rebellious, untamed look",
    "warmly": "wickedly",
    "joyful": "wild, uninhibited",
    "relaxed-fit linen": "form-fitting sheer mesh",
    "sophisticated": "daring",
    "serene": "intense, provocative",
    "elegant": "unapologetically bold",
    "soft pink pastel": "dark velvet",
    "cozy": "rebellious",
    "sweetly": "mischievously",
    "calm and ethereal": "mysterious and alluring"
}

caption_replacements = {
    "Neon nights": "Owning the neon nights",
    "Basking in": "Commanding the room in",
    "Sunset state of mind": "Wild at heart, untamed at sunset",
    "Getting wonderfully lost": "Making my own rules",
    "Infinity pool dreams": "Too glam to give a damn",
    "Urban aesthetics": "Rebel soul, city streets",
    "Finding inspiration": "Disrupting the norm",
    "Breathtaking views": "Looking down from the top",
    "Sweet tooth satisfied!": "Sugar and a lot of spice."
}

for item in prompts:
    # Make edgy
    p = item["prompt"]
    for k, v in edgy_replacements.items():
        p = re.sub(k, v, p, flags=re.IGNORECASE)
    
    # Add a spicy vibe at the end if it doesn't sound edgy enough
    if "sultry" not in p and "fierce" not in p and "bold" not in p and "rebellious" not in p:
        p = p.replace("9:16 portrait format.", "Sassy, spicy vibe with a confident, edgy attitude. 9:16 portrait format.")
    
    item["prompt"] = p
    
    # Modify caption
    c = item.get("instagram_caption", "")
    for k, v in caption_replacements.items():
        c = c.replace(k, v)
        
    if "🔥" not in c and "✨" not in c:
         c += " 🔥😈"
    else:
         c = c.replace("✨", "🔥").replace("💛", "🖤").replace("🌿", "🥀")
         
    if not c.endswith("🔥") and not c.endswith("😈"):
         c += " 🖤🔥"

    item["instagram_caption"] = c
    
    # Reset tracking
    item["status"] = "pending"
    item["video_url"] = None
    item["post_url"] = None
    item["executed_at"] = None

with open('/Users/dsen/Projects/ai-post-maker/project-2/grok_prompts.json', 'w') as f:
    json.dump(prompts, f, indent=2)

print("Updated prompts to be edgy/sassy and reset statuses.")
