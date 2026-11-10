-- Data/Writs.lua: Craftsman's Writs and the item each one asks for.
--
-- A writ is an order for one crafted thing: a Lesser Wizard's Robe, an
-- Ornate Spyglass. Hand the item and the writ to the customer and the
-- camp thinks better of you; the item may be made or bought. Each entry
-- here is the writ's item ID, then the item it asks for, how many, the
-- English name for when the client has not loaded the item yet, and
-- the writ's rank.
--
-- 150 writs, 264011 to 264160: by rank, and within a rank by alchemy,
-- blacksmithing, engineering, leatherworking and tailoring. The IDs
-- and names are from the item records of the launch build, 1.60.1, and
-- the counts from the quest each writ starts: one of everything but
-- the solid shot. The quest for the ogre strength elixir could not be
-- read and is taken to ask for one as the rest do. The sealed writs,
-- 262888 to 262890, hold a writ not yet known and are not here.
local ADDON, H = ...

-- What a writ of each rank is worth to the camp, as the guides give it.
H.WritRanks = {
  { name = "Journeyman", rep = 75 },
  { name = "Expert", rep = 125 },
  { name = "Artisan", rep = 200 },
}

H.Writs = {
  -- Journeyman alchemy
  [264011] = { 3391, 1, "Elixir of Ogre Strength", 1 },
  [264012] = { 3383, 1, "Elixir of Wisdom", 1 },
  [264013] = { 3385, 1, "Lesser Mana Potion", 1 },
  [264014] = { 6048, 1, "Shadow Protection Potion", 1 },
  [264015] = { 5634, 1, "Free Action Potion", 1 },
  [264016] = { 3390, 1, "Elixir of Lesser Agility", 1 },
  [264017] = { 3388, 1, "Lesser Troll's Blood Elixir", 1 },
  [264018] = { 8951, 1, "Elixir of Defense", 1 },
  [264019] = { 5996, 1, "Draught of Water Breathing", 1 },

  -- Journeyman blacksmithing
  [264020] = { 5540, 1, "Pearl-handled Dagger", 1 },
  [264021] = { 11128, 1, "Golden Rod", 1 },
  [264022] = { 5541, 1, "Iridescent Hammer", 1 },
  [264023] = { 15869, 1, "Silver Skeleton Key", 1 },
  [264024] = { 3491, 1, "Heavy Bronze Mace", 1 },
  [264025] = { 2865, 1, "Rough Bronze Leggings", 1 },
  [264026] = { 3485, 1, "Green Iron Gauntlets", 1 },
  [264027] = { 3848, 1, "Big Bronze Knife", 1 },
  [264028] = { 3484, 1, "Green Iron Boots", 1 },

  -- Journeyman engineering
  [264029] = { 5507, 1, "Ornate Spyglass", 1 },
  [264030] = { 4384, 1, "Explosive Sheep", 1 },
  [264031] = { 4383, 1, "Moonsight Rifle", 1 },
  [264032] = { 4381, 1, "Minor Recombobulator", 1 },
  [264033] = { 6712, 1, "Practice Lock", 1 },
  [264034] = { 4373, 1, "Shadow Goggles", 1 },
  [264035] = { 7506, 1, "Gnomish Universal Remote", 1 },
  [264036] = { 4380, 1, "Big Bronze Bomb", 1 },
  [264037] = { 8069, 200, "Crafted Solid Shot", 1 },

  -- Journeyman leatherworking
  [264038] = { 18662, 1, "Heavy Leather Ball", 1 },
  [264039] = { 5958, 1, "Fine Leather Pants", 1 },
  [264040] = { 7349, 1, "Herbalist's Gloves", 1 },
  [264041] = { 2317, 1, "Dark Leather Tunic", 1 },
  [264042] = { 7358, 1, "Pilferer's Gloves", 1 },
  [264043] = { 7371, 1, "Heavy Quiver", 1 },
  [264044] = { 4252, 1, "Dark Leather Shoulders", 1 },
  [264045] = { 4254, 1, "Barbaric Gloves", 1 },
  [264046] = { 7284, 1, "Red Whelp Gloves", 1 },

  -- Journeyman tailoring
  [264047] = { 5766, 1, "Lesser Wizard's Robe", 1 },
  [264048] = { 6263, 1, "Blue Overalls", 1 },
  [264049] = { 7048, 1, "Azure Silk Hood", 1 },
  [264050] = { 4245, 1, "Small Silk Pack", 1 },
  [264051] = { 4317, 1, "Phoenix Pants", 1 },
  [264052] = { 4313, 1, "Red Woolen Boots", 1 },
  [264053] = { 10048, 1, "Colorful Kilt", 1 },
  [264054] = { 6264, 1, "Greater Adept's Robe", 1 },
  [264055] = { 4321, 1, "Spider Silk Slippers", 1 },

  -- Expert alchemy
  [264056] = { 6050, 1, "Frost Protection Potion", 2 },
  [264057] = { 3823, 1, "Lesser Invisibility Potion", 2 },
  [264058] = { 4623, 1, "Lesser Stoneshield Potion", 2 },
  [264059] = { 6052, 1, "Nature Protection Potion", 2 },
  [264060] = { 10592, 1, "Catseye Draught", 2 },
  [264061] = { 5633, 1, "Great Rage Potion", 2 },
  [264062] = { 3827, 1, "Mana Potion", 2 },
  [264063] = { 6049, 1, "Fire Protection Potion", 2 },
  [264064] = { 3824, 1, "Shadow Oil", 2 },
  [264065] = { 9061, 1, "Goblin Rocket Fuel", 2 },
  [264066] = { 8949, 1, "Elixir of Agility", 2 },
  [264067] = { 9144, 1, "Wildvine Potion", 2 },

  -- Expert blacksmithing
  [264068] = { 7922, 1, "Steel Plate Helm", 2 },
  [264069] = { 9060, 1, "Inlaid Mithril Cylinder", 2 },
  [264070] = { 6041, 1, "Steel Weapon Chain", 2 },
  [264071] = { 7928, 1, "Ornate Mithril Shoulders", 2 },
  [264072] = { 7942, 1, "Blue Glittering Axe", 2 },
  [264073] = { 3853, 1, "Moonsteel Broadsword", 2 },
  [264074] = { 3837, 1, "Golden Scale Coif", 2 },
  [264075] = { 7964, 1, "Solid Sharpening Stone", 2 },
  [264076] = { 7943, 1, "Wicked Mithril Blade", 2 },
  [264077] = { 11144, 1, "Truesilver Rod", 2 },
  [264078] = { 9366, 1, "Golden Scale Gauntlets", 2 },
  [264079] = { 7941, 1, "Heavy Mithril Axe", 2 },

  -- Expert engineering
  [264080] = { 4396, 1, "Mechanical Dragonling", 2 },
  [264081] = { 4392, 1, "Advanced Target Dummy", 2 },
  [264082] = { 4393, 1, "Craftsman's Monocle", 2 },
  [264083] = { 4395, 1, "Goblin Land Mine", 2 },
  [264084] = { 10501, 1, "Catseye Ultra Goggles", 2 },
  [264085] = { 10560, 1, "Unstable Trigger", 2 },
  [264086] = { 4852, 1, "Flash Bomb", 2 },
  [264087] = { 10500, 1, "Fire Goggles", 2 },
  [264088] = { 10514, 1, "Mithril Frag Bomb", 2 },
  [264089] = { 10498, 1, "Gyromatic Micro-Adjustor", 2 },
  [264090] = { 11590, 1, "Mechanical Repair Kit", 2 },
  [264091] = { 16005, 1, "Dark Iron Bomb", 2 },

  -- Expert leatherworking
  [264092] = { 8174, 1, "Comfortable Leather Hat", 2 },
  [264093] = { 5965, 1, "Guardian Cloak", 2 },
  [264094] = { 7378, 1, "Dusky Bracers", 2 },
  [264095] = { 8214, 1, "Wild Leather Helmet", 2 },
  [264096] = { 8210, 1, "Wild Leather Shoulders", 2 },
  [264097] = { 8217, 1, "Quickdraw Quiver", 2 },
  [264098] = { 7391, 1, "Swift Boots", 2 },
  [264099] = { 8192, 1, "Nightscape Shoulders", 2 },
  [264100] = { 8201, 1, "Big Voodoo Mask", 2 },
  [264101] = { 8200, 1, "Big Voodoo Robe", 2 },
  [264102] = { 8189, 1, "Turtle Scale Breastplate", 2 },
  [264103] = { 8218, 1, "Thick Leather Ammo Pouch", 2 },

  -- Expert tailoring
  [264104] = { 10050, 1, "Mageweave Bag", 2 },
  [264105] = { 10023, 1, "Shadoweave Gloves", 2 },
  [264106] = { 7063, 1, "Crimson Silk Robe", 2 },
  [264107] = { 10004, 1, "Shadoweave Robe", 2 },
  [264108] = { 22246, 1, "Enchanted Mageweave Pouch", 2 },
  [264109] = { 4329, 1, "Star Belt", 2 },
  [264110] = { 9998, 1, "Black Mageweave Vest", 2 },
  [264111] = { 10009, 1, "Red Mageweave Pants", 2 },
  [264112] = { 10052, 1, "Orange Martial Shirt", 2 },
  [264113] = { 10008, 1, "White Bandit Mask", 2 },
  [264114] = { 10042, 1, "Cindercloth Robe", 2 },
  [264115] = { 7061, 1, "Earthen Silk Belt", 2 },

  -- Artisan alchemy
  [264116] = { 9224, 1, "Potion of Demon Slaying", 3 },
  [264117] = { 12190, 1, "Dreamless Sleep Potion", 3 },
  [264118] = { 13457, 1, "Greater Fire Protection Potion", 3 },
  [264119] = { 9233, 1, "Draught of Detect Demon", 3 },
  [264120] = { 9088, 1, "Gift of Arthas", 3 },
  [264121] = { 13513, 1, "Flask of Chromatic Resistance", 3 },
  [264122] = { 3387, 1, "Limited Invulnerability Potion", 3 },
  [264123] = { 18253, 1, "Major Rejuvenation Potion", 3 },
  [264124] = { 246948, 1, "Distilled Firewater", 3 },

  -- Artisan blacksmithing
  [264125] = { 12417, 1, "Radiant Circlet", 3 },
  [264126] = { 12416, 1, "Radiant Belt", 3 },
  [264127] = { 7929, 1, "Orcish War Leggings", 3 },
  [264128] = { 7969, 1, "Mithril Spurs", 3 },
  [264129] = { 12422, 1, "Imperial Plate Chest", 3 },
  [264130] = { 20549, 1, "Darkrune Gauntlets", 3 },
  [264131] = { 12775, 1, "Huge Thorium Battleaxe", 3 },
  [264132] = { 15872, 1, "Arcanite Skeleton Key", 3 },
  [264133] = { 7947, 1, "Ebon Shiv", 3 },

  -- Artisan engineering
  [264134] = { 16023, 1, "Masterwork Target Dummy", 3 },
  [264135] = { 10504, 1, "Green Lens", 3 },
  [264136] = { 15996, 1, "Lifelike Mechanical Toad", 3 },
  [264137] = { 18645, 1, "Gnomish Alarm-O-Bot", 3 },
  [264138] = { 18587, 1, "Goblin Jumper Cables XL", 3 },
  [264139] = { 18232, 1, "Field Repair Bot 74A", 3 },
  [264140] = { 18631, 1, "Truesilver Transformer", 3 },
  [264141] = { 10548, 1, "Sniper Scope", 3 },
  [264142] = { 21277, 1, "Tranquil Mechanical Yeti", 3 },

  -- Artisan leatherworking
  [264143] = { 15087, 1, "Wicked Leather Pants", 3 },
  [264144] = { 18258, 1, "Gordok Ogre Suit", 3 },
  [264145] = { 15053, 1, "Volcanic Breastplate", 3 },
  [264146] = { 15094, 1, "Runic Leather Headband", 3 },
  [264147] = { 15084, 1, "Wicked Leather Bracers", 3 },
  [264148] = { 15075, 1, "Chimeric Vest", 3 },
  [264149] = { 15080, 1, "Heavy Scorpid Helm", 3 },
  [264150] = { 15092, 1, "Runic Leather Bracers", 3 },
  [264151] = { 15071, 1, "Frostsaber Boots", 3 },

  -- Artisan tailoring
  [264152] = { 14130, 1, "Wizardweave Turban", 3 },
  [264153] = { 14046, 1, "Runecloth Bag", 3 },
  [264154] = { 13864, 1, "Runecloth Boots", 3 },
  [264155] = { 10036, 1, "Tuxedo Jacket", 3 },
  [264156] = { 14108, 1, "Felcloth Boots", 3 },
  [264157] = { 22251, 1, "Cenarion Herb Bag", 3 },
  [264158] = { 10025, 1, "Shadoweave Mask", 3 },
  [264159] = { 14141, 1, "Ghostweave Vest", 3 },
  [264160] = { 21340, 1, "Soul Pouch", 3 },
}
