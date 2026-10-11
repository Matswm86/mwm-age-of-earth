"""Every shipped sound: source, cut, clean-up, loudness class. Sources live in dl/ (downloads) or
work/ (synth/ = made for the project by synth.py; lake_premix.wav = synth + PD recording)."""

AMB = "assets/audio/amb"
AN = "assets/audio/animals"
VO = "assets/audio/voices"
SFX = "assets/audio/sfx"
UI = "assets/audio/ui"
INTRO = "assets/intro/audio"

C = "commons/"
PANT = C + "Pant-hoot_call_made_by_a_male_chimpanzee.ogg"
SOFT = (
    C
    + "Chimpanzee-Alarm-Call-Production-Meets-Key-Criteria-for-Intentionality-pone.0076674.s004.oga"
)
AHOO = (
    C
    + "Chimpanzee-Alarm-Call-Production-Meets-Key-Criteria-for-Intentionality-pone.0076674.s005.oga"
)
WAA = (
    C
    + "Chimpanzee-Alarm-Call-Production-Meets-Key-Criteria-for-Intentionality-pone.0076674.s006.oga"
)
BONO = C + "Enduring-voice-recognition-in-bonobos-srep22046-s3.oga"
BABOON = C + "Yellow_Baboon_Papio_cynocephalus_W_PAPIO_CYNOCEPHALUS_R1_C1_.ogg"
WHOOP = C + "Spotted_Hyaena_Crocuta_crocuta_W1CDR0000381_BD12_.ogg"
GIG = C + "Giggling_call_of_a_spotted_hyena_Crocuta_crocuta_-_1472-6785-10-9-S%d.oga"
LION = C + "Lionroar.wav"
IMPALA = C + "Impala_Aepyceros_melampus_W1CDR0000514_BD37_.ogg"
SPLASH = C + "Bathtub_water_splashes.ogg"
EAGLE3 = C + "Yellowstone_sound_library_-_Bald_Eagle_-_003.mp3"
EAGLE2 = C + "Yellowstone_sound_library_-_Bald_Eagle_-_002.mp3"
WEAVER = C + "White-browed_Sparrow_Weaver_Plocepasser_mahali_022A-WA03044X0028-0011M0_.ogg"
DOVE = C + "S-senegalensis.ogg"
HORNBILL = C + "African_Grey_Hornbill_Tockus_nasutus_022A-WA03044X0024-0021M0_.ogg"
IBIS = C + "Hadada_Ibis_Bostrychia_hagedash_022A-WA03044X0019-0013M0_.ogg"
GOAWAY = C + "Bare-faced_go-away_Bird_Corythaixoides_personata_022A-WA03044X0032-0005M0_.ogg"
DRONGO = C + "Fork-tailed_Drongo_Dicrurus_adsimilis_W1CDR0000988_BD2_.ogg"
BULBUL = C + "Dark-capped_Bulbul_Pycnonotus_tricolor_layardi_022A-WA03044X0003-0013M0_.oga"
CICADA = C + "Cicada_20200619.wav"
FROGS = C + "Night_Chorus_of_Frogs_and_Toads_in_Niger_Delta.ogg"
DAWN = C + "Royal_Natal_National_Park_dawn_chorus_W1CDR0001146_BD3_.ogg"
NPS = "nps/"
WIND = NPS + "yell-040201LowerGeyserBasinWindInTreesBinaural01011.mp3"
THUNDER = NPS + "yell-Thunderandbirds140704.mp3"
CHOP = NPS + "yell-YELLChopKindling20160913T0011.mp3"
SPLIT = NPS + "yell-YELLSplitLogs20160913T002.mp3"
K = "kenney/ui/Audio/"
S = "synth/"

BIRD = "highpass=f=400,lowpass=f=9000"
VOICE = "highpass=f=140,lowpass=f=7000"

ENTRIES: list[dict] = []


def add(d: str, out: str, src: str, cat: str, what: str, **kw) -> None:
    ENTRIES.append({"dir": d, "out": out, "src": src, "cat": cat, "what": what, **kw})


# ---- intro (assets/intro/audio) ----
add(
    INTRO,
    "space_hum",
    S + "intro_space_hum.wav",
    "intro",
    "deep space hum, low drone loop",
    loop=True,
    xfade=0.5,
)
add(
    INTRO,
    "rise",
    S + "intro_rise.wav",
    "intro",
    "soft rising tone over the globe",
    ogg=True,
    fade=(0.5, 3.0),
    trim_db=2,
)
add(
    INTRO,
    "dive_wind",
    S + "intro_dive_wind.wav",
    "intro",
    "air rush building through the dive",
    ogg=True,
    fade=(1.0, 1.5),
    trim_db=4,
)
add(
    INTRO,
    "cloud_whoosh",
    S + "intro_cloud_whoosh.wav",
    "sfx",
    "whoosh through the cloud deck",
    ogg=True,
    fade=(0.3, 0.8),
    trim_db=-2,
)
add(
    INTRO,
    "dawn_chorus",
    DAWN,
    "intro",
    "dawn bird chorus, South African woodland",
    start=28,
    dur=45,
    chain="highpass=f=200",
    fade=(2.0, 3.0),
    ogg=True,
)
add(
    INTRO,
    "wake_call",
    PANT,
    "voice",
    "waking hoo (chimpanzee pant-hoot introduction)",
    start=0.12,
    dur=1.38,
    chain=VOICE,
    pitch=0.9,
    fade=(0.08, 0.2),
)

# ---- ambience loops ----
add(
    AMB,
    "wind_grass",
    S + "amb_wind_grass.wav",
    "amb",
    "soft wind in dry grass",
    loop=True,
    mono=False,
    xfade=2.0,
)
add(
    AMB,
    "wind_high",
    WIND,
    "amb",
    "strong wind in trees (zoomed out)",
    start=100,
    dur=64,
    loop=True,
    mono=False,
    xfade=4.0,
    chain="highpass=f=60",
)
add(
    AMB,
    "lake_lap",
    "../work/lake_premix.wav",
    "amb",
    "small waves lapping on the shore",
    loop=True,
    mono=False,
    xfade=3.0,
)
add(
    AMB,
    "insects",
    CICADA,
    "amb",
    "cicadas in the grass",
    start=22,
    dur=36,
    chain="highpass=f=1000",
    loop=True,
    xfade=3.0,
)
add(
    AMB,
    "frogs",
    FROGS,
    "amb",
    "frog and toad chorus at the shore",
    start=0.5,
    dur=25.5,
    chain="highpass=f=300",
    loop=True,
    xfade=3.0,
)
add(
    AMB,
    "thunder_far_1",
    THUNDER,
    "amb",
    "distant thunder roll",
    start=8,
    dur=22,
    chain="lowpass=f=900",
    fade=(2.0, 4.0),
    trim_db=2,
)
add(
    AMB,
    "thunder_far_2",
    THUNDER,
    "amb",
    "distant thunder roll",
    start=146,
    dur=24,
    chain="lowpass=f=900",
    fade=(2.0, 4.0),
    trim_db=2,
)

# ---- band voices (Australopithecus stand-ins: chimpanzee and bonobo calls) ----
add(
    VO,
    "contact_1",
    SOFT,
    "voice",
    "soft hoo (chimpanzee)",
    start=0.25,
    dur=0.65,
    chain=VOICE,
    fade=(0.02, 0.1),
)
add(
    VO,
    "contact_2",
    PANT,
    "voice",
    "low hoos (chimpanzee pant-hoot intro)",
    start=0.12,
    dur=1.38,
    chain=VOICE,
    fade=(0.08, 0.2),
)
add(
    VO,
    "contact_3",
    BONO,
    "voice",
    "short contact call (bonobo, pitched down)",
    start=0.0,
    dur=0.7,
    chain=VOICE,
    pitch=0.7,
    fade=(0.02, 0.1),
)
add(
    VO,
    "contact_4",
    BONO,
    "voice",
    "short contact call (bonobo, pitched down)",
    start=3.15,
    dur=0.65,
    chain=VOICE,
    pitch=0.68,
    fade=(0.02, 0.1),
)
add(
    VO,
    "contact_5",
    BONO,
    "voice",
    "contact call (bonobo, pitched down)",
    start=4.15,
    dur=0.95,
    chain=VOICE,
    pitch=0.72,
    fade=(0.02, 0.15),
)
add(
    VO,
    "ack_1",
    AHOO,
    "voice",
    "short hoo (chimpanzee)",
    start=0.28,
    dur=0.6,
    chain=VOICE,
    pitch=1.04,
    fade=(0.01, 0.12),
)
add(
    VO,
    "ack_2",
    PANT,
    "voice",
    "single pant (chimpanzee)",
    start=2.4,
    dur=0.62,
    chain=VOICE,
    fade=(0.01, 0.1),
)
add(
    VO,
    "ack_3",
    PANT,
    "voice",
    "single pant (chimpanzee)",
    start=3.2,
    dur=0.62,
    chain=VOICE,
    pitch=1.06,
    fade=(0.01, 0.1),
)
add(
    VO,
    "ack_4",
    BONO,
    "voice",
    "short call (bonobo, pitched down)",
    start=2.0,
    dur=0.62,
    chain=VOICE,
    pitch=0.75,
    fade=(0.01, 0.1),
)
add(
    VO,
    "alarm_1",
    WAA,
    "voice",
    "waa bark alarm (chimpanzee)",
    start=0.33,
    dur=0.43,
    chain=VOICE,
    fade=(0.005, 0.08),
)
add(
    VO,
    "alarm_2",
    BABOON,
    "voice",
    "alarm bark (yellow baboon)",
    start=0.75,
    dur=1.0,
    chain="highpass=f=250,lowpass=f=6000",
    fade=(0.01, 0.15),
)
add(
    VO,
    "alarm_3",
    BABOON,
    "voice",
    "alarm bark (yellow baboon)",
    start=3.25,
    dur=1.0,
    chain="highpass=f=250,lowpass=f=6000",
    fade=(0.01, 0.15),
)
add(
    VO,
    "chorus_1",
    PANT,
    "voice",
    "pant-hoot build-up and climax (chimpanzee)",
    start=2.3,
    dur=7.1,
    chain=VOICE,
    fade=(0.05, 0.6),
)
add(
    VO,
    "chorus_2",
    PANT,
    "voice",
    "pant-hoot climax and let-down (chimpanzee)",
    start=6.5,
    dur=6.0,
    chain=VOICE,
    fade=(0.05, 0.8),
)

# ---- animals ----
for i, (a, b) in enumerate([(1.3, 4.3), (6.3, 9.3), (16.8, 19.8)]):
    add(
        AN,
        f"hyena_whoop_{i + 1}",
        WHOOP,
        "animal",
        "spotted hyena whoop",
        start=a,
        dur=b - a,
        chain="highpass=f=120,lowpass=f=3000",
        fade=(0.05, 0.4),
    )
for i, k in enumerate([1, 3, 5]):
    add(
        AN,
        f"hyena_giggle_{i + 1}",
        GIG % k,
        "animal",
        "spotted hyena giggle",
        chain="highpass=f=150",
        fade=(0.01, 0.08),
    )
add(
    AN,
    "bigcat_growl_1",
    LION,
    "animal",
    "big cat roar-growl (lion)",
    start=7.0,
    dur=3.5,
    chain="highpass=f=40,lowpass=f=2500",
    fade=(0.05, 0.5),
)
add(
    AN,
    "bigcat_growl_2",
    LION,
    "animal",
    "big cat roar-growl (lion)",
    start=11.4,
    dur=3.4,
    chain="highpass=f=40,lowpass=f=2500",
    fade=(0.05, 0.5),
)
for i, a in enumerate([3.1, 11.9, 20.4]):
    add(
        AN,
        f"gazelle_snort_{i + 1}",
        IMPALA,
        "animal",
        "antelope alarm snort (impala)",
        start=a,
        dur=1.0,
        chain="highpass=f=200",
        fade=(0.01, 0.2),
    )
for i in range(2):
    add(
        AN,
        f"hooves_{i + 1}",
        S + f"sfx_hooves_{i + 1}.wav",
        "animal",
        "antelope hooves bounding off",
        trim_db=-4,
        fade=(0.0, 0.3),
    )
for i, a in enumerate([6.9, 24.9]):
    add(
        AN,
        f"croc_splash_{i + 1}",
        SPLASH,
        "animal",
        "heavy splash (crocodile)",
        start=a,
        dur=1.9,
        chain="lowpass=f=5000",
        pitch=0.8,
        fade=(0.0, 0.4),
    )
for i in range(2):
    add(
        AN,
        f"croc_hiss_{i + 1}",
        S + f"sfx_croc_hiss_{i + 1}.wav",
        "animal",
        "crocodile hiss",
        fade=(0.05, 0.2),
    )
add(
    AN,
    "bird_eagle_1",
    EAGLE3,
    "animal",
    "eagle call (bald eagle, fish eagle stand-in)",
    start=1.3,
    dur=5.5,
    chain=BIRD,
    fade=(0.1, 0.4),
)
add(
    AN,
    "bird_eagle_2",
    EAGLE2,
    "animal",
    "eagle chatter (bald eagle, fish eagle stand-in)",
    start=4.5,
    dur=4.0,
    chain=BIRD,
    fade=(0.1, 0.4),
)
add(
    AN,
    "bird_weaver_1",
    WEAVER,
    "animal",
    "white-browed sparrow weaver chatter",
    start=0.5,
    dur=3.9,
    chain=BIRD,
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_weaver_2",
    WEAVER,
    "animal",
    "white-browed sparrow weaver chatter",
    start=9.6,
    dur=3.8,
    chain=BIRD,
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_dove_1",
    DOVE,
    "animal",
    "laughing dove coo",
    start=0.05,
    dur=2.6,
    chain="highpass=f=250",
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_dove_2",
    DOVE,
    "animal",
    "laughing dove coo",
    start=2.9,
    dur=3.2,
    chain="highpass=f=250",
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_hornbill_1",
    HORNBILL,
    "animal",
    "African grey hornbill piping",
    start=4.0,
    dur=4.0,
    chain=BIRD,
    fade=(0.1, 0.4),
)
add(
    AN,
    "bird_hornbill_2",
    HORNBILL,
    "animal",
    "African grey hornbill piping",
    start=13.0,
    dur=4.0,
    chain=BIRD,
    fade=(0.1, 0.4),
)
add(
    AN,
    "bird_ibis_1",
    IBIS,
    "animal",
    "hadada ibis calls",
    start=1.0,
    dur=4.0,
    chain=BIRD,
    fade=(0.1, 0.5),
)
add(
    AN,
    "bird_goaway_1",
    GOAWAY,
    "animal",
    "bare-faced go-away-bird",
    start=0.7,
    dur=2.5,
    chain=BIRD,
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_goaway_2",
    GOAWAY,
    "animal",
    "bare-faced go-away-bird",
    start=4.8,
    dur=2.2,
    chain=BIRD,
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_drongo_1",
    DRONGO,
    "animal",
    "fork-tailed drongo song",
    start=6.0,
    dur=3.0,
    chain=BIRD,
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_drongo_2",
    DRONGO,
    "animal",
    "fork-tailed drongo song",
    start=11.8,
    dur=2.7,
    chain=BIRD,
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_bulbul_1",
    BULBUL,
    "animal",
    "dark-capped bulbul song",
    start=29.5,
    dur=3.0,
    chain=BIRD,
    fade=(0.1, 0.3),
)
add(
    AN,
    "bird_bulbul_2",
    BULBUL,
    "animal",
    "dark-capped bulbul song",
    start=8.5,
    dur=2.5,
    chain=BIRD,
    fade=(0.1, 0.3),
)

# ---- foley ----
for name, n, what in [
    ("rustle", 4, "leaf rustle (foraging, climbing)"),
    ("stone_knock", 4, "two stones knocked together"),
    ("wood_snap", 3, "branch snapping"),
    ("bark_scrape", 4, "hands and feet scraping bark"),
    ("footstep", 4, "bare foot on dry grass"),
    ("build_place", 2, "branches set down"),
    ("build_knock", 4, "wood knock while building"),
]:
    for i in range(n):
        add(SFX, f"{name}_{i + 1}", S + f"sfx_{name}_{i + 1}.wav", "sfx", what, fade=(0.0, 0.03))
for name, what, trim in [
    ("land_thud", "landing thud on the ground", 0),
    ("knap_crack", "stone strike, flake breaks off", 0),
    ("age_swell", "rising swell and drum hit (age-up sting)", 0),
    ("research_shimmer", "soft bright shimmer (discovery done)", -6),
]:
    add(SFX, name, S + f"sfx_{name}.wav", "sfx", what, fade=(0.0, 0.05), trim_db=trim)
for i, a in enumerate([3.3, 6.3, 11.7]):
    add(
        SFX,
        f"wood_chop_{i + 1}",
        CHOP,
        "sfx",
        "wood struck (kindling chop)",
        start=a,
        dur=0.6,
        chain="highpass=f=80",
        fade=(0.0, 0.1),
    )
add(
    SFX,
    "wood_crack_1",
    SPLIT,
    "sfx",
    "wood splitting crack",
    start=2.4,
    dur=1.0,
    chain="highpass=f=60",
    fade=(0.0, 0.2),
)

# ---- UI (Kenney UI Audio, CC0) ----
add(UI, "tap_1", K + "click1.ogg", "ui", "UI tap", fade=(0.0, 0.01), trim_db=-4)
add(UI, "tap_2", K + "click2.ogg", "ui", "UI tap", fade=(0.0, 0.01), trim_db=-4)
add(UI, "confirm", K + "switch2.ogg", "ui", "UI confirm", fade=(0.0, 0.01), trim_db=-3)
add(UI, "cancel", K + "switch7.ogg", "ui", "UI cancel", fade=(0.0, 0.01), trim_db=-3)
