"""Train the crop leaf-disease classifier (TensorFlow/Keras, MobileNetV2 transfer learning).

Dataset: PlantVillage (one folder per class, e.g. Tomato___Early_blight). Use the colour images folder, e.g.
    <PlantVillage-Dataset>/raw/color
Usage (from backend/, venv active):
    python ml/disease_detection/train.py "C:\\path\\to\\PlantVillage-Dataset\\raw\\color"
Optional environment variables:  MAX_PER_CLASS (default 150, use 0 for all images)   EPOCHS (default 6)

Images of each class are split 70% train / 15% validation / 15% test BEFORE training (no leakage).
Everything reported is computed on the untouched test split. Requires: pip install tensorflow scikit-learn
"""
import json
import os
import random
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.metrics import f1_score

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(os.getenv("GEOYIELD_MODELS_DIR", ROOT / "models_store"))
SIZE, BATCH, SEED = 224, 32, 42
CAP = int(os.getenv("MAX_PER_CLASS", "150"))
EPOCHS = int(os.getenv("EPOCHS", "6"))
EXT = {".jpg", ".jpeg", ".png"}


def collect(data: Path):
    classes = sorted(d.name for d in data.iterdir() if d.is_dir())
    rng = random.Random(SEED)
    splits = {"train": ([], []), "val": ([], []), "test": ([], [])}
    for idx, c in enumerate(classes):
        files = sorted(str(p) for p in (data / c).iterdir() if p.suffix.lower() in EXT)
        rng.shuffle(files)
        if CAP > 0:
            files = files[:CAP]
        n = len(files)
        a, b = int(n * 0.70), int(n * 0.85)
        for name, part in (("train", files[:a]), ("val", files[a:b]), ("test", files[b:])):
            splits[name][0].extend(part)
            splits[name][1].extend([idx] * len(part))
    return classes, splits


def make_ds(paths, labels, training):
    ds = tf.data.Dataset.from_tensor_slices((paths, np.array(labels, dtype="int32")))
    if training:
        ds = ds.shuffle(len(paths), seed=SEED)

    def load(p, y):
        img = tf.io.decode_image(tf.io.read_file(p), channels=3, expand_animations=False)
        img = tf.image.resize(img, (SIZE, SIZE))
        img.set_shape((SIZE, SIZE, 3))
        return tf.cast(img, tf.float32), y

    return ds.map(load, num_parallel_calls=tf.data.AUTOTUNE).batch(BATCH).prefetch(tf.data.AUTOTUNE)


def main() -> None:
    if len(sys.argv) < 2 or not Path(sys.argv[1]).is_dir():
        raise SystemExit("Give the PlantVillage image folder path as the first argument.")
    classes, sp = collect(Path(sys.argv[1]))
    print(f"{len(classes)} classes | train {len(sp['train'][0])} | val {len(sp['val'][0])} | test {len(sp['test'][0])}")
    train, val, test = (make_ds(*sp["train"], True), make_ds(*sp["val"], False), make_ds(*sp["test"], False))

    weights = None if os.getenv("GEOYIELD_NO_PRETRAINED") else "imagenet"  # env var is only for offline code tests
    base = tf.keras.applications.MobileNetV2(input_shape=(SIZE, SIZE, 3), include_top=False, weights=weights)
    base.trainable = False
    inp = tf.keras.Input((SIZE, SIZE, 3))
    x = tf.keras.layers.RandomFlip("horizontal")(inp)
    x = tf.keras.layers.RandomRotation(0.1)(x)
    x = tf.keras.applications.mobilenet_v2.preprocess_input(x)
    x = base(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    out = tf.keras.layers.Dense(len(classes), activation="softmax")(x)
    model = tf.keras.Model(inp, out)
    model.compile("adam", "sparse_categorical_crossentropy", metrics=["accuracy"])
    model.fit(train, validation_data=val, epochs=EPOCHS,
              callbacks=[tf.keras.callbacks.EarlyStopping(patience=2, restore_best_weights=True)])

    loss, acc = model.evaluate(test, verbose=0)
    y_true = np.array(sp["test"][1])
    y_pred = np.argmax(model.predict(test, verbose=0), axis=1)
    metrics = {
        "dataset": "PlantVillage", "n_classes": len(classes), "max_images_per_class": CAP or "all",
        "train_images": len(sp["train"][0]), "test_images": len(y_true), "epochs_max": EPOCHS,
        "test_accuracy": round(float(acc), 4), "test_macro_f1": round(float(f1_score(y_true, y_pred, average="macro")), 4),
        "test_loss": round(float(loss), 4), "image_size": SIZE,
        "note": "PlantVillage photos are lab-style leaves on plain backgrounds; accuracy on real field photos is usually lower.",
    }
    OUT.mkdir(exist_ok=True)
    model.save(OUT / "disease_model.keras")
    (OUT / "disease_classes.json").write_text(json.dumps(classes, indent=2))
    (OUT / "disease_metrics.json").write_text(json.dumps(metrics, indent=2))
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
