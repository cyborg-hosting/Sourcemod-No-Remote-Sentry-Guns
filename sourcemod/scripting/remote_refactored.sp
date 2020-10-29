/**
 * vim: set ai et ts=4 sw=4 :
 * File: remote.sp
 * Description: Remote Controlled Sentries
 * Author(s): twistedeuphoria,CnB|Omega,Tsunami,-=|JFH|=-Naris
 * Modified by: -=|JFH|=-Naris (Murray Wilson)
 *              -- Added Native interface
 *              -- Added build support
 *              -- Merged Tsunami's build limit
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#tryinclude "amp_node"
#tryinclude "ztf2grab"
#define REQUIRE_PLUGIN

#define MAXENTITIES 2048

#define PLUGIN_VERSION "5.1"

//#include <remote>
// These define the permissions
#define HAS_REMOTE 		            (1 << 0)
#define REMOTE_CAN_ZOMBIE		    (1 << 1)
#define REMOTE_CAN_STEAL		    (1 << 2)
#define REMOTE_CAN_BUILD_INSTANTLY	(1 << 3)
#define REMOTE_CAN_BUILD_FLOATING	(1 << 4)
#define REMOTE_CAN_BUILD_MINI       (1 << 5)
#define REMOTE_CAN_BUILD_LEVEL_1    (1 << 6)
#define REMOTE_CAN_BUILD_LEVEL_2    (1 << 7)
#define REMOTE_CAN_BUILD_LEVEL_3    (1 << 8)
#define REMOTE_CAN_BUILD_AMPLIFIER  (1 << 9)
#define REMOTE_CAN_BUILD_REPAIR     (1 << 10)

// These define the HasBuiltFlags
enum HasBuiltFlags (<<= 1)
{
    HasBuiltNothing = 0,
    HasBuiltDispenser = 1,
    HasBuiltTeleporterEntrance,
    HasBuiltTeleporterExit,
    HasBuiltSentry
}

#define REMOTE_CAN_BUILD            (REMOTE_CAN_BUILD_MINI|REMOTE_CAN_BUILD_LEVEL_1|REMOTE_CAN_BUILD_LEVEL_2|REMOTE_CAN_BUILD_LEVEL_3)
#define REMOTE_CAN_BUILD_UPGRADED   (REMOTE_CAN_BUILD_LEVEL_2|REMOTE_CAN_BUILD_LEVEL_3)
#define CAN_BUILD_ACTIVATED         REMOTE_CAN_BUILD_INSTANTLY

int g_RemoteObjectRef[MAXPLAYERS+1];
bool g_RemoteBuild[MAXPLAYERS+1];
TFExtObjectType g_RemoteType[MAXPLAYERS+1];
int g_WatcherEntRef[MAXPLAYERS+1];
int clientPermissions[MAXPLAYERS+1] = { -1, ... };
float clientSpeed[MAXPLAYERS+1];
float clientFallSpeed[MAXPLAYERS+1];
float clientJumpSpeed[MAXPLAYERS+1];
float clientPosition[MAXPLAYERS+1][3];

float levelFactor[3] = { 0.50, 1.00, 1.50 };
float defaultSpeed = 400.0;
float defaultFallSpeed = -500.0;
float defaultJumpSpeed = 2000.0;
bool defaultZombie = false;

// forwards
Handle g_fwdOnBuildCommand = null;
Handle fwdOnBuildObject = null;
Handle fwdOnControlObject = null;

// convars
Handle cvarObjectsTxt = null;
Handle cvarRemote = null;
Handle cvarSteal = null;
Handle cvarZombie = null;
Handle cvarBuild = null;
Handle cvarLevel = null;
Handle cvarMini = null;
Handle cvarInstant = null;
Handle cvarAlways = null;
Handle cvarFactor = null;
Handle cvarSpeed = null;
Handle cvarJump = null;
Handle cvarFall = null;

Handle cvarBuildEnabled = null;
Handle cvarBuildImmunity = null;

#if defined _amp_node_included
    Handle cvarAmp = null;
    Handle cvarRepair = null;
#endif

#if defined _amp_node_included || defined _ztf2grab_included
    stock bool:m_AmpNodeAvailable = false;
    stock bool:m_GravgunAvailable = false;
#endif

public Plugin myinfo = {
    name = "Remote Control Sentries",
    author = "twistedeuphoria,CnB|Omega,Tsunami,-=|JFH|=-Naris",
    description = "Remotely control your sentries",
    version = PLUGIN_VERSION,
    url = "http://www.jigglysfunhouse.net"
};

/**
 * Description: Function to check the entity limit.
 *              Use before spawning an entity.
 */
#tryinclude <entlimit>
#if !defined _entlimit_included
    stock int IsEntLimitReached(int warn = 20, int critical = 16, int client = 0, const char[] message = "")
    {
        int max = GetMaxEntities();
        int count = GetEntityCount();
        int remaining = max - count;
        if (remaining <= warn)
        {
            if (count <= critical)
            {
                PrintToServer("Warning: Entity limit is nearly reached! Please switch or reload the map!");
                LogError("Entity limit is nearly reached: %d/%d (%d):%s", count, max, remaining, message);

                if (client > 0)
                {
                    PrintToConsole(client, "Entity limit is nearly reached: %d/%d (%d):%s",
                                   count, max, remaining, message);
                }
            }
            else
            {
                PrintToServer("Caution: Entity count is getting high!");
                LogMessage("Entity count is getting high: %d/%d (%d):%s", count, max, remaining, message);

                if (client > 0)
                {
                    PrintToConsole(client, "Entity count is getting high: %d/%d (%d):%s",
                                   count, max, remaining, message);
                }
            }
            return count;
        }
        else
            return 0;
    }
#endif

/**
 * Description: Stocks to return information about TF2 player condition, etc.
 */
#tryinclude <tf2_player>
#if !defined _tf2_player_included
    #define TF2_IsPlayerDisguised(%1)    TF2_IsPlayerInCondition(%1,TFCond_Disguised)
    #define TF2_IsPlayerCloaked(%1)      TF2_IsPlayerInCondition(%1,TFCond_Cloaked)
    #define TF2_IsPlayerDeadRingered(%1) TF2_IsPlayerInCondition(%1,TFCond_DeadRingered)
    #define TF2_IsPlayerBonked(%1)       TF2_IsPlayerInCondition(%1,TFCond_Bonked)
#endif

/**
 * Description: Functions to return infomation about TF2 objects.
 */
#tryinclude <tf2_objects>
#if !defined _tf2_objects_included
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

    // Max Sentry Ammo for Level:         mini,   1,   2,   3, max
    stock const TF2_MaxSentryShells[]  = { 150, 100, 120, 144,  255 };
    stock const TF2_MaxSentryRockets[] = {   0,   0,   0,  20,   63 };
    stock const TF2_SentryHealth[]     = { 100, 150, 180, 216, 8191 };

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
#endif

// build limits
Handle g_Timer = null;       
int g_iMaxEntities = MAXENTITIES;
bool g_bNativeControl = false;
bool g_WasBuilt[MAXENTITIES];
HasBuiltFlags g_HasBuilt[MAXPLAYERS+1];

Handle cvarLimits[4][TFExtObjectType];
int g_isAllowed[MAXPLAYERS+1][TFExtObjectType]; // how many buildings each player is allowed

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Register Natives
    CreateNative("ControlRemote",Native_ControlRemote);
    CreateNative("SetRemoteControl",Native_SetRemoteControl);
    CreateNative("RemoteControlObject",Native_RemoteControlObject);
    CreateNative("StopControllingObject",Native_StopControllingObject);

    // Build Natives
    CreateNative("BuildObject",Native_BuildObject);
    CreateNative("BuildSentry",Native_BuildSentry);
    CreateNative("BuildDispenser",Native_BuildDispenser);
    CreateNative("BuildTeleporterEntry",Native_BuildTeleporterEntry);
    CreateNative("BuildTeleporterExit",Native_BuildTeleporterExit);
    CreateNative("AddBuildingsToMenu",Native_AddBuildingsToMenu);
    CreateNative("DestroyBuildingMenu",Native_DestroyBuildingMenu);
    CreateNative("DestroyBuildings",Native_DestroyBuildings);
    CreateNative("CountBuildings",Native_CountBuildings);
    CreateNative("CountObjects",Native_CountObjects);

    // Build Limit Natives
    CreateNative("ControlBuild",Native_ControlBuild);
    CreateNative("ResetBuild",Native_ResetBuild);
    CreateNative("CheckBuild",Native_CheckBuild);
    CreateNative("GiveBuild",Native_GiveBuild);

    // Register Forwards
    fwdOnBuildObject=CreateGlobalForward("OnBuildObject",ET_Hook,Param_Cell,Param_Cell);
    fwdOnControlObject=CreateGlobalForward("OnControlObject",ET_Hook,Param_Cell,Param_Cell,Param_Cell);

    // Build Limit Forwards
    g_fwdOnBuildCommand=CreateGlobalForward("OnBuildCommand",ET_Hook,Param_Cell,Param_Cell,Param_Cell,Param_Cell);

    RegPluginLibrary("remote");
    return APLRes_Success;
}

public void OnPluginStart()
{		
    CreateConVar("sm_remote_version", PLUGIN_VERSION, "Remote Control/Build/Limit Buildings Version", FCVAR_REPLICATED|FCVAR_NOTIFY);

    cvarRemote = CreateConVar("sm_remote_enable", "1", "Enable or disable remote control.");
    cvarSteal = CreateConVar("sm_remote_steal", "0", "Set true to allow stealing other people's buildings.");
    cvarZombie = CreateConVar("sm_remote_zombie", "0", "Set false to stop controlling buildings when controller dies.");
    cvarBuild = CreateConVar("sm_remote_build", "0", "Set true to spawn desired building if it doesn't exist.");
    cvarLevel = CreateConVar("sm_remote_build_level", "1", "Max level building (sentry) that can be built.");
    cvarMini = CreateConVar("sm_remote_build_mini", "1", "Set true to allow mini sentries to be built.");
    cvarInstant = CreateConVar("sm_remote_instant", "0", "Set true to build buildings instantly (from the remote menu).");
    cvarAlways = CreateConVar("sm_remote_always_builds", "0", "Set true allow remote to always build new objects (within limits).");
    cvarFactor = CreateConVar("sm_remote_factor", "0.50", "Object Speed Factor: Specify either 1 factor (multiplied by (4 - upgrade level) or 3 values (one per upgrade level) separated with spaces");
    cvarSpeed = CreateConVar("sm_remote_speed", "300.0", "Speed at which remote objects move.");
    cvarJump = CreateConVar("sm_remote_jump", "2000.0", "Speed at which remote objects jump.");
    cvarFall = CreateConVar("sm_remote_fall", "500.0", "Speed at which remote objects fall.");
    cvarObjectsTxt = CreateConVar("sm_build_objects_txt", "0", "Set true if objects.txt has been modified to allow multiple buildings.");

    #if defined _amp_node_included
        cvarAmp = CreateConVar("sm_remote_build_amp", "1", "Set true to allow amplifiers to be built.");
        cvarRepair = CreateConVar("sm_remote_build_mini", "1", "Set true to allow repair nodes to be built.");

        HookConVarChange(cvarAmp, RemoteCvarChange);
        HookConVarChange(cvarRepair, RemoteCvarChange);
    #endif

    HookConVarChange(cvarRemote, RemoteCvarChange);
    HookConVarChange(cvarSteal, RemoteCvarChange);
    HookConVarChange(cvarZombie, RemoteCvarChange);
    HookConVarChange(cvarBuild, RemoteCvarChange);
    HookConVarChange(cvarMini, RemoteCvarChange);
    HookConVarChange(cvarInstant, RemoteCvarChange);
    HookConVarChange(cvarAlways, RemoteCvarChange);
    HookConVarChange(cvarFactor, RemoteCvarChange);
    HookConVarChange(cvarSpeed, RemoteCvarChange);
    HookConVarChange(cvarJump, RemoteCvarChange);

    RegConsoleCmd("sm_remote_on", RemoteOn, "Start remote controlling your buildings(sentry gun).", 0);
    RegConsoleCmd("sm_remote_off", RemoteOff, "Stop remote controlling your buildings.", 0);
    RegConsoleCmd("sm_remote", Remote, "Start/stop remote controlling your buildings(sentry gun).", 0);

    RegConsoleCmd("sm_remote_sentry", Remote, "Start/stop remote controlling your sentry gun.");
    RegConsoleCmd("sm_remote_enter", Remote, "Start/stop remote controlling your teleport entrance.");
    RegConsoleCmd("sm_remote_exit", Remote, "Start/stop remote controlling your teleport exit.");
    RegConsoleCmd("sm_remote_disp", Remote, "Start/stop remote controlling your dispenser.");

    RegConsoleCmd("sm_build", Build, "Build an object.");
    RegConsoleCmd("sm_build_sentry", Build, "Build a sentry gun.");
    RegConsoleCmd("sm_build_enter", Build, "Build a teleport entrance.");
    RegConsoleCmd("sm_build_exit", Build, "Build a teleport exit.");
    RegConsoleCmd("sm_build_disp", Build, "Build a dispenser.");

    RegAdminCmd("sm_remote_god", RemoteGod, ADMFLAG_ROOT, "Gives Sentry godmode (experimental).");

    // Build Limits
    cvarBuildEnabled  = CreateConVar("sm_buildlimit_enabled",        "1", "Enable/disable restricting buildings in TF2.");
    cvarBuildImmunity = CreateConVar("sm_buildlimit_immunity",       "0", "Enable/disable admin immunity for restricting buildings in TF2.");

    cvarLimits[2][0] = CreateConVar("sm_buildlimit_red_dispensers",   "1", "Limit for Red dispensers in TF2.");
    cvarLimits[2][1] = CreateConVar("sm_buildlimit_red_teleporters",  "1", "Limit for Red teleporter pairs in TF2.");
    cvarLimits[2][2] = CreateConVar("sm_buildlimit_red_sentries",     "1", "Limit for Red sentries in TF2.");
    //cvarLimits[2][6] = CreateConVar("sm_buildlimit_red_minisentries", "1", "Limit for Red mini sentries in TF2.");

    cvarLimits[3][0] = CreateConVar("sm_buildlimit_blu_dispensers",   "1", "Limit for Blu dispensers in TF2.");
    cvarLimits[3][1] = CreateConVar("sm_buildlimit_blu_teleporters",  "1", "Limit for Blu teleporter pairs in TF2.");
    cvarLimits[3][2] = CreateConVar("sm_buildlimit_blu_sentries",     "1", "Limit for Blu sentries in TF2.");
    //cvarLimits[3][6] = CreateConVar("sm_buildlimit_blu_minisentries", "1", "Limit for Blu mini sentries in TF2.");

    RegConsoleCmd("build", Command_Build, "Restrict buildings in TF2.");

    HookEvent("player_builtobject", PlayerBuiltObject);
    HookEvent("object_destroyed", ObjectDestroyed);
    HookEvent("player_death", PlayerDeathEvent);
    HookEvent("player_spawn",PlayerSpawnEvent);
    HookEvent("player_team",PlayerChangeTeamEvent);
    HookEventEx("teamplay_round_win",EventRoundOver,EventHookMode_PostNoCopy);
    HookEventEx("teamplay_round_stalemate",EventRoundOver,EventHookMode_PostNoCopy);

    #if defined _amp_node_included || defined _ztf2grab_included
        m_AmpNodeAvailable = LibraryExists("amp_node");
        m_GravgunAvailable = LibraryExists("ztf2grab");
    #endif
}

#if defined _amp_node_included || defined _ztf2grab_included
    public OnLibraryAdded(const String:name[])
    {
        if (StrEqual(name, "amp_node"))
        {
            if (!m_AmpNodeAvailable)
                m_AmpNodeAvailable = true;
        }
        else if (StrEqual(name, "ztf2grab"))
        {
            if (!m_GravgunAvailable)
                m_GravgunAvailable = true;
        }
    }

    public OnLibraryRemoved(const String:name[])
    {
        if (StrEqual(name, "amp_node"))
            m_AmpNodeAvailable = false;
        else if (StrEqual(name, "ztf2grab"))
            m_GravgunAvailable = false;
    }
#endif

public void OnConfigsExecuted()
{
    ParseFactorVar();
    defaultZombie = GetConVarBool(cvarZombie);
    defaultSpeed = GetConVarFloat(cvarSpeed);
    defaultJumpSpeed = GetConVarFloat(cvarJump);
    defaultFallSpeed = GetConVarFloat(cvarFall);
    if (defaultFallSpeed > 0)
        defaultFallSpeed *= -1.0;
}        

public void OnMapStart()
{
    // start timer
    g_Timer = CreateTimer(0.1, UpdateObjects, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    g_iMaxEntities  = GetMaxEntities();
}

public void OnMapEnd()
{
    CloseHandle(g_Timer);
}

public void RemoteCvarChange(Handle convar, const char[] oldValue, const char[] newValue)
{
    if (convar == cvarRemote)
    {
        int oldval = StringToInt(oldValue);
        int newval = StringToInt(newValue);
        if (newval != 0 && newval != 1)
        {
            PrintToServer("Value for sm_remote_enable is invalid %s, switching back to %s.", newValue, oldValue);
            SetConVarInt(cvarRemote, oldval);
            return;
        }
        else if (oldval == 1 && newval == 0)
        {
            for(int i = 1; i < MaxClients; i++)
                RemoteOff(i, 0);
        }
    }
    else if (convar == cvarSteal)
    {
        int oldval = StringToInt(oldValue);
        int newval = StringToInt(newValue);
        if (newval != 0 && newval != 1)
        {
            PrintToServer("Value for sm_remote_steal is invalid %s, switching back to %s.", newValue, oldValue);
            SetConVarInt(cvarSteal, oldval);
            return;
        }
    }
    else if (convar == cvarZombie)
    {
        int oldval = StringToInt(oldValue);
        int newval = StringToInt(newValue);
        if (newval != 0 && newval != 1)
        {
            PrintToServer("Value for sm_remote_zombie is invalid %s, switching back to %s.", newValue, oldValue);
            SetConVarInt(cvarZombie, oldval);
            return;
        }
        else
            defaultZombie = view_as<bool>(newval);
    }
    else if (convar == cvarBuild)
    {
        int oldval = StringToInt(oldValue);
        int newval = StringToInt(newValue);
        if (newval != 0 && newval != 1)
        {
            PrintToServer("Value for sm_remote_build is invalid %s, switching back to %s.", newValue, oldValue);
            SetConVarInt(cvarBuild, oldval);
            return;
        }
    }

    else if (convar == cvarMini)
    {
        int oldval = StringToInt(oldValue);
        int newval = StringToInt(newValue);
        if (newval != 0 && newval != 1)
        {
            PrintToServer("Value for sm_remote_mini is invalid %s, switching back to %s.", newValue, oldValue);
            SetConVarInt(cvarMini, oldval);
            return;
        }
    }
    else if (convar == cvarInstant)
    {
        int oldval = StringToInt(oldValue);
        int newval = StringToInt(newValue);
        if (newval != 0 && newval != 1)
        {
            PrintToServer("Value for sm_remote_instant is invalid %s, switching back to %s.", newValue, oldValue);
            SetConVarInt(cvarInstant, oldval);
            return;
        }
    }
    else if (convar == cvarAlways)
    {
        int oldval = StringToInt(oldValue);
        int newval = StringToInt(newValue);
        if (newval != 0 && newval != 1)
        {
            PrintToServer("Value for sm_remote_always_builds is invalid %s, switching back to %s.", newValue, oldValue);
            SetConVarInt(cvarAlways, oldval);
            return;
        }
    }
    else if (convar == cvarLevel)
    {
        int oldval = StringToInt(oldValue);
        int newval = StringToInt(newValue);
        if (newval < 0 || newval > 3)
        {
            PrintToServer("Value for sm_remote_build_level is invalid %s, switching back to %s.", newValue, oldValue);
            SetConVarInt(cvarLevel, oldval);
            return;
        }
    }
    else if (convar == cvarSpeed)
        defaultSpeed = StringToFloat(newValue);
    else if (convar == cvarJump)
        defaultJumpSpeed = StringToFloat(newValue);
    else if (convar == cvarFall)
    {
        defaultFallSpeed = StringToFloat(newValue);
        if (defaultFallSpeed > 0)
            defaultFallSpeed *= -1.0;
    }
    else if (convar == cvarFactor)
        ParseFactorVar();

    #if defined _amp_node_included
        else if (convar == cvarAmp)
        {
            new oldval = StringToInt(oldValue);
            new newval = StringToInt(newValue);
            if (newval != 0 && newval != 1)
            {
                PrintToServer("Value for sm_remote_amp is invalid %s, switching back to %s.", newValue, oldValue);
                SetConVarInt(cvarAmp, oldval);
                return;
            }
        }
        else if (convar == cvarRepair)
        {
            new oldval = StringToInt(oldValue);
            new newval = StringToInt(newValue);
            if (newval != 0 && newval != 1)
            {
                PrintToServer("Value for sm_remote_repair is invalid %s, switching back to %s.", newValue, oldValue);
                SetConVarInt(cvarRepair, oldval);
                return;
            }
        }
    #endif
}

void ParseFactorVar()
{
    char factorValue[32];
    char values[sizeof(levelFactor)][8];
    GetConVarString(cvarFactor, factorValue , sizeof(factorValue));
    if (factorValue[0])
    {
        int count = ExplodeString(factorValue," ",values, sizeof(values), sizeof(values[]));
        if (count > sizeof(levelFactor))
            count = sizeof(levelFactor);

        int level=0;
        for (; level < count; level++)
            levelFactor[level] = StringToFloat(values[level]);

        for (; level < sizeof(levelFactor); level++)
            levelFactor[level] = levelFactor[level-1] + levelFactor[0];
    }
}

public Action UpdateObjects(Handle timer)
{
    for (int i = 1; i<MaxClients;i++)
    {
        int ref = g_RemoteObjectRef[i];
        if (ref != 0 && IsClientInGame(i))
        {
            int objectID = EntRefToEntIndex(ref);
            if (objectID > 0)
            {
                int permissions = clientPermissions[i];
                bool zombie = (permissions < 0) ? ((permissions & REMOTE_CAN_ZOMBIE) != 0) : defaultZombie;
                if (!zombie && !IsPlayerAlive(i))
                    RemoteOff(i, 0);
                else
                {
                    if (permissions > 0) // Hack to find native bits
                    {
                        switch (TF2_GetPlayerClass(i))
                        {
                            case TFClass_Spy:
                            {
                                if (TF2_IsPlayerCloaked(i) || TF2_IsPlayerDeadRingered(i))
                                {
                                    RemoteOff(i, 0);
                                    continue;
                                }
                                else if (TF2_IsPlayerDisguised(i))
                                    TF2_RemovePlayerDisguise(i);
                            }
                            case TFClass_Scout:
                            {
                                if (TF2_IsPlayerBonked(i))
                                {
                                    RemoteOff(i, 0);
                                    continue;
                                }
                            }
                        }
                    }

                    float speed = (clientSpeed[i] > 0.0) ? clientSpeed[i] : defaultSpeed;
                    int level = GetEntProp(objectID, Prop_Send, "m_iUpgradeLevel");
                    if (level > sizeof(levelFactor))
                        speed *= levelFactor[0];
                    else if (level > 0)
                        speed *= levelFactor[sizeof(levelFactor)-level];
                    else
                        speed *= levelFactor[sizeof(levelFactor)-1];

                    float nspeed = speed * -1.0;

                    float angles[3];
                    GetClientEyeAngles(i, angles);
                    angles[0] = 0.0;

                    float fwdvec[3];
                    float rightvec[3];
                    float upvec[3];
                    GetAngleVectors(angles, fwdvec, rightvec, upvec);

                    float vel[3];
                    vel[2] = (clientFallSpeed[i] < 0.0) ? clientFallSpeed[i] : defaultFallSpeed;

                    int buttons = GetClientButtons(i);
                    if (buttons & IN_FORWARD)
                    {
                        vel[0] += fwdvec[0] * speed;
                        vel[1] += fwdvec[1] * speed;
                    }
                    if (buttons & IN_BACK)
                    {
                        vel[0] += fwdvec[0] * nspeed;
                        vel[1] += fwdvec[1] * nspeed;
                    }
                    if (buttons & IN_MOVELEFT)
                    {
                        vel[0] += rightvec[0] * nspeed;
                        vel[1] += rightvec[1] * nspeed;
                    }
                    if (buttons & IN_MOVERIGHT)
                    {
                        vel[0] += rightvec[0] * speed;
                        vel[1] += rightvec[1] * speed;
                    }

                    if (buttons & IN_JUMP)
                    {
                        int flags = GetEntityFlags(objectID);
                        if (flags & FL_ONGROUND)
                            vel[2] += (clientJumpSpeed[i] > 0.0) ? clientJumpSpeed[i] : defaultJumpSpeed;
                    }

                    TeleportEntity(objectID, NULL_VECTOR, angles, vel);

                    /*
                    float objectpos[3];
                    GetEntPropVector(objectID, Prop_Send, "m_vecOrigin", objectpos);

                    objectpos[0] += fwdvec[0] * -150.0;
                    objectpos[1] += fwdvec[1] * -150.0;
                    objectpos[2] += upvec[2] * 75.0;

                    int watcher = EntRefToEntIndex(g_WatcherEntRef[client]);
                    if (watcher > 0)
                        TeleportEntity(watcher, objectpos, angles, NULL_VECTOR);
                    */
                }
            }
            else
                RemoteOff(i, 0);
        }
    }
    return Plugin_Continue;
}

public Action Remote(int client, int args)
{
    int objectRef = g_RemoteObjectRef[client];
    if (objectRef != 0 && EntRefToEntIndex(objectRef) > 0)
        RemoteOff(client, args);
    else
    {
        char arg[64];
        GetCmdArg(0, arg, sizeof(arg));

        TFExtObjectType type = TFExtObject_Unknown;
        if (StrContains(arg, "sentry", false) >= 0)
            type = TFExtObject_Sentry;
        else if (StrContains(arg, "disp", false) >= 0)
            type = TFExtObject_Dispenser;
        else if (StrContains(arg, "enter", false) >= 0)
            type = TFExtObject_TeleporterEntry;
        else if (StrContains(arg, "exit", false) >= 0)
            type = TFExtObject_TeleporterExit;
        else if (GetCmdArgs() >= 1)
        {
            GetCmdArg(1, arg, sizeof(arg));
            int value = StringToInt(arg);
            if (value >= 1)
                type = view_as<TFExtObjectType>(value-1);
            else
            {
                if (StrContains(arg, "sentry", false) >= 0)
                    type = TFExtObject_Sentry;
                else if (StrContains(arg, "disp", false) >= 0)
                    type = TFExtObject_Dispenser;
                else if (StrContains(arg, "enter", false) >= 0)
                    type = TFExtObject_TeleporterEntry;
                else if (StrContains(arg, "exit", false) >= 0)
                    type = TFExtObject_TeleporterExit;
            }
        }

        RemoteControl(client, type);
    }

    return Plugin_Handled;
}

public Action RemoteOn(int client, int args)
{
    RemoteControl(client, TFExtObject_Unknown);
    return Plugin_Handled;
}

public Action Build(int client, int args)
{
    char arg[64];
    GetCmdArg(0, arg, sizeof(arg));

    TFExtObjectType type = TFExtObject_Unknown;
    if (StrContains(arg, "sentry", false) >= 0)
        type = TFExtObject_Sentry;
    else if (StrContains(arg, "disp", false) >= 0)
        type = TFExtObject_Dispenser;
    else if (StrContains(arg, "enter", false) >= 0)
        type = TFExtObject_TeleporterEntry;
    else if (StrContains(arg, "exit", false) >= 0)
        type = TFExtObject_TeleporterExit;
    else if (GetCmdArgs() >= 1)
    {
        GetCmdArg(1, arg, sizeof(arg));
        int value = StringToInt(arg);
        if (value >= 1)
            type = view_as<TFExtObjectType>(value-1);
        else
        {
            if (StrContains(arg, "sentry", false) >= 0)
                type = TFExtObject_Sentry;
            else if (StrContains(arg, "disp", false) >= 0)
                type = TFExtObject_Dispenser;
            else if (StrContains(arg, "enter", false) >= 0)
                type = TFExtObject_TeleporterEntry;
            else if (StrContains(arg, "exit", false) >= 0)
                type = TFExtObject_TeleporterExit;
        }
    }
    BuildObject(client, type);
    return Plugin_Handled;
}

void RemoteControl(int client, TFExtObjectType type)
{
    int permissions = GetPermissions(client);
    if (permissions == 0)
    {
        PrintToChat(client, "You are not authorized to use remote controls.");
        return;
    }

    // Save the client's position so we can restore it later
    GetClientAbsOrigin(client, clientPosition[client]);

    int target = GetClientAimTarget(client, false);
    if (target > 0) 
    {
        type = TF2_GetExtObjectType(target, true);
        if (type < TFExtObject_Unknown)
        {
            if ((permissions & REMOTE_CAN_STEAL) ||
                GetEntPropEnt(target,  Prop_Send, "m_hBuilder") == client)
            {
                control(client, target, type);
            }
            else
            {
                PrintToChat(client, "You don't own that!");
            }
            return;
        }
    }

    if (type == TFExtObject_Unknown)
    {
        Menu menu=CreateMenu(ObjectSelected);
        SetMenuTitle(menu,"Remote Control which Building:");

        int sum = -1;
        int counts[TFExtObjectType];
        bool okToBuild = false;
        if ((permissions & REMOTE_CAN_BUILD) != 0)
        {
            if (!g_bNativeControl)
                GetAllowances(client);

            sum = CountBuildings(client, counts);
            for (int i=0; i < sizeof(g_isAllowed[]); i++)
            {
                int num = g_isAllowed[client][i];
                if (num < 0 || counts[i] < num)
                {
                    okToBuild = true;
                    break;
                }
            }

            AddMenuItem(menu,"0","Build a Dispenser",
                        (counts[TFExtObject_Dispenser] >= g_isAllowed[client][TFExtObject_Dispenser])
                        ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

            #if defined _amp_node_included
                if (m_AmpNodeAvailable)
                {
                    if ((permissions & REMOTE_CAN_BUILD_AMPLIFIER) != 0)
                    {
                        AddMenuItem(menu,"7","Build an Amplifier",
                                    (counts[TFExtObject_Dispenser] >= g_isAllowed[client][TFExtObject_Dispenser])
                                    ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
                    }

                    if ((permissions & REMOTE_CAN_BUILD_REPAIR) != 0)
                    {
                        AddMenuItem(menu,"8","Build a Repair Node",
                                    (counts[TFExtObject_Dispenser] >= g_isAllowed[client][TFExtObject_Dispenser])
                                    ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
                    }
                }
            #endif

            AddMenuItem(menu,"4","Build a Teleporter Entry",
                        (counts[TFExtObject_TeleporterEntry] >= g_isAllowed[client][TFExtObject_TeleporterEntry])
                        ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

            AddMenuItem(menu,"5","Build a Teleporter Exit",
                        (counts[TFExtObject_TeleporterExit] >= g_isAllowed[client][TFExtObject_TeleporterExit])
                        ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

            int flag = (counts[TFExtObject_Sentry] >= g_isAllowed[client][TFExtObject_Sentry])
                       ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;

            if ((permissions & REMOTE_CAN_BUILD_MINI))
                AddMenuItem(menu,"6","Build a Mini Sentry Gun", flag);

            if ((permissions & REMOTE_CAN_BUILD_LEVEL_1) != 0)
            {
                if ((permissions & REMOTE_CAN_BUILD_UPGRADED) == 0)
                    AddMenuItem(menu,"2","Build a Sentry Gun", flag);
                else
                {
                    AddMenuItem(menu,"9","Build a Level 1 Sentry Gun", flag);
                    AddMenuItem(menu,"10","Build a Level 2 Sentry Gun", flag);
                    if ((permissions & REMOTE_CAN_BUILD_LEVEL_3) != 0)
                        AddMenuItem(menu,"11","Build a Level 3 Sentry Gun", flag);
                }
            }

            AddMenuItem(menu,"12","Destroy a Structure", ((sum > 0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
        }

        if (sum != 0)
            sum = AddBuildingsToMenu(menu, client, false, counts, target);

        if (okToBuild)
            DisplayMenu(menu,client,MENU_TIME_FOREVER);
        else if (sum == 1)
        {
            CancelMenu(menu);
            control(client, target, TF2_GetExtObjectType(target));
            return;
        }
        else if (sum == 0)
        {
            CancelMenu(menu);
            PrintToChat(client, "You have nothing to remote control!");
        }
        else
            DisplayMenu(menu,client,MENU_TIME_FOREVER);
    }
    else
    {
        int objectid = -1;
        while ((objectid = FindEntityByClassname(objectid, TF2_ObjectClassNames[type])) != -1)
        {
            if (GetEntPropEnt(objectid, Prop_Send, "m_hBuilder") == client)
                break;
        }

        if (objectid <= 0 && ((permissions & REMOTE_CAN_BUILD) != 0))
        {
            if ((permissions & REMOTE_CAN_BUILD_INSTANTLY) == 0 &&
                TF2_GetPlayerClass(client) == TFClass_Engineer &&
                (GetConVarBool(cvarObjectsTxt) ||
                 CountObjects(client,TF2_ObjectClassNames[type], TF2_ObjectModes[type]) <= 0))
            {
                g_RemoteType[client] = type;
                g_RemoteBuild[client] = true;
                g_RemoteObjectRef[client] = 0;

                int objectIDNUM, mode;
                if (type == TFExtObject_TeleporterEntry ||
                    type == TFExtObject_TeleporterExit)
                {
                    objectIDNUM = view_as<int>(TFExtObject_Teleporter);
                    mode = view_as<int>(type - TFExtObject_TeleporterEntry);
                }
                else if (type == TFExtObject_MiniSentry)
                {
                    objectIDNUM = view_as<int>(TFExtObject_Sentry);
                    mode = 1; // Not sure if this will work?
                }
                else
                {
                    objectIDNUM =view_as<int>(type);
                    mode = 0;
                }
                ClientCommand(client, "build %d %d", objectIDNUM, mode);
            }
            else
            {
                objectid = BuildSelectedObject(client, type, 1, true,
                                               .remote=((permissions & REMOTE_CAN_BUILD_INSTANTLY) == 0),
                                               .check=((permissions & REMOTE_CAN_BUILD_FLOATING) != 0));
            }
        }
        else if (objectid > 0)
            control(client, objectid, type);
        else
            PrintToChat(client, "%s not found!", TF2_ObjectNames[type]);
    }
}

void BuildObject(int client, TFExtObjectType type)
{
    int permissions = GetPermissions(client);
    if ((permissions & REMOTE_CAN_BUILD) == 0)
    {
        PrintToChat(client, "You are not authorized to build objects.");
        return;
    }

    if (type == TFExtObject_Unknown)
        BuildMenu(client, permissions, false);
}

int GetPermissions(int client)
{
    int permissions = clientPermissions[client];
    if (permissions < 0)
    {
        if (!GetConVarBool(cvarRemote))
        {
            PrintToChat(client, "Remoting is not enabled.");
            return 0;
        }
        else if (TF2_GetPlayerClass(client) != TFClass_Engineer)
        {
            PrintToChat(client, "You are not an engineer.");
            return 0;
        }
        else
        {
            permissions = HAS_REMOTE;

            if (GetConVarBool(cvarSteal))
                permissions |= REMOTE_CAN_STEAL;

            if (GetConVarBool(cvarBuild))
            {
                if (GetConVarBool(cvarInstant))
                    permissions |= REMOTE_CAN_BUILD_INSTANTLY;

                if (GetConVarBool(cvarMini))
                    permissions |= REMOTE_CAN_BUILD_MINI;

                #if defined _amp_node_included
                    if (m_AmpNodeAvailable)
                    {
                        if (GetConVarBool(cvarAmp))
                            permissions |= REMOTE_CAN_BUILD_AMPLIFIER;

                        if (GetConVarBool(cvarRepair))
                            permissions |= REMOTE_CAN_BUILD_REPAIR;
                    }
                #endif

                int level = GetConVarInt(cvarLevel);
                if (level >= 1)
                {
                    permissions |= REMOTE_CAN_BUILD_LEVEL_1;
                    if (level >= 2)
                    {
                        permissions |= REMOTE_CAN_BUILD_LEVEL_2;
                        if (level >= 3)
                            permissions |= REMOTE_CAN_BUILD_LEVEL_3;
                    }
                }
            }
        }
    }
    return permissions;
}

void GetAllowances(int client)
{
    int team = GetClientTeam(client);

    g_isAllowed[client][TFExtObject_Dispenser]  = GetConVarInt(cvarLimits[team][0]); //[TFExtObject_Dispenser]

    g_isAllowed[client][TFExtObject_Sentry]     = GetConVarInt(cvarLimits[team][2]); //[TFExtObject_Sentry]
    //g_isAllowed[client][TFExtObject_MiniSentry] = GetConVarInt(cvarLimits[team][6]); //[TFExtObject_MiniSentry]
    g_isAllowed[client][TFExtObject_MiniSentry] = g_isAllowed[client][TFExtObject_Sentry];

    int teleporterLimit = GetConVarInt(cvarLimits[team][1]); //[TFExtObject_Teleporter]
    g_isAllowed[client][TFExtObject_Teleporter] =  teleporterLimit * 2;
    g_isAllowed[client][TFExtObject_TeleporterExit] = teleporterLimit;
    g_isAllowed[client][TFExtObject_TeleporterEntry] = teleporterLimit;
}

void BuildMenu(int client, int permissions, bool control)
{
    if (!g_bNativeControl)
        GetAllowances(client);

    g_RemoteObjectRef[client] = 0;
    g_RemoteBuild[client] = control;
    Menu menu = new Menu(BuildSelected);
    SetMenuTitle(menu,"Build & Remote Control:");

    int counts[TFExtObjectType];
    int sum = CountBuildings(client, counts);

    AddMenuItem(menu,"0","Dispenser",
                (counts[TFExtObject_Dispenser] >= g_isAllowed[client][TFExtObject_Dispenser])
                ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

    #if defined _amp_node_included
        if (m_AmpNodeAvailable)
        {
            if ((permissions & REMOTE_CAN_BUILD_AMPLIFIER) != 0)
            {
                AddMenuItem(menu,"7","Amplifier",
                            (counts[TFExtObject_Dispenser] >= g_isAllowed[client][TFExtObject_Dispenser])
                            ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
            }

            if ((permissions & REMOTE_CAN_BUILD_REPAIR) != 0)
            {
                AddMenuItem(menu,"8","Repair Node",
                            (counts[TFExtObject_Dispenser] >= g_isAllowed[client][TFExtObject_Dispenser])
                            ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
            }
        }
    #endif

    AddMenuItem(menu,"4","Teleporter Entry",
                (counts[TFExtObject_TeleporterEntry] >= g_isAllowed[client][TFExtObject_TeleporterEntry])
                ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
                
    AddMenuItem(menu,"5","Teleporter Exit",
                (counts[TFExtObject_TeleporterExit] >= g_isAllowed[client][TFExtObject_TeleporterExit])
                ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

    int flag = (counts[TFExtObject_Sentry] >= g_isAllowed[client][TFExtObject_Sentry])
               ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;

    if ((permissions & REMOTE_CAN_BUILD_MINI) != 0)
        AddMenuItem(menu,"6","Mini Sentry Gun", flag);

    if ((permissions & REMOTE_CAN_BUILD_LEVEL_1) != 0)
    {
        if ((permissions & REMOTE_CAN_BUILD_UPGRADED) == 0)
            AddMenuItem(menu,"2","Sentry Gun", flag);
        else
        {
            AddMenuItem(menu,"9","Level 1 Sentry Gun", flag);
            AddMenuItem(menu,"10","Level 2 Sentry Gun", flag);
            if ((permissions & REMOTE_CAN_BUILD_LEVEL_3) != 0)
                AddMenuItem(menu,"11","Level 3 Sentry Gun", flag);
        }
    }

    AddMenuItem(menu,"12","Destroy Structure", ((sum > 0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
    DisplayMenu(menu,client,MENU_TIME_FOREVER);
}

public int BuildSelected(Menu menu, MenuAction action, int client, int selection)
{
    if (action == MenuAction_Select)
    {
        char SelectionInfo[12];
        GetMenuItem(menu,selection,SelectionInfo,sizeof(SelectionInfo));

        int permissions = GetPermissions(client);
        int item = StringToInt(SelectionInfo);
        if (item == 12)
            DestroyBuildingMenu(client);
        else
        {
            int level;
            bool mini = false;
            TFExtObjectType type;
            if (item == 4)
            {
                type = TFExtObject_TeleporterEntry;
                level = 1;
            }
            else if (item == 5)
            {
                type = TFExtObject_TeleporterExit;
                level = 1;
            }
            else if (item == 6)
            {
                type = TFExtObject_Sentry;
                mini = true;
                level = 1;
            }
            else if (item == 7 || item == 8) // Amplifier || Repair Node
            {
                type = TFExtObject_Dispenser;
                level = 1;
            }
            else if (item >= 9)
            {
                type = TFExtObject_Sentry;
                level = item - 8;
            }
            else
            {
                type = view_as<TFExtObjectType>(item);
                level = 1;
            }

            if ((permissions & REMOTE_CAN_BUILD_INSTANTLY) == 0 &&
                TF2_GetPlayerClass(client) == TFClass_Engineer &&
                (GetConVarBool(cvarObjectsTxt) ||
                 CountObjects(client,TF2_ObjectClassNames[selection], TF2_ObjectModes[selection]) <= 0))
            {
                g_RemoteType[client] = view_as<int>(type);

                int objectIDNUM, mode;
                if (type == TFExtObject_TeleporterEntry ||
                    type == TFExtObject_TeleporterExit)
                {
                    objectIDNUM = view_as<int>(TFExtObject_Teleporter);
                    mode = view_as<int>(type - TFExtObject_TeleporterEntry);
                }
                else if (type == TFExtObject_MiniSentry)
                {
                    objectIDNUM = view_as<int>(TFExtObject_Sentry);
                    mode = 1; // Not sure if this will work?
                }
                else
                {
                    objectIDNUM =view_as<int>(type);
                    mode = 0;
                }
                ClientCommand(client, "build %d %d", objectIDNUM, mode);
            }
            else
            {
                BuildSelectedObject(client, type, level, mini, .remote=g_RemoteBuild[client],
                                    .disable=((permissions & REMOTE_CAN_BUILD_INSTANTLY) == 0),
                                    .check=((permissions & REMOTE_CAN_BUILD_FLOATING) != 0));
            }
        }
    }
    else if (action == MenuAction_End)
        CloseHandle(menu);
}

int BuildSelectedObject(int client, TFExtObjectType type, int iLevel = 1, bool mini = false,
                    bool shield = false, bool disable = true, int iHealth = -1,
                    int iMaxHealth = -1, float flPercentage = 1.0, bool remote = false,
                    bool drop = true, bool check = true, float objectPosition[3] = {0.0, 0.0, 0.0})
{
    int objectid = -1;

    if (TF2_GetPlayerClass(client) == TFClass_Spy)
    {
        if (TF2_IsPlayerCloaked(client) || TF2_IsPlayerDeadRingered(client))
            return objectid;
        else if (TF2_IsPlayerDisguised(client))
            TF2_RemovePlayerDisguise(client);
    }
    else if (GetClientTeam(client) < view_as<int>(TFTeam_Red))
        return objectid;
    else if (check && !CheckBuild(client, type))
        return objectid;
    else if (IsEntLimitReached(.client=client, .message="unable to create tf2 building"))
        return objectid;

    Action res = Plugin_Continue;
    Call_StartForward(fwdOnBuildObject);
    Call_PushCell(client);
    Call_PushCell(type);
    Call_Finish(res);

    if (res == Plugin_Continue)
    {
        float pos[3];
        GetClientAbsOrigin(client, pos);

        float angles[3];
        if (!GetClientEyeAngles(client, angles))
            GetClientAbsAngles(client, angles);

        angles[0] = 0.0; // Remove any pitch
        angles[2] = 0.0; // and/or roll

        switch (type)
        {
            case TFExtObject_Sentry:
            {
                objectid = BuildSentry(client, pos, angles, iLevel, disable, mini, shield,
                                       iHealth, iMaxHealth, .flPercentage=flPercentage);
            }
            case TFExtObject_MiniSentry:
            {
                objectid = BuildSentry(client, pos, angles, iLevel, disable, true, shield,
                                       iHealth, iMaxHealth, .flPercentage=flPercentage);
            }
            case TFExtObject_Teleporter, TFExtObject_TeleporterEntry:
            {
                objectid = BuildTeleporterEntry(client, pos, angles, iLevel, disable,
                                                iHealth, iMaxHealth, flPercentage);
            }
            case TFExtObject_TeleporterExit:
            {
                objectid = BuildTeleporterExit(client, pos, angles, iLevel, disable,
                                               iHealth, iMaxHealth, flPercentage);
            }
            case TFExtObject_Dispenser, TFExtObject_Amplifier, TFExtObject_RepairNode:
            {
                objectid = BuildDispenser(client, pos, angles, iLevel, disable,
                                          iHealth, iMaxHealth, .flPercentage=flPercentage,
                                          .type=type);
            }
        }

        if (objectid > 0)
        {
            objectPosition[0] = pos[0];
            objectPosition[1] = pos[1];
            objectPosition[2] = pos[2];

            if (remote)
            {
                // Save the player's position so we can put him back.
                clientPosition[client][0] = pos[0];
                clientPosition[client][1] = pos[1];
                clientPosition[client][2] = pos[2];

                // Move player up ontop of new object
                float size[3];
                GetEntPropVector(objectid, Prop_Send, "m_vecBuildMaxs", size);

                pos[2] += (size[2] * 1.1);
                TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);

                if (!control(client, objectid, type))
                {
                    if (type != TFExtObject_Teleporter &&
                        type != TFExtObject_TeleporterEntry &&
                        type != TFExtObject_TeleporterExit)
                    {
                        // Make it noclip so you don't get stuck
                        SetEntProp(objectid, Prop_Send, "m_CollisionGroup", 5);

                        // Teleport player back to floor.
                        pos[2] = clientPosition[client][2];
                        TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
                    }
                }
            }
            else
            {
                if (type == TFExtObject_Teleporter ||
                    type == TFExtObject_TeleporterEntry ||
                    type == TFExtObject_TeleporterExit)
                {
                    // Move player up ontop of new object
                    float size[3];
                    GetEntPropVector(objectid, Prop_Send, "m_vecBuildMaxs", size);

                    pos[2] += (size[2] * 1.1);
                    TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
                }
                else
                {
                    // Make it noclip so you don't get stuck
                    SetEntProp(objectid, Prop_Send, "m_CollisionGroup", 5);
                }
            }

            #if defined _ztf2grab_included
                if (drop && m_GravgunAvailable)
                    DropEntity(objectid);
            #else
                #pragma unused drop
            #endif

            if (disable || !remote)
            {
                float delay;
                switch (type)
                {
                    case TFExtObject_Sentry:      delay = float(iLevel) * (mini ? 2.5 : 10.0);
                    case TFExtObject_MiniSentry:  delay = float(iLevel) * 2.5;
                    default:                      delay = 20.0;
                }
                CreateTimer(delay, Activate, EntIndexToEntRef(objectid), TIMER_FLAG_NO_MAPCHANGE);
            }
        }
    }

    return objectid;
}

int CountBuildings(int client, int counts[TFExtObjectType])
{
    int sum;
    for (TFExtObjectType t = TFExtObject_Dispenser;t <= TFExtObject_TeleporterExit; t++)
    {
        if (t != TFExtObject_Teleporter)
        {
            counts[t] = CountObjects(client, TF2_ObjectClassNames[t], TF2_ObjectModes[t]);
            sum += counts[t];
        }
    }
    counts[TFExtObject_Amplifier]  = counts[TFExtObject_Dispenser];
    counts[TFExtObject_RepairNode] = counts[TFExtObject_Dispenser];
    counts[TFExtObject_MiniSentry] = counts[TFExtObject_Sentry];
    counts[TFExtObject_Teleporter] = counts[TFExtObject_TeleporterEntry]
                                   + counts[TFExtObject_TeleporterExit];
    return sum;
}

int CountObjects(int client, const char[] ClassName, int mode=-1)
{
    int ent = -1;
    int count = 0;
    while ((ent = FindEntityByClassname(ent, ClassName)) != -1)
    {
        if (GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client &&
            (mode < 0 || GetEntProp(ent, Prop_Send, "m_iObjectMode") == mode))
        {
            count++;
        }
    }
    return count;
}

int AddObjectsToMenu(Menu menu, int client, const char[] ClassName, int mode = -1,
                 const char[] ObjectName, bool all = false, int &target = 0)
{
    char buf[12], item[64];
    int ent = -1;
    int count = 0;
    while ((ent = FindEntityByClassname(ent, ClassName)) != -1)
    {
        if (GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client &&
            (mode < 0 || GetEntProp(ent, Prop_Send, "m_iObjectMode") == mode) &&
            GetEntProp(ent, Prop_Send, "m_bPlacing") == 0 &&
            (all || (GetEntPropFloat(ent, Prop_Send, "m_flPercentageConstructed") >= 1.0 &&
                     !GetEntProp(ent, Prop_Send, "m_bHasSapper") &&
                     !GetEntProp(ent, Prop_Send, "m_bDisabled"))))
        {
            count++;
            target=ent;
            IntToString(EntIndexToEntRef(ent), buf, sizeof(buf));
            Format(item,sizeof(item),"%s (%d)", ObjectName, ent);
            AddMenuItem(menu,buf,item);
        }
    }
    return count;
}

int AddBuildingsToMenu(Menu menu, int client, bool all = false, int counts[TFExtObjectType] = {0}, int &target=0)
{
    int sum;
    for (TFExtObjectType t = TFExtObject_Dispenser;t <= TFExtObject_TeleporterExit; t++)
    {
        if (t != TFExtObject_Teleporter)
        {
            counts[t] = AddObjectsToMenu(menu, client, TF2_ObjectClassNames[t],
                                         TF2_ObjectModes[t], TF2_ObjectNames[t],
                                         all, target);
            sum += counts[t];
        }
    }
    counts[TFExtObject_Amplifier]  = counts[TFExtObject_Dispenser];
    counts[TFExtObject_RepairNode] = counts[TFExtObject_Dispenser];
    counts[TFExtObject_MiniSentry] = counts[TFExtObject_Sentry];
    counts[TFExtObject_Teleporter] = counts[TFExtObject_TeleporterEntry]
                                   + counts[TFExtObject_TeleporterExit];
    return sum;
}

int DestroyObjects(char[] ClassName, int client = -1, bool all = true)
{
    int ent = -1;
    int count = 0;
    int kill_ent = -1;
    while ((ent = FindEntityByClassname(ent, ClassName)) != -1)
    {
        if (kill_ent > 0)
        {
            SetVariantInt(1000);
            AcceptEntityInput(kill_ent, "RemoveHealth");
            //AcceptEntityInput(kill_ent, "Kill");
            g_WasBuilt[kill_ent] = false;
        }

        if (client <= 0 || GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == client)
        {
            if (all || g_WasBuilt[ent])
            {
                kill_ent = ent;
                count++;
            }
        }
    }

    if (kill_ent > 0)
    {
        SetVariantInt(1000);
        AcceptEntityInput(kill_ent, "RemoveHealth");
        //AcceptEntityInput(kill_ent, "Kill");
        g_WasBuilt[kill_ent] = false;
    }

    return count;
}

bool DestroyBuildingMenu(int client)
{
    Menu menu=CreateMenu(Destroy_Selected);
    SetMenuTitle(menu,"Destroy which Structure:");

    int counts[TFExtObjectType];
    int count = AddBuildingsToMenu(menu, client, true, counts);
    if (count > 0)
    {
        DisplayMenu(menu,client,MENU_TIME_FOREVER);
        return true;
    }
    else
    {
        CancelMenu(menu);
        return false;
    }
}

public int Destroy_Selected(Menu menu,MenuAction action, int client, int selection)
{
    if (action == MenuAction_Select)
    {
        char SelectionInfo[12];
        GetMenuItem(menu,selection,SelectionInfo,sizeof(SelectionInfo));

        int ref = StringToInt(SelectionInfo);
        if (ref != 0)
        {
            int ent = EntRefToEntIndex(ref);
            if (ent > 0)
                DestroyBuilding(ent);
        }
    }
}

void DestroyBuilding(int objectIDNUM)
{
    if (IsValidEdict(objectIDNUM) && IsValidEntity(objectIDNUM))
    {
        SetVariantInt(1000);
        AcceptEntityInput(objectIDNUM, "RemoveHealth");
        //AcceptEntityInput(objectIDNUM, "Kill");
        g_WasBuilt[objectIDNUM] = false;
    }
}

public void PlayerSpawnEvent(Event event, const char[] name, bool dontBroadcast)
{
    int  client = GetClientOfUserId(GetEventInt(event,"userid")); // Get clients index

    // Save the client's position so we won't teleport a newly spawned player elsewhere.
    GetClientAbsOrigin(client, clientPosition[client]);
}

public void PlayerDeathEvent(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event,"userid")); // Get clients index

    int objectRef = g_RemoteObjectRef[client];
    if (objectRef != 0 && EntRefToEntIndex(objectRef) > 0)
    {
        int permissions = clientPermissions[client];
        bool zombie = (permissions < 0) ? ((permissions & REMOTE_CAN_ZOMBIE) != 0) : defaultZombie;
        if (!zombie)
            RemoteOff(client, 0);
    }
}

public void PlayerBuiltObject(Event event, const char[] name, bool dontBroadcast)
{
    int objectid = GetEventInt(event, "index");
    if (GetEventInt(event, "sourcemod") <= 0)
        g_WasBuilt[objectid] = false;

    int index = GetClientOfUserId(GetEventInt(event, "userid"));
    if (g_RemoteBuild[index])
    {
        TFExtObjectType type = view_as<TFExtObjectType>(GetEventInt(event, "object"));
        if (g_RemoteType[index] == type)
        {
            if (objectid <= 0)
            {
                for (int i = MaxClients + 1; i < g_iMaxEntities; i++)
                {
                    if (IsValidEdict(i) && IsValidEntity(i))
                    {
                        if (TF2_GetExtObjectType(i) == type)
                        {
                            if (GetEntPropEnt(i,  Prop_Send, "m_hBuilder") == index)
                            {
                                objectid = i;
                                g_RemoteBuild[index] = false;
                                break;
                            }
                        }
                    }
                }
            }

            if (objectid > 0)
                control(index, objectid, type);
        }
    }
}

public void ObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
    int index = GetClientOfUserId(GetEventInt(event, "userid"));
    if (index > 0)
    {
        int objectIDNUM = GetEventInt(event, "index");
        if (objectIDNUM >= 0)
            g_WasBuilt[objectIDNUM] = false;
    }
}

public Action PlayerChangeTeamEvent(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    HasBuiltFlags flags = g_HasBuilt[client];
    if (client > 0 && flags != HasBuiltNothing)
    {
        if ((flags & HasBuiltDispenser) != HasBuiltNothing)
            DestroyObjects(TF2_ObjectClassNames[TFExtObject_Dispenser], client, false);

        if ((flags & HasBuiltSentry) != HasBuiltNothing)
            DestroyObjects(TF2_ObjectClassNames[TFExtObject_Sentry], client, false);

        if ((flags & HasBuiltTeleporterEntrance) != HasBuiltNothing ||
            (flags & HasBuiltTeleporterExit) != HasBuiltNothing)
        {
            DestroyObjects(TF2_ObjectClassNames[TFExtObject_Teleporter], client, false);
        }

        g_HasBuilt[client] = HasBuiltNothing;
    }
    return Plugin_Continue;
}

public void EventRoundOver(Event event, const char[] name, bool dontBroadcast)
{
    // Destroy all the objects that have been built.
    DestroyObjects(TF2_ObjectClassNames[TFExtObject_Dispenser], -1, false);
    DestroyObjects(TF2_ObjectClassNames[TFExtObject_Teleporter], -1, false);
    DestroyObjects(TF2_ObjectClassNames[TFExtObject_Sentry], -1, false);

    for (int index=0;index<sizeof(g_HasBuilt);index++)
        g_HasBuilt[index] = HasBuiltNothing;

    for (int entity=0;entity<sizeof(g_WasBuilt);entity++)
        g_WasBuilt[entity] = false;
}

public Action Activate(Handle timer, any ref)
{
    int objectIDNUM = EntRefToEntIndex(ref);
    if (objectIDNUM > 0 && IsValidEdict(objectIDNUM) && IsValidEntity(objectIDNUM))
    {
        SetEntProp(objectIDNUM, Prop_Send, "m_bDisabled", 0);
        AcceptEntityInput(objectIDNUM, "TurnOn");

        if (TF2_GetObjectType(objectIDNUM) != TFObject_Teleporter &&
            GetEntProp(objectIDNUM, Prop_Send, "m_CollisionGroup") != 0)
        {
            int builder = GetEntPropEnt(objectIDNUM, Prop_Send, "m_hBuilder");
            if (builder > 0 && IsClientInGame(builder) && IsPlayerAlive(builder))
            {
                float playerPos[3];
                GetClientAbsOrigin(builder, playerPos);

                float objectPos[3];
                GetEntPropVector(objectIDNUM, Prop_Send, "m_vecOrigin", objectPos);

                float size[3];
                GetEntPropVector(objectIDNUM, Prop_Send, "m_vecBuildMaxs", size);

                float distance = GetVectorDistance(objectPos, playerPos);
                if (distance < size[0] * -1.1 || distance > size[0] * 1.1)
                    SetEntProp(objectIDNUM, Prop_Send, "m_CollisionGroup", 0);
                else
                    CreateTimer(2.0, Activate, ref, TIMER_FLAG_NO_MAPCHANGE);
            }
            else
                SetEntProp(objectIDNUM, Prop_Send, "m_CollisionGroup", 0);
        }
    }
    return Plugin_Stop;
}

public int ObjectSelected(Menu menu, MenuAction action, int client, int selection)
{
    if (action == MenuAction_Select)
    {
        char SelectionInfo[12];
        GetMenuItem(menu,selection,SelectionInfo,sizeof(SelectionInfo));
        int objectRef = StringToInt(SelectionInfo);
        if (objectRef >= 0 && objectRef <= 12) // 0-12 are build options
        {
            g_RemoteBuild[client] = true;
            BuildSelected(menu,action,client,selection);
        }
        else
        {
            int objectid = EntRefToEntIndex(objectRef);
            if (objectid > 0 && IsValidEdict(objectid) && IsValidEntity(objectid))
                control(client, objectid, TF2_GetExtObjectType(objectid));
        }
    }
    else if (action == MenuAction_End)
        CloseHandle(menu);
}

bool control(int client, int objectid, TFExtObjectType type)
{
    Action res = Plugin_Continue;
    Call_StartForward(fwdOnControlObject);
    Call_PushCell(client);
    Call_PushCell(client); // builder);
    Call_PushCell(objectid);
    Call_Finish(res);

    if (res == Plugin_Continue &&
        !IsEntLimitReached(.client=client,.message="unable to create info_observer_point"))
    {
        int watcher = CreateEntityByName("info_observer_point");
        if (watcher > 0 && IsValidEdict(watcher) && DispatchSpawn(watcher))
        {
            float angles[3];
            GetEntPropVector(objectid, Prop_Send, "m_angRotation", angles);

            float fwdvec[3];
            float rightvec[3];
            float upvec[3];
            GetAngleVectors(angles, fwdvec, rightvec, upvec);

            float pos[3];
            GetEntPropVector(objectid, Prop_Send, "m_vecOrigin", pos);

            pos[0] += fwdvec[0] * -150.0;
            pos[1] += fwdvec[1] * -150.0;
            pos[2] += upvec[2] * 75.0;

            TeleportEntity(watcher, pos, angles, NULL_VECTOR);

            SetClientViewEntity(client, watcher);

            // Set the watcher's parent to the object.
            char strTargetName[64];
            IntToString(objectid, strTargetName, sizeof(strTargetName));

            DispatchKeyValue(objectid, "targetname", strTargetName);

            SetVariantString(strTargetName);
            AcceptEntityInput(watcher, "SetParent", -1, -1, 0);

            SetEntityMoveType(objectid, MOVETYPE_STEP);
            SetEntityMoveType(client, MOVETYPE_NONE); // MOVETYPE_STEP);

            g_RemoteType[client] = type;
            g_WatcherEntRef[client] = EntIndexToEntRef(watcher);
            g_RemoteObjectRef[client] = EntIndexToEntRef(objectid);
            return true;
        }
    }
    return false;
}

public Action RemoteOff(int client, int args)
{
    int objectRef = g_RemoteObjectRef[client];
    if (objectRef != 0)
    {
        int objectIDNUM = EntRefToEntIndex(objectRef);
        if (objectIDNUM > 0 && IsValidEdict(objectIDNUM) && IsValidEntity(objectIDNUM))
        {
            float angles[3];
            GetClientEyeAngles(client, angles);	
            angles[0] = 0.0;

            TeleportEntity(objectIDNUM, NULL_VECTOR, angles, NULL_VECTOR);

            TFExtObjectType type = g_RemoteType[client];
            if ((type != TFExtObject_Teleporter &&
                 type != TFExtObject_TeleporterEntry &&
                 type != TFExtObject_TeleporterExit) &&
                IsPlayerAlive(client))
            {
                float objectPos[3];
                GetEntPropVector(objectIDNUM, Prop_Send, "m_vecOrigin", objectPos);

                float size[3];
                GetEntPropVector(objectIDNUM, Prop_Send, "m_vecBuildMaxs", size);

                float distance = GetVectorDistance(objectPos, clientPosition[client]);
                if (distance < size[0] * -1.1 || distance > size[0] * 1.1)
                {
                    SetEntProp(objectIDNUM, Prop_Send, "m_CollisionGroup", 5);
                    //CreateTimer(2.0, Activate, EntIndexToEntRef(objectIDNUM), TIMER_FLAG_NO_MAPCHANGE);
                }
            }
        }

        if (IsClientInGame(client))
        {
            SetClientViewEntity(client, client);
            SetEntityMoveType(client, MOVETYPE_WALK);

            if (IsPlayerAlive(client))
                TeleportEntity(client, clientPosition[client], NULL_VECTOR, NULL_VECTOR);
        }
    }

    int watcher = EntRefToEntIndex(g_WatcherEntRef[client]);
    if (watcher > 0)
        RemoveEdict(watcher);

    g_RemoteBuild[client] = false;
    g_WatcherEntRef[client] = 0;
    g_RemoteObjectRef[client] = 0;
    g_RemoteType[client] = TFExtObject_Unknown;
    return Plugin_Handled;
}

public Action RemoteGod(int client, int args)
{
    int objectRef = g_RemoteObjectRef[client];
    if (objectRef == 0)
        PrintToChat(client, "Not controlling a building!");
    else
    {
        int objectIDNUM = EntRefToEntIndex(objectRef);
        if (objectIDNUM > 0 && IsValidEdict(objectIDNUM) && IsValidEntity(objectIDNUM))
        {
            if (GetEntProp(objectIDNUM, Prop_Send, "m_takedamage", 1)) // mortal
            {
                SetEntProp(objectIDNUM, Prop_Send, "m_takedamage", 0, 1);
                PrintToChat(client,"\x01\x04Building god mode on");
            }
            else // godmode
            {
                SetEntProp(objectIDNUM, Prop_Send, "m_takedamage", 1, 1);
                PrintToChat(client,"\x01\x04Building god mode off");
            }
        }
        else
        {
            PrintToChat(client, "Building has been destroyed!");
            RemoteOff(client, args);
        }
    }
}

/**
 * Description: Build Restrictions for TF2
 * Author(s): Tsunami
 */

public void OnClientPutInServer(int client)
{
    g_RemoteBuild[client] = false;
    g_WatcherEntRef[client] = 0;
    g_RemoteObjectRef[client] = 0;
    g_RemoteType[client] = TFExtObject_Unknown;

    g_HasBuilt[client] = HasBuiltNothing;
    for (int i=0; i < sizeof(g_isAllowed[]); i++)
        g_isAllowed[client][i] = 1;

    g_isAllowed[client][TFExtObject_Teleporter]++; // 1 entry + 1 exit
}

public void OnClientDisconnect(int client)
{
    g_HasBuilt[client] = HasBuiltNothing;
    for (int i=0; i < sizeof(g_isAllowed[]); i++)
        g_isAllowed[client][i] = 1;

    g_isAllowed[client][TFExtObject_Teleporter]++; // 1 entry + 1 exit
}

public Action Command_Build(int client, int args)
{
    Action iResult = Plugin_Continue;

    if (g_bNativeControl || !client || 
        (GetConVarBool(cvarBuildEnabled) &&
         (!(GetConVarBool(cvarBuildImmunity) &&
           (GetUserFlagBits(client) & (ADMFLAG_GENERIC|ADMFLAG_ROOT)) != 0))))
    {
        char sObject[16];
        GetCmdArg(1, sObject, sizeof(sObject));

        char sMode[16];
        GetCmdArg(2, sMode, sizeof(sMode));

        TFExtObjectType objectIDNUM = view_as<TFExtObjectType>(StringToInt(sObject));
        int mode = StringToInt(sMode);

        TFTeam team = view_as<TFTeam>(GetClientTeam(client));
        if (objectIDNUM < TFExtObject_Dispenser || objectIDNUM > TFExtObject_TeleporterExit || team < TFTeam_Red)
            return Plugin_Continue;

        int iCount = 0;
        if (!CheckBuild(client, objectIDNUM, mode, iCount))
            return Plugin_Handled;

        Call_StartForward(g_fwdOnBuildCommand);
        Call_PushCell(client);
        Call_PushCell(objectIDNUM);
        Call_PushCell(mode);
        Call_PushCell(iCount);
        Call_Finish(iResult);
    }

    return iResult;
}

bool CheckBuild(int client, TFExtObjectType type, int mode=-1, int &iCount=0)
{
    if (type == TFExtObject_Sapper || type == TFExtObject_Unknown)
    {
        // Don't check sappers or unknown objects
        iCount = -1;
    }
    else
    {
        if (type == TFExtObject_TeleporterEntry ||
            type == TFExtObject_TeleporterExit)
        {
            type = TFExtObject_Teleporter;
        }
        else if (type == TFExtObject_Amplifier ||
                 type == TFExtObject_RepairNode)
        {
            type = TFExtObject_Dispenser;
        }
        else if (type == TFExtObject_MiniSentry)
            type = TFExtObject_Sentry;

        int iLimit = g_bNativeControl ? g_isAllowed[client][type]
                   : GetConVarInt(cvarLimits[GetClientTeam(client)][type]);

        if (iLimit == 0)
        {
            iCount = -1;
            return false;
        }
        else if (iLimit > 0)
        {
            if (type == TFExtObject_Teleporter)
                iLimit *= 2;

            iCount = CountObjects(client,TF2_ObjectClassNames[type], (mode < 0) ? TF2_ObjectModes[type] : mode);
            return (iCount < iLimit);
        }
        else
            iCount = -1;
    }
    return true;
}

/**
 * Description: Native Interface
 */

public int Native_ControlRemote(Handle plugin, int numParams)
{
    SetConVarInt(cvarRemote, 0);
}

public int Native_SetRemoteControl(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    clientPermissions[client] = GetNativeCell(2);
    clientSpeed[client] = view_as<float>(GetNativeCell(3));
    clientFallSpeed[client] = view_as<float>(GetNativeCell(4));
    clientJumpSpeed[client] = view_as<float>(GetNativeCell(5));
}

public int Native_RemoteControlObject(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (g_RemoteObjectRef[client] != 0)
        RemoteOff(client, 0);
    else
        RemoteControl(client, GetNativeCell(2));
}

public int Native_StopControllingObject(Handle plugin, int numParams)
{
    RemoteOff(GetNativeCell(1), 0);
}

/**
 * Description: Native Interface for Build
 */

public int Native_BuildObject(Handle plugin, int numParams)
{
    float pos[3];
    int ent = BuildSelectedObject(GetNativeCell(1), view_as<TFExtObjectType>(GetNativeCell(2)), GetNativeCell(3),
                                  view_as<bool>(GetNativeCell(4)), view_as<bool>(GetNativeCell(5)), view_as<bool>(GetNativeCell(6)),
                                  GetNativeCell(7), GetNativeCell(8), view_as<float>(GetNativeCell(9)),
                                  view_as<bool>(GetNativeCell(10)), view_as<bool>(GetNativeCell(11)),
                                  view_as<bool>(GetNativeCell(12)), pos);
    SetNativeArray(13, pos, sizeof(pos));
    return ent;                                  
}

public int Native_BuildSentry(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsEntLimitReached(.client=client, .message="unable to create obj_sentrygun"))
    {
        float fOrigin[3], fAngle[3];
        GetNativeArray(2, fOrigin, sizeof(fOrigin));
        GetNativeArray(3, fAngle, sizeof(fAngle));
        return BuildSentry(client, fOrigin, fAngle, GetNativeCell(4), view_as<bool>(GetNativeCell(5)),
                           view_as<bool>(GetNativeCell(6)), view_as<bool>(GetNativeCell(7)), GetNativeCell(8),
                           GetNativeCell(9), GetNativeCell(10), GetNativeCell(11),
                           view_as<float>(GetNativeCell(12)));
    }
    else
        return -1;
}

public int Native_BuildDispenser(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsEntLimitReached(.client=client, .message="unable to create obj_dispenser"))
    {
        float fOrigin[3], fAngle[3];
        GetNativeArray(2, fOrigin, sizeof(fOrigin));
        GetNativeArray(3, fAngle, sizeof(fAngle));
        return BuildDispenser(client, fOrigin, fAngle, GetNativeCell(4), view_as<bool>(GetNativeCell(5)),
                              GetNativeCell(6), GetNativeCell(7), GetNativeCell(8),
                              view_as<float>(GetNativeCell(9)), view_as<TFExtObjectType>(GetNativeCell(10)));
    }
    else
        return -1;
}

public int Native_BuildTeleporterEntry(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsEntLimitReached(.client=client, .message="unable to create obj_teleporter entrance"))
    {
        float fOrigin[3], fAngle[3];
        GetNativeArray(2, fOrigin, sizeof(fOrigin));
        GetNativeArray(3, fAngle, sizeof(fAngle));
        return BuildTeleporterEntry(client, fOrigin, fAngle, GetNativeCell(4),
                                    view_as<bool>(GetNativeCell(5)), GetNativeCell(6),
                                    GetNativeCell(7), view_as<float>(GetNativeCell(8)));
    }
    else
        return -1;
}

public int Native_BuildTeleporterExit(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsEntLimitReached(.client=client, .message="unable to create obj_teleporter exit"))
    {
        float fOrigin[3], fAngle[3];
        GetNativeArray(2, fOrigin, sizeof(fOrigin));
        GetNativeArray(3, fAngle, sizeof(fAngle));
        return BuildTeleporterExit(client, fOrigin, fAngle, GetNativeCell(4),
                                   view_as<bool>(GetNativeCell(5)), GetNativeCell(6),
                                   GetNativeCell(7), view_as<float>(GetNativeCell(8)));
    }
    else
        return -1;
}

public int Native_CountBuildings(Handle plugin, int numParams)
{
    int counts[TFExtObjectType];
    int retval = CountBuildings(GetNativeCell(1), counts);

    // Get rid of index tag to make compiler happy :(
    int nativeCounts[sizeof(counts)];
    for (int i = 0; i < sizeof(nativeCounts); i++)
        nativeCounts[i] = counts[i];

    SetNativeArray(2, nativeCounts, sizeof(nativeCounts));
    return retval;
}

public int Native_CountObjects(Handle plugin, int numParams)
{
    char class[64];
    GetNativeString(2,class,sizeof(class));
    return CountObjects(GetNativeCell(1), class, GetNativeCell(3));
}

public int Native_AddBuildingsToMenu(Handle plugin, int numParams)
{
    int target;
    int counts[TFExtObjectType];
    int retval = AddBuildingsToMenu(view_as<Menu>(GetNativeCell(1)), GetNativeCell(2),
                                    view_as<bool>(GetNativeCell(3)), counts, target);

    // Get rid of index tag to make compiler happy :(
    int nativeCounts[sizeof(counts)];
    for (int i = 0; i < sizeof(nativeCounts); i++)
        nativeCounts[i] = counts[i];

    SetNativeArray(4, nativeCounts, sizeof(nativeCounts));
    SetNativeCellRef(5, target);
    return retval;                                       
}

public int Native_DestroyBuildings(Handle plugin, int numParams)
{
    int count = 0;
    int client = GetNativeCell(1);
    bool all = view_as<bool>(GetNativeCell(2));
    HasBuiltFlags flags = (client > 0) ? g_HasBuilt[client]
                                           : view_as<HasBuiltFlags>(-1); // all 1s

    if (all || (flags & HasBuiltDispenser) != HasBuiltNothing)
        count += DestroyObjects(TF2_ObjectClassNames[TFExtObject_Dispenser], client, all);

    if (all || (flags & HasBuiltSentry) != HasBuiltNothing)
        count += DestroyObjects(TF2_ObjectClassNames[TFExtObject_Sentry], client, all);

    if (all || (flags & HasBuiltTeleporterEntrance) != HasBuiltNothing ||
               (flags & HasBuiltTeleporterExit) != HasBuiltNothing)
    {
        count += DestroyObjects(TF2_ObjectClassNames[TFExtObject_Teleporter], client, all);
    }

    return count;
}

public int Native_DestroyBuildingMenu(Handle plugin, int numParams)
{
    return DestroyBuildingMenu(GetNativeCell(1));
}

public int Native_DestroyBuilding(Handle plugin, int numParams)
{
    DestroyBuilding(GetNativeCell(1));
}

/**
 * Description: Native Interface for Build Limit
 */

public int Native_ControlBuild(Handle plugin, int numParams)
{
    g_bNativeControl = GetNativeCell(1);
}

public int Native_GiveBuild(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    g_isAllowed[client][TFExtObject_Dispenser] = GetNativeCell(3);
    g_isAllowed[client][TFExtObject_Sentry] = GetNativeCell(2);
    g_isAllowed[client][TFExtObject_TeleporterEntry] = GetNativeCell(4);
    g_isAllowed[client][TFExtObject_TeleporterExit] = GetNativeCell(5);

    g_isAllowed[client][TFExtObject_MiniSentry] = g_isAllowed[client][TFExtObject_Sentry];
    g_isAllowed[client][TFExtObject_Teleporter] = g_isAllowed[client][TFExtObject_TeleporterEntry]
                                                + g_isAllowed[client][TFExtObject_TeleporterExit];
}

public int Native_ResetBuild(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    for (TFExtObjectType t = TFExtObject_Dispenser;t < TFExtObjectType; t++)
        g_isAllowed[client][t] = 1;

    g_isAllowed[client][TFExtObject_Teleporter]++; // 1 entry + 1 exit
}

public int Native_CheckBuild(Handle plugin, int numParams)
{
    int iCount;
    bool result = CheckBuild(GetNativeCell(1), view_as<TFExtObjectType>(GetNativeCell(2)),
                                 GetNativeCell(3), iCount);
    SetNativeCellRef(4, iCount);
    return result;
}

/**
 * Description: Functions to spawn buildings.
 */
// derived from <tf2_build>

stock int BuildSentry(int hBuilder, const float fOrigin[3], const float fAngle[3], int iLevel = 1,
                  bool bDisabled = false, bool bMini = false, bool bShielded = false,
                  int iHealth = -1, int iMaxHealth = -1, int iShells = -1, int iRockets = -1,
                  float flPercentage = 1.0)
{
    static const float fBuildMaxs[3] = { 24.0, 24.0, 66.0 };
    //static const Float:fMdlWidth[3] = { 1.0, 0.5, 0.0 };

    int iTeam = GetClientTeam(hBuilder);

    int iSentryHealth;
    int iMaxSentryShells;
    int iMaxSentryRockets;
    if (iLevel < 1 || bMini)
    {
        iLevel = 1;
        iSentryHealth = TF2_SentryHealth[0];
        iMaxSentryShells = TF2_MaxSentryShells[0];
        iMaxSentryRockets = TF2_MaxSentryRockets[0];
    }
    else if (iLevel <= 3)
    {
        iSentryHealth = TF2_SentryHealth[iLevel];
        iMaxSentryShells = TF2_MaxSentryShells[iLevel];
        iMaxSentryRockets = TF2_MaxSentryRockets[iLevel];
    }
    else if (iLevel == 4)
    {
        iLevel = 3;
        iSentryHealth = TF2_SentryHealth[3]+40;
        iMaxSentryShells = (TF2_MaxSentryShells[3]+TF2_MaxSentryShells[4])/2;
        iMaxSentryRockets = (TF2_MaxSentryRockets[3]+TF2_MaxSentryRockets[4])/2;
    }
    else
    {
        iLevel = 3;
        iSentryHealth = TF2_SentryHealth[4];
        iMaxSentryShells = TF2_MaxSentryShells[4];
        iMaxSentryRockets = TF2_MaxSentryRockets[4];
    }

    if (iShells < 0)
        iRockets = iMaxSentryRockets;

    if (iShells < 0)
        iShells = iMaxSentryShells;

    if (iMaxHealth < 0)
        iMaxHealth = iSentryHealth;

    if (iHealth < 0 || iHealth > iMaxHealth)
        iHealth = iMaxHealth;

    int iSentry = CreateEntityByName(TF2_ObjectClassNames[TFExtObject_Sentry]);
    if (iSentry > 0 && IsValidEdict(iSentry))
    {
        DispatchSpawn(iSentry);

        TeleportEntity(iSentry, fOrigin, fAngle, NULL_VECTOR);

        char sModel[64];
        if (bMini)
            strcopy(sModel, sizeof(sModel),"models/buildables/sentry1.mdl");
        else
            Format(sModel, sizeof(sModel),"models/buildables/sentry%d.mdl", iLevel);

        SetEntityModel(iSentry,sModel);

        // m_bPlayerControlled is set to make m_bShielded work,
        // but it gets reset almost immediately :(

        SetEntProp(iSentry, Prop_Send, "m_iMaxHealth", 				        iMaxHealth, 4);
        SetEntProp(iSentry, Prop_Send, "m_iHealth", 					    iHealth, 4);
        SetEntProp(iSentry, Prop_Send, "m_bDisabled", 				        bDisabled, 2);
        SetEntProp(iSentry, Prop_Send, "m_bShielded", 				        bShielded, 2);
        SetEntProp(iSentry, Prop_Send, "m_bPlayerControlled", 				bShielded, 2);
        SetEntProp(iSentry, Prop_Send, "m_bMiniBuilding", 				    bMini, 2);
        SetEntProp(iSentry, Prop_Send, "m_iObjectType", 				    view_as<int>(TFExtObject_Sentry), 1);
        SetEntProp(iSentry, Prop_Send, "m_iUpgradeLevel", 			        iLevel, 4);
        SetEntProp(iSentry, Prop_Send, "m_iAmmoRockets", 				    iRockets, 4);
        SetEntProp(iSentry, Prop_Send, "m_iAmmoShells" , 				    iShells, 4);
        SetEntProp(iSentry, Prop_Send, "m_iState" , 				        (bShielded ? 2 : 0), 4);
        SetEntProp(iSentry, Prop_Send, "m_iObjectMode", 				    0, 2);
        SetEntProp(iSentry, Prop_Send, "m_iUpgradeMetal", 			        0, 2);
        SetEntProp(iSentry, Prop_Send, "m_bBuilding", 				        0, 2);
        SetEntProp(iSentry, Prop_Send, "m_bPlacing", 					    0, 2);
        SetEntProp(iSentry, Prop_Send, "m_iState", 					        1, 1);
        SetEntProp(iSentry, Prop_Send, "m_bHasSapper", 				        0, 2);
        SetEntProp(iSentry, Prop_Send, "m_nNewSequenceParity", 		        4, 4);
        SetEntProp(iSentry, Prop_Send, "m_nResetEventsParity", 		        4, 4);
        SetEntProp(iSentry, Prop_Send, "m_bServerOverridePlacement", 	    1, 1);
        SetEntProp(iSentry, Prop_Send, "m_nSequence",                       0);

        SetEntPropEnt(iSentry, Prop_Send, "m_hBuilder", 	                hBuilder);

        SetEntPropFloat(iSentry, Prop_Send, "m_flPercentageConstructed", 	flPercentage);
        SetEntPropFloat(iSentry, Prop_Send, "m_flModelWidthScale", 	        1.0);
        SetEntPropFloat(iSentry, Prop_Send, "m_flPlaybackRate", 			1.0);
        SetEntPropFloat(iSentry, Prop_Send, "m_flCycle", 					0.0);

        SetEntPropVector(iSentry, Prop_Send, "m_vecOrigin", 			    fOrigin);
        SetEntPropVector(iSentry, Prop_Send, "m_angRotation", 		        fAngle);
        SetEntPropVector(iSentry, Prop_Send, "m_vecBuildMaxs", 		        fBuildMaxs);
        //SetEntDataVector(iSentry, FindSendPropOffs("CObjectSentrygun","m_flModelWidthScale"),	fMdlWidth, true);

        if (bMini)
        {
            SetEntProp(iSentry, Prop_Send, "m_nSkin", 					    iTeam, 1);
            SetEntProp(iSentry, Prop_Send, "m_nBody", 					    5, 1);
        }
        else
        {
            SetEntProp(iSentry, Prop_Send, "m_nSkin", 					    (iTeam-2), 1);
            SetEntProp(iSentry, Prop_Send, "m_nBody", 					    0, 1);
        }

        SetVariantInt(iTeam);
        AcceptEntityInput(iSentry, "TeamNum", -1, -1, 0);

        SetVariantInt(iTeam);
        AcceptEntityInput(iSentry, "SetTeam", -1, -1, 0);

        SetVariantInt(hBuilder);
        AcceptEntityInput(iSentry, "SetBuilder", -1, -1, 0);

        Event event = CreateEvent("player_builtobject");
        if (event != null)
        {
            SetEventInt(event, "userid", GetClientUserId(hBuilder));
            SetEventInt(event, "object", view_as<int>(TFExtObject_Sentry));
            SetEventInt(event, "index", iSentry);
            SetEventBool(event, "sourcemod", true);
            FireEvent(event);
        }

        g_WasBuilt[iSentry] = true;
        g_HasBuilt[hBuilder] |= HasBuiltSentry;
    }
    return iSentry;
}

stock int BuildDispenser(int hBuilder, const float fOrigin[3], const float fAngle[3], int iLevel = 1,
                     bool iDisabled = false, int iHealth = -1, int iMaxHealth = -1, int iMetal = -1,
                     float flPercentage = 1.0, TFExtObjectType type = TFExtObject_Dispenser)
{
    static const float fBuildMaxs[3] = { 24.0, 24.0, 66.0 };

    int iTeam = GetClientTeam(hBuilder);

    if (iMaxHealth < 0)
        iMaxHealth = 150;

    if (iHealth < 0 || iHealth > iMaxHealth)
        iHealth = iMaxHealth;

    if (iMetal < 0)
        iMetal = 1000;

    if (iLevel < 1)
        iLevel = 1;
    else if (iLevel > 3)
        iLevel = 3;

    int iDispenser = CreateEntityByName(TF2_ObjectClassNames[TFExtObject_Dispenser]);
    if (iDispenser > 0 && IsValidEdict(iDispenser))
    {
        DispatchSpawn(iDispenser);

        TeleportEntity(iDispenser, fOrigin, fAngle, NULL_VECTOR);

        char sModel[64];
        switch (type)
        {
            case TFExtObject_Amplifier:
            {
                strcopy(sModel, sizeof(sModel),"models/buildables/amplifier_test/amplifier.mdl");
            }
            case TFExtObject_RepairNode:
            {
                if (iLevel > 1)
                    Format(sModel, sizeof(sModel),"models/buildables/repair_level%d.mdl", iLevel);
                else
                    strcopy(sModel, sizeof(sModel),"models/buildables/dispenser_light.mdl");
            }
            default:
            {
                if (iLevel > 1)
                    Format(sModel, sizeof(sModel),"models/buildables/dispenser_lvl%d_light.mdl", iLevel);
                else
                    strcopy(sModel, sizeof(sModel),"models/buildables/dispenser_light.mdl");
            }
        }

        SetEntityModel(iDispenser,sModel);

        SetEntProp(iDispenser, Prop_Send, "m_iMaxHealth", 				        iMaxHealth, 4);
        SetEntProp(iDispenser, Prop_Send, "m_iHealth", 				            iHealth, 4);
        SetEntProp(iDispenser, Prop_Send, "m_iAmmoMetal", 				        iMetal, 4);
        SetEntProp(iDispenser, Prop_Send, "m_bDisabled", 				        iDisabled, 2);
        SetEntProp(iDispenser, Prop_Send, "m_iObjectType", 			            view_as<int>(TFExtObject_Dispenser), 1);
        SetEntProp(iDispenser, Prop_Send, "m_nSkin", 					        (iTeam-2), 1);
        SetEntProp(iDispenser, Prop_Send, "m_iUpgradeLevel", 			        iLevel, 4);
        SetEntProp(iDispenser, Prop_Send, "m_iObjectMode", 				        0, 2);
        SetEntProp(iDispenser, Prop_Send, "m_bBuilding", 				        0, 2);
        SetEntProp(iDispenser, Prop_Send, "m_bPlacing", 				        0, 2);
        SetEntProp(iDispenser, Prop_Send, "m_bHasSapper", 				        0, 2);
        SetEntProp(iDispenser, Prop_Send, "m_nNewSequenceParity", 		        4, 4);
        SetEntProp(iDispenser, Prop_Send, "m_nResetEventsParity", 		        4, 4);
        SetEntProp(iDispenser, Prop_Send, "m_bServerOverridePlacement",         1, 1);
        SetEntProp(iDispenser, Prop_Send, "m_nSequence",                        0);

        SetEntPropEnt(iDispenser, Prop_Send, "m_hBuilder",                      hBuilder);

        SetEntPropFloat(iDispenser, Prop_Send, "m_flPercentageConstructed", 	flPercentage);
        SetEntPropFloat(iDispenser, Prop_Send, "m_flModelWidthScale", 	        1.0);
        SetEntPropFloat(iDispenser, Prop_Send, "m_flPlaybackRate", 			    1.0);
        SetEntPropFloat(iDispenser, Prop_Send, "m_flCycle", 					0.0);

        SetEntPropVector(iDispenser, Prop_Send, "m_vecOrigin", 		            fOrigin);
        SetEntPropVector(iDispenser, Prop_Send, "m_angRotation", 		        fAngle);
        SetEntPropVector(iDispenser, Prop_Send, "m_vecBuildMaxs",		        fBuildMaxs);

        SetVariantInt(iTeam);
        AcceptEntityInput(iDispenser, "TeamNum", -1, -1, 0);

        SetVariantInt(iTeam);
        AcceptEntityInput(iDispenser, "SetTeam", -1, -1, 0);

        SetVariantInt(hBuilder);
        AcceptEntityInput(iDispenser, "SetBuilder", -1, -1, 0);

        if (!iDisabled)
            AcceptEntityInput(iDispenser, "TurnOn");

        Event event = CreateEvent("player_builtobject");
        if (event != null)
        {
            SetEventInt(event, "userid", GetClientUserId(hBuilder));
            SetEventInt(event, "object", view_as<int>(TFExtObject_Dispenser));
            SetEventInt(event, "index", iDispenser);
            SetEventBool(event, "sourcemod", true);
            FireEvent(event);
        }

        #if defined _amp_node_included
            if (m_AmpNodeAvailable)
            {
                switch (type)
                {
                    case TFExtObject_Amplifier:
                    {
                        ConvertToAmplifier(iDispenser, hBuilder);
                    }
                    case TFExtObject_RepairNode:
                    {
                        ConvertToRepairNode(iDispenser, hBuilder);
                    }
                }
            }
        #endif

        g_WasBuilt[iDispenser] = true;
        g_HasBuilt[hBuilder] |= HasBuiltDispenser;
    }
    return iDispenser;
}

stock int BuildTeleporterEntry(int hBuilder, const float fOrigin[3], const float fAngle[3],
                           int iLevel = 1, bool iDisabled = false, int iHealth = -1, int iMaxHealth = -1,
                           float flPercentage=1.0)
{
    static const float fBuildMaxs[3] = { 28.0, 28.0, 66.0 };
    //static const Float:fMdlWidth[3] = { 1.0, 0.5, 0.0 };

    int iTeam = GetClientTeam(hBuilder);

    if (iMaxHealth < 0)
        iMaxHealth = 150;

    if (iHealth < 0 || iHealth > iMaxHealth)
        iHealth = iMaxHealth;

    if (iLevel < 1)
        iLevel = 1;
    else if (iLevel > 3)
        iLevel = 3;

    int iTeleporter = CreateEntityByName(TF2_ObjectClassNames[TFExtObject_Teleporter]);
    if (iTeleporter > 0 && IsValidEdict(iTeleporter))
    {
        DispatchSpawn(iTeleporter);

        TeleportEntity(iTeleporter, fOrigin, fAngle, NULL_VECTOR);

        SetEntityModel(iTeleporter,"models/buildables/teleporter_light.mdl");

        SetEntProp(iTeleporter, Prop_Send, "m_iMaxHealth", 				        iMaxHealth, 4);
        SetEntProp(iTeleporter, Prop_Send, "m_iHealth", 					    iHealth, 4);
        SetEntProp(iTeleporter, Prop_Send, "m_bDisabled", 				        iDisabled, 2);
        SetEntProp(iTeleporter, Prop_Send, "m_iObjectType", 				    view_as<int>(TFExtObject_Teleporter), 1);
        SetEntProp(iTeleporter, Prop_Send, "m_nSkin", 					        (iTeam-2), 1);
        SetEntProp(iTeleporter, Prop_Send, "m_iUpgradeLevel", 			        iLevel, 4);
        SetEntProp(iTeleporter, Prop_Send, "m_iObjectMode", 				    0, TF2_ObjectModes[TFExtObject_TeleporterEntry]);
        SetEntProp(iTeleporter, Prop_Send, "m_bBuilding", 				        0, 2);
        SetEntProp(iTeleporter, Prop_Send, "m_bPlacing", 					    0, 2);
        SetEntProp(iTeleporter, Prop_Send, "m_bHasSapper", 				        0, 2);
        SetEntProp(iTeleporter, Prop_Send, "m_nNewSequenceParity", 		        4, 4);
        SetEntProp(iTeleporter, Prop_Send, "m_nResetEventsParity", 		        4, 4);
        SetEntProp(iTeleporter, Prop_Send, "m_bServerOverridePlacement", 	    1, 1);
        SetEntProp(iTeleporter, Prop_Send, "m_iState", 	                        1, 1);
        SetEntProp(iTeleporter, Prop_Send, "m_nSequence",                       0);

        SetEntPropEnt(iTeleporter, Prop_Send, "m_hBuilder", 	                hBuilder);

        SetEntPropFloat(iTeleporter, Prop_Send, "m_flPercentageConstructed", 	flPercentage);
        SetEntPropFloat(iTeleporter, Prop_Send, "m_flModelWidthScale", 	        1.0);
        SetEntPropFloat(iTeleporter, Prop_Send, "m_flPlaybackRate", 			1.0);
        SetEntPropFloat(iTeleporter, Prop_Send, "m_flCycle", 					0.0);

        SetEntPropVector(iTeleporter, Prop_Send, "m_vecOrigin", 			    fOrigin);
        SetEntPropVector(iTeleporter, Prop_Send, "m_angRotation", 		        fAngle);
        SetEntPropVector(iTeleporter, Prop_Send, "m_vecBuildMaxs", 		        fBuildMaxs);

        SetVariantInt(iTeam);
        AcceptEntityInput(iTeleporter, "TeamNum", -1, -1, 0);

        SetVariantInt(iTeam);
        AcceptEntityInput(iTeleporter, "SetTeam", -1, -1, 0); 

        SetVariantInt(hBuilder);
        AcceptEntityInput(iTeleporter, "SetBuilder", -1, -1, 0); 

        if (!iDisabled)
            AcceptEntityInput(iTeleporter, "TurnOn");

        Event event = CreateEvent("player_builtobject");
        if (event != null)
        {
            SetEventInt(event, "userid", GetClientUserId(hBuilder));
            SetEventInt(event, "object", view_as<int>(TFExtObject_TeleporterEntry));
            SetEventInt(event, "index", iTeleporter);
            SetEventBool(event, "sourcemod", true);
            FireEvent(event);
        }

        g_WasBuilt[iTeleporter] = true;
        g_HasBuilt[hBuilder] |= HasBuiltTeleporterEntrance;
    }
    return iTeleporter;
}

stock int BuildTeleporterExit(int hBuilder, const float fOrigin[3], const float fAngle[3],
                          int iLevel = 1, bool iDisabled = false, int iHealth = -1, int iMaxHealth = -1,
                          float flPercentage = 1.0)
{
    static const float fBuildMaxs[3] = { 28.0, 28.0, 66.0 };

    int iTeam = GetClientTeam(hBuilder);

    if (iMaxHealth < 0)
        iMaxHealth = 150;

    if (iHealth < 0 || iHealth > iMaxHealth)
        iHealth = iMaxHealth;

    if (iLevel < 1)
        iLevel = 1;
    else if (iLevel > 3)
        iLevel = 3;

    int iTeleporter = CreateEntityByName(TF2_ObjectClassNames[TFExtObject_Teleporter]);
    if (iTeleporter > 0 && IsValidEdict(iTeleporter))
    {
        DispatchSpawn(iTeleporter);

        TeleportEntity(iTeleporter, fOrigin, fAngle, NULL_VECTOR);

        SetEntityModel(iTeleporter,"models/buildables/teleporter_light.mdl");

        SetEntProp(iTeleporter, Prop_Send, "m_iMaxHealth", 				        iMaxHealth, 4);
        SetEntProp(iTeleporter, Prop_Send, "m_iHealth", 				        iHealth, 4);
        SetEntProp(iTeleporter, Prop_Send, "m_bDisabled", 				        iDisabled, 2);
        SetEntProp(iTeleporter, Prop_Send, "m_iObjectType", 			        view_as<int>(TFExtObject_Teleporter), 1);
        SetEntProp(iTeleporter, Prop_Send, "m_nSkin", 					        (iTeam-2), 1);
        SetEntProp(iTeleporter, Prop_Send, "m_iUpgradeLevel", 			        iLevel, 4);
        SetEntProp(iTeleporter, Prop_Send, "m_iObjectMode", 				    1, TF2_ObjectModes[TFExtObject_TeleporterExit]);
        SetEntProp(iTeleporter, Prop_Send, "m_bBuilding", 				        0, 2);
        SetEntProp(iTeleporter, Prop_Send, "m_bPlacing", 				        0, 2);
        SetEntProp(iTeleporter, Prop_Send, "m_bHasSapper", 				        0, 2);
        SetEntProp(iTeleporter, Prop_Send, "m_nNewSequenceParity", 		        4, 4 );
        SetEntProp(iTeleporter, Prop_Send, "m_nResetEventsParity", 		        4, 4 );
        SetEntProp(iTeleporter, Prop_Send, "m_bServerOverridePlacement", 	    1, 1);
        SetEntProp(iTeleporter, Prop_Send, "m_iState", 	                        1, 1);
        SetEntProp(iTeleporter, Prop_Send, "m_nSequence",                       0);

        SetEntPropEnt(iTeleporter, Prop_Send, "m_hBuilder", 	                hBuilder);

        SetEntPropFloat(iTeleporter, Prop_Send, "m_flPercentageConstructed", 	flPercentage);
        SetEntPropFloat(iTeleporter, Prop_Send, "m_flModelWidthScale", 	        1.0);
        SetEntPropFloat(iTeleporter, Prop_Send, "m_flPlaybackRate", 			1.0);
        SetEntPropFloat(iTeleporter, Prop_Send, "m_flCycle", 					0.0);

        SetEntPropVector(iTeleporter, Prop_Send, "m_vecOrigin", 			    fOrigin);
        SetEntPropVector(iTeleporter, Prop_Send, "m_angRotation", 		        fAngle);
        SetEntPropVector(iTeleporter, Prop_Send, "m_vecBuildMaxs", 		        fBuildMaxs);

        SetVariantInt(iTeam);
        AcceptEntityInput(iTeleporter, "TeamNum", -1, -1, 0);

        SetVariantInt(iTeam);
        AcceptEntityInput(iTeleporter, "SetTeam", -1, -1, 0); 

        SetVariantInt(hBuilder);
        AcceptEntityInput(iTeleporter, "SetBuilder", -1, -1, 0); 

        if (!iDisabled)
            AcceptEntityInput(iTeleporter, "TurnOn");

        Event event = CreateEvent("player_builtobject");
        if (event != null)
        {
            SetEventInt(event, "userid", GetClientUserId(hBuilder));
            SetEventInt(event, "object", view_as<int>(TFExtObject_TeleporterExit));
            SetEventInt(event, "index", iTeleporter);
            SetEventBool(event, "sourcemod", true);
            FireEvent(event);
        }

        g_WasBuilt[iTeleporter] = true;
        g_HasBuilt[hBuilder] |= HasBuiltTeleporterExit;
    }
    return iTeleporter;
}

