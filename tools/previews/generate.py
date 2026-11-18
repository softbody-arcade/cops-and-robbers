import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


CLIENT = Path(__file__).resolve().parents[2] / "client"
SIZE = (1000, 560)


def preview_background():
    with Image.open(CLIENT / "mod_info/CopsAndRobbers/icon.jpg") as source:
        logo = ImageOps.contain(source.convert("RGB"), (392, 392), Image.Resampling.LANCZOS)

    width, height = logo.size
    canvas = Image.new("RGB", SIZE, logo.getpixel((0, height - 1)))
    left = (canvas.width - width) // 2
    right = left + width
    left_edge = logo.crop((0, 0, 1, height))
    right_edge = logo.crop((width - 1, 0, width, height))
    canvas.paste(left_edge.resize((left, height)), (0, 0))
    canvas.paste(logo, (left, 0))
    canvas.paste(right_edge.resize((canvas.width - right, height)), (right, 0))
    return canvas


def main():
    background = preview_background()
    font = ImageFont.truetype("DejaVuSans-Bold.ttf", 92)
    for manifest in sorted((CLIENT / "ui/modules/apps").glob("CopsAndRobbers*/app.json")):
        label = json.loads(manifest.read_text())["name"].removeprefix("Cops and Robbers ")
        preview = background.copy()
        ImageDraw.Draw(preview).text((preview.width // 2, 464), label, font=font,
                                     fill="#f6f6f9", anchor="mm")
        preview.save(manifest.with_name("app.png"))


if __name__ == "__main__":
    main()
