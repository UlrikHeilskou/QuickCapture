import os
from PIL import Image, ImageDraw

iconset_dir = "/Users/ulrikheilskou/Reminder/QuickCapture_mac/Resources/Assets.xcassets/AppIcon.appiconset"
os.makedirs(iconset_dir, exist_ok=True)

# Generate 1024x1024 icon
size = 1024
img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Background rounded rectangle (squircle-like)
# Gradient background from deep indigo/blue to cyan/purple
corner_radius = 224
bg_box = [64, 64, size - 64, size - 64]

# Draw background with rounded rectangle
draw.rounded_rectangle(bg_box, radius=corner_radius, fill=(35, 110, 245, 255))

# Draw an inner subtle border / glow
draw.rounded_rectangle([72, 72, size - 72, size - 72], radius=corner_radius - 8, outline=(120, 180, 255, 100), width=6)

# Draw viewfinder corner brackets (white/cyan)
line_width = 36
bracket_len = 160
bracket_color = (255, 255, 255, 240)

# Center box for viewfinder
x1, y1 = 280, 280
x2, y2 = 744, 744

# Top-Left corner
draw.line([(x1, y1 + bracket_len), (x1, y1), (x1 + bracket_len, y1)], fill=bracket_color, width=line_width, joint="curve")
# Top-Right corner
draw.line([(x2 - bracket_len, y1), (x2, y1), (x2, y1 + bracket_len)], fill=bracket_color, width=line_width, joint="curve")
# Bottom-Left corner
draw.line([(x1, y2 - bracket_len), (x1, y2), (x1 + bracket_len, y2)], fill=bracket_color, width=line_width, joint="curve")
# Bottom-Right corner
draw.line([(x2 - bracket_len, y2), (x2, y2), (x2, y2 - bracket_len)], fill=bracket_color, width=line_width, joint="curve")

# Center camera lens circle
lens_r = 110
cx, cy = size // 2, size // 2
draw.ellipse([cx - lens_r, cy - lens_r, cx + lens_r, cy + lens_r], fill=(255, 255, 255, 230))
draw.ellipse([cx - 70, cy - 70, cx + 70, cy + 70], fill=(35, 110, 245, 255))
draw.ellipse([cx - 40, cy - 40, cx + 40, cy + 40], fill=(255, 255, 255, 240))

# Small flash dot
draw.ellipse([cx + 120, cy - 120, cx + 150, cy - 90], fill=(255, 215, 0, 255))

# Save sizes
sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for s, name in sizes:
    resized = img.resize((s, s), Image.Resampling.LANCZOS)
    resized.save(os.path.join(iconset_dir, name))

# Write Contents.json
contents = """{
  "images" : [
    {
      "size" : "16x16",
      "idiom" : "mac",
      "filename" : "icon_16x16.png",
      "scale" : "1x"
    },
    {
      "size" : "16x16",
      "idiom" : "mac",
      "filename" : "icon_16x16@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "32x32",
      "idiom" : "mac",
      "filename" : "icon_32x32.png",
      "scale" : "1x"
    },
    {
      "size" : "32x32",
      "idiom" : "mac",
      "filename" : "icon_32x32@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "128x128",
      "idiom" : "mac",
      "filename" : "icon_128x128.png",
      "scale" : "1x"
    },
    {
      "size" : "128x128",
      "idiom" : "mac",
      "filename" : "icon_128x128@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "256x256",
      "idiom" : "mac",
      "filename" : "icon_256x256.png",
      "scale" : "1x"
    },
    {
      "size" : "256x256",
      "idiom" : "mac",
      "filename" : "icon_256x256@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "512x512",
      "idiom" : "mac",
      "filename" : "icon_512x512.png",
      "scale" : "1x"
    },
    {
      "size" : "512x512",
      "idiom" : "mac",
      "filename" : "icon_512x512@2x.png",
      "scale" : "2x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
"""

with open(os.path.join(iconset_dir, "Contents.json"), "w") as f:
    f.write(contents)

# Also root Contents.json for Assets.xcassets
with open("/Users/ulrikheilskou/Reminder/QuickCapture_mac/Resources/Assets.xcassets/Contents.json", "w") as f:
    f.write('{\n  "info" : {\n    "version" : 1,\n    "author" : "xcode"\n  }\n}')

print("Generated AppIcon.appiconset successfully.")
