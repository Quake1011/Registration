#include <sourcemod>

#include <md5/md5pass.sp>

#define TIMEBAN 5                   //время бана
#define TABLENAME "Registration"    //префикс таблицы в базе
#define RETRIES 3                   //попыток для авторизации перед выдачей бана
#define PREFIX "[QUAKEAUTH] "       //префикс в чате
#define DEBUG 1                     //включание дебаг режима
#define MIN 6                       //минимальное кол-во знаков пароля

enum 
{
    mysql = 0,
    sqlite,
};

bool    
    bClientIsRegged[MAXPLAYERS+1],
    bClientIsAuthed[MAXPLAYERS+1];

int iRetries[MAXPLAYERS+1] = {RETRIES, ...};

char gBuffer[256];

Handle hClientTimerSwitchTeam[MAXPLAYERS+1] = {INVALID_HANDLE, ...};

Database gDb;

public Plugin myinfo = 
{ 
    name = "MyReg", 
    author = "Quake1011", 
    description = "registration system", 
    version = "1.1", 
    url = "https://github.com/Quake1011/Registration"
}

public void OnPluginStart()
{
    if(!SQL_CheckConfig(TABLENAME))
    {
        SetFailState("Секция \"%s\" не найдена в databases.cfg", TABLENAME);
        return;
    }

    char error[256];
    gDb = SQL_Connect(TABLENAME, true, error, sizeof(error));
    #if defined DEBUG
    LogMessage("%sConnecting to Database", PREFIX);
    #endif

    if(gDb == INVALID_HANDLE)
    {
        #if defined DEBUG
        LogMessage("%sHUETA KAKAYATo", PREFIX);
        #endif
        LogError(error);
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "error_db_con_ph", PREFIX, error);
        SetFailState(gBuffer);
        return;
    }

    #if defined DEBUG
    LogMessage("%sThe connection to the database has been successfully established!", PREFIX);
    #endif

    char driver[15];
    SQL_ReadDriver(gDb, driver, sizeof(driver));
    bool MYSQL = StrEqual(driver, "mysql", false);
    if(MYSQL) 
    {
        CreateTable(mysql);
        #if defined DEBUG
        LogMessage("%sMYSQL driver found successfully.", PREFIX);
        #endif
    }
    else 
    {
        CreateTable(sqlite);
        #if defined DEBUG
        LogMessage("%sSQLite driver found successfully.", PREFIX);
        #endif
    }
    
    AddCommandListener(cmd_cb, "jointeam");
    RegConsoleCmd("sm_reg", RegClientCallBack, "Registation command");
    RegConsoleCmd("sm_auth", AuthClientCallBack, "Authentication command");

    LoadTranslations("auth.phrases.txt");
}

public void OnClientDisconnect(int client)
{
    iRetries[client] = RETRIES;
    bClientIsRegged[client] = false;
    bClientIsAuthed[client] = false;
    KillTimer(hClientTimerSwitchTeam[client]);
    hClientTimerSwitchTeam[client] = null;
}

public void CreateTable(int driver)
{
    char sQuery[512];
    if(driver==0) FormatEx(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s` (`accountid` AUTO_INCREMENT, `steam` TEXT NOT NULL PRIMARY KEY, `password` TEXT NOT NULL, `name` TEXT NOT NULL, `retries` INT)", TABLENAME);
    else if(driver==1) FormatEx(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s` (`accountid` INTEGER(10) NOT NULL, `steam` VARCHAR(22) NOT NULL PRIMARY KEY, `password` VARCHAR(128) NOT NULL, `name` VARCHAR(128) NOT NULL, `retries` INTEGER(10))", TABLENAME);

    SQL_TQuery(gDb, SQL_TQueryCallBack, sQuery);

    #if defined DEBUG
    LogMessage("%sTables have been created.", PREFIX);
    #endif
}

public void OnClientConnected(int client)
{
    if(bClientIsRegged[client])
    {        
        char sQuery[512], auth[20];
        GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
        FormatEx(sQuery, sizeof(sQuery), "SELECT `retries` FROM `%s` WHERE='%s'", TABLENAME, auth);
        
        DBResultSet result = SQL_Query(gDb, sQuery);
        
        iRetries[client] = result.FetchInt(0);
        delete result;
    }

    hClientTimerSwitchTeam[client] = CreateTimer(0.1, TimerCallBack, client, TIMER_REPEAT);
}

public Action TimerCallBack(Handle hTimer, int client)
{
    if(IsClientInGame(client) && !IsFakeClient(client))
    {   
        if(GetClientTeam(client)!=1)
        {
            if(!bClientIsRegged[client] || !bClientIsAuthed[client])
            {
                ChangeClientTeam(client, 1);
            }
            else
            {
                KillTimer(hClientTimerSwitchTeam[client]);
                hClientTimerSwitchTeam[client] = null;
                return Plugin_Stop;
            }
        }
    }
    return Plugin_Continue;
}

public Action cmd_cb(int client, const char[] command, int argc)
{
    #if defined DEBUG
    LogMessage("%sPlayer %i tries to select a team", PREFIX, client);
    #endif
    if(!bClientIsAuthed[client]) bClientIsRegged[client] = GetClientReg(client);
    else 
    {
        #if defined DEBUG
        LogMessage("%sEnter %i the login has already been completed", PREFIX, client);
        #endif
        PrintToChatAll("bClientIsAuthed[client]=%b\nbClientIsRegged[client]=%b",bClientIsAuthed[client],bClientIsRegged[client])
    }
    
    if(!bClientIsRegged[client]) 
    {
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "reg_ph", PREFIX);
        PrintToChat(client, gBuffer);
        return Plugin_Stop;
    }
    else if(!bClientIsAuthed[client])
    {
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "auth_ph", PREFIX);
        PrintToChat(client, gBuffer);
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public bool GetClientReg(int client)
{
    char sQuery[512], auth[20];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    FormatEx(sQuery, sizeof(sQuery), "SELECT `*` FROM `%s` WHERE `steam`='%s'", TABLENAME, auth);

    SQL_LockDatabase(gDb);
    DBResultSet result = SQL_Query(gDb, sQuery);
    SQL_UnlockDatabase(gDb);

    if(result==INVALID_HANDLE)
    {
        delete result;
        return false;
    }
    else
    {
        if(result.HasResults)
        {
            #if defined DEBUG
            LogMessage("%sPlayer %i is %s", PREFIX, client, result.HasResults ? "registered" : "not registered");
            #endif
            delete result;
            return true;
        }
    }
    return false;
}

public void SQL_TQueryCallBack(Handle owner, Handle hndl, const char[] error, any data)
{
    if(hndl == INVALID_HANDLE) LogError(error);
}

public Action RegClientCallBack(int client, int args)
{
    #if defined DEBUG
    LogMessage("%sPlayer %i is trying to register", PREFIX, client);
    #endif
    if(!bClientIsRegged[client])
    {
        char sArg[256], sOutput[256], sQuery[256], name[MAX_NAME_LENGTH], auth[20];
        GetCmdArg(1, sArg, sizeof(sArg));
        if(strlen(sArg)>=MIN)
        {
            MD5String(sArg, sOutput, sizeof(sOutput));
            GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
            GetClientName(client, name, sizeof(name));

            SQL_LockDatabase(gDb);
            DBResultSet result = SQL_Query(gDb, sQuery);
            SQL_UnlockDatabase(gDb);

            int iRows;
            if(result == INVALID_HANDLE) iRows = 0
            else iRows = result.RowCount;
            FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `%s` (`accountid`, `steam`, `password`, `name`, `retries`) VALUES ('%i', '%s', '%s', '%s', '%i')", TABLENAME, iRows, auth, sOutput, name, RETRIES);

            SQL_TQuery(gDb, SQL_TQueryCallBack, sQuery);
        
            #if defined DEBUG
            LogMessage("%sPlayer %i is registered, the data is entered into the database", PREFIX, client);
            #endif
            bClientIsRegged[client] = true;
            PrintToChat(client, "%t", "reg_succ", PREFIX);
        }
        else
        {
            PrintToChat(client, "%t", "password_less_digits",PREFIX, MIN);
            #if defined DEBUG
            LogMessage("%sPlayer %i is typed less %i digits of password", PREFIX, client, MIN);
            #endif
        }
    }
    else 
    {
        FormatEx(gBuffer, sizeof(gBuffer), "%t", "reg_yet_ph", PREFIX);
        PrintToChat(client, gBuffer);
        #if defined DEBUG
        LogMessage("%sPlayer %i is trying to register, but is already registered", PREFIX, client);
        #endif
    }
    return Plugin_Continue;
}

public Action AuthClientCallBack(int client, int args)
{
    if(bClientIsRegged[client])
    {
        char sArg[256], sOutput[256], sQuery[256], auth[20];
        GetCmdArg(1, sArg, sizeof(sArg));
        if(strlen(sArg)>=MIN)
        {
            MD5String(sArg, sOutput, sizeof(sOutput));
            #if defined DEBUG
            LogMessage("%sPlayer %i is trying to log in", PREFIX, client);
            #endif
            GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
            FormatEx(sQuery, sizeof(sQuery), "SELECT `password` FROM `%s` WHERE `password`='%s' AND `steam`='%s'",TABLENAME, sOutput, auth);
            
            DBResultSet result = SQL_Query(gDb, sQuery);

            #if defined DEBUG
            LogMessage("%sChecking the hash of the entered player data %i", PREFIX, client);
            #endif
            if(result.HasResults)
            {
                if(result.RowCount == 1)
                {
                    bClientIsAuthed[client] = true;
                    FormatEx(gBuffer, sizeof(gBuffer), "%t", "auth_success_ph", PREFIX);
                    PrintToChat(client, gBuffer);
                    #if defined DEBUG
                    LogMessage("%sPlayer %i has successfully logged in", PREFIX, client);
                    #endif
                }
                else if(result.RowCount > 1)
                {
                    #if defined DEBUG
                    LogMessage("%sMatches found", PREFIX);
                    #endif
                }
                else
                {
                    #if defined DEBUG
                    LogMessage("%sMatches not found", PREFIX);
                    #endif
                }
            }

            else
            {
                iRetries[client]--;
                FormatEx(sQuery, sizeof(sQuery), "UPDATE `%s` SET `retries`='%i' WHERE `steam`='%s'", TABLENAME, iRetries[client], auth);
            
                SQL_TQuery(gDb, SQL_TQueryCallBack, sQuery);
            
                FormatEx(gBuffer, sizeof(gBuffer), "%t", "invalid_pass_ph", PREFIX, iRetries[client], TIMEBAN);
                PrintToChat(client, gBuffer);
                #if defined DEBUG
                LogMessage("%sPlayer %i entered the wrong password %i times", PREFIX, client,RETRIES-iRetries[client]);
                #endif
            }
            
            if(iRetries[client] == 0)
            {
                iRetries[client] = RETRIES;
                BanClient(client, TIMEBAN, BANFLAG_AUTHID, "INVALID PASSWORD", "INVALID PASSWORD");
                #if defined DEBUG
                LogMessage("%sPlayer %i banned for incorrect data entry", PREFIX, client);
                #endif
            }
            delete result;
        }
        else
        {
            PrintToChat(client, "%t", "password_less_digits",PREFIX, MIN);
            #if defined DEBUG
            LogMessage("%sPlayer %i is typed less %i digits of password", PREFIX, client, MIN);
            #endif
        }
    }
    else 
    {
        PrintToChat(client, "%t", "before_auth",PREFIX);
        #if defined DEBUG
        LogMessage("%sPlayer %i non-registered and trying auths", PREFIX, client);
        #endif
    }
    return Plugin_Continue;
}
