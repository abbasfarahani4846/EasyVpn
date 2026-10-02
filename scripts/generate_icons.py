import os
import struct
from io import BytesIO
from PIL import Image

def make_windows_ico(src_img, out_path, sizes):
    entries = []
    image_data_list = []

    for w, h in sizes:
        resized = src_img.resize((w, h), Image.Resampling.LANCZOS)
        buf = BytesIO()
        if w >= 256:
            resized.save(buf, 'PNG')
            raw = buf.getvalue()
        else:
            resized.save(buf, 'DIB')
            dib = buf.getvalue()
            # Double height in BITMAPINFOHEADER for icon XOR+AND masks
            raw = dib[:8] + struct.pack('<I', h * 2) + dib[12:]
        image_data_list.append(raw)
        b_w = 0 if w >= 256 else w
        b_h = 0 if h >= 256 else h
        entries.append((b_w, b_h, 0, 0, 1, 32, len(raw)))

    offset = 6 + len(entries) * 16
    ico_bytes = bytearray(struct.pack('<HHH', 0, 1, len(entries)))

    for i, (bw, bh, col, res, planes, bpp, size) in enumerate(entries):
        ico_bytes.extend(struct.pack('<BBBBHHII', bw, bh, col, res, planes, bpp, size, offset))
        offset += size

    for raw in image_data_list:
        ico_bytes.extend(raw)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'wb') as f:
        f.write(ico_bytes)
    print(f"Saved Windows ICO: {out_path} ({len(ico_bytes)} bytes)")

def generate_icons():
    src_path = "assets/app_icon_1024.png"
    if not os.path.exists(src_path):
        raise FileNotFoundError(f"{src_path} not found")

    im = Image.open(src_path).convert("RGBA")
    print(f"Loaded master icon: {im.size}, mode: {im.mode}")

    # 1. Windows app_icon.ico (standard DIB for <= 128, PNG for 256)
    win_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    win_ico_path = "windows/runner/resources/app_icon.ico"
    make_windows_ico(im, win_ico_path, win_sizes)

    # 2. Tray icons (all standard DIB for Windows taskbar compatibility)
    tray_ico_path = "assets/tray_icon.ico"
    tray_png_path = "assets/tray_icon.png"
    make_windows_ico(im, tray_ico_path, [(16, 16), (24, 24), (32, 32), (48, 48)])
    im.resize((48, 48), Image.Resampling.LANCZOS).save(tray_png_path, "PNG")
    print(f"Saved: {tray_ico_path} and {tray_png_path}")

    # 3. Android mipmap icons
    android_scales = {
        "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, 48),
        "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": (72, 72),
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": (96, 96),
        "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": (144, 144),
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, 192),
    }
    for path, size in android_scales.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        im.resize(size, Image.Resampling.LANCZOS).save(path, "PNG")
        print(f"Saved: {path} ({size})")

    # 4. macOS icons
    mac_sizes = {
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": (16, 16),
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": (32, 32),
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": (64, 64),
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": (128, 128),
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": (256, 256),
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": (512, 512),
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": (1024, 1024),
    }
    for path, size in mac_sizes.items():
        if os.path.exists(os.path.dirname(path)):
            im.resize(size, Image.Resampling.LANCZOS).save(path, "PNG")
            print(f"Saved: {path} ({size})")

    # 5. iOS icons
    ios_sizes = {
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": (20, 20),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": (40, 40),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": (60, 60),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": (29, 29),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": (58, 58),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": (87, 87),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": (40, 40),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": (80, 80),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": (120, 120),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": (120, 120),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": (180, 180),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": (76, 76),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": (152, 152),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": (167, 167),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": (1024, 1024),
    }
    for path, size in ios_sizes.items():
        if os.path.exists(os.path.dirname(path)):
            im.resize(size, Image.Resampling.LANCZOS).save(path, "PNG")
            print(f"Saved: {path} ({size})")

if __name__ == "__main__":
    generate_icons()
