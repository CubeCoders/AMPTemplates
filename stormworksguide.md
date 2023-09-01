# Stormworks Setup Guide

## Player Permissions

There are 4 settings for player permissions. Admins, Authorized, Blacklist, and Whitelist. 

### Admins

Admins are able to run the in game commands that are listed below, as well as change the settings in the Settings Menu, if enabled in the Stormworks - World settings. 

### Authorized

 In game, players have to be authorized in order to use the workbench, spawn in creatations, ect. 

### Blacklist

Simply a ban list, players can be banned in game, however, you have to remove their id from the ban list, similar to adding a player to the whitelist, however remove the `<id value="TheirID">`. 

### Whitelist

Whitlist is the only one that cannot be controlled ingame, in order to add or remove a player from the whitelist. You will have to edit the server_config.xml file. 
Under whitelist you will have to add each player using thier Steam64 ID. To find the ID of you or your friends, you can utilise websites like [https://steamidfinder.com/](https://steamidfinder.com/).

Example:
```xml
<whitelist>
    <id value="Steam64ID"/>
</whitelist>
```

## Commands

The following commands can be used in game to control player permissions and to save the game. Note that the game's console does not have inputs, so commands must be ran in game. This means that there is no way of saving the game aside from running the in game command. You can press the enter key to open the chat box and run the commands.
| Command | Discription |
| --- | --- |
| ?save \<SaveName\> | Saves the game, save name is optional |
| ?kick \<id\> | Kicks the selected player |
| ?ban \<id\> | Adds the player to the blacklist |
| ?add_admin \<id\> | Adds the player to the Admin list |
| ?remove_admin \<id\> | Removes the player from the Admin list |
| ?add_auth \<id\> | Adds the player to the Authorized list |
| ?remove_auth \<id\> | Removes the player from the Authorized list |

Note that the ID here is the session ID not the SteamID, this can be found in the players menu by pressing tab.