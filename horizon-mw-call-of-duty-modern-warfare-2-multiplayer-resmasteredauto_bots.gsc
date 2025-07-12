#include maps\mp\bots\_bots;
#include maps\mp\gametypes\_hud_util;

init()
{
    level thread onPlayerConnect();
    level thread serverBotFill();
}

onPlayerConnect()
{
    level endon( "game_ended" );

    for (;;)
    {
        level waittill("connected", player);
      
        if(player isentityabot())
        {
            player maps\mp\bots\_bots_util::bot_set_difficulty( common_scripts\utility::random( [ "regular", "hardened" ] ), undefined );
        }
        else
        {
            player thread kickBotOnJoin();
        }
    }
}

isentityabot()
{
    return isSubStr(self getguid(), "bot");
}

serverBotFill()
{
    level endon( "game_ended" );
    level waittill("connected", player);

    for (;;)
    {
        while (level.players.size < 18 && !level.gameended)
        {
            spawnBotswrapper(1);
            wait 0.5;
        }
        if (level.players.size >= 8 && contBots() > 18)
            kickbot();

        wait 0.05;
    }
}

contBots()
{
    bots = 0;
    foreach (player in level.players)
    {
        if (player isentityabot())
        {
            bots++;
        }
    }
    return bots;
}

spawnBotswrapper(a)
{
    spawn_bots(a, "autoassign");
}

kickbot()
{
    level endon( "game_ended" );

    foreach (player in level.players)
    {
        if (player isentityabot())
        {
            reason = "Replaced With Player";
            kick ( player getEntityNumber(), reason );
            break;
        }
    }
}

kickBotOnJoin()
{
    level endon( "game_ended" );

    foreach (player in level.players)
    {
        if (player isentityabot())
        {
            reason = "Replaced With Player";
            kick ( player getEntityNumber(), reason );
            break;
        }
    }
}