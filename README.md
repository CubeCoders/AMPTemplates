# AMP Templates
For the AMP community to share Generic Module templates.

# Making generic module templates
See the wiki article for the module: https://github.com/CubeCoders/AMP/wiki/Configuring-the-'Generic'-AMP-module

You can also use the online configurator at https://config.getamp.sh/ to help with building templates.

*There is a much more robust version of the [online configuration tool](https://iceofwraith.github.io/GenericConfigGen/) that is still in beta. This should provide much better results than the above even so. If you have any feedback, please contact IceOfWraith in the CubeCoders Discord.

**The online configurator can be used as a starting point for making templates. However, it will not generally produce a fully functioning template. Templates produced using the generator can be deployed for personal use but will not be accepted into the CubeCoders repository.**

# Sharing Templates
Right now the following restrictions apply to templates that may be publicly shared via this repository (some of these will be relaxed over time):

 - The application must not require any login/authentication in order to download (except for SteamCMD logins).
 - If the application does not have a Linux version you should add a Proton download via SteamCMD to support it if possible.
 - Applications that have customizable settings must use a Settings Manifest.
 - Only applications that expose some kind of Console that AMP is able to pick up.
 - Do not invoke any shell scripts/batch files. You must only launch actual executables.
 
# To share a template

Create a pull request containing the following files in the top-level directory of the repository:

    *APPLICATIONAME*.kvp
    *APPLICATIONAME*config.json
    *APPLICATIONAME*metaconfig.json (Optional)

With the names fully lower-cased.

For example, `valheim.kvp`, `valheimconfig.json`, `valheimmetaconfig.json`

Do not use any directories and include no-other files.

**If you are only submitting a draft, make sure to append (draft) to the pull request title.**

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
