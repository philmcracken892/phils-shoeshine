Config = {}

Config.RequireJob = true                   -- Set to false to disable job requirement
Config.JobName = 'shoeshiner'               -- Job name required to use shoe shine functions

-- Stand Model
Config.StandModel = 'p_shoeshinestand01x'


Config.SitOffset = { x = 0.4, y = 0.3, z = 1.1, heading = 180.0 }


Config.ShinerOffset = {
    x = 0.4,
    y = -1.3,
    z = 0.0,
    heading = 0.0
}

Config.PlacementDistance = 2.0
Config.InteractionDistance = 3.0
Config.NPCWalkDistance = 60.0
Config.WorldStandScanRadius = 100.0  

-- Pricing
Config.ShinePrice = 5
Config.ShinerEarnings = 5
Config.NPCPayAmount = 10

-- Auto NPC Shiner Settings
Config.AutoNPCShiner = {
    cost = 3,
    npcSearchRadius = 70.0
}

-- Duration (milliseconds)
Config.ShineDuration = 10000

-- NPC Queue
Config.MaxNPCQueue = 1

-- Scenarios
Config.Scenarios = {
    sit = "MP_LOBBY_PROP_HUMAN_SEAT_CHAIR_WHITTLE",
    shiner = "WORLD_HUMAN_WASH_FACE_BUCKET_GROUND_NO_BUCKET"
}

-- Prop Placer Settings
Config.PropPlacer = {
    PromptGroupName = "Place Shoe Shine Stand",
    PromptCancelName = "Cancel",
    PromptPlaceName = "Place Stand",
    PromptRotateLeft = "Rotate Left",
    PromptRotateRight = "Rotate Right",
    PromptPitchUp = "Pitch Up",
    PromptPitchDown = "Pitch Down",
    PromptRollLeft = "Roll Left",
    PromptRollRight = "Roll Right"
}