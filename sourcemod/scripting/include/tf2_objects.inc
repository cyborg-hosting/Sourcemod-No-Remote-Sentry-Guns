/**
 * vim: set ai et ts=4 sw=4 syntax=sourcepawn :
 * File: tf2_objects.inc
 * Description: Functions to return infomation about TF2 objects.
 * Author(s): Naris (Murray Wilson)
 */

#if defined _tf2_objects_included
 #endinput
#endif
#define _tf2_objects_included

#include <tf2>

enum TFExtObjectType
{
    TFExtObject_Unknown = -1,
    TFExtObject_CartDispenser = 0,
    TFExtObject_Dispenser = 0,
    TFExtObject_Teleporter = 1,
    TFExtObject_Sentry = 2,
    TFExtObject_Sapper = 3,
    TFExtObject_TeleporterEntry,
    TFExtObject_TeleporterExit,
    TFExtObject_MiniSentry,
    TFExtObject_Amplifier,
    TFExtObject_RepairNode
};

#define TFObject_Unknown            (view_as<TFObjectType>(TFExtObject_Unknown))
#define TFObject_TeleporterEntry    (view_as<TFObjectType>(TFExtObject_TeleporterEntry))
#define TFObject_TeleporterExit     (view_as<TFObjectType>(TFExtObject_TeleporterExit))
#define TFObject_MiniSentry         (view_as<TFObjectType>(TFExtObject_MiniSentry))
#define TFObject_Amplifier          (view_as<TFObjectType>(TFExtObject_Amplifier))
#define TFObject_RepairNode         (view_as<TFObjectType>(TFExtObject_RepairNode))

stock const char TF2_ObjectClassNames[TFExtObjectType][] =
{
    "obj_dispenser",
    "obj_teleporter",
    "obj_sentrygun",
    "obj_sapper",
    "obj_teleporter", // _entrance
    "obj_teleporter", // _exit
    "obj_sentrygun",  // minisentry
    "obj_dispenser",  // amplifier
    "obj_dispenser"   // repair_node
};

stock const char TF2_ObjectNames[TFExtObjectType][] =
{
    "Dispenser",
    "Teleporter",
    "Sentry Gun",
    "Sapper",
    "Teleporter Entrance",
    "Teleporter Exit",
    "Mini Sentry Gun",
    "Amplifier",
    "Repair Node"
};

stock TF2_ObjectModes[TFExtObjectType] =
{
    -1, // dispenser
    -1, // teleporter (either)
    -1, // sentrygun
    -1, // sapper
     0, // telporter_entrance
     1, // teleporter_exit
    -1, // minisentry
    -1, // amplifier
    -1  // repair_node
};

// Max Sentry Ammo for Level:         mini,   1,   2,   3,  max
stock const int TF2_MaxSentryShells[]  = { 150, 100, 120, 144,  255 };
stock const int TF2_MaxSentryRockets[] = {   0,   0,   0,  20,   63 };
stock const int TF2_SentryHealth[]     = { 100, 150, 180, 216, 8191 };

stock const int TF2_MaxUpgradeMetal    = 200;
stock const int TF2_MaxDispenserMetal  = 400;

stock TFExtObjectType TF2_GetExtObjectType(int entity, bool specific = false)
{
    char class[5];
    if (GetEdictClassname(entity, class, sizeof(class)) &&
        strncmp(class, "obj_", 4) == 0)
    {
        TFExtObjectType type = view_as<TFExtObjectType>(GetEntProp(entity, Prop_Send, "m_iObjectType"));
        if (specific)
        {
            if (type == TFExtObject_Teleporter)
            {
                type = (TF2_GetObjectMode(entity) == TFObjectMode_Exit)
                    ? TFExtObject_TeleporterExit
                : TFExtObject_TeleporterEntry;
            }
            else if (type == TFExtObject_Sentry)
            {
                if (GetEntProp(entity, Prop_Send, "m_bMiniBuilding"))
                type = TFExtObject_MiniSentry;
            }
        }
        return type;
    }
    else
        return TFExtObject_Unknown;
}