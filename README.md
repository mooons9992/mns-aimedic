# MNS AI Medic

A FiveM resource that adds an AI paramedic that responds to player injuries when no EMS personnel are online.

## Features

- AI paramedic in ambulance that responds to player injuries
- Configurable EMS count check to only work when few/no real EMS are online
- Ambulance with lights and sirens that drives from a distance to your location
- Proper animations for CPR and medical treatment
- Bank payment system with email receipts
- QBCore phone integration for sending invoices
- Configurable response times, costs, and behaviors
- Support for both ox_lib and default QBCore notifications

## Dependencies

- QBCore Framework
- qb-phone (for email notifications)
- ox_lib (optional, for improved notifications)

## Installation

1. Download the resource
2. Place it in your `resources/[mns]` folder
3. Add `ensure mns-aimedic` to your server.cfg
4. Configure the `config.lua` file to your liking

## Commands

- `/medic` - Call for an AI medic when injured
- `/testmedicmail` - Test the email notification system (Admin only)

## Configuration

The `config.lua` file contains all configurable options:

```lua
-- Core Settings
Config.Debug = false
Config.UseTarget = 'ox_target'
Config.EMSJobName = 'ambulance'
Config.MinEMSCount = 1

-- AI Medic Settings
Config.MedicModel = 's_m_m_paramedic_01'
Config.MedicVehicle = 'ambulance'
Config.ReviveCost = 1500
Config.RequiresCash = true
Config.MedicTimeout = 60000
Config.AutomaticMedic = true
Config.MedicCommand = 'medic'
Config.ReviveTime = 10000
Config.ReviveDistance = 2.0
Config.MedicArrivalTime = {min = 25, max = 35}
Config.VehicleSpawnDistance = 500.0

-- Notification Settings
Config.NotificationType = 'ox_lib'
Config.UseOxLibNotifications = true
```

## How It Works

1. When a player is injured or dies, the script checks if there are enough EMS online
2. If not, an AI medic is dispatched (automatically or via the `/medic` command)
3. An ambulance with lights and sirens will spawn and drive to the player's location
4. The paramedic will exit the vehicle and perform CPR on the player
5. If the player has enough money in their bank account, they will be charged and revived
6. An email notification with the invoice will be sent to the player's phone
7. The paramedic will return to their vehicle and drive away

## Bank Payment System

The script will check if the player has enough money in their bank account before reviving them. If they do, it will:

1. Deduct the configured amount from their bank account
2. Send them an email notification with the invoice details
3. Revive the player

If the player doesn't have enough money, the medic will leave without reviving them.

## Email Notifications

When a player is charged for medical services, they will receive an email notification through the qb-phone system with:

- A unique invoice number
- The amount charged
- The date and time of service
- A professional message from the emergency medical services

## Troubleshooting

- If the ambulance is getting stuck, try adjusting the `VehicleSpawnDistance` setting
- If emails aren't being received, use the `/testmedicmail` command to diagnose issues
- For debugging purposes, enable `Config.Debug = true` to see detailed logs

## Credits

Developed by MNS Development

## License

This resource is licensed under the MIT License