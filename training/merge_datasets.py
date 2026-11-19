#!/usr/bin/env python3
"""
merge_datasets.py - combine several YOLO-format datasets (e.g. Roboflow exports)
into ONE clean dataset for the Bill Scanner model.

What it does
  1. Reads each source (a .zip file or an unzipped folder) WITHOUT changing it.
  2. Renames the classes (for example "1Dollar" -> "usd_1").
  3. Fixes photo rotation (EXIF) and shrinks big photos (default: longest side 800 px).
     Boxes are stored as fractions of the image, so resizing keeps them correct.
  4. Removes near-duplicate photos of the same class (they would otherwise end up in
     both train and test and make your accuracy look better than it really is).
  5. Re-splits everything into train / valid / test (70 / 20 / 10), class by class.
  6. Writes data.yaml, REPORT.txt, review_list.csv and review/ contact sheets that
     show photos worth a second look (for example a second, unlabeled bill).

Needs: Python 3.9+ and Pillow   (pip install pillow)

Example (one class per source zip):
  python merge_datasets.py --out merged --zip ^
      --source 1-dolar_yolov11.zip=usd_1 ^
      --source Euro_5_yolov11.zip=eur_5

A source with several classes can be mapped by name:
  --source big_export.zip=OldName1:php_100,OldName2:php_500

Run  python merge_datasets.py --help  for all options.
"""
import argparse
import csv
import io
import os
import random
import re
import shutil
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

IMG_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SPLIT_DIRS = {"train", "valid", "val", "test"}


# --------------------------------------------------------------------------- sources
class Source:
    """A zip file or a folder, read-only."""

    def __init__(self, path):
        self.path = Path(path)
        if not self.path.exists():
            raise SystemExit(f"Source not found: {path}")
        if self.path.is_file():
            if self.path.suffix.lower() != ".zip":
                raise SystemExit(f"Source must be a .zip file or a folder: {path}")
            self.zf = zipfile.ZipFile(self.path)
            names = [n for n in self.zf.namelist() if not n.endswith("/")]
        else:
            self.zf = None
            names = [
                p.relative_to(self.path).as_posix()
                for p in self.path.rglob("*")
                if p.is_file()
            ]
        self.names = list(dict.fromkeys(names))  # drop repeated entries
        for n in self.names:
            if n.startswith("/") or ".." in n.split("/"):
                raise SystemExit(f"Unsafe path inside {path}: {n}")

    def read(self, name):
        if self.zf is not None:
            return self.zf.read(name)
        return (self.path / name).read_bytes()

    def class_names(self):
        yaml_name = next((n for n in self.names if n.split("/")[-1] == "data.yaml"), None)
        if yaml_name is None:
            return None
        text = self.read(yaml_name).decode("utf-8", "replace")
        m = re.search(r"^names:\s*\[(.*?)\]", text, re.M | re.S)
        if m:
            return [s.strip().strip("'\"") for s in m.group(1).split(",") if s.strip()]
        m = re.search(r"^names:\s*\n((?:[ \t]+.*\n?)+)", text, re.M)
        if m:
            found = {}
            for line in m.group(1).splitlines():
                mm = re.match(r"\s*(\d+)\s*:\s*(.+?)\s*$", line)
                if mm:
                    found[int(mm.group(1))] = mm.group(2).strip("'\"")
            return [found[k] for k in sorted(found)]
        return None

    def image_label_pairs(self):
        """Yield (image_name, label_name or None) for every image in a train/valid/test folder."""
        nameset = set(self.names)
        for name in self.names:
            if Path(name).suffix.lower() not in IMG_EXT:
                continue
            parts = name.split("/")
            idx = next(
                (i for i in range(len(parts) - 2)
                 if parts[i] in SPLIT_DIRS and parts[i + 1] == "images"),
                None,
            )
            if idx is None:
                continue
            stem = Path(parts[-1]).stem
            label = "/".join(parts[: idx + 1] + ["labels", stem + ".txt"])
            yield name, (label if label in nameset else None)


def parse_source_arg(value):
    if "=" not in value:
        raise SystemExit(f"--source needs PATH=CLASS, got: {value}")
    path, spec = value.rsplit("=", 1)
    return path, spec.strip()


def make_class_resolver(spec, names, path):
    """Return a function old_class_id -> new class name (or None to drop the box)."""
    if ":" in spec:
        mapping = {}
        for pair in spec.split(","):
            old, new = pair.split(":", 1)
            mapping[old.strip()] = new.strip()
        if names is None:
            raise SystemExit(f"{path}: no data.yaml with class names, cannot map by name")
        by_id = {i: mapping[n] for i, n in enumerate(names) if n in mapping}
        return lambda cid: by_id.get(cid)
    if names is not None and len(names) != 1:
        raise SystemExit(
            f"{path} has {len(names)} classes {names}. Map them by name instead:\n"
            f"  --source {path}=old1:new1,old2:new2"
        )
    return lambda cid: spec


# --------------------------------------------------------------------------- helpers
def dhash(im, n=16):
    """256-bit 'difference hash': tiny fingerprint that survives resizing/re-compression."""
    g = im.convert("L").resize((n + 1, n), Image.LANCZOS).tobytes()
    bits = 0
    for r in range(n):
        for c in range(n):
            bits = (bits << 1) | (g[r * (n + 1) + c] > g[r * (n + 1) + c + 1])
    return bits


def parse_label_lines(text):
    """-> list of (class_id, cx, cy, w, h); polygons are converted to boxes."""
    boxes, bad = [], 0
    for line in text.splitlines():
        p = line.split()
        if not p:
            continue
        try:
            cid = int(float(p[0]))
            vals = [float(v) for v in p[1:]]
        except ValueError:
            bad += 1
            continue
        if len(vals) == 4:
            cx, cy, w, h = vals
            x1, y1, x2, y2 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
        elif len(vals) >= 6 and len(vals) % 2 == 0:
            xs, ys = vals[0::2], vals[1::2]
            x1, y1, x2, y2 = min(xs), min(ys), max(xs), max(ys)
        else:
            bad += 1
            continue
        x1, y1, x2, y2 = (min(1.0, max(0.0, v)) for v in (x1, y1, x2, y2))
        if x2 - x1 < 0.005 or y2 - y1 < 0.005:
            bad += 1
            continue
        boxes.append((cid, (x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1))
    return boxes, bad


def contact_sheet(items, out_path, cols=5, cell=260):
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 16)), "white")
    d = ImageDraw.Draw(sheet)
    for k, rec in enumerate(items):
        im = Image.open(io.BytesIO(rec["jpeg"])).convert("RGB")
        W, H = im.size
        dr = ImageDraw.Draw(im)
        lw = max(2, W // 120)
        for _, cx, cy, w, h in rec["boxes"]:
            dr.rectangle(
                [(cx - w / 2) * W, (cy - h / 2) * H, (cx + w / 2) * W, (cy + h / 2) * H],
                outline=(255, 0, 0), width=lw,
            )
        im.thumbnail((cell - 6, cell - 6))
        x, y = (k % cols) * cell, (k // cols) * (cell + 16)
        sheet.paste(im, (x + 3, y + 3))
        d.text((x + 3, y + cell - 2), rec["out_name"], fill=(0, 0, 0))
    sheet.save(out_path, quality=85)


# --------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", action="append", required=True, metavar="PATH=CLASS",
                    help="a zip/folder and the class name (or old:new,old2:new2 mapping)")
    ap.add_argument("--out", default="merged_dataset", help="output folder (default: merged_dataset)")
    ap.add_argument("--max-side", type=int, default=800, help="longest image side in px (default 800, 0 = keep)")
    ap.add_argument("--quality", type=int, default=85, help="JPEG quality (default 85)")
    ap.add_argument("--split", default="70,20,10", help="train,valid,test percentages (default 70,20,10)")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dup-threshold", type=int, default=12,
                    help="max difference (of 256 bits) to call two photos duplicates (default 12)")
    ap.add_argument("--small-box", type=float, default=0.45,
                    help="flag photos whose box covers less than this share of the image (default 0.45)")
    ap.add_argument("--zip", action="store_true", help="also create OUT.zip")
    args = ap.parse_args()

    split_pct = [float(v) for v in args.split.split(",")]
    if len(split_pct) != 3 or abs(sum(split_pct) - 100) > 0.01:
        raise SystemExit("--split must be three numbers that add up to 100, e.g. 70,20,10")

    out = Path(args.out)
    if out.exists():
        raise SystemExit(f"{out} already exists. Delete it or choose another --out.")

    class_order = []          # final class list, in the order given on the command line
    records = []              # one per usable photo
    skipped = []              # (source, file, reason)
    per_source = {}

    # ---- 1. read everything
    for value in args.source:
        path, spec = parse_source_arg(value)
        src = Source(path)
        resolve = make_class_resolver(spec, src.class_names(), path)
        stats = Counter()
        for img_name, lab_name in src.image_label_pairs():
            stats["images found"] += 1
            if lab_name is None:
                skipped.append((path, img_name, "no label file"))
                continue
            try:
                im = Image.open(io.BytesIO(src.read(img_name)))
                im.load()
            except Exception as e:  # noqa: BLE001
                skipped.append((path, img_name, f"unreadable image ({e})"))
                continue
            rotated = im.getexif().get(0x0112, 1) in range(2, 9)
            im = ImageOps.exif_transpose(im).convert("RGB")
            raw_boxes, bad = parse_label_lines(src.read(lab_name).decode("utf-8", "replace"))
            boxes, names = [], []
            for cid, cx, cy, w, h in raw_boxes:
                new = resolve(cid)
                if new is None:
                    stats["boxes dropped (class not mapped)"] += 1
                    continue
                if new not in class_order:
                    class_order.append(new)
                boxes.append((new, cx, cy, w, h))
                names.append(new)
            if bad:
                stats["bad label lines ignored"] += bad
            if not boxes:
                skipped.append((path, img_name, "no usable box"))
                continue
            orig_size = im.size
            if args.max_side and max(im.size) > args.max_side:
                im.thumbnail((args.max_side, args.max_side), Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=args.quality, optimize=True)
            cls = Counter(names).most_common(1)[0][0]
            area = max(w * h for _, _, _, w, h in boxes)
            records.append(dict(
                source=Path(path).name, orig=Path(img_name).name, cls=cls, boxes=boxes,
                jpeg=buf.getvalue(), hash=dhash(im), pixels=orig_size[0] * orig_size[1],
                area=area, rotated=rotated, flags=[],
            ))
            stats["photos kept so far"] += 1
            if rotated:
                stats["photos with EXIF rotation fixed"] += 1
        per_source[Path(path).name] = stats
        print(f"read {Path(path).name}: {stats['photos kept so far']} photos")

    if not records:
        raise SystemExit("No usable photos found.")

    # ---- 2. remove near-duplicates (same class); flag lookalikes across classes
    records.sort(key=lambda r: -r["pixels"])  # keep the biggest copy
    kept, dups, cross = [], [], []
    for rec in records:
        dup_of = None
        for k in kept:
            dist = bin(rec["hash"] ^ k["hash"]).count("1")
            if dist <= args.dup_threshold:
                if k["cls"] == rec["cls"]:
                    dup_of = (k, dist)
                    break
                cross.append((rec, k, dist))
        if dup_of:
            dups.append((rec, dup_of[0], dup_of[1]))
        else:
            kept.append(rec)
    records = kept

    # ---- 3. split per class
    rng = random.Random(args.seed)
    by_class = defaultdict(list)
    for rec in records:
        by_class[rec["cls"]].append(rec)
    for cls, items in by_class.items():
        rng.shuffle(items)
        n = len(items)
        n_test = max(1, round(n * split_pct[2] / 100)) if n >= 3 else 0
        n_valid = max(1, round(n * split_pct[1] / 100)) if n >= 3 else 0
        for i, rec in enumerate(items):
            rec["split"] = "test" if i < n_test else "valid" if i < n_test + n_valid else "train"
    counters = Counter()
    for rec in sorted(records, key=lambda r: (r["cls"], r["orig"])):
        counters[rec["cls"]] += 1
        rec["out_name"] = f"{rec['cls']}_{counters[rec['cls']]:04d}"

    # ---- 4. flags for manual review
    for rec in records:
        if rec["area"] < args.small_box:
            rec["flags"].append(
                f"box covers only {rec['area'] * 100:.0f}% of the photo - check for a second, unlabeled bill or a loose box")
        if len(rec["boxes"]) > 1:
            rec["flags"].append(f"{len(rec['boxes'])} boxes in this photo")
    kept_ids = {id(r) for r in records}
    for rec, other, dist in cross:
        if id(rec) in kept_ids:
            rec["flags"].append(f"looks like {other['out_name'] if 'out_name' in other else other['orig']} "
                                f"of class {other['cls']} (difference {dist}) - same photo under two classes?")

    # ---- 5. write the dataset
    for sp in ("train", "valid", "test"):
        (out / sp / "images").mkdir(parents=True)
        (out / sp / "labels").mkdir(parents=True)
    for rec in records:
        sp = rec["split"]
        (out / sp / "images" / f"{rec['out_name']}.jpg").write_bytes(rec["jpeg"])
        lines = [f"{class_order.index(c)} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}" for c, cx, cy, w, h in rec["boxes"]]
        (out / sp / "labels" / f"{rec['out_name']}.txt").write_text("\n".join(lines) + "\n")
    names_list = ", ".join(f"'{c}'" for c in class_order)
    (out / "data.yaml").write_text(
        "train: train/images\nval: valid/images\ntest: test/images\n\n"
        f"nc: {len(class_order)}\nnames: [{names_list}]\n"
    )

    flagged = [r for r in records if r["flags"]]
    with open(out / "review_list.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["file_in_dataset", "split", "class", "original_name", "from_source", "why_to_check"])
        for r in sorted(flagged, key=lambda r: r["out_name"]):
            w.writerow([f"{r['split']}/images/{r['out_name']}.jpg", r["split"], r["cls"],
                        r["orig"], r["source"], " | ".join(r["flags"])])
    if flagged:
        (out / "review").mkdir()
        flagged.sort(key=lambda r: r["out_name"])
        for i in range(0, len(flagged), 20):
            contact_sheet(flagged[i:i + 20], out / "review" / f"review_{i // 20 + 1:02d}.jpg")

    # ---- 6. report
    split_counts = defaultdict(Counter)
    for r in records:
        split_counts[r["cls"]][r["split"]] += 1
    lines = ["MERGE REPORT", "=" * 60, ""]
    lines.append(f"Classes ({len(class_order)}, in model order): {', '.join(class_order)}")
    lines.append(f"Photos in the final dataset: {len(records)}")
    lines.append(f"Settings: longest side {args.max_side}px, JPEG quality {args.quality}, "
                 f"split {args.split}, seed {args.seed}, duplicate threshold {args.dup_threshold}/256")
    lines += ["", "Photos per class and split", "-" * 60]
    lines.append(f"{'class':<12}{'train':>8}{'valid':>8}{'test':>8}{'total':>8}")
    for c in class_order:
        sc = split_counts[c]
        lines.append(f"{c:<12}{sc['train']:>8}{sc['valid']:>8}{sc['test']:>8}{sum(sc.values()):>8}")
    lines += ["", "Per source", "-" * 60]
    for name, st in per_source.items():
        lines.append(name + ": " + ", ".join(f"{k}={v}" for k, v in st.items()))
    lines += ["", f"Duplicates removed: {len(dups)}", "-" * 60]
    for rec, keeper, dist in dups:
        lines.append(f"  removed {rec['source']}/{rec['orig']}  (same as {keeper['source']}/{keeper['orig']}, difference {dist})")
    lines += ["", f"Skipped files: {len(skipped)}", "-" * 60]
    for s, n, why in skipped:
        lines.append(f"  {Path(s).name}/{n}: {why}")
    lines += ["", f"Photos flagged for a manual look: {len(flagged)} (see review_list.csv and review/*.jpg)", "-" * 60]
    (out / "REPORT.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    if args.zip:
        shutil.make_archive(str(out), "zip", root_dir=out.parent, base_dir=out.name)
    print("\n".join(lines[: 10 + len(class_order)]))
    print(f"\nDuplicates removed: {len(dups)} | skipped: {len(skipped)} | flagged for review: {len(flagged)}")
    print(f"Written to: {out.resolve()}")


if __name__ == "__main__":
    sys.exit(main())
