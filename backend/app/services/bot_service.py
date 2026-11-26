"""WhatsApp / SMS bot brain (Telugu, Hindi, English). No smartphone skills needed: the farmer just texts.

Examples the farmer can send:   \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2      (crop, district, acres -> yield)
                                 \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2 2300 (... plus price Rs/quintal -> income)
                                 \u0C32\u0C3E\u0C2D\u0C02 \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2     (which crop earns most)
                                 \u0C27\u0C30 \u0C35\u0C30\u0C3F             (mandi price)       \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41  (government schemes)
Roman letters work too:          vari nalgonda 2 / schemes / profit nalgonda 2
Works as plain functions, so it can be tested without Twilio. See routes/upgrade.py for the web hooks.
"""
import hashlib
import os
import re
from datetime import datetime, timezone

from app.database import db
from app.services import prices, profit_service, schemes_service, yield_service

ACRE_PER_HA = 2.471
LANG_WORDS = {"english": "en", "en": "en", "\u0C07\u0C02\u0C17\u0C4D\u0C32\u0C40\u0C37\u0C4D": "en", "\u0C05\u0C02\u0C17\u0C4D\u0C32\u0C02": "en",
              "telugu": "te", "te": "te", "\u0C24\u0C46\u0C32\u0C41\u0C17\u0C41": "te",
              "hindi": "hi", "\u0939\u093F\u0928\u094D\u0926\u0940": "hi", "\u0939\u093F\u0902\u0926\u0940": "hi"}
MENU_WORDS = {"hi", "hello", "hey", "menu", "help", "start", "0", "\u0C28\u0C2E\u0C38\u0C4D\u0C24\u0C47", "\u0C28\u0C2E\u0C38\u0C4D\u0C15\u0C3E\u0C30\u0C02", "\u0C39\u0C32\u0C4B", "\u0C38\u0C39\u0C3E\u0C2F\u0C02", "\u0C2E\u0C46\u0C28\u0C42", "\u0C2E\u0C46\u0C28\u0C41",
              "\u0928\u092E\u0938\u094D\u0924\u0947", "\u092E\u0926\u0926", "\u092E\u0947\u0928\u0942", "\u0939\u0947\u0932\u094D\u092A"}
SCHEME_WORDS = ["scheme", "subsidy", "\u0C2A\u0C25\u0C15", "\u0C38\u0C2C\u0C4D\u0C38\u0C3F\u0C21\u0C40", "\u0C38\u0C4D\u0C15\u0C40\u0C2E\u0C4D", "\u092F\u094B\u091C\u0928\u093E", "\u0938\u092C\u094D\u0938\u093F\u0921\u0940"]
PROFIT_WORDS = ["profit", "income", "earn", "\u0C32\u0C3E\u0C2D\u0C02", "\u0C32\u0C3E\u0C2D", "\u0C06\u0C26\u0C3E\u0C2F\u0C02", "\u092E\u0941\u0928\u093E\u092B\u093E", "\u092E\u0941\u0928\u093E\u092B\u093C\u093E", "\u0932\u093E\u092D", "\u0915\u092E\u093E\u0908"]
PRICE_WORDS = ["price", "rate", "\u0C27\u0C30", "\u0C30\u0C47\u0C1F\u0C41", "\u0C2D\u0C3E\u0C35\u0C02", "\u092D\u093E\u0935", "\u0915\u0940\u092E\u0924", "\u0926\u093E\u092E"]
HECTARE_WORDS = ["hectare", "hectar", "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C4D", "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C41", "\u0939\u0947\u0915\u094D\u091F\u0947\u092F\u0930"]

# crop (model name): (english, telugu, hindi, extra aliases)
CROPS = {
    "Rice": ("rice", "\u0C35\u0C30\u0C3F", "\u0927\u093E\u0928", ["\u0C27\u0C3E\u0C28\u0C4D\u0C2F\u0C02", "vari", "paddy", "dhan", "chawal", "\u091A\u093E\u0935\u0932"]),
    "Maize": ("maize", "\u0C2E\u0C4A\u0C15\u0C4D\u0C15\u0C1C\u0C4A\u0C28\u0C4D\u0C28", "\u092E\u0915\u094D\u0915\u093E", ["mokkajonna", "corn"]),
    "Jowar": ("jowar", "\u0C1C\u0C4A\u0C28\u0C4D\u0C28", "\u091C\u094D\u0935\u093E\u0930", ["\u0C1C\u0C4A\u0C28\u0C4D\u0C28\u0C32\u0C41", "jonna", "sorghum"]),
    "Bajra": ("bajra", "\u0C38\u0C1C\u0C4D\u0C1C", "\u092C\u093E\u091C\u0930\u093E", ["\u0C38\u0C1C\u0C4D\u0C1C\u0C32\u0C41", "sajja"]),
    "Ragi": ("ragi", "\u0C30\u0C3E\u0C17\u0C3F", "\u0930\u093E\u0917\u0940", ["\u0C30\u0C3E\u0C17\u0C41\u0C32\u0C41"]),
    "Wheat": ("wheat", "\u0C17\u0C4B\u0C27\u0C41\u0C2E", "\u0917\u0947\u0939\u0942\u0902", ["\u0C17\u0C4B\u0C27\u0C41\u0C2E\u0C32\u0C41", "godhuma", "\u0917\u0947\u0939\u0942\u0901"]),
    "Arhar/Tur": ("red gram (tur)", "\u0C15\u0C02\u0C26\u0C3F", "\u0905\u0930\u0939\u0930", ["kandi", "tur", "toor", "arhar", "red gram", "\u0924\u0942\u0930"]),
    "Gram": ("chickpea (gram)", "\u0C36\u0C28\u0C17", "\u091A\u0928\u093E", ["\u0C36\u0C28\u0C17\u0C32\u0C41", "senaga", "chana", "gram", "chickpea"]),
    "Moong(Green Gram)": ("green gram (moong)", "\u0C2A\u0C46\u0C38\u0C30", "\u092E\u0942\u0902\u0917", ["\u0C2A\u0C46\u0C38\u0C32\u0C41", "pesara", "pesalu", "moong", "green gram", "mung"]),
    "Urad": ("black gram (urad)", "\u0C2E\u0C3F\u0C28\u0C41\u0C2E\u0C41", "\u0909\u0921\u093C\u0926", ["\u0C2E\u0C3F\u0C28\u0C41\u0C2E\u0C41\u0C32\u0C41", "minumu", "urad", "black gram"]),
    "Groundnut": ("groundnut", "\u0C35\u0C47\u0C30\u0C41\u0C36\u0C28\u0C17", "\u092E\u0942\u0902\u0917\u092B\u0932\u0940", ["verusenaga", "peanut", "groundnut"]),
    "Sunflower": ("sunflower", "\u0C2A\u0C4A\u0C26\u0C4D\u0C26\u0C41\u0C24\u0C3F\u0C30\u0C41\u0C17\u0C41\u0C21\u0C41", "\u0938\u0942\u0930\u091C\u092E\u0941\u0916\u0940", []),
    "Sesamum": ("sesame", "\u0C28\u0C41\u0C35\u0C4D\u0C35\u0C41\u0C32\u0C41", "\u0924\u093F\u0932", ["nuvvulu", "sesame", "gingelly"]),
    "Castor seed": ("castor", "\u0C06\u0C2E\u0C41\u0C26\u0C02", "\u0905\u0930\u0902\u0921\u0940", ["amudam", "castor"]),
    "Soyabean": ("soybean", "\u0C38\u0C4B\u0C2F\u0C3E\u0C2C\u0C40\u0C28\u0C4D", "\u0938\u094B\u092F\u093E\u092C\u0940\u0928", ["soyabean", "soya"]),
    "Dry chillies": ("chilli", "\u0C2E\u0C3F\u0C30\u0C4D\u0C1A\u0C3F", "\u092E\u093F\u0930\u094D\u091A", ["\u0C2E\u0C3F\u0C30\u0C2A", "\u0C2E\u0C3F\u0C30\u0C2A\u0C15\u0C3E\u0C2F", "mirchi", "mirapa", "chili", "chilly"]),
    "Turmeric": ("turmeric", "\u0C2A\u0C38\u0C41\u0C2A\u0C41", "\u0939\u0932\u094D\u0926\u0940", ["pasupu"]),
    "Onion": ("onion", "\u0C09\u0C32\u0C4D\u0C32\u0C3F", "\u092A\u094D\u092F\u093E\u091C", ["\u0C09\u0C32\u0C4D\u0C32\u0C3F\u0C2A\u0C3E\u0C2F", "ulli"]),
    "Potato": ("potato", "\u0C2C\u0C02\u0C17\u0C3E\u0C33\u0C26\u0C41\u0C02\u0C2A", "\u0906\u0932\u0942", ["\u0C06\u0C32\u0C41\u0C17\u0C21\u0C4D\u0C21", "batata"]),
    "Tomato": ("tomato", "\u0C1F\u0C2E\u0C3E\u0C1F\u0C3E", "\u091F\u092E\u093E\u091F\u0930", ["\u0C1F\u0C2E\u0C4B\u0C1F\u0C3E", "tomata"]),
    "Brinjal": ("brinjal", "\u0C35\u0C02\u0C15\u0C3E\u0C2F", "\u092C\u0948\u0902\u0917\u0928", ["vankaya", "eggplant"]),
    "Bhindi": ("okra (bhindi)", "\u0C2C\u0C46\u0C02\u0C21\u0C15\u0C3E\u0C2F", "\u092D\u093F\u0902\u0921\u0940", ["\u0C2C\u0C46\u0C02\u0C21", "bendakaya", "bhindi", "okra"]),
    "Banana": ("banana", "\u0C05\u0C30\u0C1F\u0C3F", "\u0915\u0947\u0932\u093E", ["arati"]),
    "Mango": ("mango", "\u0C2E\u0C3E\u0C2E\u0C3F\u0C21\u0C3F", "\u0906\u092E", ["mamidi"]),
    "Sugarcane": ("sugarcane", "\u0C1A\u0C46\u0C30\u0C15\u0C41", "\u0917\u0928\u094D\u0928\u093E", ["cheruku"]),
    "Rapeseed &Mustard": ("mustard", "\u0C06\u0C35\u0C3E\u0C32\u0C41", "\u0938\u0930\u0938\u094B\u0902", ["mustard"]),
    "Masoor": ("lentil (masoor)", "\u0C2E\u0C38\u0C42\u0C30\u0C4D", "\u092E\u0938\u0942\u0930", ["masoor", "lentil"]),
}
CROP_ALIASES = sorted(
    [(a.lower().replace("\u200c", ""), c) for c, (en, te, hi, extra) in CROPS.items() for a in {en, te, hi, c.lower(), *extra}],
    key=lambda x: -len(x[0]))

# district names in Telugu script (old district names used in the government data)
TELUGU_DISTRICTS = {
    "\u0C06\u0C26\u0C3F\u0C32\u0C3E\u0C2C\u0C3E\u0C26\u0C4D": "ADILABAD", "\u0C39\u0C48\u0C26\u0C30\u0C3E\u0C2C\u0C3E\u0C26\u0C4D": "HYDERABAD", "\u0C15\u0C30\u0C40\u0C02\u0C28\u0C17\u0C30\u0C4D": "KARIMNAGAR", "\u0C16\u0C2E\u0C4D\u0C2E\u0C02": "KHAMMAM",
    "\u0C2E\u0C39\u0C2C\u0C42\u0C2C\u0C4D\u200C\u0C28\u0C17\u0C30\u0C4D": "MAHBUBNAGAR", "\u0C2E\u0C39\u0C2C\u0C42\u0C2C\u0C4D \u0C28\u0C17\u0C30\u0C4D": "MAHBUBNAGAR", "\u0C2E\u0C46\u0C26\u0C15\u0C4D": "MEDAK", "\u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21": "NALGONDA",
    "\u0C28\u0C32\u0C4D\u0C32\u0C17\u0C4A\u0C02\u0C21": "NALGONDA", "\u0C28\u0C3F\u0C1C\u0C3E\u0C2E\u0C3E\u0C2C\u0C3E\u0C26\u0C4D": "NIZAMABAD", "\u0C30\u0C02\u0C17\u0C3E\u0C30\u0C46\u0C21\u0C4D\u0C21\u0C3F": "RANGAREDDI", "\u0C35\u0C30\u0C02\u0C17\u0C32\u0C4D": "WARANGAL",
    "\u0C05\u0C28\u0C02\u0C24\u0C2A\u0C41\u0C30\u0C02": "ANANTAPUR", "\u0C1A\u0C3F\u0C24\u0C4D\u0C24\u0C42\u0C30\u0C41": "CHITTOOR", "\u0C24\u0C42\u0C30\u0C4D\u0C2A\u0C41 \u0C17\u0C4B\u0C26\u0C3E\u0C35\u0C30\u0C3F": "EAST GODAVARI", "\u0C17\u0C41\u0C02\u0C1F\u0C42\u0C30\u0C41": "GUNTUR",
    "\u0C15\u0C21\u0C2A": "KADAPA", "\u0C15\u0C43\u0C37\u0C4D\u0C23\u0C3E": "KRISHNA", "\u0C15\u0C30\u0C4D\u0C28\u0C42\u0C32\u0C41": "KURNOOL", "\u0C2A\u0C4D\u0C30\u0C15\u0C3E\u0C36\u0C02": "PRAKASAM", "\u0C28\u0C46\u0C32\u0C4D\u0C32\u0C42\u0C30\u0C41": "SPSR NELLORE",
    "\u0C36\u0C4D\u0C30\u0C40\u0C15\u0C3E\u0C15\u0C41\u0C33\u0C02": "SRIKAKULAM", "\u0C35\u0C3F\u0C36\u0C3E\u0C16\u0C2A\u0C1F\u0C4D\u0C28\u0C02": "VISAKHAPATANAM", "\u0C35\u0C3F\u0C1C\u0C2F\u0C28\u0C17\u0C30\u0C02": "VIZIANAGARAM",
    "\u0C2A\u0C36\u0C4D\u0C1A\u0C3F\u0C2E \u0C17\u0C4B\u0C26\u0C3E\u0C35\u0C30\u0C3F": "WEST GODAVARI"}
ROMAN_EXTRA = {"nellore": "SPSR NELLORE", "vizag": "VISAKHAPATANAM", "cuddapah": "KADAPA", "mahabubnagar": "MAHBUBNAGAR",
               "rangareddy": "RANGAREDDI", "ranga reddy": "RANGAREDDI", "nalagonda": "NALGONDA", "kurnool": "KURNOOL"}
STATE_PREFERENCE = ("Telangana", "Andhra Pradesh")

T = {
    "menu": {
        "en": "GeoYield AI - farmer help. Send:\n1. crop + district + acres (e.g. rice nalgonda 2) = yield\n2. schemes = government schemes\n3. profit + district + acres (e.g. profit nalgonda 2) = which crop earns most\n4. price rice = mandi price\nLanguage: English / \u0C24\u0C46\u0C32\u0C41\u0C17\u0C41 / \u0939\u093F\u0928\u094D\u0926\u0940",
        "te": "GeoYield AI - \u0C30\u0C48\u0C24\u0C41 \u0C38\u0C39\u0C3E\u0C2F\u0C02. \u0C07\u0C32\u0C3E \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F:\n1. \u0C2A\u0C02\u0C1F + \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E + \u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41 (\u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2) = \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F\n2. \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41 = \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41\n3. \u0C32\u0C3E\u0C2D\u0C02 + \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E + \u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41 (\u0C09\u0C26\u0C3E: \u0C32\u0C3E\u0C2D\u0C02 \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2) = \u0C0F \u0C2A\u0C02\u0C1F\u0C15\u0C41 \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02\n4. \u0C27\u0C30 \u0C35\u0C30\u0C3F = \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30\n\u0C2D\u0C3E\u0C37: English / \u0C24\u0C46\u0C32\u0C41\u0C17\u0C41 / \u0939\u093F\u0928\u094D\u0926\u0940",
        "hi": "GeoYield AI - \u0915\u093F\u0938\u093E\u0928 \u0938\u0939\u093E\u092F\u0924\u093E\u0964 \u0910\u0938\u0947 \u092D\u0947\u091C\u0947\u0902:\n1. \u092B\u0938\u0932 + \u091C\u093C\u093F\u0932\u093E + \u090F\u0915\u0921\u093C (\u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2) = \u0909\u092A\u091C\n2. \u092F\u094B\u091C\u0928\u093E = \u0938\u0930\u0915\u093E\u0930\u0940 \u092F\u094B\u091C\u0928\u093E\u090F\u0901\n3. \u092E\u0941\u0928\u093E\u092B\u093E + \u091C\u093C\u093F\u0932\u093E + \u090F\u0915\u0921\u093C (\u091C\u0948\u0938\u0947: \u092E\u0941\u0928\u093E\u092B\u093E nalgonda 2) = \u0915\u093F\u0938 \u092B\u0938\u0932 \u0938\u0947 \u091C\u093C\u094D\u092F\u093E\u0926\u093E \u0906\u092F\n4. \u092D\u093E\u0935 \u0927\u093E\u0928 = \u092E\u0902\u0921\u0940 \u092D\u093E\u0935\n\u092D\u093E\u0937\u093E: English / \u0C24\u0C46\u0C32\u0C41\u0C17\u0C41 / \u0939\u093F\u0928\u094D\u0926\u0940"},
    "lang_set": {"en": "Language set to English.", "te": "\u0C2D\u0C3E\u0C37 \u0C24\u0C46\u0C32\u0C41\u0C17\u0C41\u0C15\u0C41 \u0C2E\u0C3E\u0C30\u0C4D\u0C1A\u0C3E\u0C02.", "hi": "\u092D\u093E\u0937\u093E \u0939\u093F\u0928\u094D\u0926\u0940 \u0915\u0930 \u0926\u0940 \u0917\u0908\u0964"},
    "need_crop": {"en": "Which crop? Example: rice nalgonda 2", "te": "\u0C0F \u0C2A\u0C02\u0C1F? \u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2", "hi": "\u0915\u094C\u0928 \u0938\u0940 \u092B\u0938\u0932? \u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2"},
    "need_district": {"en": "Which district? Example: rice nalgonda 2", "te": "\u0C0F \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E? \u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2", "hi": "\u0915\u094C\u0928 \u0938\u093E \u091C\u093C\u093F\u0932\u093E? \u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2"},
    "need_both": {"en": "Please send crop, district and acres. Example: rice nalgonda 2", "te": "\u0C2A\u0C02\u0C1F, \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E, \u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41 \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F. \u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2", "hi": "\u092B\u0938\u0932, \u091C\u093C\u093F\u0932\u093E \u0914\u0930 \u090F\u0915\u0921\u093C \u092D\u0947\u091C\u0947\u0902\u0964 \u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2"},
    "fail": {"en": "Sorry, I could not work this out: {e}", "te": "\u0C15\u0C4D\u0C37\u0C2E\u0C3F\u0C02\u0C1A\u0C02\u0C21\u0C3F, \u0C07\u0C26\u0C3F \u0C32\u0C46\u0C15\u0C4D\u0C15\u0C3F\u0C02\u0C1A\u0C32\u0C47\u0C15\u0C2A\u0C4B\u0C2F\u0C3E\u0C02: {e}", "hi": "\u0915\u094D\u0937\u092E\u093E \u0915\u0930\u0947\u0902, \u092F\u0939 \u0939\u093F\u0938\u093E\u092C \u0928\u0939\u0940\u0902 \u0939\u094B \u0938\u0915\u093E: {e}"},
    "yield": {
        "en": "{crop}, {district} ({season}), {area} {unit}\nExpected yield: about {qa} quintals per acre (total about {qt} quintals).\n{income}This is only an estimate from old government records (up to 2015); real yield can differ.",
        "te": "{crop}, {district} ({season}), {area} {unit}\n\u0C05\u0C02\u0C1A\u0C28\u0C3E \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F: \u0C0E\u0C15\u0C30\u0C3E\u0C15\u0C41 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 {qa} \u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C33\u0C4D\u0C32\u0C41 (\u0C2E\u0C4A\u0C24\u0C4D\u0C24\u0C02 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 {qt} \u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C33\u0C4D\u0C32\u0C41).\n{income}\u0C07\u0C26\u0C3F 2015 \u0C35\u0C30\u0C15\u0C41 \u0C09\u0C28\u0C4D\u0C28 \u0C2A\u0C3E\u0C24 \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C30\u0C3F\u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41\u0C32 \u0C06\u0C27\u0C3E\u0C30\u0C02\u0C17\u0C3E \u0C05\u0C02\u0C1A\u0C28\u0C3E \u0C2E\u0C3E\u0C24\u0C4D\u0C30\u0C2E\u0C47; \u0C28\u0C3F\u0C1C\u0C2E\u0C48\u0C28 \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F \u0C2D\u0C3F\u0C28\u0C4D\u0C28\u0C02\u0C17\u0C3E \u0C09\u0C02\u0C21\u0C35\u0C1A\u0C4D\u0C1A\u0C41.",
        "hi": "{crop}, {district} ({season}), {area} {unit}\n\u0905\u092A\u0947\u0915\u094D\u0937\u093F\u0924 \u0909\u092A\u091C: \u0932\u0917\u092D\u0917 {qa} \u0915\u094D\u0935\u093F\u0902\u091F\u0932 \u092A\u094D\u0930\u0924\u093F \u090F\u0915\u0921\u093C (\u0915\u0941\u0932 \u0932\u0917\u092D\u0917 {qt} \u0915\u094D\u0935\u093F\u0902\u091F\u0932)\u0964\n{income}\u092F\u0939 2015 \u0924\u0915 \u0915\u0947 \u092A\u0941\u0930\u093E\u0928\u0947 \u0938\u0930\u0915\u093E\u0930\u0940 \u0930\u093F\u0915\u0949\u0930\u094D\u0921 \u092A\u0930 \u0906\u0927\u093E\u0930\u093F\u0924 \u0905\u0928\u0941\u092E\u093E\u0928 \u0939\u0948; \u0905\u0938\u0932\u0940 \u0909\u092A\u091C \u0905\u0932\u0917 \u0939\u094B \u0938\u0915\u0924\u0940 \u0939\u0948\u0964"},
    "income": {
        "en": "At Rs {p}/quintal ({src}) income is about Rs {rev} (costs not included).\n",
        "te": "\u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C32\u0C41\u0C15\u0C41 \u20B9{p} ({src}) \u0C2A\u0C4D\u0C30\u0C15\u0C3E\u0C30\u0C02 \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 \u20B9{rev} (\u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C41 \u0C15\u0C32\u0C2A\u0C32\u0C47\u0C26\u0C41).\n",
        "hi": "\u20B9{p}/\u0915\u094D\u0935\u093F\u0902\u091F\u0932 ({src}) \u092A\u0930 \u0906\u092F \u0932\u0917\u092D\u0917 \u20B9{rev} (\u0932\u093E\u0917\u0924 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902)\u0964\n"},
    "income_hint": {"en": "For income, also send the price. Example: rice nalgonda 2 2300\n", "te": "\u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C15\u0C4B\u0C38\u0C02 \u0C27\u0C30 \u0C15\u0C42\u0C21\u0C3E \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F. \u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2 2300\n", "hi": "\u0906\u092F \u0915\u0947 \u0932\u093F\u090F \u092D\u093E\u0935 \u092D\u0940 \u092D\u0947\u091C\u0947\u0902\u0964 \u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2 2300\n"},
    "src_typed": {"en": "your price", "te": "\u0C2E\u0C40\u0C30\u0C41 \u0C1A\u0C46\u0C2A\u0C4D\u0C2A\u0C3F\u0C28 \u0C27\u0C30", "hi": "\u0906\u092A\u0915\u093E \u092D\u093E\u0935"},
    "src_live": {"en": "mandi price", "te": "\u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30", "hi": "\u092E\u0902\u0921\u0940 \u092D\u093E\u0935"},
    "price_ok": {"en": "{crop} mandi price in {state}: Rs {p} per quintal ({date}, {n} markets). Source: Agmarknet.",
                 "te": "{state}\u0C32\u0C4B {crop} \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30: \u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C32\u0C41\u0C15\u0C41 \u20B9{p} ({date}, {n} \u0C2E\u0C3E\u0C30\u0C4D\u0C15\u0C46\u0C1F\u0C4D\u0C32\u0C41). \u0C2E\u0C42\u0C32\u0C02: Agmarknet.",
                 "hi": "{state} \u092E\u0947\u0902 {crop} \u0915\u093E \u092E\u0902\u0921\u0940 \u092D\u093E\u0935: \u20B9{p} \u092A\u094D\u0930\u0924\u093F \u0915\u094D\u0935\u093F\u0902\u091F\u0932 ({date}, {n} \u092C\u093E\u091C\u093C\u093E\u0930)\u0964 \u0938\u094D\u0930\u094B\u0924: Agmarknet\u0964"},
    "price_none": {"en": "Today's price was not found. Check your mandi and send: rice nalgonda 2 2300",
                   "te": "\u0C08 \u0C30\u0C4B\u0C1C\u0C41 \u0C27\u0C30 \u0C26\u0C4A\u0C30\u0C15\u0C32\u0C47\u0C26\u0C41. \u0C2E\u0C40 \u0C2E\u0C02\u0C21\u0C3F\u0C32\u0C4B \u0C1A\u0C42\u0C38\u0C3F \u0C07\u0C32\u0C3E \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2 2300",
                   "hi": "\u0906\u091C \u0915\u093E \u092D\u093E\u0935 \u0928\u0939\u0940\u0902 \u092E\u093F\u0932\u093E\u0964 \u0905\u092A\u0928\u0940 \u092E\u0902\u0921\u0940 \u092E\u0947\u0902 \u0926\u0947\u0916\u0915\u0930 \u092D\u0947\u091C\u0947\u0902: \u0927\u093E\u0928 nalgonda 2 2300"},
    "profit_head": {"en": "{district} ({season}), {area} {unit} - crops with best income:\n", "te": "{district} ({season}), {area} {unit} - \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C07\u0C1A\u0C4D\u0C1A\u0C47 \u0C2A\u0C02\u0C1F\u0C32\u0C41:\n", "hi": "{district} ({season}), {area} {unit} - \u0938\u092C\u0938\u0947 \u0905\u0927\u093F\u0915 \u0906\u092F \u0935\u093E\u0932\u0940 \u092B\u0938\u0932\u0947\u0902:\n"},
    "profit_line": {"en": "{i}. {crop}: about Rs {inc}\n", "te": "{i}. {crop}: \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 \u20B9{inc}\n", "hi": "{i}. {crop}: \u0932\u0917\u092D\u0917 \u20B9{inc}\n"},
    "profit_tail": {"en": "Income only, costs not included. Prices change daily.", "te": "\u0C07\u0C26\u0C3F \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C2E\u0C3E\u0C24\u0C4D\u0C30\u0C2E\u0C47, \u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C41 \u0C15\u0C32\u0C2A\u0C32\u0C47\u0C26\u0C41. \u0C27\u0C30\u0C32\u0C41 \u0C30\u0C4B\u0C1C\u0C42 \u0C2E\u0C3E\u0C30\u0C24\u0C3E\u0C2F\u0C3F.", "hi": "\u0915\u0947\u0935\u0932 \u0906\u092F, \u0932\u093E\u0917\u0924 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902\u0964 \u092D\u093E\u0935 \u0930\u094B\u091C\u093C \u092C\u0926\u0932\u0924\u0947 \u0939\u0948\u0902\u0964"},
    "profit_noprice": {"en": "No live prices. Send prices from your mandi, e.g.: profit nalgonda 2 rice=2300 maize=2100", "te": "\u0C32\u0C48\u0C35\u0C4D \u0C27\u0C30\u0C32\u0C41 \u0C32\u0C47\u0C35\u0C41. \u0C2E\u0C40 \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30\u0C32\u0C41 \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F, \u0C09\u0C26\u0C3E: \u0C32\u0C3E\u0C2D\u0C02 \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2 \u0C35\u0C30\u0C3F=2300 \u0C2E\u0C4A\u0C15\u0C4D\u0C15\u0C1C\u0C4A\u0C28\u0C4D\u0C28=2100", "hi": "\u0932\u093E\u0907\u0935 \u092D\u093E\u0935 \u0928\u0939\u0940\u0902 \u0939\u0948\u0902\u0964 \u0905\u092A\u0928\u0940 \u092E\u0902\u0921\u0940 \u0915\u0947 \u092D\u093E\u0935 \u092D\u0947\u091C\u0947\u0902, \u091C\u0948\u0938\u0947: \u092E\u0941\u0928\u093E\u092B\u093E nalgonda 2 \u0927\u093E\u0928=2300 \u092E\u0915\u094D\u0915\u093E=2100"},
    "schemes_head": {"en": "Government schemes:\n", "te": "\u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41:\n", "hi": "\u0938\u0930\u0915\u093E\u0930\u0940 \u092F\u094B\u091C\u0928\u093E\u090F\u0901:\n"},
    "schemes_tail": {"en": "For details send the scheme name, e.g. PMFBY.", "te": "\u0C35\u0C3F\u0C35\u0C30\u0C3E\u0C32\u0C15\u0C41 \u0C2A\u0C25\u0C15\u0C02 \u0C2A\u0C47\u0C30\u0C41 \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F, \u0C09\u0C26\u0C3E: PMFBY.", "hi": "\u0935\u093F\u0935\u0930\u0923 \u0915\u0947 \u0932\u093F\u090F \u092F\u094B\u091C\u0928\u093E \u0915\u093E \u0928\u093E\u092E \u092D\u0947\u091C\u0947\u0902, \u091C\u0948\u0938\u0947: PMFBY\u0964"},
    "how": {"en": "How: ", "te": "\u0C0E\u0C32\u0C3E: ", "hi": "\u0915\u0948\u0938\u0947: "},
}
SEASON_WORDS = {"kharif": "Kharif", "\u0C16\u0C30\u0C40\u0C2B\u0C4D": "Kharif", "\u0916\u0930\u0940\u092B": "Kharif", "rabi": "Rabi", "\u0C30\u0C2C\u0C40": "Rabi", "\u0930\u092C\u0940": "Rabi"}
SEASON_LABEL = {"Kharif": {"en": "Kharif", "te": "\u0C16\u0C30\u0C40\u0C2B\u0C4D", "hi": "\u0916\u0930\u0940\u092B"}, "Rabi": {"en": "Rabi", "te": "\u0C30\u0C2C\u0C40", "hi": "\u0930\u092C\u0940"}}
UNIT = {"acre": {"en": "acres", "te": "\u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41", "hi": "\u090F\u0915\u0921\u093C"}, "hectare": {"en": "hectares", "te": "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C4D\u0C32\u0C41", "hi": "\u0939\u0947\u0915\u094D\u091F\u0947\u092F\u0930"}}


def _tr(key: str, lang: str, **kw) -> str:
    s = T[key].get(lang) or T[key]["en"]
    return s.format(**kw) if kw else s


# ---------- small helpers ----------
def inr(n: float) -> str:
    """Indian digit grouping: 1234567 -> 12,34,567"""
    s = str(int(round(n)))
    if len(s) <= 3:
        return s
    head, tail = s[:-3], s[-3:]
    head = re.sub(r"(\d)(?=(\d\d)+$)", r"\1,", head)
    return head + "," + tail


def num(x: float) -> str:
    return str(int(x)) if float(x).is_integer() else str(round(x, 2))


def normalise(text: str) -> str:
    out = []
    for ch in text:
        o = ord(ch)
        if 0x0C66 <= o <= 0x0C6F:
            ch = str(o - 0x0C66)       # Telugu digits
        elif 0x0966 <= o <= 0x096F:
            ch = str(o - 0x0966)       # Hindi digits
        out.append(ch)
    s = "".join(out).lower().replace("\u200c", "").replace("\u200d", "")
    s = re.sub(r"[,;!?\"'()\[\]]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def detect_lang(text: str, saved: str | None) -> str:
    if re.search(r"[\u0C00-\u0C7F]", text):
        return "te"
    if re.search(r"[\u0900-\u097F]", text):
        return "hi"
    return saved or "en"


def _scan(text: str, pairs: list[tuple[str, object]]) -> list[tuple[int, int, object]]:
    """Find alias words in text (longest first, no overlaps). Latin words must be whole words."""
    taken = [False] * len(text)
    found = []
    for alias, val in pairs:
        start = 0
        while True:
            i = text.find(alias, start)
            if i < 0:
                break
            j = i + len(alias)
            start = i + 1
            if any(taken[i:j]):
                continue
            if alias[0].isascii() and alias[0].isalnum() and i > 0 and text[i - 1].isascii() and text[i - 1].isalnum():
                continue
            if alias[-1].isascii() and alias[-1].isalnum() and j < len(text) and text[j].isascii() and text[j].isalpha():
                continue
            for k in range(i, j):
                taken[k] = True
            found.append((i, j, val))
    return sorted(found, key=lambda x: x[0])


_dist_cache: list | None = None


def _district_pairs() -> list[tuple[str, tuple[str, str]]]:
    global _dist_cache
    if _dist_cache is not None:
        return _dist_cache
    opts = yield_service.options() or {}
    where: dict[str, list[tuple[str, str]]] = {}
    for state, ds in (opts.get("districts") or {}).items():
        for d in ds:
            where.setdefault(d, []).append((state, d))

    def pick(d):
        cands = where.get(d, [])
        for s in STATE_PREFERENCE:
            for c in cands:
                if c[0] == s:
                    return c
        return cands[0] if cands else None

    pairs = []
    for d in where:
        pairs.append((d.lower(), pick(d)))
    for alias, d in {**TELUGU_DISTRICTS, **ROMAN_EXTRA}.items():
        p = pick(d)
        if p:
            pairs.append((alias.lower().replace("\u200c", ""), p))
    _dist_cache = sorted(pairs, key=lambda x: -len(x[0]))
    return _dist_cache


def _district_label(district: str, lang: str) -> str:
    if lang == "te":
        for te, d in TELUGU_DISTRICTS.items():
            if d == district:
                return te
    return district.title()


def _season_now() -> str:
    m = datetime.now().month
    return "Kharif" if m in (4, 5, 6, 7, 8, 9, 10) else "Rabi"


def parse(text: str) -> dict:
    """Pull crop(s), district, numbers, season and unit out of a farmer's message."""
    low = normalise(text)
    crops = _scan(low, CROP_ALIASES)
    dists = _scan(low, _district_pairs())
    used = [(a, b) for a, b, _ in crops + dists]
    # crop=price pairs, e.g. "rice=2300"
    typed, pair_spans = {}, []
    for a, b, crop in crops:
        m = re.match(r"\s*[=:]\s*(\d+(?:\.\d+)?)", low[b:])
        if m:
            typed[crop] = float(m.group(1))
            pair_spans.append((b, b + m.end()))
    nums = [(m.start(), float(m.group())) for m in re.finditer(r"\d+(?:\.\d+)?", low)
            if not any(s <= m.start() < e for s, e in pair_spans + used)]
    price_pos = min((low.find(w) for w in PRICE_WORDS if w in low), default=-1)
    acres = price = None
    if price_pos >= 0 and nums:
        after = [n for n in nums if n[0] >= price_pos]
        pr = after[0] if after else nums[-1]
        price = pr[1]
        rest = [n for n in nums if n is not pr]
        acres = rest[0][1] if rest else None
    elif len(nums) >= 2:
        small, big = sorted(nums, key=lambda n: n[1])[0], sorted(nums, key=lambda n: n[1])[-1]
        acres, price = small[1], (big[1] if big[1] >= 100 else None)
    elif nums:
        acres = nums[0][1]
    season = next((v for k, v in SEASON_WORDS.items() if k in low), None)
    unit = "hectare" if (any(w in low for w in HECTARE_WORDS) or re.search(r"\bha\b", low)) else "acre"
    return {"low": low, "crops": [c for _, _, c in crops], "district": dists[0][2] if dists else None,
            "typed_prices": typed, "acres": acres, "price": price, "season": season, "unit": unit,
            "has_number": bool(nums or typed)}


# ---------- language memory (phone number is stored only as a hash) ----------
def ensure_tables() -> None:
    with db.connect() as c:
        c.execute("CREATE TABLE IF NOT EXISTS bot_users (id TEXT PRIMARY KEY, lang TEXT, updated_at TEXT)")


def _uid(phone: str) -> str:
    return hashlib.sha256((os.getenv("BOT_HASH_SALT", "geoyield") + phone).encode()).hexdigest()[:24]


def _saved_lang(phone: str) -> str | None:
    if not phone:
        return None
    try:
        with db.connect() as c:
            r = c.execute("SELECT lang FROM bot_users WHERE id=?", (_uid(phone),)).fetchone()
        return r["lang"] if r else None
    except Exception:
        return None


def _save_lang(phone: str, lang: str) -> None:
    if not phone:
        return
    try:
        with db.connect() as c:
            c.execute("INSERT INTO bot_users (id, lang, updated_at) VALUES (?,?,?) "
                      "ON CONFLICT(id) DO UPDATE SET lang=excluded.lang, updated_at=excluded.updated_at",
                      (_uid(phone), lang, datetime.now(timezone.utc).isoformat(timespec="seconds")))
    except Exception:
        pass


# ---------- replies ----------
def _crop_label(crop: str, lang: str) -> str:
    en, te, hi, _ = CROPS.get(crop, (crop, crop, crop, []))
    return {"te": te, "hi": hi}.get(lang, en.title() if crop in CROPS else crop)


def _schemes_reply(state, lang):
    data = schemes_service.for_farmer(state, None, None, lang)
    lines = "".join(f"- {s['name'].split(' (')[0]}: {s['short']}\n" for s in data["schemes"])
    return _tr("schemes_head", lang) + lines + _tr("schemes_tail", lang) + "\n" + data["note"]


def _yield_reply(p, state, district, lang, phone):
    crop, unit = p["crops"][0], p["unit"]
    area = p["acres"] or 1
    area_ha = area if unit == "hectare" else area / ACRE_PER_HA
    season = p["season"] or _season_now()
    inp = {"state": state, "district": district, "season": season, "crop": crop, "area_hectares": area_ha, "lang": lang}
    res = yield_service.predict(inp)
    if res.get("model_status") == "unavailable":
        return res["message"]
    if "error" in res:
        return _tr("fail", lang, e=res["error"])
    y = res["predicted_yield"]
    qa, qt = round(y * 10 / ACRE_PER_HA, 1), round(y * 10 * area_ha, 1)
    price, src = p["price"] or p["typed_prices"].get(crop), "src_typed"
    if not price:
        live = prices.latest_price(crop, state, district)
        price, src = (live["price"], "src_live") if live else (None, None)
    income = _tr("income", lang, p=inr(price), src=_tr(src, lang), rev=inr(qt * price)) if price else _tr("income_hint", lang)
    try:
        db.save_analysis("yield_prediction", {**inp, "source": "bot"}, res, f"{crop}: {y} t/ha (bot)",
                         {"model": "sklearn regressor", "status": "trained"})
    except Exception:
        pass
    return _tr("yield", lang, crop=_crop_label(crop, lang), district=_district_label(district, lang),
               season=SEASON_LABEL.get(season, {}).get(lang, season), area=num(area), unit=UNIT[unit][lang], qa=qa, qt=qt, income=income)


def _profit_reply(p, state, district, lang):
    area, unit = p["acres"] or 1, p["unit"]
    season = p["season"] or _season_now()
    res = profit_service.compare({"state": state, "district": district, "season": season, "area": area,
                                  "area_unit": unit, "prices": p["typed_prices"], "lang": lang})
    rows = [r for r in res.get("rows", []) if r.get("income") is not None][:3]
    if not rows:
        return _tr("profit_noprice", lang)
    out = _tr("profit_head", lang, area=num(area), unit=UNIT[unit][lang], district=_district_label(district, lang),
              season=SEASON_LABEL.get(season, {}).get(lang, season))
    for i, r in enumerate(rows, 1):
        out += _tr("profit_line", lang, i=i, crop=_crop_label(r["crop"], lang), inc=inr(r["income"]))
    return out + _tr("profit_tail", lang)


def handle(text: str, phone: str = "") -> dict:
    """Main entry: message in -> {"reply": str, "lang": str}."""
    saved = _saved_lang(phone)
    lang = detect_lang(text or "", saved)
    low = normalise(text or "")
    if low in LANG_WORDS:
        lang = LANG_WORDS[low]
        _save_lang(phone, lang)
        return {"reply": _tr("lang_set", lang) + "\n" + _tr("menu", lang), "lang": lang}
    if lang != saved and re.search(r"[\u0C00-\u0C7F\u0900-\u097F]", text or ""):
        _save_lang(phone, lang)
    if not low or low in MENU_WORDS:
        return {"reply": _tr("menu", lang), "lang": lang}
    p = parse(text)
    state, district = None, None
    if p["district"]:
        state, district = p["district"]
    wants_schemes = any(w in low for w in SCHEME_WORDS) or low == "2"
    if wants_schemes:
        one = schemes_service.find(low, state, lang)
        if one:
            return {"reply": f"{one['name']}\n{one['benefit']}\n{_tr('how', lang)}{one['how']}", "lang": lang}
        return {"reply": _schemes_reply(state, lang), "lang": lang}
    if low in ("1", "3", "4"):
        return {"reply": _tr("menu", lang), "lang": lang}
    if not p["crops"] and not wants_schemes:
        one = schemes_service.find(low, state, lang)
        if one and not any(w in low for w in PROFIT_WORDS):
            return {"reply": f"{one['name']}\n{one['benefit']}\n{_tr('how', lang)}{one['how']}", "lang": lang}
    try:
        if any(w in low for w in PROFIT_WORDS):
            if not district:
                return {"reply": _tr("need_district", lang), "lang": lang}
            return {"reply": _profit_reply(p, state, district, lang), "lang": lang}
        if p["crops"] and any(w in low for w in PRICE_WORDS) and not p["has_number"] and not district:
            crop = p["crops"][0]
            st = state or "Telangana"
            live = prices.latest_price(crop, st, None)
            if not live:
                return {"reply": _tr("price_none", lang), "lang": lang}
            return {"reply": _tr("price_ok", lang, crop=_crop_label(crop, lang), state=st, p=inr(live["price"]),
                                 date=live["date"], n=live["markets"]), "lang": lang}
        if p["crops"] and district:
            return {"reply": _yield_reply(p, state, district, lang, phone), "lang": lang}
        if p["crops"]:
            return {"reply": _tr("need_district", lang), "lang": lang}
        if district:
            return {"reply": _tr("need_crop", lang), "lang": lang}
    except Exception as e:  # never crash a farmer's chat
        return {"reply": _tr("fail", lang, e=str(e)[:120]), "lang": lang}
    return {"reply": _tr("need_both", lang) + "\n\n" + _tr("menu", lang), "lang": lang}
