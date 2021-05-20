# AMP Templates
For the AMP community to share Generic Module templates.

# Making generic module templates
See the wiki article for the module: https://github.com/CubeCoders/AMP/wiki/Configuring-the-'Generic'-AMP-module

# Sharing Templates
Right now the following restrictions apply to templates that may be publicly shared via this repository (some of these will be relaxed over time):

 - The application must not require any login/authentication in order to download (including SteamCMD logins).
 - Only applications that run on both Windows *and* Linux are permitted.
 - No extra files/depencendencies. The application must be in a usable state purely using the built in update methods.
 - Applications that have customizable settings must use a Settings Manifest.
 - Only applications that expose some kind of Console that AMP is able to pick up.
 - Do not invoke any shell scripts/batch files. You must only launch actual executables.
 
# To share a template

Create a pull request containing two files in the top-level directory of the repository:

    *APPLICATIONAME*.kvp
    *APPLICATIONAME*config.json

With the names fully lower-cased.

For example, `valheim.kvp` and `valheimconfig.json`

Do not use any directories and include no-other files.

# Editing templates

If you believe that a template needs either updating or changes made, please submit a pull request for that template with a justification for why that change is needed. If possible try and contact the original author first.

# After submitting a template

Once you've submitted a pull request, your configuration will be tested in its as-is state by an automated tool. It will:

- Load the configuration
- Attempt to perform an update
- Attempt to start the application
- Verify that the application reaches the 'Ready' state.
- Attempt to stop the application
- Verify that the application reaches the 'Stopped' state.

You should ensure that your configuration can do this on both Windows and Linux before submitting your configuration.

# Module information

## Eco
The module Eco is not offical supported to run on a Linux environment. Also dotNet is required to run a server above the version 0.9

[Server on Linux](https://wiki.play.eco/en/Server_on_Linux)
[DotNet](https://docs.microsoft.com/en-us/dotnet/core/install/linux)