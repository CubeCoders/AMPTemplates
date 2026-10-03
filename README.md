# AMP Templates
For the AMP community to share Generic Module templates.

# Making generic module templates
See the wiki article for the module: https://github.com/CubeCoders/AMP/wiki/Configuring-the-'Generic'-AMP-module

You can also use the online configurator at https://config.getamp.sh/ to help with building templates.

**The online configurator can be used as a starting point for making templates. Templates produced using the generator must be fully tested prior to being submitted for review.**

**AI-assisted contributions are welcome**, as long as you've reviewed and tested the result yourself and it follows the repo's issue templates and submission guidelines. Submissions with clearly incorrect or made-up information may be closed by maintainers without notice, but you're welcome to resubmit once they're addressed.

# Sharing Templates
Right now the following restrictions apply to templates that may be publicly shared via this repository (some of these will be relaxed over time):

 - The application must not require any login/authentication in order to download (except for SteamCMD logins).
 - If the application does not have a Linux version you should add a Proton download via SteamCMD to support it if possible.
 - Applications that have customizable settings must use a Settings Manifest.
 - Do not invoke any shell scripts/batch files. You must only launch actual executables. Scripts may be used for update and pre-start stages.
 
# To share a template

Create a pull request containing the following files in the top-level directory of the repository:

    *APPLICATIONAME*.kvp
    *APPLICATIONAME*config.json
    *APPLICATIONAME*metaconfig.json
    *APPLICATIONAME*ports.json
    *APPLICATIONAME*start.json (Optional)
    *APPLICATIONAME*updates.json

With the names fully lower-cased.

For example, `valheim.kvp`, `valheimconfig.json`, `valheimmetaconfig.json`, `valheimports.json`, `valheimstart.json`, `valheinupdates.json`

Do not use any directories. The only other files included should be necessary config files when the server doesn't produce one automatically.

**If you are only submitting a draft, make sure to `Convert to draft` after opening.**

# Editing templates

If you believe that a template needs updates or changes made, please submit a pull request for that template with a justification for why that change is needed.

# After submitting a template

Once you've submitted a pull request, your configuration will be tested in its as-is state. AMP must be able to:

- Load the configuration
- Perform an update
- Start the application
- Reaches the 'Ready' state.
- Gracefully stop the application
- Reach the 'Stopped' state.
- Apply configuration changes.

You should ensure that your configuration can do this on both Windows and Linux before submitting.
