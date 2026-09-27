-- Data/Conversions.lua: the market connections graph for launch-era Azeroth.
--
-- Each entry: what comes out, how many, what goes in, which profession,
-- the skill needed, and the cast time in seconds. Cast times are the
-- usual three seconds unless noted. Item IDs are the classic ones and
-- should be spot-checked against Forever with /hound key on a link.
local ADDON, H = ...

H.Conversions = {
  -- Mining: smelting
  { out = 2840,  outQty = 1, inputs = { { 2770, 1 } },             prof = "Mining", skill = 1,   name = "Smelt Copper" },
  { out = 3576,  outQty = 1, inputs = { { 2771, 1 } },             prof = "Mining", skill = 65,  name = "Smelt Tin" },
  { out = 2841,  outQty = 2, inputs = { { 2840, 1 }, { 3576, 1 } }, prof = "Mining", skill = 65,  name = "Smelt Bronze" },
  { out = 2842,  outQty = 1, inputs = { { 2775, 1 } },             prof = "Mining", skill = 75,  name = "Smelt Silver" },
  { out = 3575,  outQty = 1, inputs = { { 2772, 1 } },             prof = "Mining", skill = 125, name = "Smelt Iron" },
  { out = 3577,  outQty = 1, inputs = { { 2776, 1 } },             prof = "Mining", skill = 155, name = "Smelt Gold" },
  { out = 3859,  outQty = 1, inputs = { { 3575, 1 }, { 3857, 1 } }, prof = "Mining", skill = 165, name = "Smelt Steel" },
  { out = 3860,  outQty = 1, inputs = { { 3858, 1 } },             prof = "Mining", skill = 175, name = "Smelt Mithril" },
  { out = 6037,  outQty = 1, inputs = { { 7911, 1 } },             prof = "Mining", skill = 230, name = "Smelt Truesilver" },
  { out = 12359, outQty = 1, inputs = { { 10620, 1 } },            prof = "Mining", skill = 250, name = "Smelt Thorium" },
  { out = 11371, outQty = 1, inputs = { { 11370, 8 } },            prof = "Mining", skill = 230, name = "Smelt Dark Iron", note = "Black Forge only" },

  -- Leatherworking: leather and hides
  { out = 2318,  outQty = 1, inputs = { { 2934, 3 } },             prof = "Leatherworking", skill = 1,   name = "Light Leather" },
  { out = 2319,  outQty = 1, inputs = { { 2318, 4 } },             prof = "Leatherworking", skill = 100, name = "Medium Leather" },
  { out = 4234,  outQty = 1, inputs = { { 2319, 5 } },             prof = "Leatherworking", skill = 150, name = "Heavy Leather" },
  { out = 4304,  outQty = 1, inputs = { { 4234, 6 } },             prof = "Leatherworking", skill = 200, name = "Thick Leather" },
  { out = 8170,  outQty = 1, inputs = { { 4304, 6 } },             prof = "Leatherworking", skill = 250, name = "Rugged Leather" },
  { out = 4231,  outQty = 1, inputs = { { 783, 1 }, { 4340, 1 } },  prof = "Leatherworking", skill = 35,  name = "Cured Light Hide" },
  { out = 4236,  outQty = 1, inputs = { { 4232, 1 }, { 4340, 1 } }, prof = "Leatherworking", skill = 100, name = "Cured Medium Hide" },
  { out = 4237,  outQty = 1, inputs = { { 4235, 1 }, { 4340, 3 } }, prof = "Leatherworking", skill = 150, name = "Cured Heavy Hide" },
  { out = 8172,  outQty = 1, inputs = { { 8169, 1 }, { 8150, 1 } }, prof = "Leatherworking", skill = 200, name = "Cured Thick Hide" },
  { out = 15407, outQty = 1, inputs = { { 8171, 1 }, { 15409, 1 } }, prof = "Leatherworking", skill = 250, name = "Cured Rugged Hide" },

  -- Tailoring: bolts
  { out = 2996,  outQty = 1, inputs = { { 2589, 2 } },             prof = "Tailoring", skill = 1,   name = "Bolt of Linen Cloth" },
  { out = 2997,  outQty = 1, inputs = { { 2592, 3 } },             prof = "Tailoring", skill = 75,  name = "Bolt of Woolen Cloth" },
  { out = 4305,  outQty = 1, inputs = { { 4306, 4 } },             prof = "Tailoring", skill = 125, name = "Bolt of Silk Cloth" },
  { out = 4339,  outQty = 1, inputs = { { 4338, 5 } },             prof = "Tailoring", skill = 175, name = "Bolt of Mageweave" },
  { out = 14048, outQty = 1, inputs = { { 14047, 5 } },            prof = "Tailoring", skill = 250, name = "Bolt of Runecloth" },
}

-- Vendor-sold inputs with an unlimited supply at a fixed price, in copper.
-- Only entries we are sure about; anything else is priced from the market.
H.VendorBuy = {
  [4340] = 500,   -- Salt
}

-- Default cast time in seconds when a recipe does not say.
H.DEFAULT_CAST = 3
