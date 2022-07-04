#include <sourcemod>

#include <md5/md5pass.sp>

#define TIMEBAN 5
#define TABLENAME "Registation"
#define RETRIES 3

bool    
    bClientIsRegged[MAXPLAYERS+1] = {false, ...},
    bClientIsAuthed[MAXPLAYERS+1] = {false, ...};

int iRetries[MAXPLAYERS+1] = {RETRIES, ...};

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
}

public void OnClientPostAdminCheck(client)
{
    char sQuery[512], auth[20];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    FormatEx(sQuery, sizeof(sQuery), "SELECT `retries` FROM `%s` WHERE='%s'", TABLENAME, auth);
    DBResultSet result = SQL_Query(gDb, sQuery, sizeof(sQuery));
    iRetries[client] = result.FetchInt(0);
    delete result;
}

public void OnClientDisconnect(client)
{
    iRetries[client] = RETRIES;
    bClientIsRegged[client] = false,
    bClientIsAuthed[client] = false;
}

public void DataBaseConnectCB(Database db, const char[] error, any data)
{
    if(db == null || error[0])
    {
        LogError(error);
        SetFailState("Ошибка подключения к базе данных: %s", error);
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
        PrintToChat(client, "Зарегистрируйтесь - \"/reg <password>\"");
        return Plugin_Handled;
    }
    else if(!bClientIsAuthed[client])
    {
        PrintToChat(client, "Авторизуйтесь - \"/auth <password>\"");
    }
    return Plugin_Continue;
}

public bool GetClientReg(client)
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
    else PrintToChat(client, "Вы уже зарегистрированы. Введите \"/auth <password>\" для авторизации");
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
        PrintToChat(client, "Авторизация успешно пройдена!");
    }

    else
    {
        iRetries[client]--;
        FormatEx(sQuery, sizeof(sQuery), "UPDATE `%s` SET `retries`='%i' WHERE `steam`='%s'", TABLENAME, iRetries[client], auth);
        SQL_Query(gDb, sQuery, sizeof(sQuery));
        PrintToChat(client, "Неправильный пароль!");
        PrintToChat(client, "Осталось %i попыток. Использовав все - вы будете забанены на %i минут", iRetries[client], TIMEBAN);
    }
    
    if(iRetries[client] == 0)
    {
        iRetries[client] = RETRIES;
        BanClient(client, TIMEBAN, BANFLAG_AUTHID, "INVALID PASSWORD", "INVALID PASSWORD");
    }
    delete result;
    return Plugin_Continue;
}
