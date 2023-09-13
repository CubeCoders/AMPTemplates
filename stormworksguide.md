# Stormworks Setup Guide

## Connection Issues

If after setting up the setting up and starting the server, you are unable to connect to the server but others are able to, you may need to install a Microsoft Loopback Adapter. You should only do this if you are having issues with connecting to the server due to the server running on the same computer or network.

- Open Control Panel > Device Manager and select Network Adapters
- Select menu Action > Add legacy hardware
- Next
- Select Install the hardware that I manually select from a list (Advanced)
- Next
- Select Network Adapters in the list
- Next
- Select Microsoft in Manufacturer list
- Select Microsoft KM-TEST Loopback Adapter in Model list
- Next > Next > Finish
- Close Device Manager window
- Open Control Panel > Network and Internet > Network Connections
- You should see a new connection that uses Microsoft Loopback Adapter but cannot establish connection
- Right click on that connection and select Properties
- Double click Internet Protocol Version 4 (TCP/IPv4)
- Select Use the following IP address
- NOTE: If it was already selected and you see some IPs entered then you opened a wrong connection. Get out of here by clicking Canel in both windows.
- Enter in IP address field your external IP address (you can see it here for example https://www.myip.com/)
- You can leave default Subnet mask
- Click OK buttons in opened windows to save settings

Steps thanks to Beginner's Dedicated Server Setup Guide on Steam.

## Linux Support

The server requires Wine to run on Linux, Preferably Wine 8. Using a container avoids the need to install this dependency on the host, otherwise,  Wine is required to be installed on the host system to run the server. 

## Player Permissions

There are 4 settings for player permissions. Admins, Authorized, Blacklist, and Whitelist, which can be edited by using the commands that are listed down below, Whitelist being the only list needing to be manualy edited.

### Admins

Admins are able to run the in game commands that are listed below, as well as change the settings in the Settings Menu, if enabled in the Stormworks - World settings. You can set the first Admin in the AMP settings, however other Admins need to be added using the commands below.

### Authorized

 In game, players have to be authorized in order to use the workbench, spawn in ceations, ect. 

### Blacklist

Simply a ban list. Players can be banned in game, however, you have to remove the line with their id from the ban list, similar to adding a player to the whitelist, however remove the line:

 ```xml
 <id value="TheirID" />
 ``` 

### Whitelist

Whitelist is the only one that cannot be controlled ingame, in order to add or remove a player from the whitelist. You will have to edit the server_config.xml file. 
Under whitelist you will have to add each player using their Steam64 ID. To find the ID of you or your friends, you can utilise websites like [https://steamidfinder.com/](https://steamidfinder.com/).

Example:
```xml
<whitelist>
    <id value="Steam64ID"/>
</whitelist>
```

## Commands

The following commands can be used in game to control player permissions and to save the game. Note that the game's console does not have inputs, so commands must be run in game. Although the game has autosave, since there is no command to run to shutdown the server, this means that there is no way of saving the game on close aside from running the in game command. You can press the enter key to open the chat box and run the commands.
| Command | Description |
| --- | --- |
| ?save \<SaveName\> | Saves the game, save name is optional |
| ?kick \<id\> | Kicks the selected player |
| ?ban \<id\> | Adds the player to the blacklist |
| ?add_admin \<id\> | Adds the player to the Admin list |
| ?remove_admin \<id\> | Removes the player from the Admin list |
| ?add_auth \<id\> | Adds the player to the Authorized list |
| ?remove_auth \<id\> | Removes the player from the Authorized list |

Note that the ID here is the session ID not the SteamID, this can be found in the players menu by pressing tab.
