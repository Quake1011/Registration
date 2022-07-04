#include <sourcemod>

#include <md5/md5pass.sp>

#define TIMEBAN 5
#define TABLENAME "Registation"
#define RETRIES 3
#define PREFIX "[QUAKEAUTH] "

bool    
    bClientIsRegged[MAXPLAYERS+1],
    bClientIsAuthed[MAXPLAYERS+1];

int iRetries[MAXPLAYERS+1] = {RETRIES, ...};

char gBuffer[256];

Handle hClientTimerSwitchTeam[MAXPLAYERS+1]={INVALID_HANDLE, ...};

Database gDb;

public Plugin myinfo = 
{ 
    name = "My Plugin", 
    author = "Quake1011", 
    description = "No desc", 
    version = "1.0", 
    url = "https://github.com/Quake1011/"
}

public void OnPluginStart()
{
    Database.Connect(DataBaseConnectCB, TABLENAME);

    AddCommandListener(cmd_cb, "jointeam");
    RegConsoleCmd("sm_reg", RegClientCallBack, "Registation command");
    RegConsoleCmd("sm_auth", AuthClientCallBack, "Authentication command");

    LoadTranslations("auth.phrases.txt")
}

public void OnClientPostAdminCheck(int client)
{
    char sQuery[512], auth[20];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    FormatEx(sQuery, sizeof(sQuery), "SELECT `retries` FROM `%s` WHERE='%s'", TABLENAME, auth);
    DBResultSet result = SQL_Query(gDb, sQuery, sizeof(sQuery));
    iRetries[client] = result.FetchInt(0);
    delete result;

    hClientTimerSwitchTeam[client] = CreateTimer(0.1, TimerCallBack, client, TIMER_REPEAT);
}

public Action TimerCallBack(Handle hTimer, int client)
{
    if(!bClientIsRegged[client] || !bClientIsAuthed[client])
    {
        ChangeClientTeam(client, 1);
    }
    else
    {
        KillTimer(hClientTimerSwitchTeam[client]);
        hClientTimerSwitchTeam[client] = null;
    }
    return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
    iRetries[client] = RETRIES;
    bClientIsRegged[client] = false;
    bClientIsAuthed[client] = false;
    KillTimer(hClientTimerSwitchTeam[client]);
    hClientTimerSwitchTeam[client] = null;
}

public void DataBaseConnectCB(Database db, const char[] error, any data)
{
    if(db == null || error[0])
    {
        LogError(error);
        FormatEx(gBuffer, sizeof(gBuffer), "%t","error_db_con_ph",PREFIX, error);               //    {1:s},{2:s}      {1}Ошибка подключения к базе данных: {2}
        SetFailState(gBuffer);
        return;
    }
    gDb = db;
    CreateTable();
}

public void CreateTable()
{
    char sQuery[512];
    FormatEx(sQuery, sizeof(sQuery), "CREATE TABLE IF EXISTS `%s` (`accountid` AUTO_INCREMENT, `steam` TEXT NOT NULL PRIMARY KEY, `password` TEXT NOT NULL, `name` TEXT NOT NULL, `retries` INT)", TABLENAME);
    SQL_Query(gDb, sQuery, sizeof(sQuery));
}

public Action cmd_cb(int client, const char[] command, int argc)
{
    bClientIsRegged[client] = GetClientReg(client);

    if(!bClientIsRegged[client]) 
    {
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "reg_ph", PREFIX);
        PrintToChat(client, gBuffer);               //    {1:s}      {1}Зарегистрируйтесь - \"/reg <password>\"
        return Plugin_Handled;
    }
    else if(!bClientIsAuthed[client])
    {
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "auth_ph", PREFIX);
        PrintToChat(client, gBuffer);               //    {1:s}      {1}Авторизуйтесь - \"/auth <password>\"
    }
    return Plugin_Continue;
}

public bool GetClientReg(int client)
{
    char sQuery[512], auth[20];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    FormatEx(sQuery, sizeof(sQuery), "SELECT `*` FROM `%s` WHERE `steam`='%s'", TABLENAME, auth);
    DBResultSet result = SQL_Query(gDb, sQuery, sizeof(sQuery));
    if(result.HasResults)
    {
        delete result;
        return true;
    }
    delete result;
    return false;
}

public Action RegClientCallBack(int client, int args)
{
    if(!bClientIsRegged[client])
    {
        char sArg[256], sOutput[256], sQuery[256], name[MAX_NAME_LENGTH], auth[20];
        GetCmdArg(1, sArg, sizeof(sArg));
        MD5String(sArg, sOutput, sizeof(sOutput));
        GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
        GetClientName(client, name, sizeof(name));
        FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `%s` (`steam`, `password`, `name`, `retries`) VALUES ('%s', '%s', '%s', '%i')", TABLENAME, auth, sOutput, name, RETRIES);
        SQL_Query(gDb, sQuery, sizeof(sQuery));
    }
    else 
    {
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "reg_yet_ph", PREFIX);
        PrintToChat(client, gBuffer);               //    {1:s}      {1}Вы уже зарегистрированы. Введите \"/auth <password>\" для авторизации
    }
    return Plugin_Continue;
}

public Action AuthClientCallBack(int client, int args)
{
    char sArg[256], sOutput[256], sQuery[256], auth[20];
    GetCmdArg(1, sArg, sizeof(sArg));
    MD5String(sArg, sOutput, sizeof(sOutput));
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    FormatEx(sQuery, sizeof(sQuery), "SELECT `password` FROM `%s` WHERE `password`='%s'",TABLENAME, sOutput);
    DBResultSet result = SQL_Query(gDb, sQuery, sizeof(sQuery));
    if(result.HasResults)
    {
        bClientIsAuthed[client] = true;
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "auth_success_ph", PREFIX);
        PrintToChat(client, gBuffer);               //    {1:s}      {1}Авторизация успешно пройдена!
    }

    else
    {
        iRetries[client]--;
        FormatEx(sQuery, sizeof(sQuery), "UPDATE `%s` SET `retries`='%i' WHERE `steam`='%s'", TABLENAME, iRetries[client], auth);
        SQL_Query(gDb, sQuery, sizeof(sQuery));
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "invalid_pass_ph", PREFIX, iRetries[client], TIMEBAN);
        PrintToChat(client, gBuffer);               //    {1:s},{2:i},{3:i}      {1}Неправильный пароль!\nОсталось {2} попыток. Использовав все - вы будете забанены на {3} минут
    }
    
    if(iRetries[client] == 0)
    {
        iRetries[client] = RETRIES;
        BanClient(client, TIMEBAN, BANFLAG_AUTHID, "INVALID PASSWORD", "INVALID PASSWORD");
    }
    delete result;
    return Plugin_Continue;
}
