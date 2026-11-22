"""Backend text localisation (English / Hindi / Telugu).
All explanation text produced by the services goes through t(). Numbers and crop/fertilizer data are never translated,
only the wording around them. Translations were prepared with AI assistance: have a native speaker review them."""

LANGS = ("en", "hi", "te")


def _(en, hi, te):
    return {"en": en, "hi": hi, "te": te}


CROPS = {
    "apple": _("apple", "सेब", "ఆపిల్"), "banana": _("banana", "केला", "అరటి"),
    "blackgram": _("blackgram", "उड़द", "మినుములు"), "chickpea": _("chickpea", "चना", "శనగలు"),
    "coconut": _("coconut", "नारियल", "కొబ్బరి"), "coffee": _("coffee", "कॉफ़ी", "కాఫీ"),
    "cotton": _("cotton", "कपास", "పత్తి"), "grapes": _("grapes", "अंगूर", "ద్రాక్ష"),
    "jute": _("jute", "जूट", "జనపనార"), "kidneybeans": _("kidney beans", "राजमा", "రాజ్మా"),
    "lentil": _("lentil", "मसूर", "మసూర్ పప్పు"), "maize": _("maize", "मक्का", "మొక్కజొన్న"),
    "mango": _("mango", "आम", "మామిడి"), "mothbeans": _("moth beans", "मोठ", "మోత్ బీన్స్"),
    "mungbean": _("mung bean", "मूंग", "పెసలు"), "muskmelon": _("muskmelon", "खरबूजा", "ఖర్బూజా"),
    "orange": _("orange", "संतरा", "నారింజ"), "papaya": _("papaya", "पपीता", "బొప్పాయి"),
    "pigeonpeas": _("pigeon peas", "अरहर", "కందులు"), "pomegranate": _("pomegranate", "अनार", "దానిమ్మ"),
    "rice": _("rice", "चावल (धान)", "వరి"), "watermelon": _("watermelon", "तरबूज", "పుచ్చకాయ"),
}

M = {
    # ---- features / words
    "f_N": _("Nitrogen", "नाइट्रोजन", "నత్రజని (నైట్రోజన్)"),
    "f_P": _("Phosphorus", "फॉस्फोरस", "భాస్వరం (ఫాస్ఫరస్)"),
    "f_K": _("Potassium", "पोटैशियम", "పొటాషియం"),
    "f_temperature": _("Temperature", "तापमान", "ఉష్ణోగ్రత"),
    "f_humidity": _("Humidity", "आर्द्रता", "తేమ"),
    "f_ph": _("Soil pH", "मिट्टी का pH", "నేల pH"),
    "f_rainfall": _("Rainfall", "वर्षा", "వర్షపాతం"),
    "n_N": _("nitrogen", "नाइट्रोजन", "నత్రజని"), "n_P": _("phosphorus", "फॉस्फोरस", "భాస్వరం"),
    "n_K": _("potassium", "पोटैशियम", "పొటాషియం"),
    "s_low": _("low", "कम", "తక్కువ"), "s_adequate": _("adequate", "पर्याप्त", "తగినంత"), "s_high": _("high", "अधिक", "ఎక్కువ"),
    # ---- crop recommendation
    "crop_in": _("{name} {v}{unit} is within the typical range for {crop} in the training data ({span}).",
                 "{name} {v}{unit} प्रशिक्षण डेटा में {crop} की सामान्य सीमा ({span}) के भीतर है।",
                 "{name} {v}{unit} శిక్షణ డేటాలో {crop} కు సాధారణ పరిధి ({span}) లోపల ఉంది."),
    "crop_out": _("{name} {v}{unit} is outside the typical range for {crop} ({span}).",
                  "{name} {v}{unit} {crop} की सामान्य सीमा ({span}) से बाहर है।",
                  "{name} {v}{unit} {crop} కు సాధారణ పరిధి ({span}) వెలుపల ఉంది."),
    "crop_model_missing": _("Crop model not trained. Run: python ml\\crop_recommendation\\train.py",
                            "फसल मॉडल प्रशिक्षित नहीं है। चलाएँ: python ml\\crop_recommendation\\train.py",
                            "పంట మోడల్ శిక్షణ పొందలేదు. రన్ చేయండి: python ml\\crop_recommendation\\train.py"),
    "note_prob": _("Probabilities are the model's class probabilities, not guaranteed success rates.",
                   "प्रायिकताएँ मॉडल की अनुमानित संभावनाएँ हैं, सफलता की गारंटी नहीं।",
                   "శాతాలు మోడల్ అంచనా సంభావ్యతలు మాత్రమే, విజయానికి హామీ కాదు."),
    "note_ignored": _("Location, soil type and season were recorded but are NOT features of this model (the training dataset has only N, P, K, temperature, humidity, pH, rainfall).",
                      "स्थान, मिट्टी का प्रकार और मौसम दर्ज किए गए हैं, लेकिन इस मॉडल में उपयोग नहीं होते (डेटा में केवल N, P, K, तापमान, आर्द्रता, pH, वर्षा हैं)।",
                      "ప్రాంతం, నేల రకం, సీజన్ నమోదు చేయబడ్డాయి, కానీ ఈ మోడల్ వాటిని ఉపయోగించదు (డేటాలో N, P, K, ఉష్ణోగ్రత, తేమ, pH, వర్షపాతం మాత్రమే ఉన్నాయి)."),
    "note_notgiven": _("Location, soil type and season were not provided; the model only uses N, P, K, temperature, humidity, pH and rainfall.",
                       "स्थान, मिट्टी का प्रकार और मौसम नहीं दिए गए; मॉडल केवल N, P, K, तापमान, आर्द्रता, pH और वर्षा का उपयोग करता है।",
                       "ప్రాంతం, నేల రకం, సీజన్ ఇవ్వలేదు; మోడల్ N, P, K, ఉష్ణోగ్రత, తేమ, pH, వర్షపాతం మాత్రమే ఉపయోగిస్తుంది."),
    "note_confirm": _("Confirm with a soil test and your local Agriculture Officer before sowing.",
                      "बुवाई से पहले मिट्टी की जाँच कराएँ और अपने स्थानीय कृषि अधिकारी से पुष्टि करें।",
                      "విత్తే ముందు నేల పరీక్ష చేయించి, స్థానిక వ్యవసాయ అధికారిని సంప్రదించండి."),
    "note_lowconf": _("The model is not very sure (top probability {p}%). Treat this recommendation with extra caution and get a soil test.",
                      "मॉडल को ज़्यादा भरोसा नहीं है (सर्वोच्च प्रायिकता {p}%)। इस सुझाव को सावधानी से लें और मिट्टी की जाँच कराएँ।",
                      "మోడల్‌కు పూర్తి నమ్మకం లేదు (అత్యధిక సంభావ్యత {p}%). ఈ సూచనను జాగ్రత్తగా తీసుకోండి, నేల పరీక్ష చేయించండి."),
    "note_extrap": _("Some inputs are outside the range the model was trained on ({fields}); the result may be unreliable.",
                     "कुछ मान उस सीमा से बाहर हैं जिस पर मॉडल प्रशिक्षित है ({fields}); परिणाम भरोसेमंद नहीं हो सकता।",
                     "కొన్ని విలువలు మోడల్ శిక్షణ పొందిన పరిధికి వెలుపల ఉన్నాయి ({fields}); ఫలితం నమ్మదగినది కాకపోవచ్చు."),
    # ---- yield
    "yield_missing": _("Yield model is not trained yet. The PPT says yield is predicted 'when a trained model is available'. Put crop_production.csv in ml/datasets/ and run: python ml/yield_prediction/train.py",
                       "यील्ड मॉडल अभी प्रशिक्षित नहीं है। (PPT के अनुसार उपज तभी बताई जाती है जब प्रशिक्षित मॉडल उपलब्ध हो।) crop_production.csv को ml/datasets/ में रखें और चलाएँ: python ml/yield_prediction/train.py",
                       "దిగుబడి మోడల్ ఇంకా శిక్షణ పొందలేదు. (PPT ప్రకారం శిక్షణ పొందిన మోడల్ ఉన్నప్పుడే దిగుబడి అంచనా.) crop_production.csv ను ml/datasets/ లో ఉంచి రన్ చేయండి: python ml/yield_prediction/train.py"),
    "yield_disclaimer": _("Estimate only; actual yield depends on real-world farming conditions.",
                          "यह केवल अनुमान है; वास्तविक उपज खेत की वास्तविक परिस्थितियों पर निर्भर करती है।",
                          "ఇది అంచనా మాత్రమే; నిజమైన దిగుబడి వాస్తవ సాగు పరిస్థితులపై ఆధారపడి ఉంటుంది."),
    "yield_unseen": _("'{f}' value '{v}' was not seen in training; the prediction is less reliable.",
                      "'{f}' का मान '{v}' प्रशिक्षण में नहीं था; अनुमान कम भरोसेमंद है।",
                      "'{f}' విలువ '{v}' శిక్షణలో లేదు; అంచనా తక్కువ నమ్మదగినది."),
    "yield_missing_inputs": _("Missing required inputs for this model: {list}",
                              "इस मॉडल के लिए आवश्यक जानकारी गायब है: {list}",
                              "ఈ మోడల్‌కు అవసరమైన వివరాలు లేవు: {list}"),
    # ---- fertilizer
    "fert_cannot_crop": _("No nutrient reference for '{crop}'. Supported crops: {list}.",
                          "'{crop}' के लिए पोषक तत्व संदर्भ उपलब्ध नहीं है। समर्थित फसलें: {list}।",
                          "'{crop}' కు పోషక సమాచారం లేదు. మద్దతు ఉన్న పంటలు: {list}."),
    "fert_cannot_fert": _("'{f}' is not in the database. Enter its N-P-K % from the bag label.",
                          "'{f}' डेटाबेस में नहीं है। बैग के लेबल से इसका N-P-K % दर्ज करें।",
                          "'{f}' డేటాబేస్‌లో లేదు. బ్యాగ్ లేబుల్ నుండి దాని N-P-K % ఇవ్వండి."),
    "fert_cannot_soil": _("Soil test values missing for: {list}. Enter them (Soil Health Card) for a reliable evaluation.",
                          "इनके लिए मिट्टी जाँच मान गायब हैं: {list}। भरोसेमंद मूल्यांकन के लिए (सॉयल हेल्थ कार्ड से) दर्ज करें।",
                          "వీటి నేల పరీక్ష విలువలు లేవు: {list}. నమ్మదగిన మూల్యాంకనం కోసం (సాయిల్ హెల్త్ కార్డ్ నుండి) ఇవ్వండి."),
    "fert_soil_line": _("Soil {nut} is {status} for {crop} (typical range {lo}–{hi}).",
                        "{crop} के लिए मिट्टी में {nut} {status} है (सामान्य सीमा {lo}–{hi})।",
                        "{crop} కు నేలలో {nut} {status} (సాధారణ పరిధి {lo}–{hi})."),
    "fert_none_needed": _("No nutrient is low for this crop, so additional fertilizer is not indicated by these values.",
                          "इस फसल के लिए कोई पोषक तत्व कम नहीं है, इसलिए इन मानों के अनुसार अतिरिक्त उर्वरक की ज़रूरत नहीं दिखती।",
                          "ఈ పంటకు ఏ పోషకమూ తక్కువగా లేదు, కాబట్టి ఈ విలువల ప్రకారం అదనపు ఎరువు అవసరం లేదు."),
    "fert_harmful": _("It supplies {list}, which is already high in your soil.",
                      "यह {list} देता है, जो आपकी मिट्टी में पहले से अधिक है।",
                      "ఇది {list} అందిస్తుంది, ఇది మీ నేలలో ఇప్పటికే ఎక్కువగా ఉంది."),
    "fert_covers": _("It supplies the low nutrient(s): {list}.",
                     "यह कम पोषक तत्व देता है: {list}।",
                     "ఇది తక్కువగా ఉన్న పోషకాలను అందిస్తుంది: {list}."),
    "fert_missed": _("It does not supply low nutrient(s): {list}.",
                     "यह कम पोषक तत्व नहीं देता: {list}।",
                     "ఇది తక్కువగా ఉన్న పోషకాలను అందించదు: {list}."),
    "fert_also_high": _("It also supplies {list}, already high.",
                        "यह {list} भी देता है, जो पहले से अधिक है।",
                        "ఇది {list} కూడా అందిస్తుంది, ఇది ఇప్పటికే ఎక్కువ."),
    "fert_ph": _("Soil pH {ph} is outside the typical range for {crop} ({lo}–{hi}); correct pH issues first as they limit nutrient uptake.",
                 "मिट्टी का pH {ph} {crop} की सामान्य सीमा ({lo}–{hi}) से बाहर है; पहले pH ठीक करें क्योंकि यह पोषक तत्वों के अवशोषण को सीमित करता है।",
                 "నేల pH {ph} {crop} కు సాధారణ పరిధి ({lo}–{hi}) వెలుపల ఉంది; పోషకాల గ్రహణం తగ్గుతుంది కాబట్టి ముందుగా pH సరిచేయండి."),
    "fert_alt_why": _("It supplies the nutrient(s) that are low ({list}) while avoiding those already high.",
                      "यह कम पोषक तत्व ({list}) देता है और जो पहले से अधिक हैं उनसे बचता है।",
                      "ఇది తక్కువగా ఉన్న పోషకాలను ({list}) అందిస్తుంది, ఇప్పటికే ఎక్కువగా ఉన్నవాటిని నివారిస్తుంది."),
    "fert_g1": _("No dosage is given here: quantity depends on yield target, soil test and local recommendations (PJTSAU / ICAR / Soil Health Card).",
                 "यहाँ मात्रा नहीं दी गई है: मात्रा उपज लक्ष्य, मिट्टी जाँच और स्थानीय सिफ़ारिशों (PJTSAU / ICAR / सॉयल हेल्थ कार्ड) पर निर्भर करती है।",
                 "ఇక్కడ మోతాదు ఇవ్వలేదు: మోతాదు దిగుబడి లక్ష్యం, నేల పరీక్ష, స్థానిక సిఫార్సులు (PJTSAU / ICAR / సాయిల్ హెల్త్ కార్డ్) పై ఆధారపడుతుంది."),
    "fert_g2": _("Apply based on a recent soil test; avoid over-application to save cost and protect soil and water.",
                 "हाल की मिट्टी जाँच के आधार पर ही डालें; ख़र्च बचाने और मिट्टी-पानी की रक्षा के लिए अधिक मात्रा से बचें।",
                 "ఇటీవలి నేల పరీక్ష ఆధారంగానే వేయండి; ఖర్చు ఆదా చేయడానికి, నేల-నీరు కాపాడటానికి ఎక్కువ వేయకండి."),
    "fert_method": _("Soil N-P-K compared with the crop's 10th–90th percentile range from the training dataset; fertilizer grades from the reference database.",
                     "मिट्टी के N-P-K की तुलना प्रशिक्षण डेटा में फसल की 10वीं–90वीं प्रतिशतक सीमा से की गई; उर्वरक ग्रेड संदर्भ डेटाबेस से।",
                     "నేల N-P-K ను శిక్షణ డేటాలో పంట 10–90 పర్సెంటైల్ పరిధితో పోల్చారు; ఎరువు గ్రేడ్లు రిఫరెన్స్ డేటాబేస్ నుండి."),
    "fert_src_db": _("fertilizer database (standard FCO grade)", "उर्वरक डेटाबेस (मानक FCO ग्रेड)", "ఎరువుల డేటాబేస్ (ప్రామాణిక FCO గ్రేడ్)"),
    "fert_src_user": _("values entered by the farmer", "किसान द्वारा दर्ज मान", "రైతు నమోదు చేసిన విలువలు"),
    # ---- symptoms
    "sym_select": _("Please select or describe at least one symptom.", "कृपया कम से कम एक लक्षण चुनें या लिखें।", "దయచేసి కనీసం ఒక లక్షణాన్ని ఎంచుకోండి లేదా వివరించండి."),
    "sym_nomatch": _("No known pattern matched. Try different wording or consult an Agriculture Officer.",
                     "कोई ज्ञात पैटर्न नहीं मिला। दूसरे शब्द आज़माएँ या कृषि अधिकारी से मिलें।",
                     "తెలిసిన నమూనా దొరకలేదు. వేరే పదాలు ప్రయత్నించండి లేదా వ్యవసాయ అధికారిని కలవండి."),
    "sym_disclaimer": _("These are POSSIBLE causes, not confirmed diagnoses. Confirm with a local expert/KVK before treatment.",
                        "ये केवल संभावित कारण हैं, पुष्ट निदान नहीं। उपचार से पहले स्थानीय विशेषज्ञ/KVK से पुष्टि करें।",
                        "ఇవి సంభావ్య కారణాలు మాత్రమే, నిర్ధారిత నిర్ణయం కాదు. చికిత్సకు ముందు స్థానిక నిపుణుడు/KVK తో నిర్ధారించుకోండి."),
    "sym_method": _("rule-based keyword matching (fallback, not a trained model)",
                    "नियम-आधारित कीवर्ड मिलान (वैकल्पिक विधि, प्रशिक्षित मॉडल नहीं)",
                    "నియమ-ఆధారిత కీవర్డ్ సరిపోలిక (ప్రత్యామ్నాయ పద్ధతి, శిక్షణ పొందిన మోడల్ కాదు)"),
    # ---- image
    "img_big": _("Image too large. Maximum {mb} MB.", "छवि बहुत बड़ी है। अधिकतम {mb} MB।", "చిత్రం చాలా పెద్దది. గరిష్టం {mb} MB."),
    "img_type": _("Unsupported file type. Upload a JPG or PNG image.", "फ़ाइल प्रकार समर्थित नहीं। JPG या PNG छवि अपलोड करें।", "ఫైల్ రకం మద్దతు లేదు. JPG లేదా PNG చిత్రం అప్‌లోడ్ చేయండి."),
    "img_invalid": _("The file is not a valid image.", "यह फ़ाइल मान्य छवि नहीं है।", "ఈ ఫైల్ సరైన చిత్రం కాదు."),
    "img_small": _("Image is too small (minimum 64x64 pixels).", "छवि बहुत छोटी है (न्यूनतम 64x64 पिक्सल)।", "చిత్రం చాలా చిన్నది (కనీసం 64x64 పిక్సెళ్లు)."),
    "img_unavailable": _("Leaf disease model is not trained yet. Train it with ml/disease_detection/train.py (PlantVillage), then restart the backend. Use the symptom-based method meanwhile.",
                         "पत्ती रोग मॉडल अभी प्रशिक्षित नहीं है। ml/disease_detection/train.py (PlantVillage) से प्रशिक्षित करें और बैकएंड रीस्टार्ट करें। तब तक लक्षण-आधारित विधि इस्तेमाल करें।",
                         "ఆకు వ్యాధి మోడల్ ఇంకా శిక్షణ పొందలేదు. ml/disease_detection/train.py (PlantVillage) తో శిక్షణ ఇచ్చి బ్యాకెండ్ రీస్టార్ట్ చేయండి. అప్పటివరకు లక్షణ-ఆధారిత పద్ధతి వాడండి."),
    "img_lowconf": _("Low confidence: the image may be unsupported or unclear. Do not rely on this result; retake the photo or consult an expert.",
                     "कम भरोसा: छवि समर्थित नहीं या अस्पष्ट हो सकती है। इस परिणाम पर भरोसा न करें; दोबारा फोटो लें या विशेषज्ञ से मिलें।",
                     "తక్కువ నమ్మకం: చిత్రం మద్దతు లేనిది లేదా అస్పష్టంగా ఉండవచ్చు. ఈ ఫలితంపై ఆధారపడకండి; మళ్లీ ఫోటో తీయండి లేదా నిపుణుడిని సంప్రదించండి."),
    "img_disclaimer": _("The model only recognises the classes it was trained on (listed in supported_classes).",
                        "मॉडल केवल उन्हीं वर्गों को पहचानता है जिन पर वह प्रशिक्षित है।",
                        "మోడల్ తాను శిక్షణ పొందిన తరగతులను మాత్రమే గుర్తిస్తుంది."),
}

# disease guidance (general, non-chemical) keyed by words in the class label
DISEASE_GUIDE = [
    ("healthy",
     _(["No disease pattern detected for the classes this model knows.", "Keep monitoring; re-check if new symptoms appear."],
       ["इस मॉडल की जानी हुई श्रेणियों में कोई रोग पैटर्न नहीं मिला।", "निगरानी रखें; नए लक्षण दिखें तो दोबारा जाँचें।"],
       ["ఈ మోడల్ తెలిసిన తరగతుల్లో వ్యాధి లక్షణం కనిపించలేదు.", "పరిశీలిస్తూ ఉండండి; కొత్త లక్షణాలు కనిపిస్తే మళ్లీ తనిఖీ చేయండి."]),
     _(["Balanced nutrition and irrigation, regular field scouting."], ["संतुलित पोषण और सिंचाई, खेत की नियमित निगरानी।"], ["సమతుల్య పోషణ, నీటి పారుదల, క్రమం తప్పకుండా పొలం పరిశీలన."])),
    ("virus",
     _(["Remove and destroy severely affected plants to limit spread.", "Check for insect vectors (whitefly, aphids) on leaf undersides.", "Confirm with the local Agriculture Officer / KVK."],
       ["फैलाव रोकने के लिए बहुत प्रभावित पौधों को हटाकर नष्ट करें।", "पत्तियों के नीचे कीट (सफ़ेद मक्खी, माहू) देखें।", "स्थानीय कृषि अधिकारी/KVK से पुष्टि करें।"],
       ["వ్యాప్తి ఆపడానికి బాగా దెబ్బతిన్న మొక్కలను తీసివేసి నాశనం చేయండి.", "ఆకుల అడుగున పురుగులు (తెల్ల ఈగ, పేనుబంక) ఉన్నాయేమో చూడండి.", "స్థానిక వ్యవసాయ అధికారి/KVK తో నిర్ధారించుకోండి."]),
     _(["Use clean or certified seedlings; control weeds that host insects."], ["साफ़ या प्रमाणित पौध इस्तेमाल करें; कीटों को आश्रय देने वाले खरपतवार नियंत्रित करें।"], ["శుభ్రమైన లేదా ధృవీకరించిన నారు వాడండి; పురుగులకు ఆశ్రయమిచ్చే కలుపు నియంత్రించండి."])),
    ("blight",
     _(["Remove and destroy affected leaves; avoid working in wet fields.", "Confirm the diagnosis with a local expert before any treatment."],
       ["प्रभावित पत्तियाँ हटाकर नष्ट करें; गीले खेत में काम से बचें।", "किसी भी उपचार से पहले स्थानीय विशेषज्ञ से पुष्टि करें।"],
       ["దెబ్బతిన్న ఆకులను తీసివేసి నాశనం చేయండి; తడి పొలంలో పని చేయకండి.", "చికిత్సకు ముందు స్థానిక నిపుణుడితో నిర్ధారించుకోండి."]),
     _(["Crop rotation, spacing for airflow, avoid leaf wetness late in the day."], ["फसल चक्र, हवा के लिए दूरी, शाम को पत्तियाँ गीली रहने से बचें।"], ["పంట మార్పిడి, గాలి కోసం దూరం, సాయంత్రం ఆకులు తడిగా ఉండకుండా చూడండి."])),
    ("spot",
     _(["Remove badly affected leaves and keep debris out of the field.", "Confirm with the local Agriculture Officer / KVK for approved treatment."],
       ["बहुत प्रभावित पत्तियाँ हटाएँ और अवशेष खेत से बाहर रखें।", "स्वीकृत उपचार के लिए स्थानीय कृषि अधिकारी/KVK से पुष्टि करें।"],
       ["బాగా దెబ్బతిన్న ఆకులను తీసివేయండి, అవశేషాలను పొలం బయట ఉంచండి.", "ఆమోదిత చికిత్స కోసం స్థానిక వ్యవసాయ అధికారి/KVK ని సంప్రదించండి."]),
     _(["Avoid overhead irrigation; use clean seed and crop rotation."], ["ऊपर से सिंचाई से बचें; साफ़ बीज और फसल चक्र अपनाएँ।"], ["పైనుండి నీరు పోయడం నివారించండి; శుభ్రమైన విత్తనం, పంట మార్పిడి వాడండి."])),
    ("mildew",
     _(["Remove heavily affected leaves; improve air circulation.", "Confirm with an extension officer before treating."],
       ["बहुत प्रभावित पत्तियाँ हटाएँ; हवा का संचार बढ़ाएँ।", "उपचार से पहले विस्तार अधिकारी से पुष्टि करें।"],
       ["బాగా దెబ్బతిన్న ఆకులను తీసివేయండి; గాలి ప్రసరణ పెంచండి.", "చికిత్సకు ముందు విస్తరణ అధికారితో నిర్ధారించుకోండి."]),
     _(["Avoid excess nitrogen; choose resistant varieties where available."], ["अधिक नाइट्रोजन से बचें; उपलब्ध हो तो प्रतिरोधी किस्में चुनें।"], ["ఎక్కువ నత్రజని వద్దు; అందుబాటులో ఉంటే నిరోధక రకాలు ఎంచుకోండి."])),
    ("rust",
     _(["Remove affected leaves; monitor neighbouring plants.", "Consult a local expert on approved treatment."],
       ["प्रभावित पत्तियाँ हटाएँ; पास के पौधों पर नज़र रखें।", "स्वीकृत उपचार के लिए स्थानीय विशेषज्ञ से मिलें।"],
       ["దెబ్బతిన్న ఆకులను తీసివేయండి; పక్క మొక్కలను గమనించండి.", "ఆమోదిత చికిత్స గురించి స్థానిక నిపుణుడిని అడగండి."]),
     _(["Use resistant varieties; avoid prolonged leaf wetness."], ["प्रतिरोधी किस्में अपनाएँ; पत्तियाँ लंबे समय तक गीली न रहने दें।"], ["నిరోధక రకాలు వాడండి; ఆకులు ఎక్కువసేపు తడిగా ఉండకుండా చూడండి."])),
    ("mold",
     _(["Improve ventilation and reduce humidity around plants.", "Consult a local expert for confirmed diagnosis."],
       ["हवा का संचार बढ़ाएँ और पौधों के आसपास नमी घटाएँ।", "पुष्ट निदान के लिए स्थानीय विशेषज्ञ से मिलें।"],
       ["గాలి ప్రసరణ పెంచి మొక్కల చుట్టూ తేమ తగ్గించండి.", "నిర్ధారణ కోసం స్థానిక నిపుణుడిని సంప్రదించండి."]),
     _(["Adequate spacing; avoid over-irrigation."], ["पर्याप्त दूरी रखें; अधिक सिंचाई से बचें।"], ["తగినంత దూరం ఉంచండి; ఎక్కువ నీరు పెట్టకండి."])),
    ("bacterial",
     _(["Remove affected plant parts; avoid handling plants when wet.", "Confirm with a local expert before treatment."],
       ["प्रभावित हिस्से हटाएँ; गीले पौधों को छूने से बचें।", "उपचार से पहले स्थानीय विशेषज्ञ से पुष्टि करें।"],
       ["దెబ్బతిన్న భాగాలను తీసివేయండి; తడి మొక్కలను ముట్టుకోకండి.", "చికిత్సకు ముందు స్థానిక నిపుణుడితో నిర్ధారించుకోండి."]),
     _(["Use disease-free seed; rotate crops; sanitise tools."], ["रोगमुक्त बीज लें; फसल चक्र अपनाएँ; औज़ार साफ़ रखें।"], ["వ్యాధి లేని విత్తనం వాడండి; పంట మార్పిడి; పనిముట్లు శుభ్రంగా ఉంచండి."])),
    ("rot",
     _(["Check drainage and remove affected plant parts.", "Consult a local expert."], ["जल निकास जाँचें और प्रभावित हिस्से हटाएँ।", "स्थानीय विशेषज्ञ से मिलें।"], ["నీటి పారుదల తనిఖీ చేసి దెబ్బతిన్న భాగాలను తీసివేయండి.", "స్థానిక నిపుణుడిని సంప్రదించండి."]),
     _(["Avoid waterlogging; rotate crops."], ["जलभराव से बचें; फसल चक्र अपनाएँ।"], ["నీరు నిలవకుండా చూడండి; పంట మార్పిడి చేయండి."])),
]
DISEASE_DEFAULT = (
    _(["Confirm the condition with your local Agriculture Officer / KVK before treating."], ["उपचार से पहले अपने स्थानीय कृषि अधिकारी/KVK से स्थिति की पुष्टि करें।"], ["చికిత్సకు ముందు స్థానిక వ్యవసాయ అధికారి/KVK తో నిర్ధారించుకోండి."]),
    _(["Regular scouting, balanced nutrition, good drainage and field hygiene."], ["नियमित निगरानी, संतुलित पोषण, अच्छा जल निकास और खेत की सफ़ाई।"], ["క్రమం తప్పకుండా పరిశీలన, సమతుల్య పోషణ, మంచి నీటి పారుదల, పొలం శుభ్రత."]),
)


def norm(lang: str | None) -> str:
    return lang if lang in LANGS else "en"


def t(key: str, lang: str = "en", **kw) -> str:
    entry = M[key]
    s = entry.get(norm(lang)) or entry["en"]
    return s.format(**kw) if kw else s


def crop_name(code: str, lang: str = "en") -> str:
    e = CROPS.get(code)
    return (e.get(norm(lang)) or e["en"]) if e else code


def disease_guidance(label: str, lang: str = "en") -> dict:
    low = label.lower()
    lg = norm(lang)
    for key, steps, prev in DISEASE_GUIDE:
        if key in low:
            return {"next_steps": steps[lg], "prevention": prev[lg]}
    return {"next_steps": DISEASE_DEFAULT[0][lg], "prevention": DISEASE_DEFAULT[1][lg]}


# ---- overrides/additions (kept at the end so the latest wording wins)
M["yield_missing"] = _(
    "Yield model is not trained yet. Run: python ml\\yield_prediction\\train.py (the dataset is bundled in ml\\datasets).",
    "यील्ड मॉडल अभी प्रशिक्षित नहीं है। चलाएँ: python ml\\yield_prediction\\train.py (डेटासेट ml\\datasets में दिया गया है)।",
    "దిగుబడి మోడల్ ఇంకా శిక్షణ పొందలేదు. రన్ చేయండి: python ml\\yield_prediction\\train.py (డేటాసెట్ ml\\datasets లో ఉంది).")
M["yield_disclaimer"] = _(
    "Estimate only; actual yield depends on real-world farming conditions (weather, pests, management).",
    "यह केवल अनुमान है; वास्तविक उपज मौसम, कीट और प्रबंधन जैसी वास्तविक परिस्थितियों पर निर्भर करती है।",
    "ఇది అంచనా మాత్రమే; నిజమైన దిగుబడి వాతావరణం, పురుగులు, నిర్వహణ వంటి వాస్తవ పరిస్థితులపై ఆధారపడి ఉంటుంది.")

M["sum_crop"] = _("Top crop: {crop} ({p}%)", "सबसे उपयुक्त फसल: {crop} ({p}%)", "ఉత్తమ పంట: {crop} ({p}%)")
M["sum_yield"] = _("{crop}: {y} tonnes per hectare", "{crop}: {y} टन प्रति हेक्टेयर", "{crop}: హెక్టారుకు {y} టన్నులు")
M["sum_img"] = _("Image: {label} ({p}%)", "फोटो: {label} ({p}%)", "చిత్రం: {label} ({p}%)")
M["sum_sym"] = _("Symptoms: {names}", "लक्षण: {names}", "లక్షణాలు: {names}")
M["sum_nomatch"] = _("no match", "कोई मेल नहीं", "సరిపోలిక లేదు")
M["sum_fert"] = _("{f} for {crop}: {v}", "{crop} के लिए {f}: {v}", "{crop} కు {f}: {v}")
M["verdict_suitable"] = _("suitable", "उपयुक्त", "తగినది")
M["verdict_potentially_suitable"] = _("potentially suitable", "संभवतः उपयुक्त", "తగినదై ఉండవచ్చు")
M["verdict_unsuitable"] = _("unsuitable", "अनुपयुक्त", "తగనిది")
M["verdict_cannot_evaluate"] = _("cannot evaluate", "मूल्यांकन संभव नहीं", "మూల్యాంకనం సాధ్యం కాదు")
M["tts_fail"] = _("Voice service is unavailable. Check the internet connection.", "आवाज़ सेवा उपलब्ध नहीं है। इंटरनेट कनेक्शन जाँचें।", "వాయిస్ సేవ అందుబాటులో లేదు. ఇంటర్నెట్ కనెక్షన్ తనిఖీ చేయండి.")
