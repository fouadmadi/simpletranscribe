# App Icons

Place your app icon here as `app.ico`.

## Requirements
- 256×256 pixels minimum (Windows requires multiple sizes embedded in a single .ico)
- Recommended sizes: 16, 32, 48, 256 pixels
- Use a tool like ImageMagick, GIMP, or an online .ico converter

## To generate from the macOS icon
```bash
# From the repo root, convert the macOS 512x512 icon:
convert simpletranscribe-mac/simpletranscribe/Assets.xcassets/AppIcon.appiconset/icon_512x512.png -resize 256x256 app.ico
```
