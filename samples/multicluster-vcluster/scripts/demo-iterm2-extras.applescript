-- Adds two tabs only. Existing observer/control panes are preserved.
-- https://iterm2.com/documentation-scripting.html
on run arguments
    if (count of arguments) is not 1 then error "Pass the demo directory"
    set commandPrefix to "cd " & quoted form of (item 1 of arguments) & " && "
    tell application id "com.googlecode.iterm2"
        if (count of windows) is 0 then
            set demoWindow to (create window with default profile)
            set deploymentsTab to current tab of demoWindow
        else
            set demoWindow to current window
            tell demoWindow to set deploymentsTab to (create tab with default profile)
        end if
        set hostWatch to current session of deploymentsTab
        tell hostWatch
            set name to "HOST / Deployment watch"
            set firstWatch to (split horizontally with default profile)
            set rows to 18
        end tell
        tell firstWatch to set secondWatch to (split vertically with default profile)
        tell secondWatch to set thirdWatch to (split vertically with default profile)
        set columns of firstWatch to 60
        set columns of secondWatch to 60
        set columns of thirdWatch to 60
        tell hostWatch to write text (commandPrefix & "make demo-deployments PANE=host")
        tell firstWatch to write text (commandPrefix & "make demo-deployments PANE=1")
        tell secondWatch to write text (commandPrefix & "make demo-deployments PANE=2")
        tell thirdWatch to write text (commandPrefix & "make demo-deployments PANE=3")

        tell demoWindow to set resourcesTab to (create tab with default profile)
        set hostShell to current session of resourcesTab
        tell hostShell to set secondShell to (split horizontally with default profile)
        tell hostShell to set firstShell to (split vertically with default profile)
        tell secondShell to set thirdShell to (split vertically with default profile)
        tell hostShell to write text (commandPrefix & "make demo-resources PANE=host")
        tell firstShell to write text (commandPrefix & "make demo-resources PANE=1")
        tell secondShell to write text (commandPrefix & "make demo-resources PANE=2")
        tell thirdShell to write text (commandPrefix & "make demo-resources PANE=3")

        tell deploymentsTab to select
        tell hostWatch to select
        tell demoWindow to select
        activate
        return "Deployment watches and interactive resource tabs are ready"
    end tell
end run
