#include <sourcemod>

#include <remote>

#pragma semicolon 1
#pragma newdecls required

ConVar g_CvarEnabled = null;
bool g_BoolEnabled = false;

public Plugin myinfo = {
    name        = "No Remote Sentry Guns",
    author      = "Jobggun",
    description = "No Remote Sentry Guns",
    version     = "1.0.0 Initial Release",
    url         = "https://example.com"
};

public void OnPluginStart()
{
    g_CvarEnabled = CreateConVar("sm_nors_enabled", "0", "", FCVAR_SPONLY, true, 0.0, true, 1.0);
    
    g_CvarEnabled.AddChangeHook(CvarEnabledChange);
    
    g_BoolEnabled = (g_CvarEnabled.IntValue == 1);
}

public void OnConfigsExecuted()
{
    g_BoolEnabled = (g_CvarEnabled.IntValue == 1);
}

void CvarEnabledChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    int iNew = StringToInt(newValue);
    int iOld = StringToInt(oldValue);
    
    if (iNew != 0 && iNew != 1)
    {
        convar.SetInt(iOld);
        g_BoolEnabled = (iOld == 1);
    } else {
        g_BoolEnabled = (iNew == 1);
    }
    
    PrintToChatAll("ConVarChanged");
}

public Action OnControlObject(int client, int builder, int ent)
{
    if (g_BoolEnabled == false)
    {
        return Plugin_Continue;
    }
    
    char classname[32];
    
    if (!GetEntityClassname(ent, classname, sizeof(classname)))
    {
        return Plugin_Continue;
    }
    
    if (StrEqual(classname, "obj_sentrygun"))
    {
        PrintToChat(client, "It is not allowed to remote sentry gun in this map.");
        return Plugin_Handled;
    }
    return Plugin_Continue;
}
