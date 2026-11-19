# Dataset guide: photographing and labeling the bills

The model is only as good as these photos. Plan for **several hours of photo-taking**, not minutes.

## Classes (exact names - the app expects these)

| Class      | Bill        |
|------------|-------------|
| `php_100`  | 100 pesos   |
| `php_500`  | 500 pesos   |
| `php_1000` | 1000 pesos  |
| `usd_1`    | 1 US dollar |
| `usd_5`    | 5 US dollars |
| `usd_20`   | 20 US dollars |
| `eur_5`    | 5 euros     |
| `eur_10`   | 10 euros    |
| `eur_20`   | 20 euros    |

Different versions of the same bill (peso paper and polymer, older and newer dollar or euro designs) share **one class**. If you want the app to recognize a version, you must photograph that version.

## What to photograph (per class)

- **Both sides** of the bill, and **each version** you can get (peso paper / polymer; older / newer dollar and euro designs).
- How many photos **per class** (all sides and versions together): about **30** to test that the whole pipeline works, about **150-300** for decent results, more if the confusion matrix shows mix-ups. With nine classes that is roughly 1,400-2,700 photos for a good model.
- Vary everything: daylight, indoor light, dim light, flashlight on; plain table, patterned cloth, hand-held, in a wallet pocket opening; flat, slightly curved, folded, crumpled; close and far (bill fills 30% to 100% of the frame); slight tilts.
- Use the **same phone you will demo on**.
- If you can, use **2-3 different physical notes** per class so the model does not memorize one bill's creases.
- Add **~10% background-only photos** (hands, table, receipts, other-colored paper, other currencies) and import them with **no boxes**, so the model learns "no bill".
- Faster way: record 30-60 second videos while slowly moving the bill, and let Roboflow sample frames from the video when you upload. Keep each video entirely in one split (see below).

Bills that look alike in color need extra photos so the model learns the difference: the blue `php_1000` vs the blue-ish `eur_20`, and the green `usd_1` vs `usd_20`. Check the confusion matrix after the first training run to see which pairs really get mixed up.

## Splitting (avoid fooling yourself)

Keep photos from the **same session** (and all frames of the same video) in the **same split** (train / valid / test). Otherwise near-identical images land in both train and test, and your accuracy will look much better than it really is. Suggested split: 70% train / 20% valid / 10% test, with the test set from a **different day or place** if possible.

## Labeling in Roboflow

1. Create a project -> *Object Detection*.
2. Create the nine classes with the exact names above.
3. Upload photos, draw **one tight box per bill** (the whole bill, not just the portrait).
4. Generate a version: resize to 640x640 (stretch or fit - either is fine), add augmentations (brightness, blur, small rotation). Do **not** augment the test split. Do not turn on horizontal flip (mirrored bills never happen in real life) or strong hue shifts (color is a key clue between bills).
5. Export -> format **YOLOv8** -> download zip -> upload to Google Drive as `bills.zip`.

Roboflow orders classes alphabetically, so the class order will not be the order in the table. That is fine: the notebook writes `labels.txt` from the trained model, so the order is always consistent.

## The prepared USD + EUR dataset (`datasets/usd_eur_dataset.zip`)

Six of the nine classes are already collected, renamed (`usd_1` ... `eur_20`), de-duplicated, resized and split 70/20/10. Inside the zip:

- `REPORT.txt` - counts per class and split, removed duplicates.
- `review_list.csv` and `review/*.jpg` - photos worth a second look, with their file names.

Known problem: in many photos (stock-photo sheets, graded-bill holders, front-and-back pairs) a **second bill has no box**. Training on those teaches the model that real bills are background. For every photo on the review sheets, either draw a box around the second bill or delete the photo (Roboflow does both). Not every flagged photo is wrong: a small box is normal when a bill lies on a big table.

## Rule of thumb for labeling

**Every bill in a photo gets a box, or the photo is deleted.** Boxes should be tight around the whole bill.

## Adding the PHP classes

Photos of the peso bills are not included. Collect or download them, then merge everything with `merge_datasets.py` on your own computer (no upload limits; it also shrinks big photos):

```
python merge_datasets.py --out final_dataset --zip ^
  --source datasets/usd_eur_dataset.zip=usd_1:usd_1,usd_5:usd_5,usd_20:usd_20,eur_5:eur_5,eur_10:eur_10,eur_20:eur_20 ^
  --source your_php100.zip=php_100 ^
  --source your_php500.zip=php_500 ^
  --source your_php1000.zip=php_1000
```

(Use `\` instead of `^` on Mac/Linux. Needs `pip install pillow`.) The result, `final_dataset.zip`, is what you upload to Google Drive as `bills.zip` for the notebook.
