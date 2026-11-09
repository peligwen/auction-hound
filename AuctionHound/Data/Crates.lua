-- Data/Crates.lua: Waylaid Crates and the bundles that fill them.
--
-- A crate's own tooltip lists its bundles ("20 Copper Ore", "20 Tin
-- Ore") and any one of them fills it. Each entry here is the crate's
-- item ID, its name after "Waylaid Crate: ", and the bundles in the
-- order the tooltip gives them: item ID, units, and the English name
-- for when the client has not loaded the item yet.
--
-- Thirty crates in seven kinds and four tiers: the raw kinds (herbs,
-- ore, textiles, curiosities) run 248682 to 248699, the worked ones
-- (fabrics, ingots, parts) 248702 to 248713. The IDs and units are
-- from the item records of the launch build, 1.60.1; the goods are
-- the classic ones. The plain "Waylaid Crate", 248549, has yet to be
-- read for its label and names no goods, and a sealed crate is already
-- full, so neither is here.
local ADDON, H = ...

H.Crates = {
  -- Herbs
  [248682] = { name = "Apprentice Herbs", bundles = {
    { 2447, 20, "Peacebloom" }, { 765, 20, "Silverleaf" }, { 2449, 10, "Earthroot" },
    { 785, 10, "Mageroyal" }, { 2450, 10, "Briarthorn" } } },
  [248686] = { name = "Journeyman Herbs", bundles = {
    { 3820, 10, "Stranglekelp" }, { 2453, 10, "Bruiseweed" }, { 3355, 10, "Wild Steelbloom" },
    { 3369, 10, "Grave Moss" }, { 3356, 10, "Kingsblood" } } },
  [248690] = { name = "Earthly Expert Herbs", bundles = {
    { 3357, 20, "Liferoot" }, { 3818, 10, "Fadeleaf" }, { 3821, 10, "Goldthorn" },
    { 3358, 10, "Khadgar's Whisker" } } },
  [248691] = { name = "Flowering Expert Herbs", bundles = {
    { 3819, 10, "Wintersbite" }, { 4625, 10, "Firebloom" }, { 8831, 20, "Purple Lotus" },
    { 8836, 10, "Arthas' Tears" } } },
  [248695] = { name = "Earthly Artisan Herbs", bundles = {
    { 13464, 10, "Golden Sansam" }, { 8838, 20, "Sungrass" }, { 8839, 10, "Blindweed" },
    { 8845, 10, "Ghost Mushroom" }, { 8846, 10, "Gromsblood" } } },
  [248696] = { name = "Flowering Artisan Herbs", bundles = {
    { 13463, 20, "Dreamfoil" }, { 13465, 20, "Mountain Silversage" }, { 13466, 20, "Plaguebloom" },
    { 13467, 20, "Icecap" } } },

  -- Ore
  [248683] = { name = "Apprentice Ore", bundles = {
    { 2770, 20, "Copper Ore" }, { 2771, 20, "Tin Ore" } } },
  [248687] = { name = "Journeyman Ore", bundles = {
    { 2775, 10, "Silver Ore" }, { 2772, 20, "Iron Ore" } } },
  [248692] = { name = "Expert Ore", bundles = {
    { 2776, 10, "Gold Ore" }, { 3858, 20, "Mithril Ore" } } },
  [248697] = { name = "Artisan Ore", bundles = {
    { 7911, 10, "Truesilver Ore" }, { 10620, 20, "Thorium Ore" }, { 11370, 20, "Dark Iron Ore" } } },

  -- Textiles: cloth and leather
  [248684] = { name = "Apprentice Textiles", bundles = {
    { 2589, 40, "Linen Cloth" }, { 2318, 20, "Light Leather" } } },
  [248688] = { name = "Journeyman Textiles", bundles = {
    { 2592, 20, "Wool Cloth" }, { 4306, 40, "Silk Cloth" }, { 2319, 20, "Medium Leather" } } },
  [248693] = { name = "Expert Textiles", bundles = {
    { 4338, 40, "Mageweave Cloth" }, { 4234, 20, "Heavy Leather" } } },
  [248698] = { name = "Artisan Textiles", bundles = {
    { 14047, 40, "Runecloth" }, { 4304, 20, "Thick Leather" }, { 8170, 20, "Rugged Leather" } } },

  -- Curiosities: dusts, essences and shards
  [248685] = { name = "Apprentice Curiosities", bundles = {
    { 10940, 20, "Strange Dust" }, { 10939, 4, "Greater Magic Essence" },
    { 10978, 6, "Small Glimmering Shard" }, { 11084, 2, "Large Glimmering Shard" } } },
  [248689] = { name = "Journeyman Curiosities", bundles = {
    { 11083, 20, "Soul Dust" }, { 11082, 4, "Greater Astral Essence" },
    { 11138, 6, "Small Glowing Shard" }, { 11139, 2, "Large Glowing Shard" } } },
  [248694] = { name = "Expert Curiosities", bundles = {
    { 11137, 20, "Vision Dust" }, { 11135, 4, "Greater Mystic Essence" },
    { 11177, 6, "Small Radiant Shard" }, { 11178, 2, "Large Radiant Shard" } } },
  [248699] = { name = "Artisan Curiosities", bundles = {
    { 11176, 20, "Dream Dust" }, { 11175, 4, "Greater Nether Essence" },
    { 14343, 6, "Small Brilliant Shard" }, { 14344, 2, "Large Brilliant Shard" } } },

  -- Fabrics: bolts and cured hides
  [248702] = { name = "Apprentice Fabrics", bundles = {
    { 4231, 2, "Cured Light Hide" }, { 2996, 20, "Bolt of Linen Cloth" } } },
  [248705] = { name = "Journeyman Fabrics", bundles = {
    { 2997, 6, "Bolt of Woolen Cloth" }, { 4305, 10, "Bolt of Silk Cloth" }, { 4233, 2, "Cured Medium Hide" } } },
  [248708] = { name = "Expert Fabrics", bundles = {
    { 4339, 8, "Bolt of Mageweave" }, { 4236, 2, "Cured Heavy Hide" } } },
  [248711] = { name = "Artisan Fabrics", bundles = {
    { 14048, 8, "Bolt of Runecloth" }, { 8172, 2, "Cured Thick Hide" } } },

  -- Ingots
  [248703] = { name = "Apprentice Ingots", bundles = {
    { 2840, 20, "Copper Bar" }, { 3576, 20, "Tin Bar" }, { 2841, 10, "Bronze Bar" } } },
  [248706] = { name = "Journeyman Ingots", bundles = {
    { 2842, 10, "Silver Bar" }, { 3575, 20, "Iron Bar" } } },
  [248709] = { name = "Expert Ingots", bundles = {
    { 3860, 20, "Mithril Bar" }, { 3859, 15, "Steel Bar" }, { 3577, 10, "Gold Bar" } } },
  [248712] = { name = "Artisan Ingots", bundles = {
    { 11371, 2, "Dark Iron Bar" }, { 6037, 10, "Truesilver Bar" }, { 12359, 20, "Thorium Bar" } } },

  -- Parts
  [248704] = { name = "Apprentice Parts", bundles = {
    { 4359, 16, "Handful of Copper Bolts" }, { 4361, 16, "Copper Tube" }, { 4363, 4, "Copper Modulator" } } },
  [248707] = { name = "Journeyman Parts", bundles = {
    { 4371, 8, "Bronze Tube" }, { 4375, 7, "Whirring Bronze Gizmo" }, { 4382, 4, "Bronze Framework" },
    { 10558, 45, "Gold Power Core" } } },
  [248710] = { name = "Expert Parts", bundles = {
    { 4387, 8, "Iron Strut" }, { 10559, 5, "Mithril Tube" }, { 10560, 12, "Unstable Trigger" },
    { 10561, 5, "Mithril Casing" } } },
  [248713] = { name = "Artisan Parts", bundles = {
    { 15994, 5, "Thorium Widget" }, { 18631, 5, "Truesilver Transformer" }, { 16000, 2, "Thorium Tube" } } },
}
