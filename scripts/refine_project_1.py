import json
import os

def refine_prompt(prompt):
    # Remove existing 9:16 portrait format to re-add it at the end
    prompt = prompt.replace(" 9:16 portrait format.", "")
    
    # Prefix
    if not prompt.startswith("Imagine the exact model"):
        prompt = "Imagine the exact model in a " + prompt[0].lower() + prompt[1:]
    
    # Realism clause
    realism_clause = " The image should be ultra realistic. The image should not be cartoonish or have AI smoothened edges. 9:16 portrait format."
    if realism_clause not in prompt:
        prompt += realism_clause
        
    # Sassy-ify adjectives
    replacements = {
        "vibrant": "neon-drenched",
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
    
    for old, new in replacements.items():
        prompt = prompt.replace(old, new)
        
    return prompt

def refine_caption(caption):
    # Add more emojis and hashtags
    hashtags = " #baddie #modelvibe #sultry #realisticai #fashionmodel #hotgirl #stunning #fitgirl #portraitmodel #edgyfashion"
    
    # Remove existing hashtags to avoid duplicates
    parts = caption.split("#")
    base_caption = parts[0].strip()
    
    # Add some spice to base caption if needed
    if "Basking" in base_caption:
        base_caption = base_caption.replace("Basking", "Owning")
    
    new_caption = f"{base_caption} 🔥😈{hashtags}"
    return new_caption

def main():
    file_path = "/Users/dsen/Projects/ai-post-maker/project-1/grok_prompts.json"
    with open(file_path, "r") as f:
        data = json.load(f)
        
    for item in data:
        item["prompt"] = refine_prompt(item["prompt"])
        item["instagram_caption"] = refine_caption(item["instagram_caption"])
        
    with open(file_path, "w") as f:
        json.dump(data, f, indent=2)
    
    print(f"Refined {len(data)} prompts in {file_path}")

if __name__ == "__main__":
    main()
