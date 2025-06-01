Config = {}

-- Core Settings
Config.Debug = false
Config.UseTarget = 'ox_target' -- Only ox_target is supported (no other target system will work)
Config.EMSJobName = 'ambulance' -- EMS job name in your framework
Config.MinEMSCount = 1 -- Minimum number of EMS required to disable AI medic

-- Notification Settings
Config.NotificationType = 'ox_lib' -- Using ox_lib notifications for player death
Config.UseOxLibNotifications = true -- Enable ox_lib notifications

-- AI Medic Settings
Config.MedicModel = 's_m_m_paramedic_01' -- Paramedic ped model instead of FBI agent
Config.MedicVehicle = 'f450ambo' -- Vehicle model for medic
Config.ReviveCost = 100 -- Cost to revive player
Config.RequiresCash = false -- If true, player needs money to be revived
Config.MedicTimeout = 60000 -- Timeout in ms between AI medic calls (60 seconds)
Config.AutomaticMedic = true -- Enable automatic medic when player is down
Config.MedicCommand = 'medic' -- Command to call medic manually
Config.ReviveTime = 10000 -- Time it takes for medic to revive player (10 seconds)
Config.ReviveDistance = 2.0 -- Distance for medic to revive player
Config.MedicArrivalTime = {min = 25, max = 35} -- Time range in seconds for medic arrival
Config.VehicleSpawnDistance = 300.0 -- Distance away to spawn the vehicle
Config.DrivingStyle = 787004 -- Combines rushed flag, ignore lights, and avoiding obstacles
Config.MaxSpeed = 35.0 -- Maximum speed for ambulance driving
Config.StuckDetectionDistance = 0.5 -- Distance to detect if vehicle is stuck
Config.MedicBlip = {
    sprite = 61,
    color = 2,
    scale = 0.8,
    label = "AI Medic"
}

-- Notifications
Config.Notifications = {    NoEMSOnline = "An AI medic has been dispatched to your location.",
    EnoughEMSOnline = "There are enough EMS online. Please wait for their assistance.",
    MedicDispatched = "AI medic has been dispatched. ETA: %s seconds.",
    MedicArrived = "AI medic has arrived to help you.",
    NotDead = "You can only call a medic when you're incapacitated or bleeding out.",
    NotEnoughMoney = "You don't have enough money in your bank account. You need $%s for medical services.",
    MoneyDeducted = "$%s has been deducted from your bank account for medical services.",
    PlayerDied = "A medic has been dispatched to your location."
}

-- ox_lib Notification Settings
Config.OxLibNotifications = {    PlayerDied = {
        title = 'Emergency Services',
        description = 'You have died. A medic has been dispatched to your location.',
        type = 'inform',
        position = 'top',
        icon = 'fas fa-ambulance',
        iconColor = '#ff0000',
        duration = 5000
    },
    MedicDispatched = {
        title = 'Emergency Services',
        description = 'An AI medic has been dispatched to your location. ETA: %s seconds.',
        type = 'inform',
        position = 'top',
        icon = 'fas fa-ambulance',
        iconColor = '#ff0000',
        duration = 5000
    }
}